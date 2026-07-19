import Foundation
import Testing
@testable import Hana

@MainActor
@Suite("Download resume state", .serialized)
struct DownloadResumeStateTests {
    @Test("legacy task snapshots decode without resume fields")
    func legacySnapshotCompatibility() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let legacyJSON: [[String: Any]] = [[
            "id": "legacy",
            "request": [
                "id": "legacy",
                "videoCode": "legacy-video",
                "title": "Legacy",
                "quality": "720P",
                "mediaURL": "https://downloads.test/legacy.mp4"
            ],
            "sessionIdentifier": "legacy-session",
            "taskIdentifier": 7,
            "status": "running",
            "progress": 0.25,
            "downloadedByteCount": 25,
            "expectedByteCount": 100,
            "createdAt": "2026-07-17T00:00:00Z",
            "updatedAt": "2026-07-17T00:01:00Z"
        ]]
        let data = try JSONSerialization.data(withJSONObject: legacyJSON)
        try data.write(to: rootURL.appending(path: "tasks.json"))

        let snapshots = try HanimeDownloadTaskStateStore(stateDirectoryURL: rootURL).allTasks()
        let snapshot = try #require(snapshots.first)
        #expect(snapshot.status == .running)
        #expect(snapshot.resumeData == nil)
        #expect(snapshot.failureKind == nil)
        #expect(snapshot.queuePosition == nil)
        #expect(snapshot.createdFromResumeData == nil)
        #expect(snapshot.downloadedByteCount == 25)
    }

    @Test("pause preserves resume data and cancel clears it")
    func stateTransitions() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = HanimeDownloadTaskStateStore(stateDirectoryURL: rootURL)
        let request = request(id: "state")

        let initialQueued = try store.markQueued(request: request, sessionIdentifier: "test")
        #expect(initialQueued.queuePosition == 0)
        let running = try store.markRunning(
            request: request,
            taskIdentifier: 1,
            sessionIdentifier: "test",
            createdFromResumeData: true
        )
        #expect(running.queuePosition == nil)
        #expect(running.createdFromResumeData == true)
        let storedRunning = try store.task(id: request.id)
        let persistedRunning = try #require(storedRunning)
        #expect(persistedRunning.createdFromResumeData == true)
        _ = try store.updateProgress(
            requestID: request.id,
            taskIdentifier: 1,
            downloadedByteCount: 40,
            expectedByteCount: 100
        )
        let resumeData = Data([1, 2, 3])
        let pausedSnapshot = try store.markPaused(requestID: request.id, resumeData: resumeData)
        let paused = try #require(pausedSnapshot)
        #expect(paused.status == .paused)
        #expect(paused.progress == 0.4)
        #expect(paused.resumeData == resumeData)
        #expect(paused.taskIdentifier == nil)
        #expect(paused.queuePosition == nil)
        #expect(paused.createdFromResumeData == nil)

        let queued = try store.markQueued(request: request, sessionIdentifier: "test")
        #expect(queued.status == .queued)
        #expect(queued.progress == 0.4)
        #expect(queued.resumeData == resumeData)
        #expect(queued.queuePosition == 0)

        let freshQueued = try store.markQueued(
            request: request,
            sessionIdentifier: "test",
            clearResumeData: true
        )
        #expect(freshQueued.progress == 0)
        #expect(freshQueued.resumeData == nil)

        let cancelledSnapshot = try store.markCancelled(requestID: request.id)
        let cancelled = try #require(cancelledSnapshot)
        #expect(cancelled.status == .cancelled)
        #expect(cancelled.progress == 0)
        #expect(cancelled.resumeData == nil)
        #expect(cancelled.downloadedByteCount == nil)
    }

    @Test("failure stores retry class and resume data")
    func failureState() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = HanimeDownloadTaskStateStore(stateDirectoryURL: rootURL)
        let request = request(id: "failure")
        let resumeData = Data([4, 5, 6])

        _ = try store.markQueued(request: request, sessionIdentifier: "test")
        _ = try store.markRunning(
            request: request,
            taskIdentifier: 2,
            sessionIdentifier: "test",
            downloadedByteCount: 50,
            expectedByteCount: 100
        )
        let failedSnapshot = try store.markFailed(
            requestID: request.id,
            failureKind: .transient,
            errorDescription: "offline",
            resumeData: resumeData
        )
        let failed = try #require(failedSnapshot)

        #expect(failed.status == .failed)
        #expect(failed.failureKind == .transient)
        #expect(failed.resumeData == resumeData)
        #expect(failed.progress == 0.5)
        #expect(failed.completedAt == nil)

        let freshFailureSnapshot = try store.markFailed(
            requestID: request.id,
            failureKind: .transient,
            errorDescription: "offline",
            resumeData: nil
        )
        let freshFailure = try #require(freshFailureSnapshot)
        #expect(freshFailure.progress == 0)
        #expect(freshFailure.errorDescription == "offline\n再次开始会从头下载。")
    }

    @Test("zero resume offset records a from-beginning fallback")
    func zeroResumeOffset() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = HanimeDownloadTaskStateStore(stateDirectoryURL: rootURL)
        let request = request(id: "offset")

        _ = try store.markQueued(request: request, sessionIdentifier: "test")
        _ = try store.markRunning(
            request: request,
            taskIdentifier: 3,
            sessionIdentifier: "test",
            downloadedByteCount: 60,
            expectedByteCount: 100
        )
        let restartedSnapshot = try store.updateResumedProgress(
            requestID: request.id,
            taskIdentifier: 3,
            fileOffset: 0,
            expectedByteCount: 100
        )
        let restarted = try #require(restartedSnapshot)

        #expect(restarted.progress == 0)
        #expect(restarted.errorDescription == "服务器不支持继续旧进度，已从头开始下载。")
    }

    @Test("concurrency limit controls real tasks in FIFO order")
    func concurrencyAndFIFO() async throws {
        ControlledDownloadURLProtocol.reset()
        let environment = makeClientEnvironment(concurrency: 1)
        defer { environment.cleanup() }
        let client = environment.client
        let requests = [request(id: "a"), request(id: "b"), request(id: "c")]
        await client.restoreBackgroundTasks()
        let tasks = requests.map { request in
            Task { try? await client.download(request) }
        }

        #expect(await waitUntil { ControlledDownloadURLProtocol.startedPaths.count == 1 })
        #expect(client.activeDownloadCount == 1)
        #expect(client.pendingDownloadIDs == ["b", "c"])
        #expect(ControlledDownloadURLProtocol.startedPaths == ["/a.mp4"])

        environment.defaults.set(2, forKey: HanaSettingsKey.downloadConcurrency)
        client.downloadConcurrencyDidChange()
        #expect(await waitUntil { ControlledDownloadURLProtocol.startedPaths.count == 2 })
        #expect(client.activeDownloadCount == 2)
        #expect(client.pendingDownloadIDs == ["c"])
        #expect(ControlledDownloadURLProtocol.startedPaths == ["/a.mp4", "/b.mp4"])

        client.cancel(id: "a")
        #expect(await waitUntil { ControlledDownloadURLProtocol.startedPaths.count == 3 })
        #expect(ControlledDownloadURLProtocol.startedPaths == ["/a.mp4", "/b.mp4", "/c.mp4"])
        #expect(client.activeDownloadCount == 2)

        client.cancel(id: "b")
        client.cancel(id: "c")
        for task in tasks {
            _ = await task.value
        }
    }

    @Test("each supported concurrency value limits active tasks", arguments: 1...5)
    func eachConcurrencyValue(limit: Int) async {
        ControlledDownloadURLProtocol.reset()
        let environment = makeClientEnvironment(concurrency: limit)
        defer { environment.cleanup() }
        let requests = (0..<(limit + 2)).map { request(id: "limit-\(limit)-\($0)") }
        await environment.client.restoreBackgroundTasks()
        let tasks = requests.map { request in
            Task { try? await environment.client.download(request) }
        }
        let pathPrefix = "/limit-\(limit)-"

        #expect(await waitUntil {
            ControlledDownloadURLProtocol.startedPaths.filter { $0.hasPrefix(pathPrefix) }.count == limit
        })
        #expect(environment.client.activeDownloadCount == limit)
        #expect(environment.client.pendingDownloadIDs.count == 2)

        for request in requests {
            environment.client.cancel(id: request.id)
        }
        for task in tasks {
            _ = await task.value
        }
    }

    @Test("lowering concurrency requeues excess tasks without changing FIFO order")
    func loweringConcurrency() async throws {
        ControlledDownloadURLProtocol.reset()
        let environment = makeClientEnvironment(concurrency: 3)
        defer { environment.cleanup() }
        let requests = ["a", "b", "c", "d"].map { request(id: "lower-\($0)") }
        await environment.client.restoreBackgroundTasks()
        let tasks = requests.map { request in
            Task { try? await environment.client.download(request) }
        }

        #expect(await waitUntil { environment.client.activeDownloadCount == 3 })
        #expect(environment.client.pendingDownloadIDs == ["lower-d"])
        environment.defaults.set(1, forKey: HanaSettingsKey.downloadConcurrency)
        environment.client.downloadConcurrencyDidChange()

        #expect(await waitUntil {
            environment.client.activeDownloadCount == 1
                && environment.client.pendingDownloadIDs == ["lower-d", "lower-b", "lower-c"]
        })
        #expect(ControlledDownloadURLProtocol.startedPaths == [
            "/lower-a.mp4", "/lower-b.mp4", "/lower-c.mp4"
        ])
        #expect(environment.client.persistedTask(id: "lower-b")?.status == .queued)
        #expect(environment.client.persistedTask(id: "lower-c")?.status == .queued)
        let queuedPositions = Dictionary(
            uniqueKeysWithValues: environment.client.persistedTasks().compactMap { snapshot in
                snapshot.queuePosition.map { (snapshot.id, $0) }
            }
        )
        let positionD = try #require(queuedPositions["lower-d"])
        let positionB = try #require(queuedPositions["lower-b"])
        let positionC = try #require(queuedPositions["lower-c"])
        #expect(positionD < positionB)
        #expect(positionB < positionC)

        environment.client.cancel(id: "lower-a")
        #expect(await waitUntil {
            ControlledDownloadURLProtocol.startedPaths.last == "/lower-d.mp4"
        })
        #expect(environment.client.pendingDownloadIDs == ["lower-b", "lower-c"])

        for request in requests {
            environment.client.cancel(id: request.id)
        }
        for task in tasks {
            _ = await task.value
        }
    }

    @Test("pause wins while a task is being requeued after lowering concurrency")
    func pauseDuringConcurrencyRequeue() async {
        ControlledDownloadURLProtocol.reset()
        let environment = makeClientEnvironment(concurrency: 2)
        defer { environment.cleanup() }
        let firstRequest = request(id: "requeue-pause-a")
        let secondRequest = request(id: "requeue-pause-b")
        await environment.client.restoreBackgroundTasks()
        let firstTask = Task { try? await environment.client.download(firstRequest) }
        let secondTask = Task { () -> Bool in
            do {
                _ = try await environment.client.download(secondRequest)
                return false
            } catch HanimeDownloadError.paused {
                return true
            } catch {
                return false
            }
        }

        #expect(await waitUntil { environment.client.activeDownloadCount == 2 })
        environment.defaults.set(1, forKey: HanaSettingsKey.downloadConcurrency)
        environment.client.downloadConcurrencyDidChange()
        environment.client.pause(id: secondRequest.id)

        #expect(await waitUntil {
            environment.client.activeDownloadCount == 1
                && environment.client.persistedTask(id: secondRequest.id)?.status == .paused
        })
        #expect(!environment.client.pendingDownloadIDs.contains(secondRequest.id))
        #expect(await secondTask.value)

        environment.client.cancel(id: firstRequest.id)
        _ = await firstTask.value
    }

    @Test("relaunch preserves existing FIFO items before concurrency requeues")
    func restoreRequeuedFIFO() async throws {
        ControlledDownloadURLProtocol.reset()
        let environment = makeClientEnvironment(concurrency: 1)
        defer { environment.cleanup() }
        let store = HanimeDownloadTaskStateStore(stateDirectoryURL: environment.rootURL)
        let requeuedB = request(id: "restore-b")
        let requeuedC = request(id: "restore-c")
        let existingPending = request(id: "restore-d")

        _ = try store.markQueued(request: requeuedB, sessionIdentifier: "test")
        _ = try store.markRunning(
            request: requeuedB,
            taskIdentifier: 1,
            sessionIdentifier: "test"
        )
        _ = try store.markQueued(request: requeuedC, sessionIdentifier: "test")
        _ = try store.markRunning(
            request: requeuedC,
            taskIdentifier: 2,
            sessionIdentifier: "test"
        )
        _ = try store.markQueued(request: existingPending, sessionIdentifier: "test")

        _ = try store.markRequeuePending(requestID: requeuedB.id)
        _ = try store.markPaused(
            requestID: requeuedB.id,
            resumeData: nil,
            preserveQueuePosition: true
        )
        _ = try store.markQueued(
            request: requeuedB,
            sessionIdentifier: "test",
            preserveQueuePosition: true
        )
        _ = try store.markRequeuePending(requestID: requeuedC.id)
        _ = try store.markPaused(
            requestID: requeuedC.id,
            resumeData: nil,
            preserveQueuePosition: true
        )
        _ = try store.markQueued(
            request: requeuedC,
            sessionIdentifier: "test",
            preserveQueuePosition: true
        )

        await environment.client.restoreBackgroundTasks()

        #expect(await waitUntil {
            ControlledDownloadURLProtocol.startedPaths == ["/restore-d.mp4"]
        })
        #expect(environment.client.pendingDownloadIDs == ["restore-b", "restore-c"])

        environment.client.cancel(id: existingPending.id)
        environment.client.cancel(id: requeuedB.id)
        environment.client.cancel(id: requeuedC.id)
    }

    @Test("duplicate request does not create a second system task")
    func duplicateRequest() async {
        ControlledDownloadURLProtocol.reset()
        let environment = makeClientEnvironment(concurrency: 2)
        defer { environment.cleanup() }
        let request = request(id: "duplicate")
        let firstTask = Task { try? await environment.client.download(request) }

        #expect(await waitUntil { environment.client.activeDownloadCount == 1 })
        do {
            _ = try await environment.client.download(request)
            Issue.record("Duplicate request unexpectedly started")
        } catch HanimeDownloadError.alreadyScheduled {
        } catch {
            Issue.record("Unexpected duplicate error: \(error)")
        }
        #expect(ControlledDownloadURLProtocol.startedPaths == ["/duplicate.mp4"])

        environment.client.cancel(id: request.id)
        _ = await firstTask.value
    }

    @Test("download restores persisted queue before checking for duplicates")
    func duplicateRequestDuringLaunchRestore() async throws {
        ControlledDownloadURLProtocol.reset()
        let environment = makeClientEnvironment(concurrency: 1)
        defer { environment.cleanup() }
        let request = request(id: "launch-duplicate")
        let store = HanimeDownloadTaskStateStore(stateDirectoryURL: environment.rootURL)
        _ = try store.markQueued(request: request, sessionIdentifier: "test")

        do {
            _ = try await environment.client.download(request)
            Issue.record("Persisted request unexpectedly started twice")
        } catch HanimeDownloadError.alreadyScheduled {
        } catch {
            Issue.record("Unexpected launch duplicate error: \(error)")
        }

        #expect(await waitUntil {
            environment.client.activeDownloadCount == 1
                && ControlledDownloadURLProtocol.startedPaths == ["/launch-duplicate.mp4"]
        })
        environment.client.cancel(id: request.id)
    }

    @Test("restore keeps one duplicate system task per request ID")
    func duplicateSystemTaskRestore() async throws {
        ControlledDownloadURLProtocol.reset()
        let request = request(id: "restored-system-duplicate")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let firstTask = session.downloadTask(with: request.mediaURL)
        let secondTask = session.downloadTask(with: request.mediaURL)
        let descriptionData = try JSONEncoder().encode(request)
        let taskDescription = try #require(String(data: descriptionData, encoding: .utf8))
        firstTask.taskDescription = taskDescription
        secondTask.taskDescription = taskDescription
        let restoredTasks: [URLSessionTask] = [firstTask, secondTask]
        let environment = makeClientEnvironment(
            concurrency: 2,
            backgroundTasksProvider: { restoredTasks }
        )
        defer { environment.cleanup() }
        let store = HanimeDownloadTaskStateStore(stateDirectoryURL: environment.rootURL)
        _ = try store.markQueued(request: request, sessionIdentifier: "test")

        await environment.client.restoreBackgroundTasks()

        let keptIdentifier = min(firstTask.taskIdentifier, secondTask.taskIdentifier)
        let duplicateTask = firstTask.taskIdentifier == keptIdentifier ? secondTask : firstTask
        #expect(environment.client.activeDownloadCount == 1)
        #expect(environment.client.persistedTask(id: request.id)?.taskIdentifier == keptIdentifier)
        #expect(duplicateTask.state != .suspended)

        do {
            _ = try await environment.client.download(request)
            Issue.record("Restored system task unexpectedly allowed a duplicate")
        } catch HanimeDownloadError.alreadyScheduled {
        } catch {
            Issue.record("Unexpected restored duplicate error: \(error)")
        }

        environment.client.cancel(id: request.id)
    }

    @Test("invalid resume data falls back to one fresh request")
    func invalidResumeDataFallback() async throws {
        ControlledDownloadURLProtocol.reset()
        let environment = makeClientEnvironment(concurrency: 1)
        defer { environment.cleanup() }
        let request = request(id: "resume")
        let store = HanimeDownloadTaskStateStore(stateDirectoryURL: environment.rootURL)
        _ = try store.markQueued(request: request, sessionIdentifier: "test")
        _ = try store.markPaused(
            requestID: request.id,
            resumeData: Data("invalid resume data".utf8)
        )

        let task = Task { try? await environment.client.download(request) }
        #expect(await waitUntil { ControlledDownloadURLProtocol.startedPaths == ["/resume.mp4"] })
        #expect(environment.client.activeDownloadCount == 1)
        #expect(environment.client.pendingDownloadIDs.isEmpty)

        environment.client.cancel(id: request.id)
        _ = await task.value
        #expect(ControlledDownloadURLProtocol.startedPaths == ["/resume.mp4"])
    }

    @Test("pausing an active task settles as paused once")
    func activePause() async {
        ControlledDownloadURLProtocol.reset()
        let environment = makeClientEnvironment(concurrency: 1)
        defer { environment.cleanup() }
        let request = request(id: "pause")
        let task = Task { () -> String in
            do {
                _ = try await environment.client.download(request)
                return "completed"
            } catch HanimeDownloadError.paused {
                return "paused"
            } catch {
                return "other"
            }
        }

        #expect(await waitUntil { environment.client.activeDownloadCount == 1 })
        environment.client.pause(id: request.id)
        #expect(await waitUntil {
            environment.client.persistedTask(id: request.id)?.status == .paused
        })
        #expect(await task.value == "paused")
        #expect(environment.client.activeDownloadCount == 0)
    }

    @Test("restore starts queued tasks but leaves paused tasks stopped")
    func restoreQueuedAndPausedTasks() async throws {
        ControlledDownloadURLProtocol.reset()
        let environment = makeClientEnvironment(concurrency: 2)
        defer { environment.cleanup() }
        let store = HanimeDownloadTaskStateStore(stateDirectoryURL: environment.rootURL)
        let queuedRequest = request(id: "restored-queued")
        let pausedRequest = request(id: "restored-paused")
        _ = try store.markQueued(request: queuedRequest, sessionIdentifier: "test")
        _ = try store.markQueued(request: pausedRequest, sessionIdentifier: "test")
        _ = try store.markPaused(requestID: pausedRequest.id, resumeData: Data([1]))

        await environment.client.restoreBackgroundTasks()
        #expect(await waitUntil {
            ControlledDownloadURLProtocol.startedPaths == ["/restored-queued.mp4"]
        })
        #expect(environment.client.activeDownloadCount == 1)
        #expect(ControlledDownloadURLProtocol.startedPaths == ["/restored-queued.mp4"])
        #expect(environment.client.persistedTask(id: pausedRequest.id)?.status == .paused)

        environment.client.cancel(id: queuedRequest.id)
    }

    @Test("snapshot states map to distinct visible statuses")
    func snapshotStatusMapping() {
        let record = DownloadQueueRecord(
            videoCode: "mapping",
            title: "Mapping",
            coverURLString: nil,
            quality: "720P",
            mediaURLString: "https://downloads.test/mapping.mp4"
        )

        var snapshot = makeSnapshot(status: .queued)
        HanaDownloadRecordSynchronizer.apply(snapshot, to: record)
        #expect(record.status == "等待下载")

        snapshot.status = .running
        HanaDownloadRecordSynchronizer.apply(snapshot, to: record)
        #expect(record.status == "下载中")

        snapshot.status = .paused
        HanaDownloadRecordSynchronizer.apply(snapshot, to: record)
        #expect(record.status == "已暂停")

        snapshot.status = .failed
        snapshot.failureKind = .transient
        HanaDownloadRecordSynchronizer.apply(snapshot, to: record)
        #expect(record.status == "暂时失败")

        snapshot.failureKind = .permanent
        HanaDownloadRecordSynchronizer.apply(snapshot, to: record)
        #expect(record.status == "下载失败")

        snapshot.status = .cancelled
        HanaDownloadRecordSynchronizer.apply(snapshot, to: record)
        #expect(record.status == "已取消")

        snapshot.status = .completed
        HanaDownloadRecordSynchronizer.apply(snapshot, to: record)
        #expect(record.status == "已完成")
    }

    @Test("group expansion JSON survives special characters and pruning")
    func groupExpansionPersistence() {
        let collapsed = Set(["A, B", "C=D", "分组/三"])
        let rawValue = DownloadGroupExpansionState.rawValue(for: collapsed)
        #expect(DownloadGroupExpansionState.collapsedGroupIDs(from: rawValue) == collapsed)

        let pruned = DownloadGroupExpansionState.pruning(
            rawValue,
            validGroupIDs: ["A, B", "new"]
        )
        #expect(DownloadGroupExpansionState.collapsedGroupIDs(from: pruned) == ["A, B"])
        #expect(!DownloadGroupExpansionState.collapsedGroupIDs(from: pruned).contains("new"))
    }

    private func request(id: String) -> HanimeDownloadRequest {
        HanimeDownloadRequest(
            id: id,
            videoCode: "video-\(id)",
            title: id,
            coverURLString: nil,
            quality: "720P",
            mediaURL: URL(string: "https://downloads.test/\(id).mp4")!
        )
    }

    private func makeSnapshot(status: HanimeDownloadTaskStatus) -> HanimePersistedDownloadTask {
        let request = request(id: "mapping")
        return HanimePersistedDownloadTask(
            id: request.id,
            request: request,
            sessionIdentifier: "test",
            taskIdentifier: nil,
            status: status,
            progress: 0.5,
            downloadedByteCount: 50,
            expectedByteCount: 100,
            localFileURLString: nil,
            errorDescription: "error",
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            notificationSentAt: nil
        )
    }

    private func temporaryRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "HanaDownloadTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeClientEnvironment(
        concurrency: Int,
        backgroundTasksProvider: (@Sendable () async -> [URLSessionTask])? = nil
    ) -> ClientEnvironment {
        let rootURL = temporaryRootURL()
        let suiteName = "HanaDownloadTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(concurrency, forKey: HanaSettingsKey.downloadConcurrency)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledDownloadURLProtocol.self]
        let sessionCookieStore = HanaSessionCookieStore(
            credentialStore: DownloadResumeCredentialStore(),
            defaults: defaults
        )
        let httpClient = HanaHTTPClient(
            baseURL: URL(string: "https://downloads.test/")!,
            sessionCookieStore: sessionCookieStore
        )
        let client = HanimeDownloadClient(
            httpClient: httpClient,
            defaults: defaults,
            downloadsRootURL: rootURL,
            sessionConfiguration: configuration,
            backgroundTasksProvider: backgroundTasksProvider
        )
        return ClientEnvironment(
            client: client,
            defaults: defaults,
            rootURL: rootURL,
            suiteName: suiteName
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

private struct DownloadResumeCredentialStore: HanaCredentialStore {
    func data(for account: String) throws -> Data? { nil }
    func set(_ data: Data, for account: String) throws {}
    func removeData(for account: String) throws {}
}

@MainActor
private struct ClientEnvironment {
    let client: HanimeDownloadClient
    let defaults: UserDefaults
    let rootURL: URL
    let suiteName: String

    func cleanup() {
        let pendingIDs = Set(client.pendingDownloadIDs)
        for requestID in client.pendingDownloadIDs {
            client.cancel(id: requestID)
        }
        for snapshot in client.persistedTasks() {
            guard !pendingIDs.contains(snapshot.id) else { continue }
            client.cancel(id: snapshot.id)
        }
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }
}

nonisolated private final class ControlledDownloadURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedStartedPaths: [String] = []

    static var startedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedStartedPaths
    }

    static func reset() {
        lock.lock()
        storedStartedPaths = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "downloads.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "video/mp4",
                    "Content-Length": "1024"
                ]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        Self.lock.lock()
        Self.storedStartedPaths.append(url.path)
        Self.lock.unlock()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([0]))
    }

    override func stopLoading() {}
}
