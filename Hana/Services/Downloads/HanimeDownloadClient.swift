import Foundation
import Observation

nonisolated struct HanimeDownloadRequest: Codable, Sendable {
    let id: String
    let videoCode: String
    let title: String
    let coverURLString: String?
    let quality: String
    let mediaURL: URL
}

nonisolated struct HanimeDownloadedFile: Sendable {
    let fileURL: URL
    let byteCount: Int64?
}

nonisolated struct HanimeLocalDownload: Identifiable, Hashable, Sendable {
    var id: String { "\(videoCode)-\(quality)-\(fileURL.absoluteString)" }

    let videoCode: String
    let title: String?
    let coverURLString: String?
    let quality: String
    let sourceURLString: String?
    let fileURL: URL
    let byteCount: Int64?
    let completedAt: Date?
}

nonisolated enum HanimeDownloadTaskStatus: String, Codable, Sendable {
    case queued
    case running
    case paused
    case completed
    case failed
    case cancelled

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .failed
    }
}

nonisolated enum HanimeDownloadFailureKind: String, Codable, Sendable {
    case transient
    case permanent
}

nonisolated enum HanimeDownloadError: LocalizedError, Sendable {
    case paused
    case alreadyScheduled

    var errorDescription: String? {
        switch self {
        case .paused:
            "下载已暂停"
        case .alreadyScheduled:
            "下载任务已在队列中"
        }
    }
}

nonisolated struct HanimePersistedDownloadTask: Codable, Identifiable, Sendable {
    let id: String
    var request: HanimeDownloadRequest
    var sessionIdentifier: String
    var taskIdentifier: Int?
    var status: HanimeDownloadTaskStatus
    var progress: Double
    var downloadedByteCount: Int64?
    var expectedByteCount: Int64?
    var localFileURLString: String?
    var errorDescription: String?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var notificationSentAt: Date?
    var resumeData: Data? = nil
    var failureKind: HanimeDownloadFailureKind? = nil
    var queuePosition: Int64? = nil
    var createdFromResumeData: Bool? = nil
}

nonisolated struct HanimeDownloadManifest: Codable, Sendable {
    var schemaVersion: Int = 1
    var videoCode: String
    var title: String
    var coverURLString: String?
    var items: [HanimeDownloadManifestItem]
}

nonisolated struct HanimeDownloadManifestItem: Codable, Identifiable, Sendable {
    var id: String { fileName }

    var quality: String
    var sourceURLString: String
    var fileName: String
    var byteCount: Int64?
    var completedAt: Date
}

nonisolated final class HanimeDownloadDirectoryAccess {
    private let stopAccessing: () -> Void
    private var isActive = true

    init(stopAccessing: @escaping () -> Void) {
        self.stopAccessing = stopAccessing
    }

    func invalidate() {
        guard isActive else { return }
        isActive = false
        stopAccessing()
    }

    deinit {
        invalidate()
    }
}

