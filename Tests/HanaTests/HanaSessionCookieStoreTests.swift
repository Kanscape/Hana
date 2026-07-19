import Foundation
import Testing
import WebKit

@testable import Hana

@MainActor
@Suite("Session cookie storage")
struct HanaSessionCookieStoreTests {
  @Test("writes to Keychain without leaving a fallback")
  func keychainWriteSuccess() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let url = try #require(URL(string: "https://mirror.example"))

    store.saveCookieHeader("session=secret", for: url)

    #expect(credentials.values["mirror.example"] == Data("session=secret".utf8))
    #expect(context.defaults.string(forKey: HanaSessionCookieStore.fallbackKey(for: url)) == nil)
  }

  @Test("falls back when Keychain cannot write")
  func keychainWriteFailureUsesFallback() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    credentials.failWrites = true
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let url = try #require(URL(string: "https://mirror.example"))

    store.saveCookieHeader("session=secret", for: url)

    #expect(
      context.defaults.string(forKey: HanaSessionCookieStore.fallbackKey(for: url))
        == "session=secret")
    #expect(store.cookieHeader(for: url) == "session=secret")
  }

  @Test("a failed Keychain update prefers the newer fallback")
  func keychainUpdateFailurePrefersFallback() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let url = try #require(URL(string: "https://mirror.example"))
    let account = try #require(HanaSessionCookieStore.account(for: url))
    let fallbackKey = HanaSessionCookieStore.fallbackKey(for: url)
    credentials.values[account] = Data("session=old".utf8)
    credentials.failWrites = true

    store.saveCookieHeader("session=new", for: url)

    #expect(credentials.values[account] == Data("session=old".utf8))
    #expect(context.defaults.string(forKey: fallbackKey) == "session=new")
    #expect(store.cookieHeader(for: url) == "session=new")

    credentials.failWrites = false
    #expect(store.cookieHeader(for: url) == "session=new")
    #expect(credentials.values[account] == Data("session=new".utf8))
    #expect(context.defaults.string(forKey: fallbackKey) == nil)
  }

  @Test("uses and migrates the fallback when Keychain cannot read")
  func keychainReadFailureUsesFallback() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    credentials.failReads = true
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let url = try #require(URL(string: "https://mirror.example"))
    let account = try #require(HanaSessionCookieStore.account(for: url))
    let fallbackKey = HanaSessionCookieStore.fallbackKey(for: url)
    context.defaults.set("session=fallback", forKey: fallbackKey)

    #expect(store.cookieHeader(for: url) == "session=fallback")
    #expect(credentials.values[account] == Data("session=fallback".utf8))
    #expect(context.defaults.string(forKey: fallbackKey) == nil)
  }

  @Test("retries fallback migration after Keychain becomes writable")
  func fallbackMigrationRetry() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    credentials.failWrites = true
    let url = try #require(URL(string: "https://mirror.example"))
    let account = try #require(HanaSessionCookieStore.account(for: url))
    let fallbackKey = HanaSessionCookieStore.fallbackKey(for: url)
    HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
      .saveCookieHeader("session=secret", for: url)

    credentials.failWrites = false
    let relaunchedStore = HanaSessionCookieStore(
      credentialStore: credentials,
      defaults: context.defaults
    )

    #expect(relaunchedStore.cookieHeader(for: url) == "session=secret")
    #expect(credentials.values[account] == Data("session=secret".utf8))
    #expect(context.defaults.string(forKey: fallbackKey) == nil)
  }

  @Test("migrates the default-host legacy value only after a successful write")
  func legacyMigrationSuccess() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let url = try #require(URL(string: HanaSiteBaseURL.defaultValue))
    let account = try #require(HanaSessionCookieStore.account(for: url))
    context.defaults.set("legacy=value", forKey: HanaSessionCookieStore.legacyCookieHeaderKey)

    #expect(store.cookieHeader(for: url) == "legacy=value")
    #expect(credentials.values[account] == Data("legacy=value".utf8))
    #expect(context.defaults.string(forKey: HanaSessionCookieStore.legacyCookieHeaderKey) == nil)
  }

  @Test("retains a legacy value when migration fails")
  func legacyMigrationFailure() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    credentials.failWrites = true
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let url = try #require(URL(string: HanaSiteBaseURL.defaultValue))
    context.defaults.set("legacy=value", forKey: HanaSessionCookieStore.legacyCookieHeaderKey)

    #expect(store.cookieHeader(for: url) == "legacy=value")
    #expect(
      context.defaults.string(forKey: HanaSessionCookieStore.legacyCookieHeaderKey)
        == "legacy=value")
  }

  @Test("replaces corrupt Keychain data with the fallback")
  func corruptKeychainDataUsesFallback() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let url = try #require(URL(string: "https://mirror.example"))
    let account = try #require(HanaSessionCookieStore.account(for: url))
    credentials.values[account] = Data([0xFF])
    context.defaults.set("session=fallback", forKey: HanaSessionCookieStore.fallbackKey(for: url))

    #expect(store.cookieHeader(for: url) == "session=fallback")
    #expect(credentials.values[account] == Data("session=fallback".utf8))
    #expect(context.defaults.string(forKey: HanaSessionCookieStore.fallbackKey(for: url)) == nil)
  }

  @Test("keeps mirror hosts isolated")
  func hostIsolation() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let firstURL = try #require(URL(string: "https://one.example"))
    let secondURL = try #require(URL(string: "https://two.example"))

    store.saveCookieHeader("session=one", for: firstURL)
    store.saveCookieHeader("session=two", for: secondURL)
    store.removeCookieHeader(for: firstURL)

    #expect(store.cookieHeader(for: firstURL) == nil)
    #expect(store.cookieHeader(for: secondURL) == "session=two")
  }

  @Test("a delete tombstone blocks stale Keychain data")
  func deleteFailureTombstone() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let url = try #require(URL(string: "https://mirror.example"))
    let account = try #require(HanaSessionCookieStore.account(for: url))
    store.saveCookieHeader("session=secret", for: url)
    credentials.failRemovals = true

    store.removeCookieHeader(for: url)

    #expect(credentials.values[account] != nil)
    #expect(context.defaults.bool(forKey: HanaSessionCookieStore.tombstoneKey(for: url)))
    #expect(store.cookieHeader(for: url) == nil)

    credentials.failRemovals = false
    #expect(store.cookieHeader(for: url) == nil)
    #expect(credentials.values[account] == nil)
    #expect(!context.defaults.bool(forKey: HanaSessionCookieStore.tombstoneKey(for: url)))
  }

  @Test("restores Cloudflare verification from persisted cookies")
  func cloudflareStatusRestoration() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let url = try #require(URL(string: "https://cloudflare-test.invalid"))
    let cookie = try #require(
      HTTPCookie(properties: [
        .domain: "cloudflare-test.invalid",
        .path: "/",
        .name: "cf_clearance",
        .value: "secret",
        .secure: "TRUE",
        .expires: Date(timeIntervalSinceNow: 60),
      ]))
    SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)
      .sync(cookies: [cookie])
    HTTPCookieStorage.shared.deleteCookie(cookie)

    let restoredSession = SiteWebSession(
      baseURL: url,
      defaults: context.defaults,
      cookieStore: store
    )

    #expect(restoredSession.cloudflareStatusText == "已验证")
  }

  @Test("logout clears the selected host session")
  func siteSessionLogout() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let credentials = TestCredentialStore()
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let url = try #require(URL(string: "https://logout-test.invalid"))
    let cookieName = "session-\(UUID().uuidString)"
    let otherCookieName = "session-\(UUID().uuidString)"
    let cookie = try #require(
      HTTPCookie(properties: [
        .domain: "logout-test.invalid",
        .path: "/",
        .name: cookieName,
        .value: "secret",
        .secure: "TRUE",
      ]))
    let otherCookie = try #require(
      HTTPCookie(properties: [
        .domain: "other-session.invalid",
        .path: "/",
        .name: otherCookieName,
        .value: "other-secret",
        .secure: "TRUE",
      ]))
    let webCookieStore = WKWebsiteDataStore.default().httpCookieStore
    await set(cookie, in: webCookieStore)
    await set(otherCookie, in: webCookieStore)
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)
    session.sync(cookies: [cookie])

    await session.logout()

    let remainingWebCookies = await allCookies(in: webCookieStore)
    #expect(store.cookieHeader(for: url) == nil)
    #expect(HTTPCookieStorage.shared.cookies(for: url)?.isEmpty != false)
    #expect(!remainingWebCookies.contains { $0.name == cookieName })
    #expect(remainingWebCookies.contains { $0.name == otherCookieName })

    await remove(otherCookie, from: webCookieStore)
  }

  @Test("production storage preserves the session with or without Keychain access")
  func productionStorageAvailability() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let service = "sh.celia.hana.tests.\(UUID().uuidString)"
    let credentials = HanaKeychainCredentialStore(service: service)
    let store = HanaSessionCookieStore(credentialStore: credentials, defaults: context.defaults)
    let url = try #require(URL(string: "https://production-store.example"))
    let account = try #require(HanaSessionCookieStore.account(for: url))
    let fallbackKey = HanaSessionCookieStore.fallbackKey(for: url)
    defer { try? credentials.removeData(for: account) }

    store.saveCookieHeader("session=secret", for: url)

    let keychainData = try? credentials.data(for: account)
    if keychainData == Data("session=secret".utf8) {
      #expect(context.defaults.string(forKey: fallbackKey) == nil)
    } else {
      #expect(context.defaults.string(forKey: fallbackKey) == "session=secret")
      #expect(store.cookieHeader(for: url) == "session=secret")
    }
  }

  @Test("privacy manifest declares the audited UserDefaults reason")
  func privacyManifest() throws {
    let appBundle = try #require(
      Bundle.allBundles.first { $0.bundleIdentifier == "sh.celia.hana" }
        ?? (Bundle.main.bundleIdentifier == "sh.celia.hana" ? Bundle.main : nil)
    )
    let url = try #require(appBundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    let data = try Data(contentsOf: url)
    let manifest = try #require(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
    let apiTypes = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    let userDefaultsEntry = try #require(
      apiTypes.first {
        $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
      })
    let reasons = try #require(userDefaultsEntry["NSPrivacyAccessedAPITypeReasons"] as? [String])

    #expect(reasons == ["CA92.1"])
    #expect(manifest["NSPrivacyTracking"] as? Bool == false)
    #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
  }

  private func set(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
    await withCheckedContinuation { continuation in
      store.setCookie(cookie) { continuation.resume() }
    }
  }

  private func remove(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
    await withCheckedContinuation { continuation in
      store.delete(cookie) { continuation.resume() }
    }
  }

  private func allCookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
    await withCheckedContinuation { continuation in
      store.getAllCookies { continuation.resume(returning: $0) }
    }
  }
}

@MainActor
private final class TestCredentialStore: HanaCredentialStore {
  enum Failure: Error {
    case forced
  }

  var values: [String: Data] = [:]
  var failReads = false
  var failWrites = false
  var failRemovals = false

  func data(for account: String) throws -> Data? {
    if failReads { throw Failure.forced }
    return values[account]
  }

  func set(_ data: Data, for account: String) throws {
    if failWrites { throw Failure.forced }
    values[account] = data
  }

  func removeData(for account: String) throws {
    if failRemovals { throw Failure.forced }
    values[account] = nil
  }
}

private struct TestContext {
  let suiteName: String
  let defaults: UserDefaults

  init() throws {
    let suiteName = "HanaSessionCookieStoreTests.\(UUID().uuidString)"
    self.suiteName = suiteName
    self.defaults = try #require(UserDefaults(suiteName: suiteName))
    self.defaults.removePersistentDomain(forName: suiteName)
  }

  func cleanup() {
    defaults.removePersistentDomain(forName: suiteName)
  }
}
