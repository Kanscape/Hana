import Foundation
import SwiftUI
#if canImport(AppKit) && os(macOS)
import AppKit
#endif

enum HanaSettingsKey {
    static let siteBaseURL = "hana.settings.siteBaseURL"
    static let appearanceMode = "hana.settings.appearanceMode"
    static let themeColor = "hana.settings.themeColor"
    static let demoModeEnabled = "hana.settings.demoModeEnabled"
    static let defaultVideoQuality = "hana.settings.defaultVideoQuality"
    static let allowResumePlayback = "hana.settings.allowResumePlayback"
    static let showPlayedIndicator = "hana.settings.showPlayedIndicator"
    static let videoLanguage = "hana.settings.videoLanguage"
    static let pictureInPictureEnabled = "hana.settings.pictureInPictureEnabled"
    static let loopPlaybackEnabled = "hana.settings.loopPlaybackEnabled"
    static let playerLongPressRate = "hana.settings.playerLongPressRate"
    static let hKeyframesEnabled = "hana.settings.hKeyframesEnabled"
    static let hKeyframeCountdownSeconds = "hana.settings.hKeyframeCountdownSeconds"
    static let hKeyframeShowPrompt = "hana.settings.hKeyframeShowPrompt"
    static let sharedHKeyframesEnabled = "hana.settings.sharedHKeyframesEnabled"
    static let sharedHKeyframesPreferred = "hana.settings.sharedHKeyframesPreferred"
    static let defaultDownloadQuality = "hana.settings.defaultDownloadQuality"
    static let downloadConcurrency = "hana.settings.downloadConcurrency"
    static let startDownloadsImmediately = "hana.settings.startDownloadsImmediately"
    static let collapsedDownloadGroupIDs = "hana.settings.collapsedDownloadGroupIDs"
    static let warnBeforeMobileDataDownload = "hana.settings.warnBeforeMobileDataDownload"
    nonisolated static let downloadDirectoryBookmark = "hana.settings.downloadDirectoryBookmark"
    static let networkProxyMode = "hana.settings.networkProxyMode"
    static let networkProxyHost = "hana.settings.networkProxyHost"
    static let networkProxyPort = "hana.settings.networkProxyPort"
    static let autoCheckForUpdates = "hana.settings.autoCheckForUpdates"
    static let lastUpdateCheckDate = "hana.settings.lastUpdateCheckDate"
    static let updateLinkDestination = "hana.settings.updateLinkDestination"
    static let disciplineModeConfiguration = "hana.settings.disciplineModeConfiguration"
}

enum HanaSiteBaseURL {
    static let defaultValue = "https://hanime1.me/"
    static let options: [String] = [
        "https://hanime1.me/",
        "https://hanime1.com/",
        "https://hanimeone.me/"
    ]

    static func normalized(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let withScheme = text.contains("://") ? text : "https://\(text)"
        guard var components = URLComponents(string: withScheme),
              components.host?.isEmpty == false else {
            return nil
        }
        components.scheme = "https"
        components.path = components.path.isEmpty ? "/" : components.path
        return components.url?.absoluteString
    }
}

enum HanaAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "跟随系统"
        case .light:
            "浅色"
        case .dark:
            "深色"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            "circle.lefthalf.filled"
        case .light:
            "sun.max"
        case .dark:
            "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

#if os(macOS)
extension HanaAppearanceMode {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func applyToApplication() {
        NSApp.appearance = nsAppearance
        for window in NSApp.windows {
            window.appearance = nil
            Self.clearExplicitAppearance(in: window.contentViewController?.view)
            Self.clearExplicitAppearance(in: window.contentView)
            window.contentView?.needsDisplay = true
            window.contentViewController?.view.needsDisplay = true
            window.invalidateShadow()
        }
    }

    private static func clearExplicitAppearance(in view: NSView?) {
        guard let view else { return }
        view.appearance = nil
        for subview in view.subviews {
            clearExplicitAppearance(in: subview)
        }
    }
}
#endif

enum HanaThemeColor: String, CaseIterable, Identifiable {
    case pink
    case blue
    case purple
    case orange
    case green
    case teal

    static let defaultValue = pink.rawValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pink:
            "粉色"
        case .blue:
            "蓝色"
        case .purple:
            "紫色"
        case .orange:
            "橙色"
        case .green:
            "绿色"
        case .teal:
            "青色"
        }
    }

    var color: Color {
        switch self {
        case .pink:
            .pink
        case .blue:
            .blue
        case .purple:
            .purple
        case .orange:
            .orange
        case .green:
            .green
        case .teal:
            .teal
        }
    }
}

enum HanaNetworkProxyMode: String, CaseIterable, Identifiable {
    case system
    case direct
    case http
    case socks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "系统设置"
        case .direct:
            "直连"
        case .http:
            "HTTP"
        case .socks:
            "SOCKS"
        }
    }

    var requiresEndpoint: Bool {
        self == .http || self == .socks
    }
}

struct HanaNetworkProxySettings: Hashable, Sendable {
    var mode: HanaNetworkProxyMode
    var host: String
    var port: Int

    static func current(defaults: UserDefaults = .standard) -> HanaNetworkProxySettings {
        let mode = HanaNetworkProxyMode(
            rawValue: defaults.string(forKey: HanaSettingsKey.networkProxyMode) ?? HanaNetworkProxyMode.system.rawValue
        ) ?? .system
        let host = defaults.string(forKey: HanaSettingsKey.networkProxyHost) ?? ""
        let port = defaults.object(forKey: HanaSettingsKey.networkProxyPort) as? Int ?? 7890
        return HanaNetworkProxySettings(mode: mode, host: host, port: port)
    }