nonisolated struct HanimeDownloadFileStore {
    let fileManager: FileManager
    private let externalDirectoryResolver: () throws -> URL?
    private let defaultDownloadsRootURLOverride: ((Bool) throws -> URL)?
    private let startAccessingExternalDirectory: (URL) -> Bool
    private let stopAccessingExternalDirectory: (URL) -> Void

    init(
        fileManager: FileManager = .default,
        externalDirectoryResolver: @escaping () throws -> URL? = {
            try HanaDownloadDirectoryPreference.resolvedExternalDirectory()
        },
        defaultDownloadsRootURL: ((Bool) throws -> URL)? = nil,
        startAccessingExternalDirectory: @escaping (URL) -> Bool = {
            $0.startAccessingSecurityScopedResource()
        },
        stopAccessingExternalDirectory: @escaping (URL) -> Void = {
            $0.stopAccessingSecurityScopedResource()
        }
    ) {
        self.fileManager = fileManager
        self.externalDirectoryResolver = externalDirectoryResolver
        self.defaultDownloadsRootURLOverride = defaultDownloadsRootURL
        self.startAccessingExternalDirectory = startAccessingExternalDirectory
        self.stopAccessingExternalDirectory = stopAccessingExternalDirectory
    }

    func moveDownloadedFile(
        from temporaryURL: URL,
        response: HTTPURLResponse,
        request: HanimeDownloadRequest
    ) throws -> HanimeDownloadedFile {
        try withDownloadsRootURL(create: true) { downloadsURL in
            let destinationURL = try destinationURL(for: request, response: response, downloadsURL: downloadsURL)
            let folderURL = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)

            let values = try? destinationURL.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = values?.fileSize.map(Int64.init)
            try writeManifest(for: request, fileURL: destinationURL, byteCount: byteCount)
            return HanimeDownloadedFile(fileURL: destinationURL, byteCount: byteCount)
        }
    }

    func localDownloads() throws -> [HanimeLocalDownload] {
        try withDownloadsRootURL(create: false) { downloadsURL in
            guard fileManager.fileExists(atPath: downloadsURL.path) else {
                return []
            }

            let videoFolders = try fileManager.contentsOfDirectory(
                at: downloadsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var files = [HanimeLocalDownload]()
            for folderURL in videoFolders {
                let values = try? folderURL.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory == true else { continue }
                let videoCode = folderURL.lastPathComponent
                let manifest = try? readManifest(in: folderURL)
                let metadataByFileName = Dictionary(
                    uniqueKeysWithValues: (manifest?.items ?? []).map { ($0.fileName, $0) }
                )
                let fileURLs = try fileManager.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
                for fileURL in fileURLs where Self.videoFileExtensions.contains(fileURL.pathExtension.lowercased()) {
                    let fileValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
                    let metadata = metadataByFileName[fileURL.lastPathComponent]
                    files.append(HanimeLocalDownload(
                        videoCode: videoCode,
                        title: manifest?.title,
                        coverURLString: manifest?.coverURLString,
                        quality: metadata?.quality ?? fileURL.deletingPathExtension().lastPathComponent,
                        sourceURLString: metadata?.sourceURLString,
                        fileURL: fileURL,
                        byteCount: metadata?.byteCount ?? fileValues?.fileSize.map(Int64.init),
                        completedAt: metadata?.completedAt
                    ))
                }
            }

            return files.sorted {
                if $0.videoCode == $1.videoCode {
                    return $0.quality > $1.quality
                }
                return $0.videoCode > $1.videoCode
            }
        }
    }

    func beginExternalDirectoryAccess() throws -> HanimeDownloadDirectoryAccess? {
        guard let externalURL = try externalDirectoryResolver() else {
            return nil
        }
        guard startAccessingExternalDirectory(externalURL) else {
            throw HanaDownloadDirectoryError.accessDenied
        }
        return HanimeDownloadDirectoryAccess {
            stopAccessingExternalDirectory(externalURL)
        }
    }

    func deleteLocalDownload(fileURL: URL) throws {
        try withDownloadFileAccess(fileURL: fileURL) {
            let folderURL = fileURL.deletingLastPathComponent()
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }

            if var manifest = try? readManifest(in: folderURL) {
                manifest.items.removeAll { $0.fileName == fileURL.lastPathComponent }
                if manifest.items.isEmpty {
                    try? fileManager.removeItem(at: manifestURL(in: folderURL))
                } else {
                    try writeManifest(manifest, in: folderURL)
                }
            }

            let remaining = (try? fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            let hasRemainingVideo = remaining.contains { Self.videoFileExtensions.contains($0.pathExtension.lowercased()) }
            if !hasRemainingVideo {
                try? fileManager.removeItem(at: folderURL)
            }
        }
    }

    func exportDefaultDownloadsToExternalDirectory() throws -> Int {
        guard let externalURL = try externalDirectoryResolver() else {
            throw HanaDownloadDirectoryError.directoryNotConfigured
        }
        let sourceURL = try defaultDownloadsRootURL(create: false)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return 0
        }
        return try withExternalDirectoryAccess(externalURL) {
            let destinationURL = externalURL.appending(path: "HanaDownloads", directoryHint: .isDirectory)
            guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else {
                return 0
            }
            return try copyDirectoryContents(from: sourceURL, to: destinationURL)
        }
    }

    func importExternalDownloadsToDefaultDirectory() throws -> Int {
        guard let externalURL = try externalDirectoryResolver() else {
            throw HanaDownloadDirectoryError.directoryNotConfigured
        }
        return try withExternalDirectoryAccess(externalURL) {
            let sourceURL = externalURL.appending(path: "HanaDownloads", directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                return 0
            }
            let destinationURL = try defaultDownloadsRootURL(create: true)
            return try copyDirectoryContents(from: sourceURL, to: destinationURL)
        }
    }

    private func destinationURL(
        for request: HanimeDownloadRequest,
        response: HTTPURLResponse,
        downloadsURL: URL
    ) throws -> URL {
        let videoFolderURL = downloadsURL.appending(path: request.videoCode, directoryHint: .isDirectory)
        let fileName = "\(safeFileName(request.quality)).\(fileExtension(for: request, response: response))"
        return videoFolderURL.appending(path: fileName, directoryHint: .notDirectory)
    }

    private func withDownloadsRootURL<T>(create: Bool, _ body: (URL) throws -> T) throws -> T {
        if let externalURL = try externalDirectoryResolver() {
            return try withExternalDirectoryAccess(externalURL) {
                let downloadsURL = externalURL.appending(path: "HanaDownloads", directoryHint: .isDirectory)
                if create {
                    try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
                }
                return try body(downloadsURL)
            }
        }

        let downloadsURL = try defaultDownloadsRootURL(create: create)
        return try body(downloadsURL)
    }

    private func withDownloadFileAccess<T>(fileURL: URL, _ body: () throws -> T) throws -> T {
        let defaultDownloadsURL = try defaultDownloadsRootURL(create: false)
        if isDescendant(fileURL, of: defaultDownloadsURL) {
            return try body()
        }

        guard let externalURL = try externalDirectoryResolver() else {
            return try body()
        }
        let externalDownloadsURL = externalURL.appending(path: "HanaDownloads", directoryHint: .isDirectory)
        guard isDescendant(fileURL, of: externalDownloadsURL) else {
            return try body()
        }
        return try withExternalDirectoryAccess(externalURL, body)
    }

    private func isDescendant(_ fileURL: URL, of directoryURL: URL) -> Bool {
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        let directoryComponents = directoryURL.standardizedFileURL.pathComponents
        guard fileComponents.count > directoryComponents.count else { return false }
        return fileComponents.prefix(directoryComponents.count).elementsEqual(directoryComponents)
    }

    private func withExternalDirectoryAccess<T>(_ url: URL, _ body: () throws -> T) throws -> T {
        guard startAccessingExternalDirectory(url) else {
            throw HanaDownloadDirectoryError.accessDenied
        }
        defer { stopAccessingExternalDirectory(url) }
        return try body()
    }

    private func defaultDownloadsRootURL(create: Bool) throws -> URL {
        if let defaultDownloadsRootURLOverride {
            return try defaultDownloadsRootURLOverride(create)
        }
        let rootURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        return rootURL.appending(path: "HanaDownloads", directoryHint: .isDirectory)
    }

    private func copyDirectoryContents(from sourceURL: URL, to destinationURL: URL) throws -> Int {
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let entries = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var copiedCount = 0
        for sourceEntry in entries {
            let destinationEntry = destinationURL.appendingPathComponent(sourceEntry.lastPathComponent)
            if fileManager.fileExists(atPath: destinationEntry.path) {
                try fileManager.removeItem(at: destinationEntry)
            }
            try fileManager.copyItem(at: sourceEntry, to: destinationEntry)
            copiedCount += try countVideoFiles(in: destinationEntry)
        }
        return copiedCount
    }

    private func countVideoFiles(in url: URL) throws -> Int {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else {
            return Self.videoFileExtensions.contains(url.pathExtension.lowercased()) ? 1 : 0
        }

        let entries = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try entries.reduce(0) { total, entry in
            try total + countVideoFiles(in: entry)
        }
    }

    private func fileExtension(
        for request: HanimeDownloadRequest,
        response: HTTPURLResponse
    ) -> String {
        let pathExtension = request.mediaURL.pathExtension
        if !pathExtension.isEmpty {
            return pathExtension
        }

        guard let mimeType = response.mimeType?.lowercased() else {
            return "mp4"
        }
        if mimeType.contains("mpegurl") {
            return "m3u8"
        }
        if let subtype = mimeType.split(separator: "/").last, !subtype.isEmpty {
            return String(subtype)
        }
        return "mp4"
    }

    private func writeManifest(
        for request: HanimeDownloadRequest,
        fileURL: URL,
        byteCount: Int64?
    ) throws {
        let folderURL = fileURL.deletingLastPathComponent()
        var manifest = (try? readManifest(in: folderURL)) ?? HanimeDownloadManifest(
            videoCode: request.videoCode,
            title: request.title,
            coverURLString: request.coverURLString,
            items: []
        )
        manifest.videoCode = request.videoCode
        manifest.title = request.title
        manifest.coverURLString = request.coverURLString

        let item = HanimeDownloadManifestItem(
            quality: request.quality,
            sourceURLString: request.mediaURL.absoluteString,
            fileName: fileURL.lastPathComponent,
            byteCount: byteCount,
            completedAt: .now
        )
        manifest.items.removeAll { $0.fileName == item.fileName || $0.quality == item.quality }
        manifest.items.append(item)
        manifest.items.sort { $0.quality > $1.quality }

        try writeManifest(manifest, in: folderURL)
    }

    private func readManifest(in folderURL: URL) throws -> HanimeDownloadManifest {
        let data = try Data(contentsOf: manifestURL(in: folderURL))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HanimeDownloadManifest.self, from: data)
    }

    private func writeManifest(_ manifest: HanimeDownloadManifest, in folderURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL(in: folderURL), options: .atomic)
    }

    private func manifestURL(in folderURL: URL) -> URL {
        folderURL.appending(path: "info.json", directoryHint: .notDirectory)
    }

    private func safeFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let parts = value.components(separatedBy: invalidCharacters)
        let fileName = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return fileName.isEmpty ? "video" : fileName
    }

    private static let videoFileExtensions: Set<String> = [
        "mp4", "m4v", "mov", "m3u8", "ts"
    ]
}

