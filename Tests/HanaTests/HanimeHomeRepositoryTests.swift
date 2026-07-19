import Foundation
import Testing

@testable import Hana

@Suite("Home recommendation repository", .serialized)
struct HanimeHomeRepositoryTests {
    @Test("requests the configured homepage and returns parsed recommendations")
    @MainActor
    func homePageRequest() async throws {
        let fixtureURL = try #require(
            Bundle(for: HomeRepositoryFixtureBundleToken.self).url(
                forResource: "home-recommendations-reference",
                withExtension: "html"
            )
        )
        HomeRepositoryURLProtocol.reset(
            responseData: try Data(contentsOf: fixtureURL)
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HomeRepositoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let defaultsSuiteName = "HanimeHomeRepositoryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuiteName))
        defer {
            session.invalidateAndCancel()
            HomeRepositoryURLProtocol.reset(responseData: Data())
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let baseURL = try #require(URL(string: "https://example.invalid/base/"))
        let sessionCookieStore = HanaSessionCookieStore(
            credentialStore: HomeRepositoryCredentialStore(),
            defaults: defaults
        )
        let repository = HanimeRepository(
            httpClient: HanaHTTPClient(
                baseURL: baseURL,
                sessionCookieStore: sessionCookieStore,
                session: session
            ),
            parser: HanimeHTMLParser(baseURL: baseURL)
        )

        let page = try await repository.homePage()

        #expect(HomeRepositoryURLProtocol.requestedURL?.absoluteString == "https://example.invalid/base/")
        #expect(page.sections.first?.key == "latest_hanime")
        #expect(page.sections.last?.key == "cosplay")
    }
}

private final class HomeRepositoryFixtureBundleToken {}

private struct HomeRepositoryCredentialStore: HanaCredentialStore {
    func data(for account: String) throws -> Data? { nil }
    func set(_ data: Data, for account: String) throws {}
    func removeData(for account: String) throws {}
}

nonisolated private final class HomeRepositoryURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedResponseData = Data()
    private static var storedRequestedURL: URL?

    static var requestedURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestedURL
    }

    static func reset(responseData: Data) {
        lock.lock()
        storedResponseData = responseData
        storedRequestedURL = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        Self.lock.lock()
        Self.storedRequestedURL = url
        let responseData = Self.storedResponseData
        Self.lock.unlock()

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
