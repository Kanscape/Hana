import Foundation
import Testing
@testable import Hana

@Suite("Download directory access")
struct DownloadDirectoryTests {
    @Test("missing bookmark uses the application directory")
    func missingBookmark() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(
            try HanaDownloadDirectoryPreference.resolvedExternalDirectory(defaults: defaults) == nil
        )
        #expect(HanaDownloadDirectoryPreference.displayName(defaults: defaults) == "应用目录")
    }

    @Test("stale bookmark requires reselection")
    func staleBookmark() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data([0x01]), forKey: HanaSettingsKey.downloadDirectoryBookmark)

        #expect {
            try HanaDownloadDirectoryPreference.resolvedExternalDirectory(
                defaults: defaults
            ) { _ in
                (URL(filePath: "/tmp/stale"), true)
            }
        } throws: { error in
            error as? HanaDownloadDirectoryError == .staleBookmark
        }
        #expect(HanaDownloadDirectoryPreference.displayName(defaults: defaults) == "需要重新选择")
    }

    @Test("bookmark resolution errors require reselection")
    func invalidBookmark() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data([0x02]), forKey: HanaSettingsKey.downloadDirectoryBookmark)

        #expect {
            try HanaDownloadDirectoryPreference.resolvedExternalDirectory(
                defaults: defaults
            ) { _ in
                throw TestError.invalidBookmark
            }
        } throws: { error in
            error as? HanaDownloadDirectoryError == .invalidBookmark
        }
    }

#if os(macOS)
    @Test("security-scoped bookmark survives persistence")
    func securityScopedBookmarkRoundTrip() throws {
        let fixture = try DownloadDirectoryFixture()
        defer { fixture.remove() }
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        try HanaDownloadDirectoryPreference.saveExternalDirectory(
            fixture.externalRoot,
            defaults: defaults
        )
        let resolvedDirectory = try HanaDownloadDirectoryPreference.resolvedExternalDirectory(
            defaults: defaults
        )
        let resolvedURL = try #require(resolvedDirectory)

        #expect(resolvedURL.standardizedFileURL == fixture.externalRoot.standardizedFileURL)
        #expect(resolvedURL.startAccessingSecurityScopedResource())
        resolvedURL.stopAccessingSecurityScopedResource()
    }