nonisolated struct HanimeDownloadTaskStateStore {
    let fileManager: FileManager
    let stateDirectoryURLOverride: URL?

    init(fileManager: FileManager = .default, stateDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.stateDirectoryURLOverride = stateDirectoryURL
    }

    func allTasks() throws -> [HanimePersistedDownloadTask] {
        try readTasks().sorted { $0.updatedAt > $1.updatedAt }
    }

    func task(id: String) throws -> HanimePersistedDownloadTask? {
        try readTasks().first { $0.id == id }
    }

    @discardableResult
    func markQueued(
        request: HanimeDownloadRequest,
        sessionIdentifier: String,
        clearResumeData: Bool = false,
        errorDescription: String? = nil,
        preserveQueuePosition: Bool = false,
        atFront: Bool = false
    ) throws -> HanimePersistedDownloadTask {
        var tasks = try readTasks()
        let now = Date()
        let previous = tasks.first { $0.id == request.id }
        var task = previous ?? HanimePersistedDownloadTask(
            id: request.id,
            request: request,
            sessionIdentifier: sessionIdentifier,
            taskIdentifier: nil,
            status: .queued,
            progress: 0,
            downloadedByteCount: nil,
            expectedByteCount: nil,
            localFileURLString: nil,
            errorDescription: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            notificationSentAt: nil
        )
        task.request = request
        task.sessionIdentifier = sessionIdentifier
        task.taskIdentifier = nil
        task.status = .queued
        task.localFileURLString = nil
        task.errorDescription = errorDescription
        task.failureKind = nil
        task.createdFromResumeData = nil
        task.updatedAt = now
        task.completedAt = nil
        task.notificationSentAt = nil
        if !preserveQueuePosition || task.queuePosition == nil {
            task.queuePosition = nextQueuePosition(in: tasks, atFront: atFront)
        }
        if clearResumeData {
            task.resumeData = nil
        }
        if task.resumeData == nil {
            resetTransferState(&task)
        }
        replace(task, in: &tasks)
        try writeTasks(tasks)
        return task
    }

    @discardableResult
    func markRunning(
        request: HanimeDownloadRequest,
        taskIdentifier: Int,
        sessionIdentifier: String,
        downloadedByteCount: Int64? = nil,
        expectedByteCount: Int64? = nil,
        createdFromResumeData: Bool = false
    ) throws -> HanimePersistedDownloadTask {
        var tasks = try readTasks()
        let now = Date()
        let previous = tasks.first { $0.id == request.id }
        var task = previous ?? HanimePersistedDownloadTask(
            id: request.id,
            request: request,
            sessionIdentifier: sessionIdentifier,
            taskIdentifier: taskIdentifier,
            status: .running,
            progress: 0,
            downloadedByteCount: nil,
            expectedByteCount: nil,
            localFileURLString: nil,
            errorDescription: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            notificationSentAt: nil
        )
        task.request = request
        task.sessionIdentifier = sessionIdentifier
        task.taskIdentifier = taskIdentifier
        task.status = .running
        task.downloadedByteCount = downloadedByteCount ?? task.downloadedByteCount
        task.expectedByteCount = expectedByteCount ?? task.expectedByteCount
        task.progress = progress(downloaded: task.downloadedByteCount, expected: task.expectedByteCount) ?? task.progress
        task.localFileURLString = nil
        task.resumeData = nil
        task.failureKind = nil
        task.queuePosition = nil
        task.createdFromResumeData = createdFromResumeData
        task.updatedAt = now
        task.completedAt = nil
        replace(task, in: &tasks)
        try writeTasks(tasks)
        return task
    }

    @discardableResult
    func updateProgress(
        requestID: String,
        taskIdentifier: Int,
        downloadedByteCount: Int64,
        expectedByteCount: Int64
    ) throws -> HanimePersistedDownloadTask? {
        var tasks = try readTasks()
        guard var task = tasks.first(where: { $0.id == requestID }) else {
            return nil
        }
        task.taskIdentifier = taskIdentifier
        task.status = .running
        task.downloadedByteCount = downloadedByteCount
        task.expectedByteCount = expectedByteCount > 0 ? expectedByteCount : nil
        task.progress = progress(downloaded: downloadedByteCount, expected: task.expectedByteCount) ?? task.progress
        task.updatedAt = .now
        replace(task, in: &tasks)
        try writeTasks(tasks)
        return task
    }

    @discardableResult
    func updateResumedProgress(
        requestID: String,
        taskIdentifier: Int,
        fileOffset: Int64,
        expectedByteCount: Int64
    ) throws -> HanimePersistedDownloadTask? {
        var tasks = try readTasks()
        guard var task = tasks.first(where: { $0.id == requestID }) else {
            return nil
        }
        let previousDownloadedByteCount = task.downloadedByteCount ?? 0
        task.taskIdentifier = taskIdentifier
        task.status = .running
        task.downloadedByteCount = fileOffset
        task.expectedByteCount = expectedByteCount > 0 ? expectedByteCount : nil
        task.progress = progress(downloaded: fileOffset, expected: task.expectedByteCount) ?? task.progress
        task.errorDescription = fileOffset == 0 && previousDownloadedByteCount > 0
            ? "服务器不支持继续旧进度，已从头开始下载。"
            : nil
        task.updatedAt = .now
        replace(task, in: &tasks)
        try writeTasks(tasks)
        return task
    }

    @discardableResult
    func markPaused(
        requestID: String,
        resumeData: Data?,
        preserveQueuePosition: Bool = false
    ) throws -> HanimePersistedDownloadTask? {
        var tasks = try readTasks()
        guard var task = tasks.first(where: { $0.id == requestID }) else {
            return nil
        }
        task.taskIdentifier = nil
        task.status = .paused
        task.resumeData = resumeData
        task.failureKind = nil
        task.createdFromResumeData = nil
        if !preserveQueuePosition {
            task.queuePosition = nil
        }
        task.localFileURLString = nil
        task.errorDescription = resumeData == nil
            ? "服务器未提供可恢复数据，再次开始会从头下载。"
            : nil
        task.updatedAt = .now
        task.completedAt = nil
        if resumeData == nil {
            resetTransferState(&task)
        }
        replace(task, in: &tasks)
        try writeTasks(tasks)
        return task
    }

    @discardableResult
    func markFailed(
        requestID: String,
        failureKind: HanimeDownloadFailureKind,
        errorDescription: String,
        resumeData: Data?
    ) throws -> HanimePersistedDownloadTask? {
        var tasks = try readTasks()
        guard var task = tasks.first(where: { $0.id == requestID }) else {
            return nil
        }
        task.taskIdentifier = nil
        task.status = .failed
        task.resumeData = resumeData
        task.failureKind = failureKind
        task.queuePosition = nil
        task.createdFromResumeData = nil
        task.localFileURLString = nil
        task.errorDescription = resumeData == nil
            ? "\(errorDescription)\n再次开始会从头下载。"
            : errorDescription
        task.updatedAt = .now
        task.completedAt = nil
        if resumeData == nil {
            resetTransferState(&task)
        }
        replace(task, in: &tasks)
        try writeTasks(tasks)
        return task
    }

    @discardableResult
    func markCancelled(requestID: String) throws -> HanimePersistedDownloadTask? {
        var tasks = try readTasks()
        guard var task = tasks.first(where: { $0.id == requestID }) else {
            return nil
        }
        task.taskIdentifier = nil
        task.status = .cancelled
        task.localFileURLString = nil
        task.errorDescription = nil
        task.failureKind = nil
        task.queuePosition = nil
        task.createdFromResumeData = nil
        task.updatedAt = .now
        task.completedAt = nil
        task.resumeData = nil
        resetTransferState(&task)
        replace(task, in: &tasks)
        try writeTasks(tasks)
        return task
    }

    @discardableResult
    func markCompleted(
        request: HanimeDownloadRequest,
        taskIdentifier: Int,
        sessionIdentifier: String,
        file: HanimeDownloadedFile
    ) throws -> HanimePersistedDownloadTask {
        var tasks = try readTasks()
        let now = Date()
        var task = tasks.first { $0.id == request.id } ?? HanimePersistedDownloadTask(
            id: request.id,
            request: request,
            sessionIdentifier: sessionIdentifier,
            taskIdentifier: taskIdentifier,
            status: .completed,
            progress: 1,
            downloadedByteCount: file.byteCount,
            expectedByteCount: file.byteCount,
            localFileURLString: file.fileURL.absoluteString,
            errorDescription: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: now,
            notificationSentAt: nil
        )
        task.request = request
        task.sessionIdentifier = sessionIdentifier
        task.taskIdentifier = taskIdentifier
        task.status = .completed
        task.progress = 1
        task.downloadedByteCount = file.byteCount ?? task.downloadedByteCount
        task.expectedByteCount = file.byteCount ?? task.expectedByteCount
        task.localFileURLString = file.fileURL.absoluteString
        task.errorDescription = nil
        task.resumeData = nil
        task.failureKind = nil
        task.queuePosition = nil
        task.createdFromResumeData = nil
        task.updatedAt = now
        task.completedAt = now
        replace(task, in: &tasks)
        try writeTasks(tasks)
        return task
    }

    func markNotificationSent(requestID: String, sentAt: Date) throws {
        var tasks = try readTasks()
        guard var task = tasks.first(where: { $0.id == requestID }) else { return }
        task.notificationSentAt = sentAt
        task.updatedAt = .now
        replace(task, in: &tasks)
        try writeTasks(tasks)
    }

    func removeTask(requestID: String) throws {
        var tasks = try readTasks()
        tasks.removeAll { $0.id == requestID }
        try writeTasks(tasks)
    }

    @discardableResult
    func markRequeuePending(requestID: String) throws -> HanimePersistedDownloadTask? {
        var tasks = try readTasks()
        guard var task = tasks.first(where: { $0.id == requestID }) else {
            return nil
        }
        task.queuePosition = nextQueuePosition(in: tasks, atFront: false)
        task.updatedAt = .now
        replace(task, in: &tasks)
        try writeTasks(tasks)
        return task
    }

    private func replace(_ task: HanimePersistedDownloadTask, in tasks: inout [HanimePersistedDownloadTask]) {
        tasks.removeAll { $0.id == task.id }
        tasks.append(task)
    }

    private func resetTransferState(_ task: inout HanimePersistedDownloadTask) {
        task.progress = 0
        task.downloadedByteCount = nil
        task.expectedByteCount = nil
    }

    private func progress(downloaded: Int64?, expected: Int64?) -> Double? {
        guard let downloaded,
              let expected,
              expected > 0 else {
            return nil
        }
        return min(max(Double(downloaded) / Double(expected), 0), 1)
    }

    private func nextQueuePosition(
        in tasks: [HanimePersistedDownloadTask],
        atFront: Bool
    ) -> Int64 {
        let positions = tasks.compactMap(\.queuePosition)
        if atFront {
            guard let position = positions.min() else { return 0 }
            return position == .min ? .min : position - 1
        }
        guard let position = positions.max() else { return 0 }
        return position == .max ? .max : position + 1
    }

    private func readTasks() throws -> [HanimePersistedDownloadTask] {
        let url = try stateURL(create: false)
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HanimePersistedDownloadTask].self, from: data)
    }

    private func writeTasks(_ tasks: [HanimePersistedDownloadTask]) throws {
        let url = try stateURL(create: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tasks.sorted { $0.createdAt < $1.createdAt })
        try data.write(to: url, options: .atomic)
    }

    private func stateURL(create: Bool) throws -> URL {
        let rootURL: URL
        if let stateDirectoryURLOverride {
            rootURL = stateDirectoryURLOverride
        } else {
            rootURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: create
            ).appending(path: "HanaDownloads", directoryHint: .isDirectory)
        }
        if create {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        return rootURL.appending(path: "tasks.json", directoryHint: .notDirectory)
    }
}

