import Foundation
import SwiftData

nonisolated struct HanaBackupImportSummary: Equatable, Sendable {
    var added = 0
    var updated = 0
    var skipped = 0
    var failed = 0
    var settingsRestored = false

    var message: String {
        let records = "新增 \(added)，更新 \(updated)，跳过 \(skipped)，失败 \(failed)"
        return settingsRestored ? "\(records)，设置已恢复" : records
    }
}

@MainActor
enum HanaBackupService {
    static let restoredDownloadMediaURL = "file://hana-backup/refresh-required"
    static let restoredDownloadMessage = "请打开视频详情重新加入下载队列，以获取当前下载地址。"

    static func makeArchive(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        exportedAt: Date = .now
    ) throws -> HanaBackupArchive {
        let archive = HanaBackupArchive(
            schemaVersion: HanaBackupArchive.currentSchemaVersion,
            exportedAt: exportedAt,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            settings: makeSettings(defaults: defaults),
            watchHistory: try modelContext.fetch(FetchDescriptor<WatchHistoryRecord>())
                .map(HanaBackupWatchHistory.init)
                .sorted { $0.videoCode < $1.videoCode },
            searchHistory: try modelContext.fetch(FetchDescriptor<SearchHistoryRecord>())
                .map(HanaBackupSearchHistory.init)
                .sorted { $0.query < $1.query },
            advancedSearchHistory: try modelContext.fetch(FetchDescriptor<AdvancedSearchHistoryRecord>())
                .map(HanaBackupAdvancedSearchHistory.init)
                .sorted { $0.criteriaKey < $1.criteriaKey },
            favorites: try modelContext.fetch(FetchDescriptor<FavoriteVideoRecord>())
                .map(HanaBackupFavorite.init)
                .sorted { $0.videoCode < $1.videoCode },
            watchLater: try modelContext.fetch(FetchDescriptor<WatchLaterRecord>())
                .map(HanaBackupWatchLater.init)
                .sorted { $0.videoCode < $1.videoCode },
            playlists: try modelContext.fetch(FetchDescriptor<PlaylistRecord>())
                .map(HanaBackupPlaylist.init)
                .sorted { $0.id < $1.id },
            playlistItems: try modelContext.fetch(FetchDescriptor<PlaylistItemRecord>())
                .map(HanaBackupPlaylistItem.init)
                .sorted { $0.identity < $1.identity },
            downloadQueue: try modelContext.fetch(FetchDescriptor<DownloadQueueRecord>())
                .map(HanaBackupDownload.init)
                .sorted { $0.identity < $1.identity },
            downloadGroups: try modelContext.fetch(FetchDescriptor<DownloadGroupRecord>())
                .map(HanaBackupDownloadGroup.init)
                .sorted { $0.name < $1.name },
            hKeyframes: try modelContext.fetch(FetchDescriptor<HKeyframeRecord>())
                .map(HanaBackupHKeyframe.init)
                .sorted { $0.videoCode < $1.videoCode }
        )
        return try archive.validated()
    }

