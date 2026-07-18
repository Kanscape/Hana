import Foundation
import SwiftData

@MainActor
enum HanaDownloadRecordSynchronizer {
    static func synchronize(
        downloadClient: HanimeDownloadClient,
        modelContext: ModelContext,
        records: [DownloadQueueRecord]
    ) async {
        await downloadClient.restoreBackgroundTasks()

        var records = records
        var changed = false
        changed = syncPersistedTasks(
            downloadClient: downloadClient,
            modelContext: modelContext,
            records: &records
        ) || changed
        changed = importLocalDownloads(
            downloadClient: downloadClient,
            modelContext: modelContext,
            records: &records
        ) || changed
        changed = recoverInterruptedDownloads(
            downloadClient: downloadClient,
            records: records
        ) || changed
        changed = deleteDuplicateRecords(
            modelContext: modelContext,
            records: &records
        ) || changed
        changed = deleteMissingCompletedRecords(
            modelContext: modelContext,
            records: &records
        ) || changed

        if changed {
            try? modelContext.save()
        }
    }

    @discardableResult
    static func syncPersistedTasks(
        downloadClient: HanimeDownloadClient,
        modelContext: ModelContext,
        records: inout [DownloadQueueRecord]
    ) -> Bool {
        let snapshots = downloadClient.persistedTasks()
        guard !snapshots.isEmpty else { return false }

        var changed = false
        for snapshot in snapshots {
            let request = snapshot.request
            if let existing = records.first(where: { $0.id == snapshot.id })
                ?? records.first(where: { downloadRecordKey(videoCode: $0.videoCode, quality: $0.quality) == downloadRecordKey(videoCode: request.videoCode, quality: request.quality) }) {
                existing.id = snapshot.id
                existing.title = request.title
                existing.coverURLString = request.coverURLString ?? existing.coverURLString
                existing.mediaURLString = request.mediaURL.absoluteString
                apply(snapshot, to: existing)
                changed = true
                continue
            }

            let record = DownloadQueueRecord(
                videoCode: request.videoCode,
                title: request.title,
                coverURLString: request.coverURLString,
                quality: request.quality,
                mediaURLString: request.mediaURL.absoluteString,
                createdAt: snapshot.createdAt,
                status: downloadStatusTitle(for: snapshot)
            )
            apply(snapshot, to: record)
            modelContext.insert(record)
            records.append(record)
            changed = true
        }
        return changed
    }

    @discardableResult
    static func importLocalDownloads(
        downloadClient: HanimeDownloadClient,
        modelContext: ModelContext,
        records: inout [DownloadQueueRecord]
    ) -> Bool {
        guard let files = try? downloadClient.localDownloads(), !files.isEmpty else {
            return false
        }

        let knownTitles = Dictionary(grouping: records, by: \.videoCode)
            .compactMapValues { $0.first?.title }
        let knownCovers = Dictionary(grouping: records, by: \.videoCode)
            .compactMapValues { $0.first?.coverURLString }
        var changed = false

        for file in files {
            let matches = matchingRecords(for: file, records: records)
            if let existing = preferredRecord(for: file, records: matches) {
                apply(file, to: existing)
                let duplicateIDs = Set(matches.map(\.id).filter { $0 != existing.id })
                for duplicate in matches where duplicate.id != existing.id {
                    modelContext.delete(duplicate)
                }
                if !duplicateIDs.isEmpty {
                    records.removeAll { duplicateIDs.contains($0.id) }
                }
                changed = true
                continue
            }

            let record = DownloadQueueRecord(
                videoCode: file.videoCode,
                title: file.title ?? knownTitles[file.videoCode] ?? file.videoCode,
                coverURLString: file.coverURLString ?? knownCovers[file.videoCode],
                quality: file.quality,
                mediaURLString: file.sourceURLString ?? file.fileURL.absoluteString,
                status: "已完成"
            )
            record.localFileURLString = file.fileURL.absoluteString
            record.completedAt = file.completedAt ?? .now
            record.progress = 1
            record.errorMessage = file.byteCount.map { ByteCountFormatStyle().format($0) }
            modelContext.insert(record)
            records.append(record)
            changed = true
        }

        return changed
    }

    @discardableResult
    static func recoverInterruptedDownloads(
        downloadClient: HanimeDownloadClient,
        records: [DownloadQueueRecord]
    ) -> Bool {
        var changed = false
        for record in records where !downloadClient.isDownloading(id: record.id) {
            guard record.status == "下载中" || record.status == "重试中" else { continue }
            record.status = "暂时失败"
            record.errorMessage = "后台任务已结束，可重新开始下载。"
            changed = true
        }
        return changed
    }

