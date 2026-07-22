import Foundation
import Testing

@testable import Hana

@Suite("Favorite repository", .serialized)
struct HanimeFavoriteRepositoryTests {
    @Test("successful favorite changes update the cached video and revision")
    @MainActor
    func successfulFavoriteChanges() async throws {
        let (repository, session) = try makeRepository(
            html: videoHTML(isFavorite: false, favoriteCount: 7),
            postStatusCode: 200
        )
        defer {
            session.invalidateAndCancel()
            FavoriteRepositoryURLProtocol.reset()
        }

        let video = try await repository.video(code: "9001")
        try await repository.setVideoFavorite(video: video, shouldFavorite: true)

        let favorited = try #require(repository.cachedVideo(code: "9001"))
        #expect(favorited.isFavorite)
        #expect(favorited.favoriteCount == 8)
        #expect(repository.favoriteRevision == 1)

        try await repository.setVideoFavorite(video: favorited, shouldFavorite: false)

        let unfavorited = try #require(repository.cachedVideo(code: "9001"))
        #expect(!unfavorited.isFavorite)
        #expect(unfavorited.favoriteCount == 7)
        #expect(repository.favoriteRevision == 2)
        #expect(FavoriteRepositoryURLProtocol.lastMethod == "POST")
    }

    @Test("unfavoriting never reduces the cached count below zero")
    @MainActor
    func favoriteCountClampsAtZero() async throws {
        let (repository, session) = try makeRepository(
            html: videoHTML(isFavorite: true, favoriteCount: 0),
            postStatusCode: 200
        )
        defer {
            session.invalidateAndCancel()
            FavoriteRepositoryURLProtocol.reset()
        }

        let video = try await repository.video(code: "9001")
        try await repository.setVideoFavorite(video: video, shouldFavorite: false)

        let cached = try #require(repository.cachedVideo(code: "9001"))
        #expect(!cached.isFavorite)
        #expect(cached.favoriteCount == 0)
    }

    @Test("failed favorite changes preserve the cached state and revision")
    @MainActor
    func failedFavoriteChangePreservesState() async throws {
        let (repository, session) = try makeRepository(
            html: videoHTML(isFavorite: false, favoriteCount: 7),
            postStatusCode: 500
        )
        defer {
            session.invalidateAndCancel()
            FavoriteRepositoryURLProtocol.reset()
        }

        let video = try await repository.video(code: "9001")
        do {
            try await repository.setVideoFavorite(video: video, shouldFavorite: true)
            Issue.record("The favorite request unexpectedly succeeded")
        } catch {
            #expect(error is HanaNetworkError)
        }

        let cached = try #require(repository.cachedVideo(code: "9001"))
        #expect(!cached.isFavorite)
        #expect(cached.favoriteCount == 7)
        #expect(repository.favoriteRevision == 0)
    }

    @Test("removing a favorite from the account list updates the cached video and revision")
    @MainActor
    func removingFavoriteFromAccountList() async throws {
        let (repository, session) = try makeRepository(
            html: videoHTML(isFavorite: true, favoriteCount: 7),
            postStatusCode: 200,
            deleteResponseData: Data(#"{"success":true}"#.utf8)
        )
        defer {
            session.invalidateAndCancel()
            FavoriteRepositoryURLProtocol.reset()
        }

        _ = try await repository.video(code: "9001")
        try await repository.deleteAccountVideo(
            kind: .favorites,
            videoCode: "9001",
            csrfToken: "token"
        )

        let cached = try #require(repository.cachedVideo(code: "9001"))
        #expect(!cached.isFavorite)
        #expect(cached.favoriteCount == 6)
        #expect(repository.favoriteRevision == 1)
        #expect(FavoriteRepositoryURLProtocol.lastMethod == "DELETE")
    }

    @Test("removing an uncached favorite still increments the revision")
    @MainActor
    func removingUncachedFavoriteFromAccountList() async throws {
        let (repository, session) = try makeRepository(
            html: videoHTML(isFavorite: true, favoriteCount: 7),
            postStatusCode: 200,
            deleteResponseData: Data(#"{"success":true}"#.utf8)
        )
        defer {
            session.invalidateAndCancel()
            FavoriteRepositoryURLProtocol.reset()
        }

        try await repository.deleteAccountVideo(
            kind: .favorites,
            videoCode: "9001",
            csrfToken: "token"
        )

        #expect(repository.cachedVideo(code: "9001") == nil)
        #expect(repository.favoriteRevision == 1)
        #expect(FavoriteRepositoryURLProtocol.lastMethod == "DELETE")
    }

    @MainActor
    private func makeRepository(
        html: String,
        postStatusCode: Int,
        deleteResponseData: Data? = nil
    ) throws -> (HanimeRepository, URLSession) {
        FavoriteRepositoryURLProtocol.reset(
            responseData: Data(html.utf8),
            postStatusCode: postStatusCode,
            deleteResponseData: deleteResponseData
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FavoriteRepositoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let baseURL = try #require(URL(string: "https://example.invalid/"))
        let defaults = try #require(UserDefaults(suiteName: "HanimeFavoriteRepositoryTests.\(UUID().uuidString)"))
        let cookieStore = HanaSessionCookieStore(
            credentialStore: FavoriteRepositoryCredentialStore(),
            defaults: defaults
        )
        return (
            HanimeRepository(
                httpClient: HanaHTTPClient(
                    baseURL: baseURL,
                    sessionCookieStore: cookieStore,
                    session: session
                ),
                parser: HanimeHTMLParser(baseURL: baseURL)
            ),
            session
        )
    }

    private func videoHTML(isFavorite: Bool, favoriteCount: Int) -> String {
        let likeStatus = isFavorite ? #"<input name="like-status" value="1">"# : ""
        return """
        <!doctype html>
        <html>
        <head><title>Favorite Example</title></head>
        <body>
          <h1 id="shareBtn-title">Favorite Example</h1>
          <input name="_token" value="token">
          <input name="like-user-id" value="user">
          \(likeStatus)
          <input name="likes-count" value="\(favoriteCount)">
        </body>
        </html>
        """
    }
}

private struct FavoriteRepositoryCredentialStore: HanaCredentialStore {
    func data(for account: String) throws -> Data? { nil }
    func set(_ data: Data, for account: String) throws {}
    func removeData(for account: String) throws {}
}

nonisolated private final class FavoriteRepositoryURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responseData = Data()
    private static var deleteResponseData: Data?
    private static var postStatusCode = 200
    private static var method: String?

    static var lastMethod: String? {
        lock.lock()
        defer { lock.unlock() }
        return method
    }

    static func reset(
        responseData: Data = Data(),
        postStatusCode: Int = 200,
        deleteResponseData: Data? = nil
    ) {
        lock.lock()
        Self.responseData = responseData
        Self.postStatusCode = postStatusCode
        Self.deleteResponseData = deleteResponseData
        Self.method = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.lock.lock()
        Self.method = request.httpMethod
        let statusCode = request.httpMethod == "POST" ? Self.postStatusCode : 200
        let data = request.httpMethod == "DELETE" ? (Self.deleteResponseData ?? Self.responseData) : Self.responseData
        Self.lock.unlock()

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