    static func importArchive(
        _ unvalidatedArchive: HanaBackupArchive,
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        beforeTransactionCompletion: () throws -> Void = {}
    ) throws -> HanaBackupImportSummary {
        let archive = try unvalidatedArchive.validated()
        let disciplineModeData = try archive.settings.disciplineModeConfiguration.map {
            try JSONEncoder().encode($0)
        }
        if modelContext.hasChanges {
            try modelContext.save()
        }

        var watchHistoryByID = try dictionary(
            modelContext.fetch(FetchDescriptor<WatchHistoryRecord>()),
            identity: \WatchHistoryRecord.videoCode
        )
        var searchHistoryByID = try dictionary(
            modelContext.fetch(FetchDescriptor<SearchHistoryRecord>()),
            identity: \SearchHistoryRecord.query
        )
        var advancedSearchHistoryByID = try dictionary(
            modelContext.fetch(FetchDescriptor<AdvancedSearchHistoryRecord>()),
            identity: \AdvancedSearchHistoryRecord.criteriaKey
        )
        var favoritesByID = try dictionary(
            modelContext.fetch(FetchDescriptor<FavoriteVideoRecord>()),
            identity: \FavoriteVideoRecord.videoCode
        )
        var watchLaterByID = try dictionary(
            modelContext.fetch(FetchDescriptor<WatchLaterRecord>()),
            identity: \WatchLaterRecord.videoCode
        )
        var playlistsByID = try dictionary(
            modelContext.fetch(FetchDescriptor<PlaylistRecord>()),
            identity: \PlaylistRecord.id
        )
        var playlistItemsByID = try dictionary(
            modelContext.fetch(FetchDescriptor<PlaylistItemRecord>()),
            identity: \PlaylistItemRecord.id
        )
        var downloadGroupsByID = try dictionary(
            modelContext.fetch(FetchDescriptor<DownloadGroupRecord>()),
            identity: \DownloadGroupRecord.name
        )
        var hKeyframesByID = try dictionary(
            modelContext.fetch(FetchDescriptor<HKeyframeRecord>()),
            identity: \HKeyframeRecord.videoCode
        )
        let existingDownloads = try modelContext.fetch(FetchDescriptor<DownloadQueueRecord>())
        var downloadsByID: [String: DownloadQueueRecord] = [:]
        for record in existingDownloads {
            let identity = downloadIdentity(videoCode: record.videoCode, quality: record.quality)
            guard downloadsByID.updateValue(record, forKey: identity) == nil else {
                throw HanaBackupError.duplicateRecord("本机下载数据 \(record.videoCode) \(record.quality)")
            }
        }

        let archiveGroupNames = Set(archive.downloadGroups.map(\.name))
        let existingGroupNames = Set(downloadGroupsByID.keys)
        let availableGroupNames = archiveGroupNames.union(existingGroupNames)
        let advancedSearchSummaries = Set(archive.advancedSearchHistory.map(\.summary))
        var summary = HanaBackupImportSummary()

        do {
            try modelContext.transaction {
                for item in archive.watchHistory {
                    if let existing = watchHistoryByID[item.videoCode] {
                        guard item.watchDate > existing.watchDate else {
                            summary.skipped += 1
                            continue
                        }
                        item.apply(to: existing)
                        summary.updated += 1
                    } else {
                        let record = item.makeRecord()
                        modelContext.insert(record)
                        watchHistoryByID[item.videoCode] = record
                        summary.added += 1
                    }
                }

                for item in archive.searchHistory {
                    let shouldCountInSummary = !advancedSearchSummaries.contains(item.query)
                    if let existing = searchHistoryByID[item.query] {
                        guard item.createdAt > existing.createdAt else {
                            if shouldCountInSummary {
                                summary.skipped += 1
                            }
                            continue
                        }
                        item.apply(to: existing)
                        if shouldCountInSummary {
                            summary.updated += 1
                        }
                    } else {
                        let record = item.makeRecord()
                        modelContext.insert(record)
                        searchHistoryByID[item.query] = record
                        if shouldCountInSummary {
                            summary.added += 1
                        }
                    }
                }

                for item in archive.advancedSearchHistory {
                    if let existing = advancedSearchHistoryByID[item.criteriaKey] {
                        guard item.createdAt > existing.createdAt else {
                            summary.skipped += 1
                            continue
                        }
                        item.apply(to: existing)
                        summary.updated += 1
                    } else {
                        let record = try item.makeRecord()
                        modelContext.insert(record)
                        advancedSearchHistoryByID[item.criteriaKey] = record
                        summary.added += 1
                    }
                }

                for item in archive.favorites {
                    if let existing = favoritesByID[item.videoCode] {
                        guard item.createdAt > existing.createdAt else {
                            summary.skipped += 1
                            continue
                        }
                        item.apply(to: existing)
                        summary.updated += 1
                    } else {
                        let record = item.makeRecord()
                        modelContext.insert(record)
                        favoritesByID[item.videoCode] = record
                        summary.added += 1
                    }
                }

                for item in archive.watchLater {
                    if let existing = watchLaterByID[item.videoCode] {
                        guard item.createdAt > existing.createdAt else {
                            summary.skipped += 1
                            continue
                        }
                        item.apply(to: existing)
                        summary.updated += 1
                    } else {
                        let record = item.makeRecord()
                        modelContext.insert(record)
                        watchLaterByID[item.videoCode] = record
                        summary.added += 1
                    }
                }

                for item in archive.playlists {
                    if let existing = playlistsByID[item.id] {
                        guard item.updatedAt > existing.updatedAt else {
                            summary.skipped += 1
                            continue
                        }
                        item.apply(to: existing)
                        summary.updated += 1
                    } else {
                        let record = item.makeRecord()
                        modelContext.insert(record)
                        playlistsByID[item.id] = record
                        summary.added += 1
                    }
                }

                for item in archive.playlistItems {
                    if let existing = playlistItemsByID[item.identity] {
                        guard item.createdAt > existing.createdAt else {
                            summary.skipped += 1
                            continue
                        }
                        item.apply(to: existing)
                        summary.updated += 1
                    } else {
                        let record = item.makeRecord()
                        modelContext.insert(record)
                        playlistItemsByID[item.identity] = record
                        summary.added += 1
                    }
                }

                for item in archive.downloadGroups {
                    if downloadGroupsByID[item.name] != nil {
                        summary.skipped += 1
                    } else {
                        let record = item.makeRecord()
                        modelContext.insert(record)
                        downloadGroupsByID[item.name] = record
                        summary.added += 1
                    }
                }

                for item in archive.downloadQueue {
                    if downloadsByID[item.identity] != nil {
                        summary.skipped += 1
                    } else {
                        let record = item.makeRecord(
                            groupName: availableGroupNames.contains(item.downloadGroupName)
                                ? item.downloadGroupName
                                : "默认分组"
                        )
                        modelContext.insert(record)
                        downloadsByID[item.identity] = record
                        summary.added += 1
                    }
                }

                for item in archive.hKeyframes {
                    if let existing = hKeyframesByID[item.videoCode] {
                        guard item.updatedAt > existing.updatedAt else {
                            summary.skipped += 1
                            continue
                        }
                        item.apply(to: existing)
                        summary.updated += 1
                    } else {
                        let record = item.makeRecord()
                        modelContext.insert(record)
                        hKeyframesByID[item.videoCode] = record
                        summary.added += 1
                    }
                }

                try beforeTransactionCompletion()
            }
        } catch {
            modelContext.rollback()
            throw error
        }

        applySettings(archive.settings, disciplineModeData: disciplineModeData, defaults: defaults)
        summary.settingsRestored = true
        return summary
    }

