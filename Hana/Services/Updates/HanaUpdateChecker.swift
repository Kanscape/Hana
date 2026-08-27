import Foundation
import Observation

struct HanaAvailableUpdate: Identifiable, Equatable, Sendable {
    var id: String { latestVersion.displayText }

    let currentVersion: HanaReleaseVersion
    let latestVersion: HanaReleaseVersion
    let releaseName: String
    let releaseNotes: String
    let releaseURL: URL

    var title: String {
        "发现新版本 \(latestVersion.displayText)"
    }

    var message: String {
        "当前版本 \(currentVersion.prefixedDisplayText)，点击以查看更新"
    }
}

enum HanaUpdateCheckResult: Equatable, Sendable {
    case updateAvailable(HanaAvailableUpdate)
    case upToDate(HanaReleaseVersion)
    case noRelease
}

enum HanaUpdateLinkDestination: String, CaseIterable, Identifiable {
    case github
    case altStore
    case sideStore
    case feather

    var id: String { rawValue }

    static let defaultValue = HanaUpdateLinkDestination.github.rawValue

    var title: String {
        switch self {
        case .github:
            "GitHub"
        case .altStore:
            "AltStore"
        case .sideStore:
            "SideStore"
        case .feather:
            "Feather"
        }
    }

    var buttonTitle: String {
        switch self {
        case .github:
            "下载"
        case .altStore:
            "打开 AltStore"
        case .sideStore:
            "打开 SideStore"
        case .feather:
            "打开 Feather"
        }
    }

    var launchURL: URL? {
        switch self {
        case .github:
            nil
        case .altStore:
            URL(string: "altstore://")
        case .sideStore:
            URL(string: "sidestore://")
        case .feather:
            URL(string: "feather://")
        }
    }

    var opensExternalSideloadingApp: Bool {
        self != .github
    }
}

enum HanaUpdateCheckError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case invalidCurrentVersion
    case invalidReleaseVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub 返回了无效响应"
        case .httpStatus(let statusCode):
            "GitHub 返回 HTTP \(statusCode)"
        case .invalidCurrentVersion:
            "当前版本号无效"
        case .invalidReleaseVersion(let version):
            "Release 版本号无效：\(version)"
        }
    }
}

@Observable
@MainActor
final class HanaUpdateChecker {
    static let websiteURL = URL(string: "https://hana.celia.sh")!
    static let repositoryURL = URL(string: "https://github.com/celia-sh/Hana")!
    static let releasesURL = URL(string: "https://github.com/celia-sh/Hana/releases")!
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/celia-sh/Hana/releases/latest")!
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    var isChecking = false
    var availableUpdate: HanaAvailableUpdate?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private let session: URLSession

    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        session: URLSession? = nil
    ) {
        self.defaults = defaults
        self.bundle = bundle

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 12
            configuration.connectionProxyDictionary = HanaNetworkProxySettings.current(defaults: defaults).connectionProxyDictionary
            self.session = URLSession(configuration: configuration)
        }
    }

    func checkAutomaticallyIfNeeded() async {
        guard defaults.object(forKey: HanaSettingsKey.autoCheckForUpdates) as? Bool ?? true else { return }
        guard shouldRunAutomaticCheck else { return }

        do {
            let result = try await checkForUpdates()
            markChecked()
            if case .updateAvailable(let update) = result {
                availableUpdate = update
            }
        } catch {
            markChecked()
        }
    }

    func checkManually() async throws -> HanaUpdateCheckResult {
        defer { markChecked() }
        return try await checkForUpdates()
    }

    private var shouldRunAutomaticCheck: Bool {
        guard let lastCheck = defaults.object(forKey: HanaSettingsKey.lastUpdateCheckDate) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCheck) >= Self.automaticCheckInterval
    }

    private func markChecked() {
        defaults.set(Date(), forKey: HanaSettingsKey.lastUpdateCheckDate)
    }

    private func checkForUpdates() async throws -> HanaUpdateCheckResult {
        guard !isChecking else {
            if let availableUpdate {
                return .updateAvailable(availableUpdate)
            }
            return .upToDate(try currentVersion())
        }

        isChecking = true
        defer { isChecking = false }

        let release = try await fetchLatestRelease()
        guard let release else {
            return .noRelease
        }

        let current = try currentVersion()
        guard let latest = HanaReleaseVersion(release.tagName) else {
            throw HanaUpdateCheckError.invalidReleaseVersion(release.tagName)
        }

        if latest > current {
            let update = HanaAvailableUpdate(
                currentVersion: current,
                latestVersion: latest,
                releaseName: release.name ?? release.tagName,
                releaseNotes: release.body ?? "",
                releaseURL: release.htmlURL
            )
            return .updateAvailable(update)
        }

        return .upToDate(current)
    }

    private func fetchLatestRelease() async throws -> GitHubRelease? {
        var request = URLRequest(url: Self.latestReleaseAPIURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(HanaHTTPClient.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HanaUpdateCheckError.invalidResponse
        }
        if httpResponse.statusCode == 404 {
            return nil
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HanaUpdateCheckError.httpStatus(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func currentVersion() throws -> HanaReleaseVersion {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let version, let releaseVersion = HanaReleaseVersion(version) else {
            throw HanaUpdateCheckError.invalidCurrentVersion
        }
        return releaseVersion
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
    }
}
