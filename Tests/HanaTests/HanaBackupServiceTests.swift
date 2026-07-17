import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers

@testable import Hana

@Suite("Hana backup service")
@MainActor
struct HanaBackupServiceTests {
    @Test("registers the backup filename extension")
    func backupFilenameExtensionRegistration() {
        #expect(UTType.hanaBackup.preferredFilenameExtension == "hanabackup")
        #expect(UTType(filenameExtension: "hanabackup", conformingTo: .json) == .hanaBackup)
    }

    @Test("round trips all persisted model types and settings")
    func roundTrip() throws {
        let sourceContainer = try makeContainer()
        let sourceContext = sourceContainer.mainContext
        let sourceDefaults = makeDefaults()
        let exportedAt = Date(timeIntervalSince1970: 1_800_000_000)
        seedAllModelTypes(in: sourceContext)
        try sourceContext.save()
        let disciplineConfiguration = DisciplineModeConfiguration(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            mode: .weekly(.init(allowedWeekdayNumbers: [2, 4, 6]))
        )
        sourceDefaults.set("dark", forKey: HanaSettingsKey.appearanceMode)
        sourceDefaults.set(3, forKey: HanaSettingsKey.downloadConcurrency)
        sourceDefaults.set(
            try JSONEncoder().encode(disciplineConfiguration),
            forKey: HanaSettingsKey.disciplineModeConfiguration
        )

        let sourceArchive = try HanaBackupService.makeArchive(
            modelContext: sourceContext,
            defaults: sourceDefaults,
            exportedAt: exportedAt
        )
        let decodedArchive = try HanaBackupArchive.decode(HanaBackupArchive.encode(sourceArchive))

        let destinationContainer = try makeContainer()
        let destinationContext = destinationContainer.mainContext
        let destinationDefaults = makeDefaults()
        let summary = try HanaBackupService.importArchive(
            decodedArchive,
            modelContext: destinationContext,
            defaults: destinationDefaults
        )
        let verificationContext = ModelContext(destinationContainer)
        let destinationArchive = try HanaBackupService.makeArchive(
            modelContext: verificationContext,
            defaults: destinationDefaults,
            exportedAt: exportedAt
        )

        #expect(summary.added == 10)
        #expect(summary.updated == 0)
        #expect(summary.skipped == 0)
        #expect(summary.failed == 0)
        #expect(summary.settingsRestored)
        #expect(destinationArchive == sourceArchive)
    }

    @Test("rejects future versions and malformed JSON")
    func rejectsUnsupportedFiles() throws {
        var futureArchive = makeEmptyArchive()
        futureArchive.schemaVersion = HanaBackupArchive.currentSchemaVersion + 1

        do {
            _ = try HanaBackupArchive.decode(HanaBackupArchive.encode(futureArchive))
            Issue.record("Future schema version was accepted")
        } catch let error as HanaBackupError {
            #expect(error == .unsupportedSchemaVersion(HanaBackupArchive.currentSchemaVersion + 1))
        }

        do {
            _ = try HanaBackupArchive.decode(Data("{".utf8))
            Issue.record("Malformed JSON was accepted")
        } catch let error as HanaBackupError {
            guard case .invalidArchive = error else {
                Issue.record("Unexpected malformed JSON error: \(error)")
                return
            }
        }
    }

    @Test("counts paired search storage as one visible entry")
    func pairedSearchHistorySummary() throws {
        let container = try makeContainer()
        var archive = makeEmptyArchive()
        let criteria = [
            HanimeSearchCriteria(query: "najar", genre: "2D 動畫"),
            HanimeSearchCriteria(tags: ["无码"]),
        ]
        archive.searchHistory = criteria.enumerated().map { index, criteria in
            HanaBackupSearchHistory(
                query: criteria.summary,
                createdAt: Date(timeIntervalSince1970: TimeInterval(100 + index))
            )
        }
        archive.advancedSearchHistory = try criteria.enumerated().map { index, criteria in
            HanaBackupAdvancedSearchHistory(
                criteriaKey: criteria.historyKey,
                summary: criteria.summary,
                criteriaJSON: try #require(criteria.encodedJSONString()),
                createdAt: Date(timeIntervalSince1970: TimeInterval(100 + index))
            )
        }

        let summary = try HanaBackupService.importArchive(
            archive,
            modelContext: container.mainContext,
            defaults: makeDefaults()
        )

        #expect(summary.added == 2)
        #expect(try container.mainContext.fetch(FetchDescriptor<SearchHistoryRecord>()).count == 2)
        #expect(try container.mainContext.fetch(FetchDescriptor<AdvancedSearchHistoryRecord>()).count == 2)
    }

