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

  @Test("Cloudflare cookie matching rejects expired and lookalike domains")
  func cloudflareCookieScope() throws {
    let url = try #require(URL(string: "https://example.invalid/path"))
    let valid = try makeCookie(
      domain: ".example.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )
    let expired = try makeCookie(
      domain: "example.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: -60)
    )
    let lookalike = try makeCookie(
      domain: "evil-example.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )
    let childDomain = try makeCookie(
      domain: "child.example.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )

    #expect(SiteWebCookieScope.matches(valid, url: url))
    #expect(!SiteWebCookieScope.matches(lookalike, url: url))
    #expect(!SiteWebCookieScope.matches(childDomain, url: url))
    #expect(SiteWebCookieScope.cloudflareClearance(in: [expired], for: url) == nil)
    #expect(SiteWebCookieScope.cloudflareClearance(in: [lookalike], for: url) == nil)
    #expect(SiteWebCookieScope.cloudflareClearance(in: [valid], for: url) === valid)
  }

  @Test("Cloudflare verification fans concurrent requests into one flow")
  func cloudflareWaiterFanIn() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://fan-in.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)

    let first = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    let second = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    for _ in 0..<200 where session.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }

    guard let flow = session.activeFlow, flow.kind == .cloudflare else {
      session.cancel()
      _ = await (first.value, second.value)
      Issue.record("The shared Cloudflare flow was not presented")
      return
    }
    #expect(session.cloudflareStatusText == "验证中")
    let clearance = try makeCookie(
      domain: "fan-in.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )
    #expect(session.complete(flowID: flow.id, with: [clearance]))
    #expect(await first.value)
    #expect(await second.value)
    #expect(session.activeFlow == nil)
    #expect(session.cloudflareStatusText == "已验证")
    #expect(session.lastCloudflareVerifiedAt != nil)
    #expect(session.lastCookieSyncAt == nil)

    HTTPCookieStorage.shared.deleteCookie(clearance)
  }

  @Test("a delayed challenge reuses a newer verification generation")
  func delayedChallengeReusesVerificationGeneration() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://generation.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)
    let requestGeneration = session.cloudflareVerificationGeneration

    let first = Task { @MainActor in
      await session.resolveCloudflareChallenge(
        at: url,
        requestGeneration: requestGeneration
      )
    }
    for _ in 0..<200 where session.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    let flowID = try #require(session.activeFlow?.id)
    let clearance = try makeCookie(
      domain: "generation.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )
    #expect(session.complete(flowID: flowID, with: [clearance]))
    #expect(await first.value)
    #expect(session.cloudflareVerificationGeneration == requestGeneration + 1)

    let delayedResult = await session.resolveCloudflareChallenge(
      at: url,
      requestGeneration: requestGeneration
    )
    #expect(delayedResult)
    #expect(session.activeFlow == nil)
    #expect(session.cloudflareVerificationGeneration == requestGeneration + 1)

    HTTPCookieStorage.shared.deleteCookie(clearance)
  }

  @Test("stale flow callbacks cannot complete or cancel a newer flow")
  func staleFlowCallbacksAreIgnored() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://flow-identity.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)

    await session.requestCloudflareVerification(url)
    let firstFlowID = try #require(session.activeFlow?.id)
    session.cancel(flowID: firstFlowID)
    await session.requestCloudflareVerification(url)
    let secondFlowID = try #require(session.activeFlow?.id)
    #expect(firstFlowID != secondFlowID)

    let clearance = try makeCookie(
      domain: "flow-identity.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )
    session.cancel(flowID: firstFlowID)
    #expect(!session.complete(flowID: firstFlowID, with: [clearance]))
    #expect(session.activeFlow?.id == secondFlowID)
    #expect(session.lastCloudflareVerifiedAt == nil)

    #expect(session.complete(flowID: secondFlowID, with: [clearance]))
    #expect(session.activeFlow == nil)

    HTTPCookieStorage.shared.deleteCookie(clearance)
  }

  @Test("generic Cookie sync neither broadcasts nor restores clearance during recovery")
  func genericCookieSyncIsSuppressedDuringRecovery() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://sync-recovery.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)
    let sessionCookie = try makeCookie(domain: "sync-recovery.invalid", name: "session")
    let clearance = try makeCookie(
      domain: "sync-recovery.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )
    session.sync(cookies: [sessionCookie])
    let previousSyncAt = session.lastCookieSyncAt

    let request = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    for _ in 0..<200 where session.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    session.sync(
      cookies: [sessionCookie, clearance],
      acceptsCloudflareClearance: false
    )

    #expect(session.lastCookieSyncAt == previousSyncAt)
    #expect(store.cookieHeader(for: url) == "session=value")
    #expect(HTTPCookieStorage.shared.cookies(for: url)?.contains {
      $0.name == SiteWebCookieScope.cloudflareClearanceName
    } != true)

    session.cancel()
    #expect(!(await request.value))
    HTTPCookieStorage.shared.deleteCookie(sessionCookie)
    HTTPCookieStorage.shared.deleteCookie(clearance)
  }

  @Test("a stale async Cookie snapshot cannot overwrite newer verification")
  func staleAsyncCookieSnapshotIsDiscarded() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://stale-sync.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)
    let loader = ControlledCookieLoader()
    let staleSession = try makeCookie(
      domain: "stale-sync.invalid",
      name: "session",
      value: "stale"
    )
    let freshSession = try makeCookie(
      domain: "stale-sync.invalid",
      name: "session",
      value: "fresh"
    )
    let clearance = try makeCookie(
      domain: "stale-sync.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )

    let staleSync = Task { @MainActor in
      await session.syncDefaultWebCookies { await loader.load() }
    }
    for _ in 0..<200 where !loader.didStart {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(loader.didStart)

    let request = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    for _ in 0..<200 where session.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    let flowID = try #require(session.activeFlow?.id)
    #expect(session.complete(flowID: flowID, with: [freshSession, clearance]))
    #expect(await request.value)

    loader.resume(with: [staleSession])
    await staleSync.value

    let persistedHeader = try #require(store.cookieHeader(for: url))
    #expect(persistedHeader.contains("session=fresh"))
    #expect(persistedHeader.contains("cf_clearance=value"))
    #expect(!persistedHeader.contains("session=stale"))

    HTTPCookieStorage.shared.deleteCookie(staleSession)
    HTTPCookieStorage.shared.deleteCookie(freshSession)
    HTTPCookieStorage.shared.deleteCookie(clearance)
  }

  @Test("invalidation cancels the active flow before deleting clearance")
  func invalidationRejectsActiveFlowCompletion() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://invalidate-active.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)
    let request = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    for _ in 0..<200 where session.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    let staleFlowID = try #require(session.activeFlow?.id)
    let clearance = try makeCookie(
      domain: "invalidate-active.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )

    let invalidation = Task { @MainActor in
      await session.invalidateCloudflareVerification()
    }
    for _ in 0..<200 where session.activeFlow != nil {
      try await Task.sleep(for: .milliseconds(10))
    }

    #expect(!session.complete(flowID: staleFlowID, with: [clearance]))
    await invalidation.value
    #expect(!(await request.value))
    #expect(session.activeFlow == nil)
    #expect(session.lastCloudflareVerifiedAt == nil)
    #expect(store.cookieHeader(for: url)?.contains("cf_clearance") != true)

    HTTPCookieStorage.shared.deleteCookie(clearance)
  }

  @Test("new flows wait for an older physical invalidation to finish")
  func invalidationIsSerializedAcrossFlows() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let gate = ControlledInvalidationGate()
    let url = try #require(URL(string: "https://serialized-invalidation.invalid/path"))
    let session = SiteWebSession(
      baseURL: url,
      defaults: context.defaults,
      cookieStore: store,
      cloudflareWebInvalidator: { await gate.wait() }
    )

    let first = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    for _ in 0..<200 where !gate.didStart {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(gate.didStart)
    #expect(session.activeFlow == nil)

    first.cancel()
    #expect(!(await first.value))
    session.requestLogin()
    #expect(session.activeFlow == nil)

    let second = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    try await Task.sleep(for: .milliseconds(20))
    #expect(session.activeFlow == nil)

    gate.resume()
    for _ in 0..<200 where session.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    let flowID = try #require(session.activeFlow?.id)
    #expect(session.activeFlow?.kind == .cloudflare)

    let clearance = try makeCookie(
      domain: "serialized-invalidation.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )
    #expect(session.complete(flowID: flowID, with: [clearance]))
    #expect(await second.value)

    HTTPCookieStorage.shared.deleteCookie(clearance)
  }

  @Test("login cannot replace a pending automatic Cloudflare flow")
  func loginDoesNotStrandCloudflareWaiter() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://login-race.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)
    let request = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    for _ in 0..<200 where !session.isCloudflareVerificationInProgress {
      try await Task.sleep(for: .milliseconds(10))
    }

    session.requestLogin()
    for _ in 0..<200 where session.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(session.activeFlow?.kind == .cloudflare)

    session.cancel()
    #expect(!(await request.value))
    #expect(session.activeFlow == nil)
  }

  @Test("cancelling Cloudflare verification releases every waiter")
  func cloudflareWaiterCancellation() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://cancel-flow.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)

    let first = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    let second = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    for _ in 0..<200 where session.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    session.cancel()

    #expect(!(await first.value))
    #expect(!(await second.value))
    #expect(session.activeFlow == nil)
    #expect(!session.isCloudflareVerificationInProgress)
    #expect(session.cloudflareStatusText == "需要验证")
  }

  @Test("cancelling one Cloudflare waiter preserves the shared flow")
  func partialCloudflareWaiterCancellation() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://partial-cancel.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)

    let first = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    let second = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    for _ in 0..<200 where session.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }

    first.cancel()
    #expect(!(await first.value))
    let flowID = try #require(session.activeFlow?.id)
    #expect(session.activeFlow?.kind == .cloudflare)

    let clearance = try makeCookie(
      domain: "partial-cancel.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )
    #expect(session.complete(flowID: flowID, with: [clearance]))
    #expect(await second.value)
    #expect(session.activeFlow == nil)

    HTTPCookieStorage.shared.deleteCookie(clearance)
  }

  @Test("cancelling the final Cloudflare waiter closes the automatic flow")
  func finalCloudflareWaiterCancellation() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://final-cancel.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)

    let request = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    for _ in 0..<200 where session.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(session.activeFlow?.kind == .cloudflare)

    request.cancel()

    #expect(!(await request.value))
    #expect(session.activeFlow == nil)
    #expect(!session.isCloudflareVerificationInProgress)
    #expect(session.cloudflareStatusText == "需要验证")
  }

  @Test("task cancellation racing completion resumes the waiter once")
  func cancellationRacingCompletion() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://cancel-complete-race.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)
    let request = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
    for _ in 0..<200 where session.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    let flowID = try #require(session.activeFlow?.id)
    let clearance = try makeCookie(
      domain: "cancel-complete-race.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: Date(timeIntervalSinceNow: 60)
    )

    request.cancel()
    _ = session.complete(flowID: flowID, with: [clearance])

    #expect(!(await request.value))
    #expect(session.activeFlow == nil)
    #expect(!session.isCloudflareVerificationInProgress)

    HTTPCookieStorage.shared.deleteCookie(clearance)
  }

  @Test("an immediately cancelled Cloudflare request never leaves a flow")
  func immediateCloudflareWaiterCancellation() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://immediate-cancel.invalid/path"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)

    for _ in 0..<100 {
      let request = Task { @MainActor in await session.resolveCloudflareChallenge(at: url) }
      request.cancel()
      #expect(!(await request.value))
    }

    try await Task.sleep(for: .milliseconds(50))
    #expect(session.activeFlow == nil)
    #expect(!session.isCloudflareVerificationInProgress)
  }

  @Test("verification and task cancellation preserve existing login state")
  func transientVerificationErrorsPreserveLoginState() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://preserve-login.invalid"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)

    #expect(session.shouldPreserveLoginState(after: HanaNetworkError.cloudflareVerificationCancelled))
    #expect(session.shouldPreserveLoginState(after: HanaNetworkError.cloudflareVerificationFailed))
    #expect(session.shouldPreserveLoginState(after: CancellationError()))
    #expect(!session.shouldPreserveLoginState(after: HanaNetworkError.authenticationFailed))
    #expect(!session.shouldPreserveLoginState(after: HanaNetworkError.httpStatus(401, url)))
  }

  @Test("Cloudflare completion requires a fresh scoped clearance")
  func cloudflareCompletionGateAndStatus() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://completion.invalid/path"))
    var currentTime = Date(timeIntervalSince1970: 10_000)
    let session = SiteWebSession(
      baseURL: url,
      defaults: context.defaults,
      cookieStore: store,
      now: { currentTime }
    )
    #expect(session.cloudflareStatusText == "无需验证")
    session.cloudflareVerificationDidFail()
    #expect(session.cloudflareStatusText == "需要验证")
    await session.requestCloudflareVerification(url)
    #expect(session.cloudflareStatusText == "验证中")
    let flowID = try #require(session.activeFlow?.id)

    let expired = try makeCookie(
      domain: "completion.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: currentTime.addingTimeInterval(-1)
    )
    let lookalike = try makeCookie(
      domain: "evil-completion.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: currentTime.addingTimeInterval(60)
    )
    #expect(!session.complete(flowID: flowID, with: [expired]))
    #expect(!session.complete(flowID: flowID, with: [lookalike]))
    #expect(session.activeFlow?.kind == .cloudflare)

    let valid = try makeCookie(
      domain: "completion.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName,
      expires: currentTime.addingTimeInterval(60)
    )
    #expect(session.complete(flowID: flowID, with: [valid]))
    #expect(session.cloudflareStatusText == "已验证")
    currentTime = currentTime.addingTimeInterval(61)
    #expect(session.cloudflareStatusText == "已过期")

    HTTPCookieStorage.shared.deleteCookie(valid)
  }

  @Test("invalidating Cloudflare preserves sessions and unrelated hosts")
  func cloudflareInvalidationIsScoped() async throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = HanaSessionCookieStore(
      credentialStore: TestCredentialStore(),
      defaults: context.defaults
    )
    let url = try #require(URL(string: "https://scope.invalid"))
    let session = SiteWebSession(baseURL: url, defaults: context.defaults, cookieStore: store)
    let sessionCookie = try makeCookie(domain: "scope.invalid", name: "session")
    let clearance = try makeCookie(
      domain: ".scope.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName
    )
    let unrelated = try makeCookie(
      domain: "unrelated.invalid",
      name: SiteWebCookieScope.cloudflareClearanceName
    )
    let webCookieStore = WKWebsiteDataStore.default().httpCookieStore
    for cookie in [sessionCookie, clearance, unrelated] {
      HTTPCookieStorage.shared.setCookie(cookie)
      await set(cookie, in: webCookieStore)
    }
    session.sync(cookies: [sessionCookie, clearance])

    await session.invalidateCloudflareVerification()

    let persistedHeader = try #require(store.cookieHeader(for: url))
    let webCookies = await allCookies(in: webCookieStore)
    #expect(persistedHeader == "session=value")
    #expect(HTTPCookieStorage.shared.cookies(for: url)?.contains { $0.name == "session" } == true)
    #expect(HTTPCookieStorage.shared.cookies(for: url)?.contains {
      $0.name == SiteWebCookieScope.cloudflareClearanceName
    } != true)
    let unrelatedURL = try #require(URL(string: "https://unrelated.invalid"))
    #expect(HTTPCookieStorage.shared.cookies(for: unrelatedURL)?.contains {
      $0.name == SiteWebCookieScope.cloudflareClearanceName
    } == true)
    #expect(!webCookies.contains {
      $0.name == SiteWebCookieScope.cloudflareClearanceName
        && SiteWebCookieScope.matches($0, url: url)
    })
    #expect(webCookies.contains { $0.name == "session" && SiteWebCookieScope.matches($0, url: url) })
    #expect(webCookies.contains { $0.name == SiteWebCookieScope.cloudflareClearanceName && $0.domain == "unrelated.invalid" })

    for cookie in [sessionCookie, clearance, unrelated] {
      HTTPCookieStorage.shared.deleteCookie(cookie)
      await remove(cookie, from: webCookieStore)
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

  private func makeCookie(
    domain: String,
    name: String,
    value: String = "value",
    expires: Date? = nil
  ) throws -> HTTPCookie {
    var properties: [HTTPCookiePropertyKey: Any] = [
      .domain: domain,
      .path: "/",
      .name: name,
      .value: value,
      .secure: "TRUE",
    ]
    if let expires {
      properties[.expires] = expires
    }
    return try #require(HTTPCookie(properties: properties))
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
private final class ControlledInvalidationGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var didStart = false

  func wait() async {
    didStart = true
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func resume() {
    let continuation = continuation
    self.continuation = nil
    continuation?.resume()
  }
}

@MainActor
private final class ControlledCookieLoader {
  private var continuation: CheckedContinuation<[HTTPCookie], Never>?
  private(set) var didStart = false

  func load() async -> [HTTPCookie] {
    didStart = true
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func resume(with cookies: [HTTPCookie]) {
    let continuation = continuation
    self.continuation = nil
    continuation?.resume(returning: cookies)
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