#endif

    @Test("denied access does not create external files")
    func deniedAccess() throws {
        let fixture = try DownloadDirectoryFixture()
        defer { fixture.remove() }
        try fixture.writeVideo(Data("source".utf8), under: fixture.defaultRoot)

        let store = fixture.makeStore(startAccessing: { _ in false })

        #expect(throws: HanaDownloadDirectoryError.accessDenied) {
            try store.exportDefaultDownloadsToExternalDirectory()
        }
        #expect(!fixture.fileManager.fileExists(atPath: fixture.externalDownloadsRoot.path))
    }

    @Test("denied access does not delete external files")
    func deniedDelete() throws {
        let fixture = try DownloadDirectoryFixture()
        defer { fixture.remove() }
        try fixture.writeVideo(Data("video".utf8), under: fixture.externalDownloadsRoot)
        let fileURL = fixture.videoURL(under: fixture.externalDownloadsRoot)
        let store = fixture.makeStore(startAccessing: { _ in false })

        #expect(throws: HanaDownloadDirectoryError.accessDenied) {
            try store.deleteLocalDownload(fileURL: fileURL)
        }
        #expect(fixture.fileManager.fileExists(atPath: fileURL.path))
    }

    @Test("default download deletion ignores an invalid external bookmark")
    func deleteDefaultDownloadWithInvalidExternalBookmark() throws {
        let fixture = try DownloadDirectoryFixture()
        defer { fixture.remove() }
        try fixture.writeVideo(Data("video".utf8), under: fixture.defaultRoot)
        let fileURL = fixture.videoURL(under: fixture.defaultRoot)
        var externalResolutionCount = 0
        var accessStartCount = 0
        let store = HanimeDownloadFileStore(
            fileManager: fixture.fileManager,
            externalDirectoryResolver: {
                externalResolutionCount += 1
                throw HanaDownloadDirectoryError.staleBookmark
            },
            defaultDownloadsRootURL: { _ in fixture.defaultRoot },
            startAccessingExternalDirectory: { _ in
                accessStartCount += 1
                return false
            }
        )

        try store.deleteLocalDownload(fileURL: fileURL)

        #expect(!fixture.fileManager.fileExists(atPath: fileURL.path))
        #expect(externalResolutionCount == 0)
        #expect(accessStartCount == 0)
    }

    @Test("missing transfer sources return zero files")
    func emptyTransfers() throws {
        let fixture = try DownloadDirectoryFixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()

        #expect(try store.exportDefaultDownloadsToExternalDirectory() == 0)
        #expect(try store.importExternalDownloadsToDefaultDirectory() == 0)
    }

    @Test("explicit transfers require an external directory")
    func transferRequiresExternalDirectory() throws {
        let fixture = try DownloadDirectoryFixture()
        defer { fixture.remove() }
        let store = HanimeDownloadFileStore(
            fileManager: fixture.fileManager,
            externalDirectoryResolver: { nil },
            defaultDownloadsRootURL: { _ in fixture.defaultRoot }
        )

        #expect(throws: HanaDownloadDirectoryError.directoryNotConfigured) {
            try store.exportDefaultDownloadsToExternalDirectory()
        }
        #expect(throws: HanaDownloadDirectoryError.directoryNotConfigured) {
            try store.importExternalDownloadsToDefaultDirectory()
        }
    }

    @Test("export overwrites files and balances scoped access")
    func exportDownloads() throws {
        let fixture = try DownloadDirectoryFixture()
        defer { fixture.remove() }
        let source = Data("new".utf8)
        try fixture.writeVideo(source, under: fixture.defaultRoot)
        try fixture.writeVideo(Data("old".utf8), under: fixture.externalDownloadsRoot)
        var started = 0
        var stopped = 0
        let store = fixture.makeStore(
            startAccessing: { _ in
                started += 1
                return true
            },
            stopAccessing: { _ in stopped += 1 }
        )

        let count = try store.exportDefaultDownloadsToExternalDirectory()

        #expect(count == 1)
        #expect(
            try Data(contentsOf: fixture.videoURL(under: fixture.externalDownloadsRoot)) == source
        )
        #expect(started == 1)
        #expect(stopped == 1)
    }

    @Test("import overwrites files and balances scoped access")
    func importDownloads() throws {
        let fixture = try DownloadDirectoryFixture()
        defer { fixture.remove() }
        let source = Data("external".utf8)
        try fixture.writeVideo(source, under: fixture.externalDownloadsRoot)
        try fixture.writeVideo(Data("local".utf8), under: fixture.defaultRoot)
        var started = 0
        var stopped = 0
        let store = fixture.makeStore(
            startAccessing: { _ in
                started += 1
                return true
            },
            stopAccessing: { _ in stopped += 1 }
        )

        let count = try store.importExternalDownloadsToDefaultDirectory()

        #expect(count == 1)
        #expect(try Data(contentsOf: fixture.videoURL(under: fixture.defaultRoot)) == source)
        #expect(started == 1)
        #expect(stopped == 1)
    }

    @Test("delete uses scoped access")
    func deleteDownload() throws {
        let fixture = try DownloadDirectoryFixture()
        defer { fixture.remove() }
        try fixture.writeVideo(Data("video".utf8), under: fixture.externalDownloadsRoot)
        let fileURL = fixture.videoURL(under: fixture.externalDownloadsRoot)
        var stopped = 0
        let store = fixture.makeStore(
            startAccessing: { _ in true },
            stopAccessing: { _ in stopped += 1 }
        )

        try store.deleteLocalDownload(fileURL: fileURL)

        #expect(!fixture.fileManager.fileExists(atPath: fileURL.path))
        #expect(stopped == 1)
    }

    @Test("missing download still uses scoped access and clears metadata")
    func deleteMissingDownload() throws {
        let fixture = try DownloadDirectoryFixture()
        defer { fixture.remove() }
        let fileURL = fixture.videoURL(under: fixture.externalDownloadsRoot)
        try fixture.writeManifest(for: fileURL)
        var started = 0
        var stopped = 0
        let store = fixture.makeStore(
            startAccessing: { _ in
                started += 1
                return true
            },
            stopAccessing: { _ in stopped += 1 }
        )

        try store.deleteLocalDownload(fileURL: fileURL)

        #expect(started == 1)
        #expect(stopped == 1)
        #expect(!fixture.fileManager.fileExists(atPath: fileURL.deletingLastPathComponent().path))
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "DownloadDirectoryTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }
}

private enum TestError: Error {
    case invalidBookmark
}

private final class DownloadDirectoryFixture {
    let fileManager = FileManager.default
    let root: URL
    let defaultRoot: URL
    let externalRoot: URL

    var externalDownloadsRoot: URL {
        externalRoot.appending(path: "HanaDownloads", directoryHint: .isDirectory)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(
                path: "HanaDownloadDirectoryTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defaultRoot = root.appending(path: "Application/HanaDownloads", directoryHint: .isDirectory)
        externalRoot = root.appending(path: "External", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: externalRoot, withIntermediateDirectories: true)
    }

    func makeStore(
        startAccessing: @escaping (URL) -> Bool = { _ in true },
        stopAccessing: @escaping (URL) -> Void = { _ in }
    ) -> HanimeDownloadFileStore {
        HanimeDownloadFileStore(
            fileManager: fileManager,
            externalDirectoryResolver: { self.externalRoot },
            defaultDownloadsRootURL: { create in
                if create {
                    try self.fileManager.createDirectory(
                        at: self.defaultRoot,
                        withIntermediateDirectories: true
                    )
                }
                return self.defaultRoot
            },
            startAccessingExternalDirectory: startAccessing,
            stopAccessingExternalDirectory: stopAccessing
        )
    }

    func writeVideo(_ data: Data, under downloadsRoot: URL) throws {
        let url = videoURL(under: downloadsRoot)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    func writeManifest(for fileURL: URL) throws {
        let folderURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let manifest = HanimeDownloadManifest(
            videoCode: "video-code",
            title: "Video",
            coverURLString: nil,
            items: [
                HanimeDownloadManifestItem(
                    quality: "1080P",
                    sourceURLString: "https://example.com/video.mp4",
                    fileName: fileURL.lastPathComponent,
                    byteCount: 5,
                    completedAt: Date(timeIntervalSince1970: 1)
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: folderURL.appending(path: "info.json", directoryHint: .notDirectory))
    }

    func videoURL(under downloadsRoot: URL) -> URL {
        downloadsRoot.appending(path: "video-code/1080P.mp4", directoryHint: .notDirectory)
    }

    func remove() {
        try? fileManager.removeItem(at: root)
    }
}
