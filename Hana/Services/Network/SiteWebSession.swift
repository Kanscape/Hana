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
    private let legacyCookieHeaderKey = "Hana.SiteWebSession.cookieHeader"
    private let legacyIsLoggedInKey = "Hana.SiteWebSession.isLoggedIn"
    private let legacyUserIDKey = "Hana.SiteWebSession.userID"
    private let legacyUsernameKey = "Hana.SiteWebSession.username"
    private let legacyAvatarURLStringKey = "Hana.SiteWebSession.avatarURLString"

    private var keySuffix: String {
        Self.keySuffix(for: baseURL)
    }

    private var cookieHeaderKey: String {
        Self.scopedKey("cookieHeader", suffix: keySuffix)
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
        defaults.string(forKey: cookieHeaderKey) ?? (canReadLegacyKeys ? defaults.string(forKey: legacyCookieHeaderKey) : nil)
    }

    init(baseURL: URL, defaults: UserDefaults = .standard) {
        self.baseURL = baseURL
        self.defaults = defaults
        let legacyHost = baseURL.host() == URL(string: HanaSiteBaseURL.defaultValue)?.host()
        let keySuffix = Self.keySuffix(for: baseURL)
        let isLoggedInKey = Self.scopedKey("isLoggedIn", suffix: keySuffix)
        let userIDKey = Self.scopedKey("userID", suffix: keySuffix)
        let usernameKey = Self.scopedKey("username", suffix: keySuffix)
        let avatarURLStringKey = Self.scopedKey("avatarURLString", suffix: keySuffix)
        self.isLoggedIn = defaults.object(forKey: isLoggedInKey) as? Bool
            ?? (legacyHost ? defaults.bool(forKey: legacyIsLoggedInKey) : false)
        self.userID = defaults.string(forKey: userIDKey)
            ?? (legacyHost ? defaults.string(forKey: legacyUserIDKey) : nil)
        self.username = defaults.string(forKey: usernameKey)
            ?? (legacyHost ? defaults.string(forKey: legacyUsernameKey) : nil)
        self.avatarURLString = defaults.string(forKey: avatarURLStringKey)
            ?? (legacyHost ? defaults.string(forKey: legacyAvatarURLStringKey) : nil)
        restoreStoredCookies()
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
            defaults.set(cookieHeader, forKey: cookieHeaderKey)
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

    func logout() {
        isLoggedIn = false
        userID = nil
        username = nil
        avatarURLString = nil
        defaults.removeObject(forKey: cookieHeaderKey)
        defaults.set(false, forKey: isLoggedInKey)
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: usernameKey)
        defaults.removeObject(forKey: avatarURLStringKey)
        removeCookiesForCurrentHost()
    }

    func cancel() {
        activeFlow = nil
    }

    private func restoreStoredCookies() {
        guard let storedCookieHeader, !storedCookieHeader.isEmpty else { return }
        let cookies = cookies(from: storedCookieHeader)
        cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
        lastSyncedCookieCount = cookies.count
    }

    private func cookieHeader(from cookies: [HTTPCookie]) -> String? {
        let header = cookies
            .filter { cookie in
                guard let host = baseURL.host() else { return true }
                return cookie.domain.contains(host) || host.contains(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }
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
        guard let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) else { return nil }
        return cookies.first { $0.name == "cf_clearance" }
    }

    private func removeCookiesForCurrentHost() {
        guard let host = baseURL.host() else {
            HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
            return
        }
        HTTPCookieStorage.shared.cookies?.forEach { cookie in
            let cookieDomain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if cookieDomain.contains(host) || host.contains(cookieDomain) {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    private static func keySuffix(for baseURL: URL) -> String {
        baseURL.host()?.replacingOccurrences(of: ".", with: "_") ?? "default"
    }

    private static func scopedKey(_ name: String, suffix: String) -> String {
        "Hana.SiteWebSession.\(suffix).\(name)"
    }
}