private final class HanimeBackgroundDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private weak var client: HanimeDownloadClient?
    private let fileStore: HanimeDownloadFileStore

    init(client: HanimeDownloadClient, fileStore: HanimeDownloadFileStore) {
        self.client = client
        self.fileStore = fileStore
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let request = HanimeDownloadClient.request(from: downloadTask),
              totalBytesExpectedToWrite > 0 else {
            return
        }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor [weak client] in
            client?.updateProgress(
                requestID: request.id,
                taskIdentifier: downloadTask.taskIdentifier,
                fraction: fraction,
                downloadedByteCount: totalBytesWritten,
                expectedByteCount: totalBytesExpectedToWrite
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        guard let request = HanimeDownloadClient.request(from: downloadTask) else {
            return
        }
        Task { @MainActor [weak client] in
            client?.updateResumedProgress(
                requestID: request.id,
                taskIdentifier: downloadTask.taskIdentifier,
                fileOffset: fileOffset,
                expectedByteCount: expectedTotalBytes
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let request = HanimeDownloadClient.request(from: downloadTask),
              let response = downloadTask.response as? HTTPURLResponse else {
            Task { @MainActor [weak client] in
                client?.completeTask(
                    taskIdentifier: downloadTask.taskIdentifier,
                    requestID: nil,
                    error: HanaNetworkError.invalidResponse
                )
            }
            return
        }

        do {
            guard (200..<300).contains(response.statusCode) else {
                throw HanaNetworkError.httpStatus(response.statusCode, request.mediaURL)
            }
            let file = try fileStore.moveDownloadedFile(
                from: location,
                response: response,
                request: request
            )
            Task { @MainActor [weak client] in
                client?.completeTask(
                    taskIdentifier: downloadTask.taskIdentifier,
                    request: request,
                    file: file
                )
            }
        } catch {
            Task { @MainActor [weak client] in
                client?.completeTask(
                    taskIdentifier: downloadTask.taskIdentifier,
                    requestID: request.id,
                    error: error
                )
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let requestID = HanimeDownloadClient.request(from: task)?.id
        guard let error else {
            Task { @MainActor [weak client] in
                client?.completeTask(
                    taskIdentifier: task.taskIdentifier,
                    requestID: requestID,
                    error: nil
                )
            }
            return
        }

        Task { @MainActor [weak client] in
            client?.completeTask(
                taskIdentifier: task.taskIdentifier,
                requestID: requestID,
                error: error
            )
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            HanimeDownloadClient.finishBackgroundEvents(identifier: session.configuration.identifier ?? "")
        }
    }
}

private enum HanimeDownloadTaskIntent {
    case pause
    case cancel
    case requeue
}

private enum HanimeDownloadTaskCreationMode {
    case fresh
    case resumed
}

@Observable
final class HanimeDownloadClient {
    static let backgroundSessionIdentifier = "com.kanscape.Hana.downloads"
    private static let backgroundEventsNotification = Notification.Name("HanaDownloadClientBackgroundEvents")

    private let httpClient: HanaHTTPClient
    private let defaults: UserDefaults
    private let sessionConfigurationOverride: URLSessionConfiguration?
    private let backgroundTasksProviderOverride: (@Sendable () async -> [URLSessionTask])?
    private let fileStore: HanimeDownloadFileStore
    private let stateStore: HanimeDownloadTaskStateStore
    @ObservationIgnored private lazy var backgroundDelegate = HanimeBackgroundDownloadDelegate(
        client: self,
        fileStore: fileStore
    )
    @ObservationIgnored private lazy var backgroundSession: URLSession = makeBackgroundSession()
    @ObservationIgnored private var backgroundEventsObserver: NSObjectProtocol?
    @ObservationIgnored private var externalDirectoryAccess: HanimeDownloadDirectoryAccess?
    @ObservationIgnored private var externalDirectoryAccessFailure: HanaDownloadDirectoryError?
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var pendingRequestIDs: [String] = []
    private var pendingRequests: [String: HanimeDownloadRequest] = [:]
    private var activeRequestIDsInStartOrder: [String] = []
    private var progressByID: [String: Double] = [:]
    private var continuationsByRequestID: [String: CheckedContinuation<HanimeDownloadedFile, Error>] = [:]
    private var requestIDsByTaskID: [Int: String] = [:]
    private var taskIntentsByTaskID: [Int: HanimeDownloadTaskIntent] = [:]
    private var taskCreationModesByTaskID: [Int: HanimeDownloadTaskCreationMode] = [:]
    private var finalizedTaskIDs = Set<Int>()
    @ObservationIgnored private var backgroundTaskRestoration: Task<Void, Never>?
    @ObservationIgnored private var didRestoreBackgroundTasks = false
    private static var backgroundCompletionHandlers: [String: () -> Void] = [:]

    init(
        httpClient: HanaHTTPClient,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        downloadsRootURL: URL? = nil,
        sessionConfiguration: URLSessionConfiguration? = nil,
        backgroundTasksProvider: (@Sendable () async -> [URLSessionTask])? = nil
    ) {
        self.httpClient = httpClient
        self.defaults = defaults
        self.sessionConfigurationOverride = sessionConfiguration
        self.backgroundTasksProviderOverride = backgroundTasksProvider

        let defaultDownloadsRootURL: ((Bool) throws -> URL)? = downloadsRootURL.map { rootURL in
            { create in
                if create {
                    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
                }
                return rootURL
            }
        }
        let fileStore = HanimeDownloadFileStore(
            fileManager: fileManager,
            externalDirectoryResolver: {
                try HanaDownloadDirectoryPreference.resolvedExternalDirectory(defaults: defaults)
            },
            defaultDownloadsRootURL: defaultDownloadsRootURL
        )
        self.fileStore = fileStore
        self.stateStore = HanimeDownloadTaskStateStore(
            fileManager: fileManager,
            stateDirectoryURL: downloadsRootURL
        )
        do {
            self.externalDirectoryAccess = try fileStore.beginExternalDirectoryAccess()
        } catch {
            self.externalDirectoryAccess = nil
            self.externalDirectoryAccessFailure = Self.directoryAccessError(from: error)
        }
        self.backgroundEventsObserver = NotificationCenter.default.addObserver(
            forName: Self.backgroundEventsNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.activateBackgroundSession()
        }
        activateBackgroundSession()
    }

    deinit {
        externalDirectoryAccess?.invalidate()
        if let backgroundEventsObserver {
            NotificationCenter.default.removeObserver(backgroundEventsObserver)
        }
    }

    func download(
        _ request: HanimeDownloadRequest,
        onTaskCreated: ((HanimePersistedDownloadTask) -> Void)? = nil
    ) async throws -> HanimeDownloadedFile {
        await restoreBackgroundTasks()
        try Task.checkCancellation()

        guard activeTasks[request.id] == nil,
              pendingRequests[request.id] == nil,
              continuationsByRequestID[request.id] == nil else {
            throw HanimeDownloadError.alreadyScheduled
        }

        let snapshot = try stateStore.markQueued(
            request: request,
            sessionIdentifier: Self.backgroundSessionIdentifier
        )
        onTaskCreated?(snapshot)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuationsByRequestID[request.id] = continuation
                enqueue(request)
                schedulePendingDownloads()
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel(id: request.id)
            }
        }
    }

    func progress(for id: String) -> Double? {
        progressByID[id]
    }

    func isDownloading(id: String) -> Bool {
        activeTasks[id] != nil || pendingRequests[id] != nil
    }

    var hasActiveDownloads: Bool {
        !activeTasks.isEmpty || !pendingRequests.isEmpty
    }

    var activeDownloadCount: Int {
        activeTasks.count
    }

    var pendingDownloadIDs: [String] {
        pendingRequestIDs
    }

    func pause(id: String) {
        if let task = activeTasks[id] {
            let taskIdentifier = task.taskIdentifier
            if taskIntentsByTaskID[taskIdentifier] == .requeue {
                removePendingRequest(id: id)
                taskIntentsByTaskID[taskIdentifier] = .pause
                return
            }
            taskIntentsByTaskID[taskIdentifier] = .pause
            task.cancel(byProducingResumeData: { [self] resumeData in
                Task { @MainActor [self] in
                    self.finishPausedTask(
                        taskIdentifier: taskIdentifier,
                        requestID: id,
                        resumeData: resumeData
                    )
                }
            })
            return
        }

        if pendingRequests[id] != nil {
            removePendingRequest(id: id)
            _ = try? stateStore.markPaused(
                requestID: id,
                resumeData: persistedTask(id: id)?.resumeData
            )
            resumeContinuation(requestID: id, throwing: HanimeDownloadError.paused)
            schedulePendingDownloads()
        }
    }

    func cancel(id: String) {
        if let task = activeTasks[id] {
            removePendingRequest(id: id)
            taskIntentsByTaskID[task.taskIdentifier] = .cancel
            task.cancel()
            finishCancelledTask(taskIdentifier: task.taskIdentifier, requestID: id)
            return
        }

        if pendingRequests[id] != nil {
            removePendingRequest(id: id)
            _ = try? stateStore.markCancelled(requestID: id)
            resumeContinuation(requestID: id, throwing: CancellationError())
            schedulePendingDownloads()
            return
        }

        _ = try? stateStore.markCancelled(requestID: id)
    }

    func remove(id: String) {
        cancel(id: id)
        try? stateStore.removeTask(requestID: id)
    }

    func downloadConcurrencyDidChange() {
        enforceConcurrencyLimit()
        schedulePendingDownloads()
    }

    func deleteLocalDownload(fileURL: URL) throws {
        do {
            try fileStore.deleteLocalDownload(fileURL: fileURL)
        } catch {
            recordDirectoryAccessFailure(from: error)
            throw error
        }
    }

    func localDownloads() throws -> [HanimeLocalDownload] {
        do {
            return try fileStore.localDownloads()
        } catch {
            recordDirectoryAccessFailure(from: error)
            throw error
        }
    }

    func refreshExternalDirectoryAccess() throws {
        do {
            let nextAccess = try fileStore.beginExternalDirectoryAccess()
            externalDirectoryAccess?.invalidate()
            externalDirectoryAccess = nextAccess
            externalDirectoryAccessFailure = nil
        } catch {
            recordDirectoryAccessFailure(from: error)
            throw error
        }
    }

    var externalDirectoryAccessError: HanaDownloadDirectoryError? {
        externalDirectoryAccessFailure
    }

    func exportDownloadsToExternalDirectory() throws -> Int {
        do {
            return try fileStore.exportDefaultDownloadsToExternalDirectory()
        } catch {
            recordDirectoryAccessFailure(from: error)
            throw error
        }
    }

    func importDownloadsFromExternalDirectory() throws -> Int {
        do {
            return try fileStore.importExternalDownloadsToDefaultDirectory()
        } catch {
            recordDirectoryAccessFailure(from: error)
            throw error
        }
    }

    func persistedTasks() -> [HanimePersistedDownloadTask] {
        (try? stateStore.allTasks()) ?? []
    }

    func persistedTask(id: String) -> HanimePersistedDownloadTask? {
        try? stateStore.task(id: id)
    }

    func restoreBackgroundTasks() async {
        if didRestoreBackgroundTasks {
            return
        }
        if let backgroundTaskRestoration {
            await backgroundTaskRestoration.value
            return
        }

        let restoration = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performBackgroundTaskRestoration()
        }
        backgroundTaskRestoration = restoration
        await restoration.value
        didRestoreBackgroundTasks = true
        backgroundTaskRestoration = nil
    }

    private func performBackgroundTaskRestoration() async {
        activateBackgroundSession()
        let tasks = await allBackgroundSessionTasks()
        let restoredTasks = tasks.compactMap { task -> (URLSessionDownloadTask, HanimeDownloadRequest)? in
            guard let downloadTask = task as? URLSessionDownloadTask,
                  let request = Self.request(from: task) else {
                return nil
            }
            return (downloadTask, request)
        }
        let tasksByRequestID = Dictionary(grouping: restoredTasks) { $0.1.id }

        for (requestID, entries) in tasksByRequestID {
            let sortedEntries = entries.sorted { lhs, rhs in
                if lhs.0.countOfBytesReceived != rhs.0.countOfBytesReceived {
                    return lhs.0.countOfBytesReceived > rhs.0.countOfBytesReceived
                }
                return lhs.0.taskIdentifier < rhs.0.taskIdentifier
            }
            guard let (downloadTask, request) = sortedEntries.first else { continue }

            for (duplicateTask, _) in sortedEntries.dropFirst() {
                finalizedTaskIDs.insert(duplicateTask.taskIdentifier)
                duplicateTask.cancel()
            }

            activeTasks[request.id] = downloadTask
            requestIDsByTaskID[downloadTask.taskIdentifier] = request.id
            let wasCreatedFromResumeData = persistedTask(id: request.id)?.createdFromResumeData == true
            let creationMode: HanimeDownloadTaskCreationMode = wasCreatedFromResumeData
                ? .resumed
                : .fresh
            taskCreationModesByTaskID[downloadTask.taskIdentifier] = creationMode

            let expected = downloadTask.countOfBytesExpectedToReceive > 0
                ? downloadTask.countOfBytesExpectedToReceive
                : nil
            if let snapshot = try? stateStore.markRunning(
                request: request,
                taskIdentifier: downloadTask.taskIdentifier,
                sessionIdentifier: Self.backgroundSessionIdentifier,
                downloadedByteCount: downloadTask.countOfBytesReceived,
                expectedByteCount: expected,
                createdFromResumeData: creationMode == .resumed
            ) {
                progressByID[request.id] = snapshot.progress
            }

            removePendingRequest(id: requestID)
        }

        activeRequestIDsInStartOrder = activeTasks.values
            .sorted { $0.taskIdentifier < $1.taskIdentifier }
            .compactMap { requestIDsByTaskID[$0.taskIdentifier] }

        let activeRequestIDs = Set(tasksByRequestID.keys)
        let snapshots = persistedTasks()
        let queuedSnapshots = snapshots
            .filter {
                $0.status == .queued || ($0.status == .running && $0.queuePosition != nil)
            }
            .sorted(by: Self.isOrderedBeforeInQueue)

        for snapshot in queuedSnapshots {
            guard !activeRequestIDs.contains(snapshot.id),
                  pendingRequests[snapshot.id] == nil else {
                continue
            }
            if snapshot.status == .running {
                _ = try? stateStore.markQueued(
                    request: snapshot.request,
                    sessionIdentifier: Self.backgroundSessionIdentifier,
                    errorDescription: "重新排队时应用已退出，将重新开始下载。",
                    preserveQueuePosition: true
                )
            }
            enqueue(snapshot.request)
        }

        for snapshot in snapshots where snapshot.status == .running && snapshot.queuePosition == nil {
            guard !activeRequestIDs.contains(snapshot.id),
                  activeTasks[snapshot.id] == nil else {
                continue
            }
            _ = try? stateStore.markFailed(
                requestID: snapshot.id,
                failureKind: .transient,
                errorDescription: "后台任务已结束，可重新开始下载。",
                resumeData: snapshot.resumeData
            )
        }

        enforceConcurrencyLimit()
        schedulePendingDownloads()
    }

    static func handleBackgroundEvents(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        backgroundCompletionHandlers[identifier] = completionHandler
        NotificationCenter.default.post(name: backgroundEventsNotification, object: nil)
    }

    private func makeBackgroundSession() -> URLSession {
        if let sessionConfigurationOverride {
            return URLSession(
                configuration: sessionConfigurationOverride,
                delegate: backgroundDelegate,
                delegateQueue: nil
            )
        }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = .shared
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration, delegate: backgroundDelegate, delegateQueue: nil)
    }

    private func recordDirectoryAccessFailure(from error: Error) {
        guard let directoryError = error as? HanaDownloadDirectoryError else { return }
        externalDirectoryAccessFailure = directoryError
    }

    private static func directoryAccessError(from error: Error) -> HanaDownloadDirectoryError {
        error as? HanaDownloadDirectoryError ?? .accessDenied
    }

    private func activateBackgroundSession() {
        _ = backgroundSession
    }

    private func allBackgroundSessionTasks() async -> [URLSessionTask] {
        if let backgroundTasksProviderOverride {
            return await backgroundTasksProviderOverride()
        }
        return await withCheckedContinuation { continuation in
            backgroundSession.getAllTasks { tasks in
                continuation.resume(returning: tasks)
            }
        }
    }

    fileprivate func updateProgress(
        requestID: String,
        taskIdentifier: Int,
        fraction: Double,
        downloadedByteCount: Int64,
        expectedByteCount: Int64
    ) {
        guard activeTasks[requestID]?.taskIdentifier == taskIdentifier,
              !finalizedTaskIDs.contains(taskIdentifier) else {
            return
        }
        progressByID[requestID] = min(max(fraction, 0), 1)
        _ = try? stateStore.updateProgress(
            requestID: requestID,
            taskIdentifier: taskIdentifier,
            downloadedByteCount: downloadedByteCount,
            expectedByteCount: expectedByteCount
        )
    }

    fileprivate func updateResumedProgress(
        requestID: String,
        taskIdentifier: Int,
        fileOffset: Int64,
        expectedByteCount: Int64
    ) {
        guard activeTasks[requestID]?.taskIdentifier == taskIdentifier,
              !finalizedTaskIDs.contains(taskIdentifier) else {
            return
        }
        let fraction = expectedByteCount > 0
            ? Double(fileOffset) / Double(expectedByteCount)
            : 0
        progressByID[requestID] = min(max(fraction, 0), 1)
        _ = try? stateStore.updateResumedProgress(
            requestID: requestID,
            taskIdentifier: taskIdentifier,
            fileOffset: fileOffset,
            expectedByteCount: expectedByteCount
        )
    }

    fileprivate func completeTask(
        taskIdentifier: Int,
        request: HanimeDownloadRequest,
        file: HanimeDownloadedFile
    ) {
        guard finalizeTask(taskIdentifier: taskIdentifier, requestID: request.id) else {
            return
        }
        progressByID[request.id] = 1
        _ = try? stateStore.markCompleted(
            request: request,
            taskIdentifier: taskIdentifier,
            sessionIdentifier: Self.backgroundSessionIdentifier,
            file: file
        )
        Task {
            if let sentAt = await HanaDownloadNotifications.notifyCompleted(request: request, file: file) {
                try? self.stateStore.markNotificationSent(requestID: request.id, sentAt: sentAt)
            }
        }
        continuationsByRequestID.removeValue(forKey: request.id)?.resume(returning: file)
        schedulePendingDownloads()
    }

    fileprivate func completeTask(
        taskIdentifier: Int,
        requestID: String?,
        error: Error?
    ) {
        if finalizedTaskIDs.contains(taskIdentifier) {
            return
        }

        guard let resolvedRequestID = requestID ?? requestIDsByTaskID[taskIdentifier] else {
            finalizedTaskIDs.insert(taskIdentifier)
            return
        }

        switch taskIntentsByTaskID[taskIdentifier] {
        case .pause:
            if let resumeData = error.flatMap(Self.resumeData(from:)) {
                finishPausedTask(
                    taskIdentifier: taskIdentifier,
                    requestID: resolvedRequestID,
                    resumeData: resumeData
                )
            }
            return
        case .cancel:
            finishCancelledTask(taskIdentifier: taskIdentifier, requestID: resolvedRequestID)
            return
        case .requeue:
            if let resumeData = error.flatMap(Self.resumeData(from:)) {
                finishRequeuedTask(
                    taskIdentifier: taskIdentifier,
                    requestID: resolvedRequestID,
                    resumeData: resumeData
                )
            }
            return
        case nil:
            break
        }

        let resolvedError = error ?? HanaNetworkError.invalidResponse
        if taskCreationModesByTaskID[taskIdentifier] == .resumed,
           Self.isUnusableResumeData(resolvedError),
           let request = persistedTask(id: resolvedRequestID)?.request {
            guard finalizeTask(taskIdentifier: taskIdentifier, requestID: resolvedRequestID) else {
                return
            }
            progressByID[resolvedRequestID] = 0
            _ = try? stateStore.markQueued(
                request: request,
                sessionIdentifier: Self.backgroundSessionIdentifier,
                clearResumeData: true,
                errorDescription: "无法继续旧进度，已从头开始下载。",
                atFront: true
            )
            enqueue(request, atFront: true)
            schedulePendingDownloads()
            return
        }

        guard finalizeTask(taskIdentifier: taskIdentifier, requestID: resolvedRequestID) else {
            return
        }
        let resumeData = Self.resumeData(from: resolvedError)
        let failureKind = Self.failureKind(for: resolvedError)
        _ = try? stateStore.markFailed(
            requestID: resolvedRequestID,
            failureKind: failureKind,
            errorDescription: resolvedError.localizedDescription,
            resumeData: resumeData
        )
        if resumeData == nil {
            progressByID[resolvedRequestID] = nil
        }
        resumeContinuation(requestID: resolvedRequestID, throwing: resolvedError)
        schedulePendingDownloads()
    }

    private var maximumConcurrentDownloadCount: Int {
        let configuredValue = defaults.object(forKey: HanaSettingsKey.downloadConcurrency) == nil
            ? 2
            : defaults.integer(forKey: HanaSettingsKey.downloadConcurrency)
        return min(max(configuredValue, 1), 5)
    }

    private func enforceConcurrencyLimit() {
        let maximumCount = maximumConcurrentDownloadCount
        guard activeTasks.count > maximumCount else { return }

        let knownActiveIDs = Set(activeTasks.keys)
        let orderedActiveIDs = activeRequestIDsInStartOrder.filter { knownActiveIDs.contains($0) }
            + activeTasks.keys
                .filter { !activeRequestIDsInStartOrder.contains($0) }
                .sorted()

        for requestID in orderedActiveIDs.dropFirst(maximumCount) {
            guard let task = activeTasks[requestID],
                  taskIntentsByTaskID[task.taskIdentifier] == nil,
                  let request = Self.request(from: task) ?? persistedTask(id: requestID)?.request else {
                continue
            }

            if pendingRequests[requestID] == nil {
                pendingRequests[requestID] = request
                pendingRequestIDs.append(requestID)
            }
            _ = try? stateStore.markRequeuePending(requestID: requestID)
            let taskIdentifier = task.taskIdentifier
            taskIntentsByTaskID[taskIdentifier] = .requeue
            task.cancel(byProducingResumeData: { [self] resumeData in
                Task { @MainActor [self] in
                    self.finishRequeuedTask(
                        taskIdentifier: taskIdentifier,
                        requestID: requestID,
                        resumeData: resumeData
                    )
                }
            })
        }
    }

    private func enqueue(_ request: HanimeDownloadRequest, atFront: Bool = false) {
        guard activeTasks[request.id] == nil,
              pendingRequests[request.id] == nil else {
            return
        }
        pendingRequests[request.id] = request
        if atFront {
            pendingRequestIDs.insert(request.id, at: 0)
        } else {
            pendingRequestIDs.append(request.id)
        }
    }

    private func removePendingRequest(id: String) {
        pendingRequests[id] = nil
        pendingRequestIDs.removeAll { $0 == id }
    }

    private func schedulePendingDownloads() {
        while activeTasks.count < maximumConcurrentDownloadCount,
              let requestID = pendingRequestIDs.first {
            if activeTasks[requestID] != nil {
                break
            }
            pendingRequestIDs.removeFirst()
            guard let request = pendingRequests.removeValue(forKey: requestID) else {
                continue
            }

            do {
                try startDownloadTask(for: request)
            } catch {
                _ = try? stateStore.markFailed(
                    requestID: request.id,
                    failureKind: .permanent,
                    errorDescription: error.localizedDescription,
                    resumeData: nil
                )
                progressByID[request.id] = nil
                resumeContinuation(requestID: request.id, throwing: error)
            }
        }
    }

    private func startDownloadTask(for request: HanimeDownloadRequest) throws {
        let taskDescription = try Self.taskDescription(for: request)
        let snapshot = try stateStore.task(id: request.id)
        let resumeData = snapshot?.resumeData
        let task: URLSessionDownloadTask
        let creationMode: HanimeDownloadTaskCreationMode

        if let resumeData {
            task = backgroundSession.downloadTask(withResumeData: resumeData)
            creationMode = .resumed
        } else {
            var urlRequest = URLRequest(url: request.mediaURL)
            urlRequest.httpMethod = "GET"
            urlRequest.timeoutInterval = 60
            httpClient.mediaHeaders(for: request.mediaURL).forEach { key, value in
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            task = backgroundSession.downloadTask(with: urlRequest)
            creationMode = .fresh
        }

        task.taskDescription = taskDescription
        let runningSnapshot: HanimePersistedDownloadTask
        do {
            runningSnapshot = try stateStore.markRunning(
                request: request,
                taskIdentifier: task.taskIdentifier,
                sessionIdentifier: Self.backgroundSessionIdentifier,
                createdFromResumeData: creationMode == .resumed
            )
        } catch {
            finalizedTaskIDs.insert(task.taskIdentifier)
            task.cancel()
            throw error
        }
        activeTasks[request.id] = task
        activeRequestIDsInStartOrder.removeAll { $0 == request.id }
        activeRequestIDsInStartOrder.append(request.id)
        progressByID[request.id] = runningSnapshot.progress
        requestIDsByTaskID[task.taskIdentifier] = request.id
        taskCreationModesByTaskID[task.taskIdentifier] = creationMode
        task.resume()
    }

    @discardableResult
    private func finalizeTask(taskIdentifier: Int, requestID: String) -> Bool {
        guard finalizedTaskIDs.insert(taskIdentifier).inserted else {
            return false
        }
        if activeTasks[requestID]?.taskIdentifier == taskIdentifier {
            activeTasks[requestID] = nil
        }
        activeRequestIDsInStartOrder.removeAll { $0 == requestID }
        requestIDsByTaskID[taskIdentifier] = nil
        taskIntentsByTaskID[taskIdentifier] = nil
        taskCreationModesByTaskID[taskIdentifier] = nil
        return true
    }

    private func finishPausedTask(
        taskIdentifier: Int,
        requestID: String,
        resumeData: Data?
    ) {
        guard finalizeTask(taskIdentifier: taskIdentifier, requestID: requestID) else {
            return
        }
        let snapshot = try? stateStore.markPaused(requestID: requestID, resumeData: resumeData)
        progressByID[requestID] = snapshot?.progress
        resumeContinuation(requestID: requestID, throwing: HanimeDownloadError.paused)
        schedulePendingDownloads()
    }

    private func finishCancelledTask(taskIdentifier: Int, requestID: String) {
        guard finalizeTask(taskIdentifier: taskIdentifier, requestID: requestID) else {
            return
        }
        _ = try? stateStore.markCancelled(requestID: requestID)
        progressByID[requestID] = nil
        resumeContinuation(requestID: requestID, throwing: CancellationError())
        schedulePendingDownloads()
    }

    private func finishRequeuedTask(
        taskIdentifier: Int,
        requestID: String,
        resumeData: Data?
    ) {
        if taskIntentsByTaskID[taskIdentifier] == .pause {
            finishPausedTask(
                taskIdentifier: taskIdentifier,
                requestID: requestID,
                resumeData: resumeData
            )
            return
        }
        if taskIntentsByTaskID[taskIdentifier] == .cancel {
            finishCancelledTask(taskIdentifier: taskIdentifier, requestID: requestID)
            return
        }

        let request = pendingRequests[requestID] ?? persistedTask(id: requestID)?.request
        guard finalizeTask(taskIdentifier: taskIdentifier, requestID: requestID) else {
            return
        }
        guard let request else {
            removePendingRequest(id: requestID)
            resumeContinuation(requestID: requestID, throwing: HanaNetworkError.invalidResponse)
            schedulePendingDownloads()
            return
        }
        _ = try? stateStore.markPaused(
            requestID: requestID,
            resumeData: resumeData,
            preserveQueuePosition: true
        )
        let snapshot = try? stateStore.markQueued(
            request: request,
            sessionIdentifier: Self.backgroundSessionIdentifier,
            preserveQueuePosition: true
        )
        progressByID[requestID] = snapshot?.progress
        schedulePendingDownloads()
    }

    private func resumeContinuation(requestID: String, throwing error: Error) {
        continuationsByRequestID.removeValue(forKey: requestID)?.resume(throwing: error)
    }

    private static func isOrderedBeforeInQueue(
        _ lhs: HanimePersistedDownloadTask,
        _ rhs: HanimePersistedDownloadTask
    ) -> Bool {
        switch (lhs.queuePosition, rhs.queuePosition) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        default:
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }

    nonisolated private static func resumeData(from error: Error) -> Data? {
        (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    }

    nonisolated private static func isUnusableResumeData(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain,
              resumeData(from: error) == nil else {
            return false
        }
        let unusableResumeCodes: Set<URLError.Code> = [
            .badURL,
            .unsupportedURL,
            .resourceUnavailable,
            .cannotDecodeRawData,
            .cannotDecodeContentData
        ]
        return unusableResumeCodes.contains(URLError.Code(rawValue: nsError.code))
    }

    nonisolated private static func failureKind(for error: Error) -> HanimeDownloadFailureKind {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return .permanent
        }

        let transientCodes: Set<URLError.Code> = [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
            .internationalRoamingOff,
            .callIsActive,
            .dataNotAllowed,
            .backgroundSessionWasDisconnected
        ]
        return transientCodes.contains(URLError.Code(rawValue: nsError.code))
            ? .transient
            : .permanent
    }

    fileprivate static func finishBackgroundEvents(identifier: String) {
        guard let completionHandler = backgroundCompletionHandlers.removeValue(forKey: identifier) else {
            return
        }
        completionHandler()
    }

    private static func taskDescription(for request: HanimeDownloadRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        guard let text = String(data: data, encoding: .utf8) else {
            throw HanaNetworkError.invalidTextEncoding
        }
        return text
    }

    nonisolated fileprivate static func request(from task: URLSessionTask) -> HanimeDownloadRequest? {
        guard let description = task.taskDescription,
              let data = description.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(HanimeDownloadRequest.self, from: data)
    }
}
