import Foundation
import Observation
import WebKit

enum SiteWebFlowKind: Hashable {
    case login
    case cloudflare
}

struct SiteWebFlow: Identifiable, Hashable {
    let id: UUID
    let kind: SiteWebFlowKind
    let url: URL

    init(id: UUID = UUID(), kind: SiteWebFlowKind, url: URL) {
        self.id = id
        self.kind = kind
        self.url = url
    }

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

nonisolated private final class CloudflareWaiterCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var isRegistered = false
    private var isFinished = false
    private var isCancelled = false

    func register() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return false }
        isRegistered = true
        return !isCancelled
    }

    func cancel() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return false }
        isCancelled = true
        return isRegistered
    }

    @discardableResult
    func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        isFinished = true
        return !isCancelled
    }
}

private struct CloudflareWaiter {
    let continuation: CheckedContinuation<Bool, Never>
    let cancellation: CloudflareWaiterCancellation
}

@Observable
final class SiteWebSession: HanaCloudflareChallengeResolving {
    let baseURL: URL
    var activeFlow: SiteWebFlow?
    var lastSyncedCookieCount = 0
    var lastCookieSyncAt: Date?
    var lastLoginOpenedAt: Date?
    private(set) var lastCloudflareVerifiedAt: Date?
    private(set) var cloudflareVerificationGeneration: UInt64 = 0
    private(set) var isCloudflareVerificationPreparing = false
    private(set) var isCloudflareVerificationRequired = false
    var isLoggedIn: Bool
    var userID: String?
    var username: String?
    var avatarURLString: String?