    var connectionProxyDictionary: [AnyHashable: Any]? {
        switch mode {
        case .system:
            return nil
        case .direct:
            return [
                HanaProxyDictionaryKey.httpEnable: 0,
                HanaProxyDictionaryKey.httpsEnable: 0,
                HanaProxyDictionaryKey.socksEnable: 0
            ]
        case .http:
            guard isEndpointValid else { return nil }
            return [
                HanaProxyDictionaryKey.httpEnable: 1,
                HanaProxyDictionaryKey.httpProxy: host,
                HanaProxyDictionaryKey.httpPort: port,
                HanaProxyDictionaryKey.httpsEnable: 1,
                HanaProxyDictionaryKey.httpsProxy: host,
                HanaProxyDictionaryKey.httpsPort: port
            ]
        case .socks:
            guard isEndpointValid else { return nil }
            return [
                HanaProxyDictionaryKey.socksEnable: 1,
                HanaProxyDictionaryKey.socksProxy: host,
                HanaProxyDictionaryKey.socksPort: port
            ]
        }
    }

    private var isEndpointValid: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && port > 0
    }
}

private enum HanaProxyDictionaryKey {
    static let httpEnable = "HTTPEnable"
    static let httpProxy = "HTTPProxy"
    static let httpPort = "HTTPPort"
    static let httpsEnable = "HTTPSEnable"
    static let httpsProxy = "HTTPSProxy"
    static let httpsPort = "HTTPSPort"
    static let socksEnable = "SOCKSEnable"
    static let socksProxy = "SOCKSProxy"
    static let socksPort = "SOCKSPort"
}

nonisolated enum HanaDownloadDirectoryError: LocalizedError, Equatable {
    case invalidBookmark
    case staleBookmark
    case accessDenied
    case directoryNotConfigured

    var errorDescription: String? {
        switch self {
        case .invalidBookmark:
            "外部下载目录授权已损坏，请重新选择目录。"
        case .staleBookmark:
            "外部下载目录授权已失效，请重新选择目录。"
        case .accessDenied:
            "无法访问外部下载目录，请重新选择该目录后再试。"
        case .directoryNotConfigured:
            "请先选择外部下载目录。"
        }
    }
}

nonisolated enum HanaDownloadDirectoryPreference {
    typealias BookmarkResolver = (Data) throws -> (url: URL, isStale: Bool)

    nonisolated static func saveExternalDirectory(_ url: URL, defaults: UserDefaults = .standard) throws {
#if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
#else
        let options: URL.BookmarkCreationOptions = []
#endif
        let bookmarkData = try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmarkData, forKey: HanaSettingsKey.downloadDirectoryBookmark)
    }

    nonisolated static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: HanaSettingsKey.downloadDirectoryBookmark)
    }

    nonisolated static func hasExternalDirectoryBookmark(defaults: UserDefaults = .standard) -> Bool {
        defaults.data(forKey: HanaSettingsKey.downloadDirectoryBookmark) != nil
    }

    nonisolated static func resolvedExternalDirectory(
        defaults: UserDefaults = .standard,
        resolver: BookmarkResolver? = nil
    ) throws -> URL? {
        guard let data = defaults.data(forKey: HanaSettingsKey.downloadDirectoryBookmark) else {
            return nil
        }

        let resolution: (url: URL, isStale: Bool)
        do {
            resolution = try (resolver ?? resolveBookmark)(data)
        } catch {
            throw HanaDownloadDirectoryError.invalidBookmark
        }
        guard !resolution.isStale else {
            throw HanaDownloadDirectoryError.staleBookmark
        }
        return resolution.url
    }

    nonisolated static func displayName(defaults: UserDefaults = .standard) -> String {
        do {
            return try resolvedExternalDirectory(defaults: defaults)?.lastPathComponent ?? "应用目录"
        } catch {
            return "需要重新选择"
        }
    }

    private nonisolated static func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
#if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
#else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
#endif
        let url = try URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }
}

enum HanaVideoQualityPreference: String, CaseIterable, Identifiable {
    case p480 = "480P"
    case p720 = "720P"
    case p1080 = "1080P"

    var id: String { rawValue }

    static let defaultValue = HanaVideoQualityPreference.p1080

    static func normalizedRawValue(_ value: String) -> String {
        HanaVideoQualityPreference(rawValue: value)?.rawValue ?? defaultValue.rawValue
    }

    var title: String {
        rawValue
    }

    var qualityText: String {
        rawValue
    }
}

enum HanaVideoLanguagePreference: String, CaseIterable, Identifiable {
    case automatic = "automatic"
    case zhHans = "zhs"
    case zhHant = "zht"

    var id: String { rawValue }

    static let cookieName = "user_lang"

    var title: String {
        switch self {
        case .automatic:
            "自动"
        case .zhHans:
            "简体中文"
        case .zhHant:
            "繁体中文"
        }
    }

    var cookieValue: String? {
        switch self {
        case .automatic:
            nil
        case .zhHans:
            "zhs"
        case .zhHant:
            "zht"
        }
    }

    static func normalizedRawValue(_ rawValue: String) -> String {
        switch rawValue {
        case "zh-Hans":
            Self.zhHans.rawValue
        case "zh-Hant":
            Self.zhHant.rawValue
        default:
            rawValue
        }
    }

    static func cookieValue(for rawValue: String?) -> String? {
        let normalized = normalizedRawValue(rawValue ?? Self.zhHans.rawValue)
        return Self(rawValue: normalized)?.cookieValue
    }
}
