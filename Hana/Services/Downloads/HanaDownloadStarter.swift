import Foundation
import SwiftData

@MainActor
enum HanaDownloadStarter {
    static func start(
        _ item: DownloadQueueRecord,
        downloadClient: HanimeDownloadClient,
        siteSession: SiteWebSession,
        modelContext: ModelContext
    ) async {
        guard !downloadClient.isDownloading(id: item.id) else { return }
        guard let mediaURL = URL(string: item.mediaURLString) else {
            item.status = "下载失败"
            item.errorMessage = "下载地址无效"
            try? modelContext.save()
            return
        }

        await HanaDownloadNotifications.requestAuthorizationIfNeeded()
        item.status = "等待下载"
        item.errorMessage = nil
        item.completedAt = nil
        item.retryCount += 1
        try? modelContext.save()

        let request = HanimeDownloadRequest(
            id: item.id,
            videoCode: item.videoCode,
            title: item.title,
            coverURLString: item.coverURLString,
            quality: item.quality,
            mediaURL: mediaURL
        )

        do {
            let file = try await downloadClient.download(request) { snapshot in
                HanaDownloadRecordSynchronizer.apply(snapshot, to: item)
                try? modelContext.save()
            }
            item.status = "已完成"
            item.localFileURLString = file.fileURL.absoluteString
            item.completedAt = .now
            item.progress = 1
            item.downloadedByteCount = file.byteCount
            item.expectedByteCount = file.byteCount
            item.backgroundTaskUpdatedAt = .now
            item.errorMessage = file.byteCount.map { ByteCountFormatStyle().format($0) }
        } catch {
            if let snapshot = downloadClient.persistedTask(id: item.id) {
                HanaDownloadRecordSynchronizer.apply(snapshot, to: item)
            } else if siteSession.handle(error) {
                item.status = "需要 Cloudflare 验证"
            } else if error is CancellationError
                        || (error as? URLError)?.code == .cancelled {
                item.status = "已取消"
                item.errorMessage = nil
            } else {
                item.status = "下载失败"
                item.errorMessage = error.localizedDescription
            }
        }
        try? modelContext.save()
    }
}