    private let defaults: UserDefaults
    private let cookieStore: HanaSessionCookieStore
    private let now: () -> Date
    private let cloudflareWebInvalidator: (() async -> Void)?
    private var cloudflarePreparationID: UUID?
    private var isCloudflareInvalidationInProgress = false
    private var cloudflareInvalidationWaiters: [CheckedContinuation<Void, Never>] = []
    private var cookieStateGeneration: UInt64 = 0
    private var cloudflareWaiters: [UUID: CloudflareWaiter] = [:]

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
        isCloudflareVerificationPreparing
            || activeFlow?.kind == .cloudflare
            || !cloudflareWaiters.isEmpty
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
        now: @escaping () -> Date = Date.init,
        cloudflareWebInvalidator: (() async -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.defaults = defaults
        self.cookieStore = cookieStore
        self.now = now
        self.cloudflareWebInvalidator = cloudflareWebInvalidator
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

    func shouldPreserveLoginState(after error: Error) -> Bool {
        if error is CancellationError
            || (error as? URLError)?.code == .cancelled {
            return true
        }
        guard let networkError = error as? HanaNetworkError else { return false }
        switch networkError {
        case .cloudflareChallenge,
             .cloudflareVerificationCancelled,
             .cloudflareVerificationFailed:
            return true
        default:
            return false
        }
    }

    func requestLogin() {
        guard activeFlow == nil,
              !isCloudflareVerificationPreparing,
              !isCloudflareInvalidationInProgress,
              cloudflareWaiters.isEmpty else {
            return
        }
        activeFlow = SiteWebFlow(kind: .login, url: baseURL.appending(path: "login"))
        lastLoginOpenedAt = now()
    }

    func requestCloudflareVerification(_ url: URL? = nil) async {
        guard activeFlow == nil, !isCloudflareVerificationPreparing else { return }

        isCloudflareVerificationRequired = true
        let preparationID = UUID()
        cloudflarePreparationID = preparationID
        isCloudflareVerificationPreparing = true
        await performCloudflareInvalidation()

        guard cloudflarePreparationID == preparationID else { return }
        isCloudflareVerificationPreparing = false
        activeFlow = SiteWebFlow(kind: .cloudflare, url: url ?? baseURL)
    }

    func resolveCloudflareChallenge(
        at url: URL,
        requestGeneration: UInt64
    ) async -> Bool {
        if requestGeneration < cloudflareVerificationGeneration,
           isCloudflareVerified {
            return true
        }

        isCloudflareVerificationRequired = true
        let waiterID = UUID()
        let cancellation = CloudflareWaiterCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                registerCloudflareWaiter(
                    continuation,
                    id: waiterID,
                    url: url,
                    cancellation: cancellation
                )
            }
        } onCancel: {
            guard cancellation.cancel() else { return }
            Task { @MainActor [weak self] in
                self?.cancelCloudflareWaiter(id: waiterID)
            }
        }
    }

    func resolveCloudflareChallenge(at url: URL) async -> Bool {
        await resolveCloudflareChallenge(
            at: url,
            requestGeneration: cloudflareVerificationGeneration
        )
    }

    @discardableResult
    func complete(flowID: UUID, with cookies: [HTTPCookie]) -> Bool {
        guard let flow = activeFlow, flow.id == flowID else { return false }
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
                broadcastsAccountCookieChange: !usesExactRequestRetry,
                completesCloudflareFlow: true
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
            cloudflareVerificationGeneration &+= 1
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
        broadcastsAccountCookieChange: Bool = true,
        acceptsCloudflareClearance: Bool = true,
        completesCloudflareFlow: Bool = false
    ) {
        cookieStateGeneration &+= 1
        let cookiesToSync = acceptsCloudflareClearance
            ? cookies
            : cookies.filter { cookie in
                cookie.name != SiteWebCookieScope.cloudflareClearanceName
                    || !cookieMatchesCurrentHost(cookie)
            }
        let storage = HTTPCookieStorage.shared
        cookiesToSync.forEach { storage.setCookie($0) }
        let scopedCookies = cookiesToSync.filter(cookieMatchesCurrentHost)
        if let cookieHeader = cookieHeader(
            from: scopedCookies,
            preservingStoredCloudflareClearance: !acceptsCloudflareClearance
        ) {
            cookieStore.saveCookieHeader(cookieHeader, for: baseURL)
            if acceptsCloudflareClearance {
                updateCloudflareExpiryMetadata(from: scopedCookies)
            }
        }
        lastSyncedCookieCount = scopedCookies.count
        let shouldBroadcast = broadcastsAccountCookieChange
            && (completesCloudflareFlow
                || (!isCloudflareVerificationInProgress && cloudflareWaiters.isEmpty))
        if shouldBroadcast {
            lastCookieSyncAt = now()
        }
    }

    func syncDefaultWebCookies() async {
        await syncDefaultWebCookies { [self] in
            await defaultWebCookies()
        }
    }

    func syncDefaultWebCookies(
        loading loadCookies: () async -> [HTTPCookie]
    ) async {
        let startingGeneration = cookieStateGeneration
        let cookies = await loadCookies()
        guard startingGeneration == cookieStateGeneration else { return }
        sync(cookies: cookies, acceptsCloudflareClearance: false)
    }

    func syncSharedHTTPCookies() {
        let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        sync(cookies: cookies, acceptsCloudflareClearance: false)
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
        cookieStateGeneration &+= 1
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
        cancel()
        await performCloudflareInvalidation()
    }

    private func performCloudflareInvalidation() async {
        if isCloudflareInvalidationInProgress {
            await withCheckedContinuation { continuation in
                cloudflareInvalidationWaiters.append(continuation)
            }
            return
        }

        isCloudflareInvalidationInProgress = true
        cookieStateGeneration &+= 1
        removeSharedCloudflareClearance()
        removePersistedCloudflareClearance()
        clearCloudflareMetadata()
        if let cloudflareWebInvalidator {
            await cloudflareWebInvalidator()
        } else {
            await removeDefaultWebCloudflareClearance()
        }
        isCloudflareInvalidationInProgress = false
        let waiters = cloudflareInvalidationWaiters
        cloudflareInvalidationWaiters.removeAll()
        for continuation in waiters {
            continuation.resume()
        }
    }

    func cancel(flowID: UUID) {
        guard activeFlow?.id == flowID else { return }
        cancel()
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
        url: URL,
        cancellation: CloudflareWaiterCancellation
    ) {
        guard cancellation.register(), !Task.isCancelled else {
            cancellation.finish()
            continuation.resume(returning: false)
            return
        }
        if activeFlow?.kind == .login {
            cancellation.finish()
            continuation.resume(returning: false)
            return
        }

        cloudflareWaiters[id] = CloudflareWaiter(
            continuation: continuation,
            cancellation: cancellation
        )
        if !isCloudflareVerificationPreparing,
           activeFlow?.kind != .cloudflare {
            Task { @MainActor [weak self] in
                guard let self, self.cloudflareWaiters[id] != nil else { return }
                await self.requestCloudflareVerification(url)
            }
        }
    }

    private func cancelCloudflareWaiter(id: UUID) {
        guard let waiter = cloudflareWaiters.removeValue(forKey: id) else { return }
        waiter.cancellation.finish()
        waiter.continuation.resume(returning: false)

        guard cloudflareWaiters.isEmpty,
              isCloudflareVerificationPreparing || activeFlow?.kind == .cloudflare else {
            return
        }
        cancel()
    }

    private func resumeCloudflareWaiters(with result: Bool) {
        let waiters = Array(cloudflareWaiters.values)
        cloudflareWaiters.removeAll()
        for waiter in waiters {
            let wasNotCancelled = waiter.cancellation.finish()
            waiter.continuation.resume(returning: result && wasNotCancelled)
        }
    }

    private func loadStoredCookieMetadata() {
        guard let storedCookieHeader, !storedCookieHeader.isEmpty else { return }
        lastSyncedCookieCount = cookiePairs(from: storedCookieHeader).count
    }

    private func cookieHeader(
        from cookies: [HTTPCookie],
        preservingStoredCloudflareClearance: Bool
    ) -> String? {
        var pairs = cookies.map { (name: $0.name, value: $0.value) }
        if preservingStoredCloudflareClearance,
           !pairs.contains(where: { $0.name == SiteWebCookieScope.cloudflareClearanceName }),
           let storedCookieHeader,
           let clearance = cookiePairs(from: storedCookieHeader).first(where: {
               $0.name == SiteWebCookieScope.cloudflareClearanceName
           }) {
            pairs.append(clearance)
        }
        let header = pairs
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
