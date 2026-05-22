import Foundation
import SwiftUI

enum HanaSettingsKey {
    static let siteBaseURL = "hana.settings.siteBaseURL"
    static let appearanceMode = "hana.settings.appearanceMode"
    static let themeColor = "hana.settings.themeColor"
    static let defaultVideoQuality = "hana.settings.defaultVideoQuality"
    static let allowResumePlayback = "hana.settings.allowResumePlayback"
    static let showPlayedIndicator = "hana.settings.showPlayedIndicator"
    static let videoLanguage = "hana.settings.videoLanguage"
    static let pictureInPictureEnabled = "hana.settings.pictureInPictureEnabled"
    static let playerLongPressRate = "hana.settings.playerLongPressRate"
    static let hKeyframesEnabled = "hana.settings.hKeyframesEnabled"
    static let hKeyframeCountdownSeconds = "hana.settings.hKeyframeCountdownSeconds"
    static let hKeyframeShowPrompt = "hana.settings.hKeyframeShowPrompt"
    static let sharedHKeyframesEnabled = "hana.settings.sharedHKeyframesEnabled"
    static let sharedHKeyframesPreferred = "hana.settings.sharedHKeyframesPreferred"
    static let defaultDownloadQuality = "hana.settings.defaultDownloadQuality"
    static let downloadConcurrency = "hana.settings.downloadConcurrency"
    static let warnBeforeMobileDataDownload = "hana.settings.warnBeforeMobileDataDownload"
    static let networkProxyMode = "hana.settings.networkProxyMode"
    static let networkProxyHost = "hana.settings.networkProxyHost"
    static let networkProxyPort = "hana.settings.networkProxyPort"
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

enum HanaDownloadDirectoryPreference {
    nonisolated static func saveExternalDirectory(_ url: URL, defaults: UserDefaults = .standard) throws {
        let bookmarkData = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmarkData, forKey: "hana.settings.downloadDirectoryBookmark")
    }

    nonisolated static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "hana.settings.downloadDirectoryBookmark")
    }

    nonisolated static func resolvedExternalDirectory(defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: "hana.settings.downloadDirectoryBookmark") else {
            return nil
        }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    nonisolated static func displayName(defaults: UserDefaults = .standard) -> String {
        resolvedExternalDirectory(defaults: defaults)?.lastPathComponent ?? "应用目录"
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