    static func apply(_ snapshot: HanimePersistedDownloadTask, to record: DownloadQueueRecord) {
        record.backgroundSessionIdentifier = snapshot.sessionIdentifier
        record.backgroundTaskIdentifier = snapshot.taskIdentifier
        record.backgroundTaskStartedAt = snapshot.createdAt
        record.backgroundTaskUpdatedAt = snapshot.updatedAt
        record.downloadedByteCount = snapshot.downloadedByteCount
        record.expectedByteCount = snapshot.expectedByteCount
        record.completionNotificationSentAt = snapshot.notificationSentAt
        record.progress = snapshot.progress

        switch snapshot.status {
        case .queued:
            guard record.status != "已完成" else { return }
            record.status = "等待下载"
            record.localFileURLString = nil
            record.errorMessage = snapshot.errorDescription
            record.completedAt = nil
        case .running:
            guard record.status != "已完成" else { return }
            record.status = "下载中"
            record.localFileURLString = nil
            record.errorMessage = snapshot.errorDescription ?? progressMessage(for: snapshot)
            record.completedAt = nil
        case .paused:
            guard record.status != "已完成" else { return }
            record.status = "已暂停"
            record.localFileURLString = nil
            record.errorMessage = snapshot.errorDescription
            record.completedAt = nil
        case .completed:
            record.status = "已完成"
            record.localFileURLString = snapshot.localFileURLString
            record.completedAt = snapshot.completedAt ?? record.completedAt ?? .now
            record.progress = 1
            record.errorMessage = snapshot.downloadedByteCount.map { ByteCountFormatStyle().format($0) }
        case .failed:
            guard record.status != "已完成" else { return }
            record.status = snapshot.failureKind == .transient ? "暂时失败" : "下载失败"
            record.errorMessage = snapshot.errorDescription
            record.completedAt = nil
        case .cancelled:
            guard record.status != "已完成" else { return }
            record.status = "已取消"
            record.errorMessage = nil
            record.completedAt = nil
        }
    }

    static func downloadStatusTitle(for status: HanimeDownloadTaskStatus) -> String {
        switch status {
        case .queued:
            "等待下载"
        case .running:
            "下载中"
        case .paused:
            "已暂停"
        case .completed:
            "已完成"
        case .failed:
            "下载失败"
        case .cancelled:
            "已取消"
        }
    }

    static func downloadStatusTitle(for snapshot: HanimePersistedDownloadTask) -> String {
        if snapshot.status == .failed, snapshot.failureKind == .transient {
            return "暂时失败"
        }
        return downloadStatusTitle(for: snapshot.status)
    }

    private static func matchingRecords(
        for file: HanimeLocalDownload,
        records: [DownloadQueueRecord]
    ) -> [DownloadQueueRecord] {
        let fileKey = downloadRecordKey(videoCode: file.videoCode, quality: file.quality)
        return records.filter { record in
            downloadRecordKey(videoCode: record.videoCode, quality: record.quality) == fileKey
        }
    }

    private static func preferredRecord(
        for file: HanimeLocalDownload,
        records: [DownloadQueueRecord]
    ) -> DownloadQueueRecord? {
        records.max { lhs, rhs in
            recordScore(lhs, for: file) < recordScore(rhs, for: file)
        }
    }

    private static func recordScore(_ record: DownloadQueueRecord, for file: HanimeLocalDownload) -> Int {
        if record.localFileURLString == file.fileURL.absoluteString {
            return 4
        }
        if let sourceURLString = file.sourceURLString, record.mediaURLString == sourceURLString {
            return 3
        }
        if record.mediaURLString == file.fileURL.absoluteString {
            return 2
        }
        if record.status == "已完成" {
            return 1
        }
        return 0
    }

    private static func apply(_ file: HanimeLocalDownload, to record: DownloadQueueRecord) {
        record.title = file.title ?? record.title
        record.coverURLString = file.coverURLString ?? record.coverURLString
        record.mediaURLString = file.sourceURLString ?? record.mediaURLString
        record.localFileURLString = file.fileURL.absoluteString
        record.status = "已完成"
        record.completedAt = file.completedAt ?? record.completedAt ?? .now
        record.progress = 1
        record.errorMessage = file.byteCount.map { ByteCountFormatStyle().format($0) }
        record.downloadedByteCount = file.byteCount ?? record.downloadedByteCount
        record.expectedByteCount = file.byteCount ?? record.expectedByteCount
    }

