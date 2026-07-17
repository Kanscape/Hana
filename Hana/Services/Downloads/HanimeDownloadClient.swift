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
    case running
    case completed
    case failed
    case cancelled
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

    func deleteLocalDownload(fileURL: URL) throws {
        try withConfiguredDownloadDirectoryAccess {
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

    private func withConfiguredDownloadDirectoryAccess<T>(_ body: () throws -> T) throws -> T {
        guard let externalURL = try externalDirectoryResolver() else {
            return try body()
        }
        return try withExternalDirectoryAccess(externalURL, body)
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

nonisolated private struct HanimeDownloadTaskStateStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func allTasks() throws -> [HanimePersistedDownloadTask] {
        try readTasks().sorted { $0.updatedAt > $1.updatedAt }
    }

    func task(id: String) throws -> HanimePersistedDownloadTask? {
        try readTasks().first { $0.id == id }
    }

    @discardableResult
    func markRunning(
        request: HanimeDownloadRequest,
        taskIdentifier: Int,
        sessionIdentifier: String,
        downloadedByteCount: Int64? = nil,
        expectedByteCount: Int64? = nil
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
        task.errorDescription = nil
        task.updatedAt = now
        task.completedAt = nil
        tasks.removeAll { $0.id == request.id }
        tasks.append(task)
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
        tasks.removeAll { $0.id == requestID }
        tasks.append(task)
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
        task.updatedAt = now
        task.completedAt = now
        tasks.removeAll { $0.id == request.id }
        tasks.append(task)
        try writeTasks(tasks)
        return task
    }

    @discardableResult
    func markFinished(
        requestID: String,
        taskIdentifier: Int,
        status: HanimeDownloadTaskStatus,
        errorDescription: String?
    ) throws -> HanimePersistedDownloadTask? {
        var tasks = try readTasks()
        guard var task = tasks.first(where: { $0.id == requestID }) else {
            return nil
        }
        let now = Date()
        task.taskIdentifier = taskIdentifier
        task.status = status
        task.errorDescription = errorDescription
        task.updatedAt = now
        task.completedAt = now
        tasks.removeAll { $0.id == requestID }
        tasks.append(task)
        try writeTasks(tasks)
        return task
    }

    func markNotificationSent(requestID: String, sentAt: Date) throws {
        var tasks = try readTasks()
        guard var task = tasks.first(where: { $0.id == requestID }) else { return }
        task.notificationSentAt = sentAt
        task.updatedAt = .now
        tasks.removeAll { $0.id == requestID }
        tasks.append(task)
        try writeTasks(tasks)
    }

    private func progress(downloaded: Int64?, expected: Int64?) -> Double? {
        guard let downloaded,
              let expected,
              expected > 0 else {
            return nil
        }
        return min(max(Double(downloaded) / Double(expected), 0), 1)
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
        let rootURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        ).appending(path: "HanaDownloads", directoryHint: .isDirectory)
        if create {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        return rootURL.appending(path: "tasks.json", directoryHint: .notDirectory)
    }
}

private final class HanimeBackgroundDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private weak var client: HanimeDownloadClient?

    init(client: HanimeDownloadClient) {
        self.client = client
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
            let file = try HanimeDownloadFileStore().moveDownloadedFile(
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

@Observable
final class HanimeDownloadClient {
    static let backgroundSessionIdentifier = "com.kanscape.Hana.downloads"
    private static let backgroundEventsNotification = Notification.Name("HanaDownloadClientBackgroundEvents")

    private let httpClient: HanaHTTPClient
    private let session: URLSession
    private let fileManager: FileManager
    private let fileStore: HanimeDownloadFileStore
    private let stateStore: HanimeDownloadTaskStateStore
    @ObservationIgnored private lazy var backgroundDelegate = HanimeBackgroundDownloadDelegate(client: self)
    @ObservationIgnored private lazy var backgroundSession: URLSession = makeBackgroundSession()
    @ObservationIgnored private var backgroundEventsObserver: NSObjectProtocol?
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var progressByID: [String: Double] = [:]
    private var continuationsByTaskID: [Int: CheckedContinuation<HanimeDownloadedFile, Error>] = [:]
    private var requestIDsByTaskID: [Int: String] = [:]
    private var completedTaskIDs = Set<Int>()
    private static var backgroundCompletionHandlers: [String: () -> Void] = [:]

    init(
        httpClient: HanaHTTPClient,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.httpClient = httpClient
        self.session = session
        self.fileManager = fileManager
        self.fileStore = HanimeDownloadFileStore(fileManager: fileManager)
        self.stateStore = HanimeDownloadTaskStateStore(fileManager: fileManager)
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
        if let backgroundEventsObserver {
            NotificationCenter.default.removeObserver(backgroundEventsObserver)
        }
    }

    func download(
        _ request: HanimeDownloadRequest,
        onTaskCreated: ((HanimePersistedDownloadTask) -> Void)? = nil
    ) async throws -> HanimeDownloadedFile {
        var urlRequest = URLRequest(url: request.mediaURL)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = 60
        httpClient.mediaHeaders(for: request.mediaURL).forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let task = backgroundSession.downloadTask(with: urlRequest)
        task.taskDescription = try Self.taskDescription(for: request)
        activeTasks[request.id] = task
        progressByID[request.id] = 0
        requestIDsByTaskID[task.taskIdentifier] = request.id
        if let snapshot = try? stateStore.markRunning(
            request: request,
            taskIdentifier: task.taskIdentifier,
            sessionIdentifier: Self.backgroundSessionIdentifier
        ) {
            onTaskCreated?(snapshot)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuationsByTaskID[task.taskIdentifier] = continuation
                task.resume()
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
        activeTasks[id] != nil
    }

    var hasActiveDownloads: Bool {
        !activeTasks.isEmpty
    }

    func cancel(id: String) {
        activeTasks[id]?.cancel()
        activeTasks[id] = nil
        progressByID[id] = nil
        if let task = try? stateStore.task(id: id),
           let taskIdentifier = task.taskIdentifier {
            _ = try? stateStore.markFinished(
                requestID: id,
                taskIdentifier: taskIdentifier,
                status: .cancelled,
                errorDescription: nil
            )
        }
    }

    func deleteLocalDownload(fileURL: URL) throws {
        try fileStore.deleteLocalDownload(fileURL: fileURL)
    }

    func localDownloads() throws -> [HanimeLocalDownload] {
        try fileStore.localDownloads()
    }

    func exportDownloadsToExternalDirectory() throws -> Int {
        try fileStore.exportDefaultDownloadsToExternalDirectory()
    }

    func importDownloadsFromExternalDirectory() throws -> Int {
        try fileStore.importExternalDownloadsToDefaultDirectory()
    }

    func persistedTasks() -> [HanimePersistedDownloadTask] {
        (try? stateStore.allTasks()) ?? []
    }

    func persistedTask(id: String) -> HanimePersistedDownloadTask? {
        try? stateStore.task(id: id)
    }

    func restoreBackgroundTasks() async {
        activateBackgroundSession()
        let tasks = await allBackgroundSessionTasks()
        for task in tasks {
            guard let downloadTask = task as? URLSessionDownloadTask,
                  let request = Self.request(from: task) else {
                continue
            }
            activeTasks[request.id] = downloadTask
            requestIDsByTaskID[downloadTask.taskIdentifier] = request.id

            let expected = downloadTask.countOfBytesExpectedToReceive > 0
                ? downloadTask.countOfBytesExpectedToReceive
                : nil
            if let snapshot = try? stateStore.markRunning(
                request: request,
                taskIdentifier: downloadTask.taskIdentifier,
                sessionIdentifier: Self.backgroundSessionIdentifier,
                downloadedByteCount: downloadTask.countOfBytesReceived,
                expectedByteCount: expected
            ) {
                progressByID[request.id] = snapshot.progress
            }
        }
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

    private func activateBackgroundSession() {
        _ = backgroundSession
    }

    private func allBackgroundSessionTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
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
        progressByID[requestID] = min(max(fraction, 0), 1)
        _ = try? stateStore.updateProgress(
            requestID: requestID,
            taskIdentifier: taskIdentifier,
            downloadedByteCount: downloadedByteCount,
            expectedByteCount: expectedByteCount
        )
    }

    fileprivate func completeTask(
        taskIdentifier: Int,
        request: HanimeDownloadRequest,
        file: HanimeDownloadedFile
    ) {
        completedTaskIDs.insert(taskIdentifier)
        activeTasks[request.id] = nil
        progressByID[request.id] = 1
        requestIDsByTaskID[taskIdentifier] = nil
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
        continuationsByTaskID.removeValue(forKey: taskIdentifier)?.resume(returning: file)
    }

    fileprivate func completeTask(
        taskIdentifier: Int,
        requestID: String?,
        error: Error?
    ) {
        if completedTaskIDs.remove(taskIdentifier) != nil {
            requestIDsByTaskID[taskIdentifier] = nil
            continuationsByTaskID[taskIdentifier] = nil
            return
        }

        let resolvedRequestID = requestID ?? requestIDsByTaskID[taskIdentifier]
        if let resolvedRequestID {
            activeTasks[resolvedRequestID] = nil
            progressByID[resolvedRequestID] = nil
            if let error {
                let status: HanimeDownloadTaskStatus = (error as? URLError)?.code == .cancelled ? .cancelled : .failed
                _ = try? stateStore.markFinished(
                    requestID: resolvedRequestID,
                    taskIdentifier: taskIdentifier,
                    status: status,
                    errorDescription: status == .cancelled ? nil : error.localizedDescription
                )
            }
        }
        requestIDsByTaskID[taskIdentifier] = nil

        if let error {
            continuationsByTaskID.removeValue(forKey: taskIdentifier)?.resume(throwing: error)
        } else {
            continuationsByTaskID[taskIdentifier] = nil
        }
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