    private static func makeSettings(defaults: UserDefaults) -> HanaBackupSettings {
        let disciplineModeConfiguration = defaults.data(
            forKey: HanaSettingsKey.disciplineModeConfiguration
        )
        .flatMap { try? JSONDecoder().decode(DisciplineModeConfiguration.self, from: $0) }

        return HanaBackupSettings(
            siteBaseURL: HanaSiteBaseURL.normalized(
                string(defaults, HanaSettingsKey.siteBaseURL, HanaSiteBaseURL.defaultValue))
                ?? HanaSiteBaseURL.defaultValue,
            appearanceMode: string(
                defaults, HanaSettingsKey.appearanceMode, HanaAppearanceMode.system.rawValue),
            themeColor: string(defaults, HanaSettingsKey.themeColor, HanaThemeColor.defaultValue),
            demoModeEnabled: bool(defaults, HanaSettingsKey.demoModeEnabled, false),
            defaultVideoQuality: string(
                defaults, HanaSettingsKey.defaultVideoQuality,
                HanaVideoQualityPreference.defaultValue.rawValue),
            allowResumePlayback: bool(defaults, HanaSettingsKey.allowResumePlayback, true),
            showPlayedIndicator: bool(defaults, HanaSettingsKey.showPlayedIndicator, true),
            videoLanguage: HanaVideoLanguagePreference.normalizedRawValue(
                string(defaults, HanaSettingsKey.videoLanguage, HanaVideoLanguagePreference.zhHans.rawValue)
            ),
            pictureInPictureEnabled: bool(defaults, HanaSettingsKey.pictureInPictureEnabled, true),
            loopPlaybackEnabled: bool(defaults, HanaSettingsKey.loopPlaybackEnabled, false),
            playerLongPressRate: double(
                defaults, HanaSettingsKey.playerLongPressRate, HanaPlaybackSpeedCatalog.defaultLongPressRate
            ),
            hKeyframesEnabled: bool(defaults, HanaSettingsKey.hKeyframesEnabled, true),
            hKeyframeCountdownSeconds: integer(defaults, HanaSettingsKey.hKeyframeCountdownSeconds, 10),
            hKeyframeShowPrompt: bool(defaults, HanaSettingsKey.hKeyframeShowPrompt, true),
            sharedHKeyframesEnabled: bool(defaults, HanaSettingsKey.sharedHKeyframesEnabled, true),
            sharedHKeyframesPreferred: bool(defaults, HanaSettingsKey.sharedHKeyframesPreferred, false),
            defaultDownloadQuality: string(
                defaults, HanaSettingsKey.defaultDownloadQuality,
                HanaVideoQualityPreference.defaultValue.rawValue),
            downloadConcurrency: integer(defaults, HanaSettingsKey.downloadConcurrency, 2),
            warnBeforeMobileDataDownload: bool(
                defaults, HanaSettingsKey.warnBeforeMobileDataDownload, true),
            autoCheckForUpdates: bool(defaults, HanaSettingsKey.autoCheckForUpdates, true),
            updateLinkDestination: string(
                defaults, HanaSettingsKey.updateLinkDestination, HanaUpdateLinkDestination.defaultValue),
            disciplineModeConfiguration: disciplineModeConfiguration
        )
    }

