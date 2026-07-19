import Foundation
import Observation
import WebKit

enum SiteWebFlowKind: Hashable {
    case login
    case cloudflare
}

struct SiteWebFlow: Identifiable, Hashable {
    var id: String { "\(kind)-\(url.absoluteString)" }
    let kind: SiteWebFlowKind
    let url: URL

    var title: String {
        switch kind {
        case .login:
            "登录"
        case .cloudflare:
            "站点验证"
        }
    }
}

@Observable
final class SiteWebSession {
    let baseURL: URL
    var activeFlow: SiteWebFlow?
    var lastSyncedCookieCount = 0
    var lastCookieSyncAt: Date?
    var lastLoginOpenedAt: Date?
    var isLoggedIn: Bool
    var userID: String?
    var username: String?
    var avatarURLString: String?

    private let defaults: UserDefaults
    private let cookieStore: HanaSessionCookieStore
    private static let legacyIsLoggedInKey = "Hana.SiteWebSession.isLoggedIn"
    private static let legacyUserIDKey = "Hana.SiteWebSession.userID"
    private static let legacyUsernameKey = "Hana.SiteWebSession.username"
    private static let legacyAvatarURLStringKey = "Hana.SiteWebSession.avatarURLString"

    private var keySuffix: String {
        Self.keySuffix(for: baseURL)
    }

    private var isLoggedInKey: String {
        Self.scopedKey("isLoggedIn", suffix: keySuffix)
    }

    private var userIDKey: String {
        Self.scopedKey("userID", suffix: keySuffix)
    }

    private var usernameKey: String {
        Self.scopedKey("username", suffix: keySuffix)
    }

    private var avatarURLStringKey: String {
        Self.scopedKey("avatarURLString", suffix: keySuffix)
    }

    private var canReadLegacyKeys: Bool {
        baseURL.host() == URL(string: HanaSiteBaseURL.defaultValue)?.host()
    }

    var hasStoredCookies: Bool {
        storedCookieHeader?.isEmpty == false
    }

    var displayName: String {
        username ?? "已登录"
    }

    var cloudflareStatusText: String {
        guard let cookie = cloudflareClearanceCookie else {
            return "未验证"
        }
        if let expiresDate = cookie.expiresDate, expiresDate < .now {
            return "已过期"
        }
        return "已验证"
    }

    private var storedCookieHeader: String? {
        cookieStore.cookieHeader(for: baseURL)
    }

    init(
        baseURL: URL,
        defaults: UserDefaults = .standard,
        cookieStore: HanaSessionCookieStore
    ) {
        self.baseURL = baseURL
        self.defaults = defaults
        self.cookieStore = cookieStore
        let legacyHost = baseURL.host() == URL(string: HanaSiteBaseURL.defaultValue)?.host()
        let keySuffix = Self.keySuffix(for: baseURL)
        let isLoggedInKey = Self.scopedKey("isLoggedIn", suffix: keySuffix)
        let userIDKey = Self.scopedKey("userID", suffix: keySuffix)
        let usernameKey = Self.scopedKey("username", suffix: keySuffix)
        let avatarURLStringKey = Self.scopedKey("avatarURLString", suffix: keySuffix)
        self.isLoggedIn = defaults.object(forKey: isLoggedInKey) as? Bool
            ?? (legacyHost ? defaults.bool(forKey: Self.legacyIsLoggedInKey) : false)
        self.userID = defaults.string(forKey: userIDKey)
            ?? (legacyHost ? defaults.string(forKey: Self.legacyUserIDKey) : nil)
        self.username = defaults.string(forKey: usernameKey)
            ?? (legacyHost ? defaults.string(forKey: Self.legacyUsernameKey) : nil)
        self.avatarURLString = defaults.string(forKey: avatarURLStringKey)
            ?? (legacyHost ? defaults.string(forKey: Self.legacyAvatarURLStringKey) : nil)
        loadStoredCookieMetadata()
    }

    @discardableResult
    func handle(_ error: Error) -> Bool {
        if case HanaNetworkError.cloudflareChallenge(let url) = error {
            requestCloudflareVerification(url)
            return true
        }
        return false
    }

    func requestLogin() {
        activeFlow = SiteWebFlow(kind: .login, url: baseURL.appending(path: "login"))
        lastLoginOpenedAt = .now
    }

