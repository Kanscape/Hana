import Foundation
import UserNotifications

enum HanaDownloadNotifications {
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func notifyCompleted(request: HanimeDownloadRequest, file: HanimeDownloadedFile) async -> Date? {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus.allowsNotificationDelivery else {
            return nil
        }

        let content = UNMutableNotificationContent()
        content.title = "下载完成"
        content.body = "\(request.title) \(request.quality) 已保存"
        if let byteCount = file.byteCount {
            content.subtitle = ByteCountFormatStyle().format(byteCount)
        }
        content.sound = .default

        let notification = UNNotificationRequest(
            identifier: "hana.download.completed.\(request.id)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(notification)
            return .now
        } catch {
            return nil
        }
    }
}

private extension UNAuthorizationStatus {
    var allowsNotificationDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .denied, .notDetermined:
            false
        @unknown default:
            false
        }
    }
}