    private static func applySettings(
        _ settings: HanaBackupSettings,
        disciplineModeData: Data?,
        defaults: UserDefaults
    ) {
        defaults.set(settings.siteBaseURL, forKey: HanaSettingsKey.siteBaseURL)
        defaults.set(settings.appearanceMode, forKey: HanaSettingsKey.appearanceMode)
        defaults.set(settings.themeColor, forKey: HanaSettingsKey.themeColor)
        defaults.set(settings.demoModeEnabled, forKey: HanaSettingsKey.demoModeEnabled)
        defaults.set(settings.defaultVideoQuality, forKey: HanaSettingsKey.defaultVideoQuality)
        defaults.set(settings.allowResumePlayback, forKey: HanaSettingsKey.allowResumePlayback)
        defaults.set(settings.showPlayedIndicator, forKey: HanaSettingsKey.showPlayedIndicator)
        defaults.set(settings.videoLanguage, forKey: HanaSettingsKey.videoLanguage)
        defaults.set(settings.pictureInPictureEnabled, forKey: HanaSettingsKey.pictureInPictureEnabled)
        defaults.set(settings.loopPlaybackEnabled, forKey: HanaSettingsKey.loopPlaybackEnabled)
        defaults.set(settings.playerLongPressRate, forKey: HanaSettingsKey.playerLongPressRate)
        defaults.set(settings.hKeyframesEnabled, forKey: HanaSettingsKey.hKeyframesEnabled)
        defaults.set(
            settings.hKeyframeCountdownSeconds, forKey: HanaSettingsKey.hKeyframeCountdownSeconds)
        defaults.set(settings.hKeyframeShowPrompt, forKey: HanaSettingsKey.hKeyframeShowPrompt)
        defaults.set(settings.sharedHKeyframesEnabled, forKey: HanaSettingsKey.sharedHKeyframesEnabled)
        defaults.set(
            settings.sharedHKeyframesPreferred, forKey: HanaSettingsKey.sharedHKeyframesPreferred)
        defaults.set(settings.defaultDownloadQuality, forKey: HanaSettingsKey.defaultDownloadQuality)
        defaults.set(settings.downloadConcurrency, forKey: HanaSettingsKey.downloadConcurrency)
        defaults.set(
            settings.warnBeforeMobileDataDownload, forKey: HanaSettingsKey.warnBeforeMobileDataDownload)
        defaults.set(settings.autoCheckForUpdates, forKey: HanaSettingsKey.autoCheckForUpdates)
        defaults.set(settings.updateLinkDestination, forKey: HanaSettingsKey.updateLinkDestination)
        if let disciplineModeData {
            defaults.set(disciplineModeData, forKey: HanaSettingsKey.disciplineModeConfiguration)
        } else {
            defaults.removeObject(forKey: HanaSettingsKey.disciplineModeConfiguration)
        }
    }

