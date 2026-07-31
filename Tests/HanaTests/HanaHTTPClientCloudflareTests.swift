import Foundation
import Testing

@testable import Hana

@MainActor
@Suite("Cloudflare HTTP retry", .serialized)
struct HanaHTTPClientCloudflareTests {
  @Test("GET retries once with refreshed cookies and the original request policy")
  func getRetry() async throws {
    let harness = try Harness(mode: .firstChallengeThenSuccess)
    defer { harness.cleanup() }
    harness.installFreshClearance()
    let url = harness.baseURL.appending(path: "page")

    let data = try await harness.client.data(
      from: url,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: 7
    )

    let requests = ChallengeURLProtocol.capturedRequests
    #expect(data == Data("ok".utf8))
    #expect(harness.resolver.callCount == 1)
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.method == "GET" && $0.url == url })
    #expect(requests.allSatisfy { $0.timeoutInterval == 7 })
    #expect(requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
    #expect(requests.first?.headers["Cookie"]?.contains("cf_clearance") != true)
    #expect(requests.last?.headers["Cookie"]?.contains("cf_clearance") == true)
  }

  @Test("a delayed concurrent challenge reuses the newer verification generation")
  func delayedChallengeReusesGeneration() async throws {
    let harness = try Harness(mode: .delayedConcurrentChallenges)
    defer { harness.cleanup() }
    harness.installFreshClearance()
    let delayedURL = harness.baseURL.appending(path: "delayed")
    let firstURL = harness.baseURL.appending(path: "first")

    let request = Task { @MainActor in
      try await harness.client.data(from: delayedURL)
    }
    for _ in 0..<200 where !ChallengeURLProtocol.hasPendingDelayedChallenge {
      try await Task.sleep(for: .milliseconds(10))
    }
    guard ChallengeURLProtocol.hasPendingDelayedChallenge else {
      request.cancel()
      ChallengeURLProtocol.releaseDelayedChallenge()
      _ = try? await request.value
      Issue.record("The delayed request was not captured")
      return
    }

    let firstData = try await harness.client.data(from: firstURL)
    #expect(firstData == Data("ok".utf8))
    #expect(harness.resolver.callCount == 1)

    ChallengeURLProtocol.releaseDelayedChallenge()
    let data = try await request.value

    #expect(data == Data("ok".utf8))
    #expect(harness.resolver.callCount == 1)
    #expect(harness.resolver.reusedGenerationCount == 1)
    #expect(ChallengeURLProtocol.capturedRequests.count == 4)
    #expect(ChallengeURLProtocol.capturedRequests.last?.headers["Cookie"]?.contains("cf_clearance") == true)
  }

  @Test("form POST retries with the same body and non-cookie headers")
  func postRetry() async throws {
    let harness = try Harness(mode: .firstChallengeThenSuccess)
    defer { harness.cleanup() }
    harness.installFreshClearance()

    let data = try await harness.client.postForm(
      to: HanaEndpoint(path: "submit"),
      fields: ["name": "value"],
      csrfToken: "csrf"
    )

    let requests = ChallengeURLProtocol.capturedRequests
    #expect(data == Data("ok".utf8))
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.method == "POST" })
    #expect(requests.first?.body == requests.last?.body)
    #expect(requests.first?.headers["X-CSRF-Token"] == requests.last?.headers["X-CSRF-Token"])
    #expect(requests.first?.headers["X-Requested-With"] == "XMLHttpRequest")
    #expect(requests.last?.headers["Cookie"]?.contains("cf_clearance") == true)
  }

  @Test("JSON DELETE retries with the same body and content contract")
  func deleteRetry() async throws {
    let harness = try Harness(mode: .firstChallengeThenSuccess)
    defer { harness.cleanup() }
    harness.installFreshClearance()

    let data = try await harness.client.deleteJSON(
      to: HanaEndpoint(path: "delete"),
      body: ["id": "42"],
      csrfToken: "csrf"
    )

    let requests = ChallengeURLProtocol.capturedRequests
    #expect(data == Data("ok".utf8))
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.method == "DELETE" })
    #expect(requests.first?.body == requests.last?.body)
    #expect(requests.allSatisfy { $0.headers["Content-Type"] == "application/json" })
    #expect(requests.last?.headers["Cookie"]?.contains("cf_clearance") == true)
  }

  @Test("a second challenge is terminal and does not present again")
  func secondChallengeIsTerminal() async throws {
    let harness = try Harness(mode: .alwaysChallenge)
    defer { harness.cleanup() }
    harness.installFreshClearance()

    do {
      _ = try await harness.client.data(from: harness.baseURL)
      Issue.record("The repeated challenge unexpectedly succeeded")
    } catch let error as HanaNetworkError {
      guard case .cloudflareVerificationFailed = error else {
        Issue.record("Unexpected network error: \(error.localizedDescription)")
        return
      }
    }

    #expect(harness.resolver.callCount == 1)
    #expect(harness.resolver.failureCount == 1)
    #expect(ChallengeURLProtocol.capturedRequests.count == 2)
  }

  @Test("an ordinary Cloudflare 403 does not start verification")
  func ordinaryCloudflareForbiddenDoesNotResolve() async throws {
    let harness = try Harness(mode: .ordinaryCloudflareForbidden)
    defer { harness.cleanup() }
    let url = harness.baseURL.appending(path: "forbidden")

    do {
      _ = try await harness.client.data(from: url)
      Issue.record("The ordinary 403 unexpectedly succeeded")
    } catch let error as HanaNetworkError {
      guard case .httpStatus(let statusCode, let responseURL) = error else {
        Issue.record("Unexpected network error: \(error.localizedDescription)")
        return
      }
      #expect(statusCode == 403)
      #expect(responseURL == url)
    }

    #expect(harness.resolver.callCount == 0)
    #expect(ChallengeURLProtocol.capturedRequests.count == 1)
  }

  @Test("deferred recovery returns the challenge without awaiting the resolver")
  func deferredRecoveryReturnsChallenge() async throws {
    let harness = try Harness(mode: .alwaysChallenge)
    defer { harness.cleanup() }

    do {
      _ = try await harness.client.data(
        from: harness.baseURL,
        automaticallyResolvesCloudflareChallenges: false
      )
      Issue.record("The deferred challenge unexpectedly succeeded")
    } catch let error as HanaNetworkError {
      guard case .cloudflareChallenge(let url) = error else {
        Issue.record("Unexpected network error: \(error.localizedDescription)")
        return
      }
      #expect(url == harness.baseURL)
    }

    #expect(harness.resolver.callCount == 0)
    #expect(ChallengeURLProtocol.capturedRequests.count == 1)
  }

  @Test("a child-host challenge does not use the base-host resolver")
  func childHostChallengeDoesNotResolve() async throws {
    let harness = try Harness(mode: .alwaysChallenge)
    defer { harness.cleanup() }
    let baseHost = try #require(harness.baseURL.host())
    let url = try #require(URL(string: "https://api.\(baseHost)/forbidden"))

    do {
      _ = try await harness.client.data(from: url)
      Issue.record("The child-host challenge unexpectedly succeeded")
    } catch let error as HanaNetworkError {
      guard case .httpStatus(let statusCode, let responseURL) = error else {
        Issue.record("Unexpected network error: \(error.localizedDescription)")
        return
      }
      #expect(statusCode == 403)
      #expect(responseURL == url)
    }

    #expect(harness.resolver.callCount == 0)
    #expect(ChallengeURLProtocol.capturedRequests.count == 1)
  }

  @Test("a redirected child-host challenge does not use the base-host resolver")
  func redirectedChildHostChallengeDoesNotResolve() async throws {
    let harness = try Harness(mode: .redirectedChildChallenge)
    defer { harness.cleanup() }
    let url = harness.baseURL.appending(path: "redirected")

    do {
      _ = try await harness.client.data(from: url)
      Issue.record("The redirected child-host challenge unexpectedly succeeded")
    } catch let error as HanaNetworkError {
      guard case .httpStatus(let statusCode, _) = error else {
        Issue.record("Unexpected network error: \(error.localizedDescription)")
        return
      }
      #expect(statusCode == 403)
    }

    #expect(harness.resolver.callCount == 0)
    #expect(ChallengeURLProtocol.capturedRequests.count == 1)
  }

  @Test("cancelling an HTTP task closes the real shared verification flow")
  func cancelledHTTPTaskClosesVerification() async throws {
    ChallengeURLProtocol.reset(mode: .alwaysChallenge)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ChallengeURLProtocol.self]
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    let urlSession = URLSession(configuration: configuration)
    let defaultsSuiteName = "HanaHTTPClientCloudflareCancellation.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsSuiteName))
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    let baseURL = try #require(URL(string: "https://http-cancel-\(UUID().uuidString).invalid/"))
    let cookieStore = HanaSessionCookieStore(
      credentialStore: HTTPTestCredentialStore(),
      defaults: defaults
    )
    let siteSession = SiteWebSession(
      baseURL: baseURL,
      defaults: defaults,
      cookieStore: cookieStore
    )
    let client = HanaHTTPClient(
      baseURL: baseURL,
      sessionCookieStore: cookieStore,
      cloudflareChallengeResolver: siteSession,
      session: urlSession
    )
    defer {
      siteSession.cancel()
      urlSession.invalidateAndCancel()
      defaults.removePersistentDomain(forName: defaultsSuiteName)
      ChallengeURLProtocol.reset(mode: .alwaysChallenge)
    }

    let request = Task { @MainActor in try await client.data(from: baseURL) }
    for _ in 0..<200 where siteSession.activeFlow == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(siteSession.activeFlow?.kind == .cloudflare)

    request.cancel()
    do {
      _ = try await request.value
      Issue.record("The cancelled HTTP task unexpectedly succeeded")
    } catch is CancellationError {
      // Expected.
    }

    #expect(siteSession.activeFlow == nil)
    #expect(!siteSession.isCloudflareVerificationInProgress)
    #expect(ChallengeURLProtocol.capturedRequests.count == 1)
  }

  @Test("a redirected child-host challenge on retry stays an HTTP error")
  func redirectedRetryChallengeDoesNotFailBaseVerification() async throws {
    let harness = try Harness(mode: .firstChallengeThenRedirectedChildChallenge)
    defer { harness.cleanup() }
    harness.installFreshClearance()

    do {
      _ = try await harness.client.data(from: harness.baseURL)
      Issue.record("The redirected retry challenge unexpectedly succeeded")
    } catch let error as HanaNetworkError {
      guard case .httpStatus(let statusCode, _) = error else {
        Issue.record("Unexpected network error: \(error.localizedDescription)")
        return
      }
      #expect(statusCode == 403)
    }

    #expect(harness.resolver.callCount == 1)
    #expect(harness.resolver.failureCount == 0)
    #expect(ChallengeURLProtocol.capturedRequests.count == 2)
  }

  @Test("cancelling verification does not retry")
  func cancelledVerificationDoesNotRetry() async throws {
    let harness = try Harness(mode: .alwaysChallenge, verificationResult: false)
    defer { harness.cleanup() }

    do {
      _ = try await harness.client.data(from: harness.baseURL)
      Issue.record("The cancelled verification unexpectedly succeeded")
    } catch let error as HanaNetworkError {
      guard case .cloudflareVerificationCancelled = error else {
        Issue.record("Unexpected network error: \(error.localizedDescription)")
        return
      }
    }

    #expect(harness.resolver.callCount == 1)
    #expect(ChallengeURLProtocol.capturedRequests.count == 1)
  }
}

