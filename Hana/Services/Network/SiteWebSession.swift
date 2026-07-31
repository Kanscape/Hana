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

enum SiteWebCookieScope {
    static let cloudflareClearanceName = "cf_clearance"

    static func matches(_ cookie: HTTPCookie, url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        let domain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !domain.isEmpty else { return false }
        return domain == host || host.hasSuffix(".\(domain)")
    }

    static func cloudflareClearance(
        in cookies: [HTTPCookie],
        for url: URL,
        now: Date = .now
    ) -> HTTPCookie? {
        cookies.first { cookie in
            cookie.name == cloudflareClearanceName
                && matches(cookie, url: url)
                && cookie.expiresDate.map { $0 > now } != false
        }
    }
}

@Observable
final class SiteWebSession: HanaCloudflareChallengeResolving {
    let baseURL: URL
    var activeFlow: SiteWebFlow?
    var lastSyncedCookieCount = 0
    var lastCookieSyncAt: Date?
    var lastLoginOpenedAt: Date?
    private(set) var lastCloudflareVerifiedAt: Date?
    private(set) var isCloudflareVerificationPreparing = false
    private(set) var isCloudflareVerificationRequired = false
    var isLoggedIn: Bool
    var userID: String?
    var username: String?
    var avatarURLString: String?

    private let defaults: UserDefaults
    private let cookieStore: HanaSessionCookieStore
    private let now: () -> Date
    private var cloudflarePreparationID: UUID?
    private var cloudflareWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var cancelledCloudflareWaiterIDs: Set<UUID> = []

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

    private var cloudflareVerifiedAtKey: String {
        Self.scopedKey("cloudflareVerifiedAt", suffix: keySuffix)
    }

    private var cloudflareExpiresAtKey: String {
        Self.scopedKey("cloudflareExpiresAt", suffix: keySuffix)
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

    var isCloudflareVerificationInProgress: Bool {
        isCloudflareVerificationPreparing || activeFlow?.kind == .cloudflare
    }

    var isCloudflareVerified: Bool {
        guard hasCloudflareClearance else { return false }
        return cloudflareClearanceExpiryDate.map { $0 > now() } != false
    }

    var cloudflareStatusText: String {
        if isCloudflareVerificationInProgress {
            return "验证中"
        }
        if isCloudflareVerificationRequired {
            return "需要验证"
        }
        guard hasCloudflareClearance else {
            return "无需验证"
        }
        if cloudflareClearanceExpiryDate.map({ $0 <= now() }) == true {
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
        cookieStore: HanaSessionCookieStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.defaults = defaults
        self.cookieStore = cookieStore
        self.now = now
        let legacyHost = baseURL.host() == URL(string: HanaSiteBaseURL.defaultValue)?.host()
        let keySuffix = Self.keySuffix(for: baseURL)
        let isLoggedInKey = Self.scopedKey("isLoggedIn", suffix: keySuffix)
        let userIDKey = Self.scopedKey("userID", suffix: keySuffix)
        let usernameKey = Self.scopedKey("username", suffix: keySuffix)
        let avatarURLStringKey = Self.scopedKey("avatarURLString", suffix: keySuffix)
        let cloudflareVerifiedAtKey = Self.scopedKey("cloudflareVerifiedAt", suffix: keySuffix)
        self.isLoggedIn = defaults.object(forKey: isLoggedInKey) as? Bool
            ?? (legacyHost ? defaults.bool(forKey: Self.legacyIsLoggedInKey) : false)
        self.userID = defaults.string(forKey: userIDKey)
            ?? (legacyHost ? defaults.string(forKey: Self.legacyUserIDKey) : nil)
        self.username = defaults.string(forKey: usernameKey)
            ?? (legacyHost ? defaults.string(forKey: Self.legacyUsernameKey) : nil)
        self.avatarURLString = defaults.string(forKey: avatarURLStringKey)
            ?? (legacyHost ? defaults.string(forKey: Self.legacyAvatarURLStringKey) : nil)
        self.lastCloudflareVerifiedAt = defaults.object(forKey: cloudflareVerifiedAtKey) as? Date
        loadStoredCookieMetadata()
    }

    @discardableResult
    func handle(_ error: Error) -> Bool {
        if case HanaNetworkError.cloudflareChallenge(let url) = error {
            Task { await requestCloudflareVerification(url) }
            return true
        }
        return false
    }

    func requestLogin() {
        guard activeFlow == nil, !isCloudflareVerificationPreparing else { return }
        activeFlow = SiteWebFlow(kind: .login, url: baseURL.appending(path: "login"))
        lastLoginOpenedAt = now()
    }

    func requestCloudflareVerification(_ url: URL? = nil) async {
        guard activeFlow == nil, !isCloudflareVerificationPreparing else { return }

        isCloudflareVerificationRequired = true
        let preparationID = UUID()
        cloudflarePreparationID = preparationID
        isCloudflareVerificationPreparing = true
        await invalidateCloudflareVerification()

        guard cloudflarePreparationID == preparationID else { return }
        isCloudflareVerificationPreparing = false
        activeFlow = SiteWebFlow(kind: .cloudflare, url: url ?? baseURL)
    }

    func resolveCloudflareChallenge(at url: URL) async -> Bool {
        isCloudflareVerificationRequired = true
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                registerCloudflareWaiter(continuation, id: waiterID, url: url)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelCloudflareWaiter(id: waiterID)
            }
        }
    }