    @Test("validation failures leave records and settings unchanged")
    func validationFailuresAreAtomic() throws {
        let duplicateContainer = try makeContainer()
        let duplicateDefaults = makeDefaults()
        duplicateDefaults.set("light", forKey: HanaSettingsKey.appearanceMode)
        var duplicateArchive = makeEmptyArchive()
        duplicateArchive.settings.appearanceMode = "dark"
        duplicateArchive.searchHistory = [
            .init(query: "same", createdAt: Date(timeIntervalSince1970: 100)),
            .init(query: "same", createdAt: Date(timeIntervalSince1970: 200)),
        ]

        #expect(throws: HanaBackupError.self) {
            try HanaBackupService.importArchive(
                duplicateArchive,
                modelContext: duplicateContainer.mainContext,
                defaults: duplicateDefaults
            )
        }
        #expect(
            try duplicateContainer.mainContext.fetch(FetchDescriptor<SearchHistoryRecord>()).isEmpty)
        #expect(duplicateDefaults.string(forKey: HanaSettingsKey.appearanceMode) == "light")

        let referenceContainer = try makeContainer()
        let referenceDefaults = makeDefaults()
        var referenceArchive = makeEmptyArchive()
        referenceArchive.playlistItems = [
            .init(
                playlistID: "missing-playlist",
                videoCode: "video",
                title: "Broken reference",
                coverURLString: nil,
                createdAt: Date(timeIntervalSince1970: 100)
            )
        ]

        #expect(throws: HanaBackupError.self) {
            try HanaBackupService.importArchive(
                referenceArchive,
                modelContext: referenceContainer.mainContext,
                defaults: referenceDefaults
            )
        }
        #expect(try referenceContainer.mainContext.fetch(FetchDescriptor<PlaylistItemRecord>()).isEmpty)
    }

    @Test("transaction failure rolls back records before settings are applied")
    func transactionFailureIsAtomic() throws {
        enum InjectedFailure: Error { case stop }

        let container = try makeContainer()
        let defaults = makeDefaults()
        defaults.set("system", forKey: HanaSettingsKey.appearanceMode)
        var archive = makeEmptyArchive()
        archive.settings.appearanceMode = "dark"
        archive.searchHistory = [
            .init(query: "rollback", createdAt: Date(timeIntervalSince1970: 100))
        ]

        #expect(throws: InjectedFailure.self) {
            try HanaBackupService.importArchive(
                archive,
                modelContext: container.mainContext,
                defaults: defaults,
                beforeTransactionCompletion: { throw InjectedFailure.stop }
            )
        }

        #expect(try container.mainContext.fetch(FetchDescriptor<SearchHistoryRecord>()).isEmpty)
        #expect(defaults.string(forKey: HanaSettingsKey.appearanceMode) == "system")
    }

    @Test("merges newer records and keeps local download ownership")
    func mergeRulesAndDownloadReset() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let localFavorite = FavoriteVideoRecord(
            videoCode: "favorite",
            title: "Old title",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let localWatchLater = WatchLaterRecord(
            videoCode: "later",
            title: "New local title",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let localDownload = DownloadQueueRecord(
            videoCode: "download-local",
            title: "Local file",
            coverURLString: nil,
            quality: "1080P",
            mediaURLString: "https://local.invalid/video.mp4",
            createdAt: Date(timeIntervalSince1970: 100),
            status: "已完成"
        )
        localDownload.localFileURLString = "file:///Users/test/local.mp4"
        localDownload.progress = 1
        context.insert(localFavorite)
        context.insert(localWatchLater)
        context.insert(localDownload)
        try context.save()

        var archive = makeEmptyArchive()
        archive.favorites = [
            .init(
                videoCode: "favorite",
                title: "New title",
                coverURLString: nil,
                createdAt: Date(timeIntervalSince1970: 200)
            )
        ]
        archive.watchLater = [
            .init(
                videoCode: "later",
                title: "Old imported title",
                coverURLString: nil,
                createdAt: Date(timeIntervalSince1970: 200)
            )
        ]
        archive.downloadQueue = [
            .init(
                videoCode: "download-local",
                title: "Imported duplicate",
                coverURLString: nil,
                quality: "1080P",
                downloadGroupName: "默认分组",
                createdAt: Date(timeIntervalSince1970: 200)
            ),
            .init(
                videoCode: "download-new",
                title: "Imported new",
                coverURLString: nil,
                quality: "720P",
                downloadGroupName: "missing-group",
                createdAt: Date(timeIntervalSince1970: 200)
            ),
        ]

        let summary = try HanaBackupService.importArchive(
            archive,
            modelContext: context,
            defaults: makeDefaults()
        )
        let favorites = try context.fetch(FetchDescriptor<FavoriteVideoRecord>())
        let watchLater = try context.fetch(FetchDescriptor<WatchLaterRecord>())
        let downloads = try context.fetch(FetchDescriptor<DownloadQueueRecord>())
        let keptDownload = try #require(downloads.first { $0.videoCode == "download-local" })
        let restoredDownload = try #require(downloads.first { $0.videoCode == "download-new" })

        #expect(summary.added == 1)
        #expect(summary.updated == 1)
        #expect(summary.skipped == 2)
        #expect(favorites.first?.title == "New title")
        #expect(watchLater.first?.title == "New local title")
        #expect(keptDownload.status == "已完成")
        #expect(keptDownload.localFileURLString == "file:///Users/test/local.mp4")
        #expect(restoredDownload.status == "等待下载")
        #expect(restoredDownload.mediaURLString == HanaBackupService.restoredDownloadMediaURL)
        #expect(restoredDownload.downloadGroupName == "默认分组")
        #expect(restoredDownload.localFileURLString == nil)
        #expect(restoredDownload.progress == 0)
        #expect(restoredDownload.errorMessage == HanaBackupService.restoredDownloadMessage)
    }

    @Test("export excludes credentials paths and temporary download URLs")
    func exportPrivacyBoundary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let defaults = makeDefaults()
        let download = DownloadQueueRecord(
            videoCode: "private-download",
            title: "Private",
            coverURLString: nil,
            quality: "1080P",
            mediaURLString: "https://media.invalid/video.mp4?token=MEDIA_SECRET"
        )
        download.localFileURLString = "file:///Users/private/LOCAL_PATH_SECRET.mp4"
        download.backgroundSessionIdentifier = "BACKGROUND_SESSION_SECRET"
        download.backgroundTaskIdentifier = 987_654
        context.insert(download)
        try context.save()
        defaults.set("COOKIE_SECRET", forKey: "Hana.SiteWebSession.cookieHeader")
        defaults.set("PROXY_SECRET", forKey: HanaSettingsKey.networkProxyHost)
        defaults.set(4321, forKey: HanaSettingsKey.networkProxyPort)
        defaults.set(Data("BOOKMARK_SECRET".utf8), forKey: "hana.settings.downloadDirectoryBookmark")

        let archive = try HanaBackupService.makeArchive(modelContext: context, defaults: defaults)
        let json = try #require(String(data: HanaBackupArchive.encode(archive), encoding: .utf8))

        for secret in [
            "COOKIE_SECRET",
            "PROXY_SECRET",
            "BOOKMARK_SECRET",
            "MEDIA_SECRET",
            "LOCAL_PATH_SECRET",
            "BACKGROUND_SESSION_SECRET",
            "mediaURLString",
            "localFileURLString",
            "backgroundSessionIdentifier",
            "backgroundTaskIdentifier",
        ] {
            #expect(!json.contains(secret))
        }
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WatchHistoryRecord.self,
            SearchHistoryRecord.self,
            AdvancedSearchHistoryRecord.self,
            FavoriteVideoRecord.self,
            WatchLaterRecord.self,
            PlaylistRecord.self,
            PlaylistItemRecord.self,
            DownloadQueueRecord.self,
            DownloadGroupRecord.self,
            HKeyframeRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "HanaBackupServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeEmptyArchive() -> HanaBackupArchive {
        HanaBackupArchive(
            schemaVersion: HanaBackupArchive.currentSchemaVersion,
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
            appVersion: "1.0",
            buildNumber: "1",
            settings: HanaBackupSettings(
                siteBaseURL: HanaSiteBaseURL.defaultValue,
                appearanceMode: HanaAppearanceMode.system.rawValue,
                themeColor: HanaThemeColor.defaultValue,
                demoModeEnabled: false,
                defaultVideoQuality: HanaVideoQualityPreference.defaultValue.rawValue,
                allowResumePlayback: true,
                showPlayedIndicator: true,
                videoLanguage: HanaVideoLanguagePreference.zhHans.rawValue,
                pictureInPictureEnabled: true,
                loopPlaybackEnabled: false,
                playerLongPressRate: HanaPlaybackSpeedCatalog.defaultLongPressRate,
                hKeyframesEnabled: true,
                hKeyframeCountdownSeconds: 10,
                hKeyframeShowPrompt: true,
                sharedHKeyframesEnabled: true,
                sharedHKeyframesPreferred: false,
                defaultDownloadQuality: HanaVideoQualityPreference.defaultValue.rawValue,
                downloadConcurrency: 2,
                warnBeforeMobileDataDownload: true,
                autoCheckForUpdates: true,
                updateLinkDestination: HanaUpdateLinkDestination.defaultValue,
                disciplineModeConfiguration: nil
            ),
            watchHistory: [],
            searchHistory: [],
            advancedSearchHistory: [],
            favorites: [],
            watchLater: [],
            playlists: [],
            playlistItems: [],
            downloadQueue: [],
            downloadGroups: [],
            hKeyframes: []
        )
    }

    private func seedAllModelTypes(in context: ModelContext) {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(
            WatchHistoryRecord(
                videoCode: "watch",
                title: "Watch",
                coverURLString: "https://example.invalid/watch.jpg",
                releaseDate: baseDate,
                watchDate: baseDate.addingTimeInterval(10),
                progress: 120,
                duration: 600,
                watchedAt: baseDate.addingTimeInterval(20)
            )
        )
        context.insert(SearchHistoryRecord(query: "query", createdAt: baseDate))
        context.insert(
            AdvancedSearchHistoryRecord(
                criteria: HanimeSearchCriteria(query: "advanced", tags: ["tag"]),
                createdAt: baseDate
            )
        )
        context.insert(
            FavoriteVideoRecord(videoCode: "favorite", title: "Favorite", createdAt: baseDate))
        context.insert(WatchLaterRecord(videoCode: "later", title: "Later", createdAt: baseDate))
        context.insert(
            PlaylistRecord(
                id: "playlist",
                title: "Playlist",
                detail: "Detail",
                createdAt: baseDate,
                updatedAt: baseDate.addingTimeInterval(30)
            )
        )
        context.insert(
            PlaylistItemRecord(
                playlistID: "playlist",
                videoCode: "playlist-video",
                title: "Playlist video",
                createdAt: baseDate
            )
        )
        let download = DownloadQueueRecord(
            videoCode: "download",
            title: "Download",
            coverURLString: "https://example.invalid/download.jpg",
            quality: "1080P",
            mediaURLString: "https://example.invalid/video.mp4?token=not-exported",
            createdAt: baseDate,
            status: "已完成"
        )
        download.downloadGroupName = "Group"
        download.localFileURLString = "file:///Users/test/not-exported.mp4"
        download.progress = 1
        context.insert(download)
        context.insert(DownloadGroupRecord(name: "Group", createdAt: baseDate))
        context.insert(
            HKeyframeRecord(
                videoCode: "keyframe",
                title: "Keyframe",
                groupTitle: "Series",
                episode: 1,
                author: "Author",
                keyframes: [.init(positionMilliseconds: 12_000, prompt: "Prompt")],
                createdAt: baseDate,
                updatedAt: baseDate.addingTimeInterval(40)
            )
        )
    }
}