@MainActor
private final class ControlledChallengeResolver: HanaCloudflareChallengeResolving {
  var result: Bool
  var cloudflareVerificationGeneration: UInt64 = 0
  var callCount = 0
  var reusedGenerationCount = 0
  var failureCount = 0
  var onResolve: (() -> Void)?

  init(result: Bool) {
    self.result = result
  }

  func resolveCloudflareChallenge(
    at url: URL,
    requestGeneration: UInt64
  ) async -> Bool {
    if requestGeneration < cloudflareVerificationGeneration, result {
      reusedGenerationCount += 1
      return true
    }

    callCount += 1
    onResolve?()
    if result {
      cloudflareVerificationGeneration &+= 1
    }
    return result
  }

  func cloudflareVerificationDidFail() {
    failureCount += 1
  }
}

@MainActor
private final class Harness {
  let baseURL: URL
  let client: HanaHTTPClient
  let resolver: ControlledChallengeResolver

  private let session: URLSession
  private let defaults: UserDefaults
  private let defaultsSuiteName: String
  private var installedCookie: HTTPCookie?

  init(mode: ChallengeURLProtocol.Mode, verificationResult: Bool = true) throws {
    ChallengeURLProtocol.reset(mode: mode)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ChallengeURLProtocol.self]
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    session = URLSession(configuration: configuration)