    @discardableResult
    func complete(with cookies: [HTTPCookie]) -> Bool {
        guard let flow = activeFlow else { return false }
        if flow.kind == .cloudflare {
            guard let clearance = SiteWebCookieScope.cloudflareClearance(
                in: cookies,
                for: flow.url,
                now: now()
            ) else {
                return false
            }

            let usesExactRequestRetry = !cloudflareWaiters.isEmpty
            sync(
                cookies: cookies,
                broadcastsAccountCookieChange: !usesExactRequestRetry
            )
            let verifiedAt = now()
            lastCloudflareVerifiedAt = verifiedAt
            isCloudflareVerificationRequired = false
            defaults.set(verifiedAt, forKey: cloudflareVerifiedAtKey)
            if let expiresAt = clearance.expiresDate {
                defaults.set(expiresAt, forKey: cloudflareExpiresAtKey)
            } else {
                defaults.removeObject(forKey: cloudflareExpiresAtKey)
            }
            activeFlow = nil
            cloudflarePreparationID = nil
            resumeCloudflareWaiters(with: true)
            return true
        }

        sync(cookies: cookies)
        activeFlow = nil
        return true
    }

    func cloudflareVerificationDidFail() {
        isCloudflareVerificationRequired = true
    }

    func sync(
        cookies: [HTTPCookie],
        broadcastsAccountCookieChange: Bool = true
    ) {
        let storage = HTTPCookieStorage.shared
        cookies.forEach { storage.setCookie($0) }
        let scopedCookies = cookies.filter(cookieMatchesCurrentHost)
        if let cookieHeader = cookieHeader(from: scopedCookies) {
            cookieStore.saveCookieHeader(cookieHeader, for: baseURL)
            updateCloudflareExpiryMetadata(from: scopedCookies)
        }
        lastSyncedCookieCount = scopedCookies.count
        if broadcastsAccountCookieChange {
            lastCookieSyncAt = now()
        }
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
        cancel()
        isLoggedIn = false
        isCloudflareVerificationRequired = false
        userID = nil
        username = nil
        avatarURLString = nil
        cookieStore.removeCookieHeader(for: baseURL)
        defaults.set(false, forKey: isLoggedInKey)
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: usernameKey)
        defaults.removeObject(forKey: avatarURLStringKey)
        clearCloudflareMetadata()
        removeCookiesForCurrentHost()
        await removeDefaultWebCookiesForCurrentHost()
    }

    func invalidateCloudflareVerification() async {
        removeSharedCloudflareClearance()
        removePersistedCloudflareClearance()
        await removeDefaultWebCloudflareClearance()
        clearCloudflareMetadata()
    }

    func cancel() {
        let wasResolvingCloudflare = isCloudflareVerificationPreparing
            || activeFlow?.kind == .cloudflare
            || !cloudflareWaiters.isEmpty
        cloudflarePreparationID = nil
        isCloudflareVerificationPreparing = false
        activeFlow = nil
        if wasResolvingCloudflare {
            resumeCloudflareWaiters(with: false)
        }
    }

    private func registerCloudflareWaiter(
        _ continuation: CheckedContinuation<Bool, Never>,
        id: UUID,
        url: URL
    ) {
        if Task.isCancelled || cancelledCloudflareWaiterIDs.remove(id) != nil {
            continuation.resume(returning: false)
            return
        }
        if activeFlow?.kind == .login {
            continuation.resume(returning: false)
            return
        }

        cloudflareWaiters[id] = continuation
        if !isCloudflareVerificationInProgress {
            Task { @MainActor [weak self] in
                await self?.requestCloudflareVerification(url)
            }
        }
    }

    private func cancelCloudflareWaiter(id: UUID) {
        guard let continuation = cloudflareWaiters.removeValue(forKey: id) else {
            cancelledCloudflareWaiterIDs.insert(id)
            return
        }
        continuation.resume(returning: false)
    }

    private func resumeCloudflareWaiters(with result: Bool) {
        let waiters = cloudflareWaiters
        cloudflareWaiters.removeAll()
        for id in waiters.keys {
            cancelledCloudflareWaiterIDs.remove(id)
        }
        for continuation in waiters.values {
            continuation.resume(returning: result)
        }
    }

    private func loadStoredCookieMetadata() {
        guard let storedCookieHeader, !storedCookieHeader.isEmpty else { return }
        lastSyncedCookieCount = cookiePairs(from: storedCookieHeader).count
    }

    private func cookieHeader(from cookies: [HTTPCookie]) -> String? {
        let header = cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        return header.isEmpty ? nil : header
    }

    private func cookies(from header: String) -> [HTTPCookie] {
        guard let host = baseURL.host() else { return [] }
        return cookiePairs(from: header).compactMap { pair in
            HTTPCookie(properties: [
                .domain: host,
                .path: "/",
                .name: pair.name,
                .value: pair.value,
                .secure: baseURL.scheme == "https",
                .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)
            ])
        }
    }

    private func cookiePairs(from header: String) -> [(name: String, value: String)] {
        header.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return (parts[0], parts[1])
        }
    }

    private func defaultWebCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private var hasCloudflareClearance: Bool {
        let sharedCookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        if sharedCookies.contains(where: {
            $0.name == SiteWebCookieScope.cloudflareClearanceName && cookieMatchesCurrentHost($0)
        }) {
            return true
        }
        guard let storedCookieHeader else { return false }
        return cookiePairs(from: storedCookieHeader).contains {
            $0.name == SiteWebCookieScope.cloudflareClearanceName
        }
    }

    private var cloudflareClearanceExpiryDate: Date? {
        let sharedExpirations = (HTTPCookieStorage.shared.cookies(for: baseURL) ?? [])
            .filter {
                $0.name == SiteWebCookieScope.cloudflareClearanceName && cookieMatchesCurrentHost($0)
            }
            .compactMap(\.expiresDate)
        return sharedExpirations.max()
            ?? defaults.object(forKey: cloudflareExpiresAtKey) as? Date
    }

    private func updateCloudflareExpiryMetadata(from cookies: [HTTPCookie]) {
        guard let clearance = cookies.first(where: {
            $0.name == SiteWebCookieScope.cloudflareClearanceName && cookieMatchesCurrentHost($0)
        }) else {
            defaults.removeObject(forKey: cloudflareExpiresAtKey)
            return
        }
        if let expiresAt = clearance.expiresDate {
            defaults.set(expiresAt, forKey: cloudflareExpiresAtKey)
        } else {
            defaults.removeObject(forKey: cloudflareExpiresAtKey)
        }
    }

    private func clearCloudflareMetadata() {
        lastCloudflareVerifiedAt = nil
        defaults.removeObject(forKey: cloudflareVerifiedAtKey)
        defaults.removeObject(forKey: cloudflareExpiresAtKey)
    }

    private func removeSharedCloudflareClearance() {
        HTTPCookieStorage.shared.cookies?.forEach { cookie in
            if cookie.name == SiteWebCookieScope.cloudflareClearanceName,
               cookieMatchesCurrentHost(cookie) {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    private func removePersistedCloudflareClearance() {
        guard let storedCookieHeader else { return }
        let remainingPairs = cookiePairs(from: storedCookieHeader).filter {
            $0.name != SiteWebCookieScope.cloudflareClearanceName
        }
        guard remainingPairs.count != cookiePairs(from: storedCookieHeader).count else { return }
        let remainingHeader = remainingPairs
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if remainingHeader.isEmpty {
            cookieStore.removeCookieHeader(for: baseURL)
        } else {
            cookieStore.saveCookieHeader(remainingHeader, for: baseURL)
        }
        lastSyncedCookieCount = remainingPairs.count
    }

    private func removeCookiesForCurrentHost() {
        HTTPCookieStorage.shared.cookies?.forEach { cookie in
            if cookieMatchesCurrentHost(cookie) {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    private func removeDefaultWebCloudflareClearance() async {
        let webCookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            webCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies
        where cookie.name == SiteWebCookieScope.cloudflareClearanceName
            && cookieMatchesCurrentHost(cookie) {
            await withCheckedContinuation { continuation in
                webCookieStore.delete(cookie) { continuation.resume() }
            }
        }
    }

    private func removeDefaultWebCookiesForCurrentHost() async {
        let webCookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            webCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where cookieMatchesCurrentHost(cookie) {
            await withCheckedContinuation { continuation in
                webCookieStore.delete(cookie) { continuation.resume() }
            }
        }
    }

    private func cookieMatchesCurrentHost(_ cookie: HTTPCookie) -> Bool {
        SiteWebCookieScope.matches(cookie, url: baseURL)
    }

    private static func keySuffix(for baseURL: URL) -> String {
        baseURL.host()?.replacingOccurrences(of: ".", with: "_") ?? "default"
    }

    private static func scopedKey(_ name: String, suffix: String) -> String {
        "Hana.SiteWebSession.\(suffix).\(name)"
    }
}