    func requestCloudflareVerification(_ url: URL? = nil) {
        activeFlow = SiteWebFlow(kind: .cloudflare, url: url ?? baseURL)
    }

    func complete(with cookies: [HTTPCookie]) {
        sync(cookies: cookies)
        activeFlow = nil
    }

    func sync(cookies: [HTTPCookie]) {
        let storage = HTTPCookieStorage.shared
        cookies.forEach { storage.setCookie($0) }
        if let cookieHeader = cookieHeader(from: cookies) {
            cookieStore.saveCookieHeader(cookieHeader, for: baseURL)
        }
        lastSyncedCookieCount = cookies.count
        lastCookieSyncAt = .now
    }

    func syncDefaultWebCookies() async {
        let cookies = await defaultWebCookies()
        sync(cookies: cookies)
    }

    func syncSharedHTTPCookies() {
        let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        sync(cookies: cookies)
    }

    func updateLoginState(user: HanimeUserProfile?) {
        guard let user else {
            isLoggedIn = false
            userID = nil
            username = nil
            avatarURLString = nil
            defaults.set(false, forKey: isLoggedInKey)
            defaults.removeObject(forKey: userIDKey)
            defaults.removeObject(forKey: usernameKey)
            defaults.removeObject(forKey: avatarURLStringKey)
            return
        }

        isLoggedIn = true
        userID = user.id
        username = user.username
        avatarURLString = user.avatarURL?.absoluteString
        defaults.set(true, forKey: isLoggedInKey)
        defaults.set(user.id, forKey: userIDKey)
        defaults.set(user.username, forKey: usernameKey)
        defaults.set(user.avatarURL?.absoluteString, forKey: avatarURLStringKey)
    }

    func logout() async {
        isLoggedIn = false
        userID = nil
        username = nil
        avatarURLString = nil
        cookieStore.removeCookieHeader(for: baseURL)
        defaults.set(false, forKey: isLoggedInKey)
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: usernameKey)
        defaults.removeObject(forKey: avatarURLStringKey)
        removeCookiesForCurrentHost()
        await removeDefaultWebCookiesForCurrentHost()
    }

    func cancel() {
        activeFlow = nil
    }

    private func loadStoredCookieMetadata() {
        guard let storedCookieHeader, !storedCookieHeader.isEmpty else { return }
        let cookies = cookies(from: storedCookieHeader)
        lastSyncedCookieCount = cookies.count
    }

    private func cookieHeader(from cookies: [HTTPCookie]) -> String? {
        let header = cookies
            .filter(cookieMatchesCurrentHost)
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        return header.isEmpty ? nil : header
    }

    private func cookies(from header: String) -> [HTTPCookie] {
        guard let host = baseURL.host() else { return [] }
        return header.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return HTTPCookie(properties: [
                .domain: host,
                .path: "/",
                .name: parts[0],
                .value: parts[1],
                .secure: baseURL.scheme == "https",
                .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)
            ])
        }
    }

    private func defaultWebCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private var cloudflareClearanceCookie: HTTPCookie? {
        if let cookie = HTTPCookieStorage.shared.cookies(for: baseURL)?.first(where: { $0.name == "cf_clearance" }) {
            return cookie
        }
        guard let storedCookieHeader else { return nil }
        return cookies(from: storedCookieHeader).first { $0.name == "cf_clearance" }
    }

    private func removeCookiesForCurrentHost() {
        HTTPCookieStorage.shared.cookies?.forEach { cookie in
            if cookieMatchesCurrentHost(cookie) {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    private func removeDefaultWebCookiesForCurrentHost() async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where cookieMatchesCurrentHost(cookie) {
            await withCheckedContinuation { continuation in
                cookieStore.delete(cookie) { continuation.resume() }
            }
        }
    }

    private func cookieMatchesCurrentHost(_ cookie: HTTPCookie) -> Bool {
        guard let host = baseURL.host()?.lowercased() else { return false }
        let cookieDomain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return cookieDomain == host
            || cookieDomain.hasSuffix(".\(host)")
            || host.hasSuffix(".\(cookieDomain)")
    }

    private static func keySuffix(for baseURL: URL) -> String {
        baseURL.host()?.replacingOccurrences(of: ".", with: "_") ?? "default"
    }

    private static func scopedKey(_ name: String, suffix: String) -> String {
        "Hana.SiteWebSession.\(suffix).\(name)"
    }
}