    defaultsSuiteName = "HanaHTTPClientCloudflareTests.\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: defaultsSuiteName))
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    baseURL = try #require(URL(string: "https://cloudflare-http-\(UUID().uuidString).invalid/"))
    resolver = ControlledChallengeResolver(result: verificationResult)
    let cookieStore = HanaSessionCookieStore(
      credentialStore: HTTPTestCredentialStore(),
      defaults: defaults
    )
    client = HanaHTTPClient(
      baseURL: baseURL,
      sessionCookieStore: cookieStore,
      cloudflareChallengeResolver: resolver,
      session: session
    )
  }

  func installFreshClearance() {
    let host = baseURL.host() ?? "invalid"
    let cookie = HTTPCookie(properties: [
      .domain: host,
      .path: "/",
      .name: SiteWebCookieScope.cloudflareClearanceName,
      .value: "test-value",
      .secure: "TRUE",
      .expires: Date(timeIntervalSinceNow: 60),
    ])
    installedCookie = cookie
    resolver.onResolve = {
      if let cookie {
        HTTPCookieStorage.shared.setCookie(cookie)
      }
    }
  }

  func cleanup() {
    if let installedCookie {
      HTTPCookieStorage.shared.deleteCookie(installedCookie)
    }
    session.invalidateAndCancel()
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    ChallengeURLProtocol.reset(mode: .alwaysChallenge)
  }
}