    private static func deleteDuplicateRecords(
        modelContext: ModelContext,
        records: inout [DownloadQueueRecord]
    ) -> Bool {
        var changed = false
        let groupedRecords = Dictionary(grouping: records) { record in
            downloadRecordKey(videoCode: record.videoCode, quality: record.quality)
        }

        for group in groupedRecords.values where group.count > 1 {
            guard let keptRecord = preferredRecordForDuplicateGroup(group) else { continue }
            let duplicates = group.filter { $0.id != keptRecord.id }
            merge(duplicates, into: keptRecord)
            for duplicate in duplicates {
                modelContext.delete(duplicate)
            }
            let duplicateIDs = Set(duplicates.map(\.id))
            records.removeAll { duplicateIDs.contains($0.id) }
            changed = true
        }

        return changed
    }

    private static func deleteMissingCompletedRecords(
        modelContext: ModelContext,
        records: inout [DownloadQueueRecord]
    ) -> Bool {
        let missingRecords = records.filter { record in
            guard record.status == "已完成" else { return false }
            guard let localFileURLString = record.localFileURLString,
                  let url = URL(string: localFileURLString) else {
                return true
            }
            return !FileManager.default.fileExists(atPath: url.path)
        }
        guard !missingRecords.isEmpty else { return false }

        for record in missingRecords {
            modelContext.delete(record)
        }
        let missingIDs = Set(missingRecords.map(\.id))
        records.removeAll { missingIDs.contains($0.id) }
        return true
    }

    private static func preferredRecordForDuplicateGroup(
        _ records: [DownloadQueueRecord]
    ) -> DownloadQueueRecord? {
        records.max { lhs, rhs in
            duplicateRecordScore(lhs) < duplicateRecordScore(rhs)
        }
    }

    private static func duplicateRecordScore(_ record: DownloadQueueRecord) -> Int {
        var score = 0
        if record.status == "已完成" {
            score += 100
        }
        if let localFileURLString = record.localFileURLString,
           let url = URL(string: localFileURLString),
           FileManager.default.fileExists(atPath: url.path) {
            score += 50
        }
        if !record.mediaURLString.hasPrefix("file://") {
            score += 20
        }
        if record.backgroundTaskIdentifier != nil {
            score += 10
        }
        score += Int(min(record.progress * 9, 9))
        return score
    }

    private static func merge(_ records: [DownloadQueueRecord], into keptRecord: DownloadQueueRecord) {
        for record in records {
            if keptRecord.coverURLString == nil {
                keptRecord.coverURLString = record.coverURLString
            }
            if keptRecord.mediaURLString.hasPrefix("file://"), !record.mediaURLString.hasPrefix("file://") {
                keptRecord.mediaURLString = record.mediaURLString
            }
            if keptRecord.localFileURLString == nil {
                keptRecord.localFileURLString = record.localFileURLString
            }
            if keptRecord.completedAt == nil {
                keptRecord.completedAt = record.completedAt
            }
            if keptRecord.errorMessage == nil {
                keptRecord.errorMessage = record.errorMessage
            }
            keptRecord.downloadedByteCount = keptRecord.downloadedByteCount ?? record.downloadedByteCount
            keptRecord.expectedByteCount = keptRecord.expectedByteCount ?? record.expectedByteCount
            keptRecord.backgroundSessionIdentifier = keptRecord.backgroundSessionIdentifier ?? record.backgroundSessionIdentifier
            keptRecord.backgroundTaskIdentifier = keptRecord.backgroundTaskIdentifier ?? record.backgroundTaskIdentifier
            keptRecord.backgroundTaskStartedAt = keptRecord.backgroundTaskStartedAt ?? record.backgroundTaskStartedAt
            keptRecord.backgroundTaskUpdatedAt = keptRecord.backgroundTaskUpdatedAt ?? record.backgroundTaskUpdatedAt
            keptRecord.completionNotificationSentAt = keptRecord.completionNotificationSentAt ?? record.completionNotificationSentAt
            if keptRecord.downloadGroupName == "默认分组", record.downloadGroupName != "默认分组" {
                keptRecord.downloadGroupName = record.downloadGroupName
            }
            keptRecord.createdAt = min(keptRecord.createdAt, record.createdAt)
        }
    }

    private static func downloadRecordKey(videoCode: String, quality: String) -> String {
        "\(videoCode.trimmingCharacters(in: .whitespacesAndNewlines))|\(quality.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func progressMessage(for snapshot: HanimePersistedDownloadTask) -> String? {
        guard let downloaded = snapshot.downloadedByteCount,
              let expected = snapshot.expectedByteCount,
              expected > 0 else {
            return nil
        }
        let downloadedText = ByteCountFormatStyle().format(downloaded)
        let expectedText = ByteCountFormatStyle().format(expected)
        return "\(downloadedText) / \(expectedText)"
    }
}