    private static func dictionary<Model>(
        _ models: [Model],
        identity: KeyPath<Model, String>
    ) throws -> [String: Model] {
        var result: [String: Model] = [:]
        for model in models {
            let key = model[keyPath: identity]
            guard result.updateValue(model, forKey: key) == nil else {
                throw HanaBackupError.duplicateRecord("本机数据 \(key)")
            }
        }
        return result
    }

    private static func downloadIdentity(videoCode: String, quality: String) -> String {
        "\(videoCode)\u{1F}\(quality)"
    }

    private static func string(_ defaults: UserDefaults, _ key: String, _ fallback: String) -> String {
        defaults.string(forKey: key) ?? fallback
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private static func integer(_ defaults: UserDefaults, _ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    private static func double(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? fallback
    }
}

extension HanaBackupWatchHistory {
    fileprivate init(_ record: WatchHistoryRecord) {
        self.init(
            videoCode: record.videoCode,
            title: record.title,
            coverURLString: record.coverURLString,
            releaseDate: record.releaseDate,
            watchDate: record.watchDate,
            progress: record.progress,
            duration: record.duration,
            watchedAt: record.watchedAt
        )
    }

    fileprivate func makeRecord() -> WatchHistoryRecord {
        WatchHistoryRecord(
            videoCode: videoCode,
            title: title,
            coverURLString: coverURLString,
            releaseDate: releaseDate,
            watchDate: watchDate,
            progress: progress,
            duration: duration,
            watchedAt: watchedAt
        )
    }

    fileprivate func apply(to record: WatchHistoryRecord) {
        record.title = title
        record.coverURLString = coverURLString
        record.releaseDate = releaseDate
        record.watchDate = watchDate
        record.progress = progress
        record.duration = duration
        record.watchedAt = watchedAt
    }
}

extension HanaBackupSearchHistory {
    fileprivate init(_ record: SearchHistoryRecord) {
        self.init(query: record.query, createdAt: record.createdAt)
    }

    fileprivate func makeRecord() -> SearchHistoryRecord {
        SearchHistoryRecord(query: query, createdAt: createdAt)
    }

    fileprivate func apply(to record: SearchHistoryRecord) {
        record.createdAt = createdAt
    }
}

extension HanaBackupAdvancedSearchHistory {
    fileprivate init(_ record: AdvancedSearchHistoryRecord) {
        self.init(
            criteriaKey: record.criteriaKey,
            summary: record.summary,
            criteriaJSON: record.criteriaJSON,
            createdAt: record.createdAt
        )
    }

    fileprivate func makeRecord() throws -> AdvancedSearchHistoryRecord {
        guard let criteria = HanimeSearchCriteria.decoded(from: criteriaJSON) else {
            throw HanaBackupError.invalidField("高级搜索条件")
        }
        let record = AdvancedSearchHistoryRecord(criteria: criteria, createdAt: createdAt)
        apply(to: record)
        return record
    }

    fileprivate func apply(to record: AdvancedSearchHistoryRecord) {
        record.criteriaKey = criteriaKey
        record.summary = summary
        record.criteriaJSON = criteriaJSON
        record.createdAt = createdAt
    }
}

extension HanaBackupFavorite {
    fileprivate init(_ record: FavoriteVideoRecord) {
        self.init(
            videoCode: record.videoCode,
            title: record.title,
            coverURLString: record.coverURLString,
            createdAt: record.createdAt
        )
    }

    fileprivate func makeRecord() -> FavoriteVideoRecord {
        FavoriteVideoRecord(
            videoCode: videoCode,
            title: title,
            coverURLString: coverURLString,
            createdAt: createdAt
        )
    }

    fileprivate func apply(to record: FavoriteVideoRecord) {
        record.title = title
        record.coverURLString = coverURLString
        record.createdAt = createdAt
    }
}

extension HanaBackupWatchLater {
    fileprivate init(_ record: WatchLaterRecord) {
        self.init(
            videoCode: record.videoCode,
            title: record.title,
            coverURLString: record.coverURLString,
            createdAt: record.createdAt
        )
    }

    fileprivate func makeRecord() -> WatchLaterRecord {
        WatchLaterRecord(
            videoCode: videoCode,
            title: title,
            coverURLString: coverURLString,
            createdAt: createdAt
        )
    }

    fileprivate func apply(to record: WatchLaterRecord) {
        record.title = title
        record.coverURLString = coverURLString
        record.createdAt = createdAt
    }
}

extension HanaBackupPlaylist {
    fileprivate init(_ record: PlaylistRecord) {
        self.init(
            id: record.id,
            title: record.title,
            detail: record.detail,
            coverURLString: record.coverURLString,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    fileprivate func makeRecord() -> PlaylistRecord {
        PlaylistRecord(
            id: id,
            title: title,
            detail: detail,
            coverURLString: coverURLString,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    fileprivate func apply(to record: PlaylistRecord) {
        record.title = title
        record.detail = detail
        record.coverURLString = coverURLString
        record.createdAt = createdAt
        record.updatedAt = updatedAt
    }
}

extension HanaBackupPlaylistItem {
    fileprivate init(_ record: PlaylistItemRecord) {
        self.init(
            playlistID: record.playlistID,
            videoCode: record.videoCode,
            title: record.title,
            coverURLString: record.coverURLString,
            createdAt: record.createdAt
        )
    }

    fileprivate func makeRecord() -> PlaylistItemRecord {
        PlaylistItemRecord(
            playlistID: playlistID,
            videoCode: videoCode,
            title: title,
            coverURLString: coverURLString,
            createdAt: createdAt
        )
    }

    fileprivate func apply(to record: PlaylistItemRecord) {
        record.playlistID = playlistID
        record.videoCode = videoCode
        record.id = identity
        record.title = title
        record.coverURLString = coverURLString
        record.createdAt = createdAt
    }
}

extension HanaBackupDownload {
    fileprivate init(_ record: DownloadQueueRecord) {
        self.init(
            videoCode: record.videoCode,
            title: record.title,
            coverURLString: record.coverURLString,
            quality: record.quality,
            downloadGroupName: record.downloadGroupName,
            createdAt: record.createdAt
        )
    }

    fileprivate func makeRecord(groupName: String) -> DownloadQueueRecord {
        let record = DownloadQueueRecord(
            videoCode: videoCode,
            title: title,
            coverURLString: coverURLString,
            quality: quality,
            mediaURLString: HanaBackupService.restoredDownloadMediaURL,
            createdAt: createdAt,
            status: "等待下载"
        )
        record.downloadGroupName = groupName
        record.errorMessage = HanaBackupService.restoredDownloadMessage
        return record
    }
}

extension HanaBackupDownloadGroup {
    fileprivate init(_ record: DownloadGroupRecord) {
        self.init(name: record.name, createdAt: record.createdAt)
    }

    fileprivate func makeRecord() -> DownloadGroupRecord {
        DownloadGroupRecord(name: name, createdAt: createdAt)
    }
}

extension HanaBackupHKeyframe {
    fileprivate init(_ record: HKeyframeRecord) {
        self.init(
            videoCode: record.videoCode,
            title: record.title,
            groupTitle: record.groupTitle,
            episode: record.episode,
            author: record.author,
            keyframes: record.keyframes,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    fileprivate func makeRecord() -> HKeyframeRecord {
        HKeyframeRecord(
            videoCode: videoCode,
            title: title,
            groupTitle: groupTitle,
            episode: episode,
            author: author,
            keyframes: keyframes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    fileprivate func apply(to record: HKeyframeRecord) {
        record.title = title
        record.groupTitle = groupTitle
        record.episode = episode
        record.author = author
        record.keyframes = keyframes
        record.createdAt = createdAt
        record.updatedAt = updatedAt
    }
}