private struct HTTPTestCredentialStore: HanaCredentialStore {
  func data(for account: String) throws -> Data? { nil }
  func set(_ data: Data, for account: String) throws {}
  func removeData(for account: String) throws {}
}

nonisolated private final class ChallengeURLProtocol: URLProtocol, @unchecked Sendable {
  enum Mode: Sendable {
    case firstChallengeThenSuccess
    case alwaysChallenge
    case ordinaryCloudflareForbidden
    case delayedConcurrentChallenges
    case redirectedChildChallenge
    case firstChallengeThenRedirectedChildChallenge
  }

  struct CapturedRequest: Sendable {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let body: Data?
    let timeoutInterval: TimeInterval
    let cachePolicy: URLRequest.CachePolicy
  }

  private static let lock = NSLock()
  private static var mode: Mode = .alwaysChallenge
  private static var requests: [CapturedRequest] = []
  private static var pendingDelayedChallenge: ChallengeURLProtocol?

  static var hasPendingDelayedChallenge: Bool {
    lock.lock()
    defer { lock.unlock() }
    return pendingDelayedChallenge != nil
  }

  static var capturedRequests: [CapturedRequest] {
    lock.lock()
    defer { lock.unlock() }
    return requests
  }

  static func reset(mode: Mode) {
    lock.lock()
    self.mode = mode
    requests = []
    pendingDelayedChallenge = nil
    lock.unlock()
  }

  static func releaseDelayedChallenge() {
    lock.lock()
    let pending = pendingDelayedChallenge
    pendingDelayedChallenge = nil
    lock.unlock()
    pending?.sendResponse(
      statusCode: 403,
      headers: ["Content-Type": "text/html", "cf-mitigated": "challenge", "Server": "cloudflare"],
      body: "challenge"
    )
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host?.hasSuffix(".invalid") == true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let captured = CapturedRequest(
      url: request.url,
      method: request.httpMethod,
      headers: request.allHTTPHeaderFields ?? [:],
      body: request.httpBody,
      timeoutInterval: request.timeoutInterval,
      cachePolicy: request.cachePolicy
    )

    Self.lock.lock()
    Self.requests.append(captured)
    let requestNumber = Self.requests.count
    let mode = Self.mode
    let hasClearance = captured.headers["Cookie"]?.contains("cf_clearance") == true
    if mode == .delayedConcurrentChallenges,
       request.url?.path == "/delayed",
       !hasClearance {
      Self.pendingDelayedChallenge = self
      Self.lock.unlock()
      return
    }
    Self.lock.unlock()

    let isChallenge = mode == .alwaysChallenge
      || mode == .redirectedChildChallenge
      || mode == .firstChallengeThenRedirectedChildChallenge
      || (mode == .firstChallengeThenSuccess && requestNumber == 1)
      || (mode == .delayedConcurrentChallenges && !hasClearance)
    let statusCode = (isChallenge || mode == .ordinaryCloudflareForbidden) ? 403 : 200
    let headers: [String: String]
    let body: String
    if isChallenge {
      headers = ["Content-Type": "text/html", "cf-mitigated": "challenge", "Server": "cloudflare"]
      body = "challenge"
    } else if mode == .ordinaryCloudflareForbidden {
      headers = ["Content-Type": "text/html", "Server": "cloudflare"]
      body = "forbidden"
    } else {
      headers = ["Content-Type": "application/octet-stream"]
      body = "ok"
    }
    let responseURL: URL?
    if (mode == .redirectedChildChallenge
          || (mode == .firstChallengeThenRedirectedChildChallenge && requestNumber > 1)),
       let host = request.url?.host() {
      responseURL = URL(string: "https://api.\(host)/challenge")
    } else {
      responseURL = request.url
    }
    sendResponse(
      statusCode: statusCode,
      headers: headers,
      body: body,
      responseURL: responseURL
    )
  }

  override func stopLoading() {
    Self.lock.lock()
    if Self.pendingDelayedChallenge === self {
      Self.pendingDelayedChallenge = nil
    }
    Self.lock.unlock()
  }

  private func sendResponse(
    statusCode: Int,
    headers: [String: String],
    body: String,
    responseURL: URL? = nil
  ) {
    guard let url = responseURL ?? request.url,
          let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
          ) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}
