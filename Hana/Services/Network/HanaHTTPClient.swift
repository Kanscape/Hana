import Foundation

enum HanaNetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case authenticationFailed
    case httpStatus(Int, URL?)
    case cloudflareChallenge(URL)
    case invalidTextEncoding

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "URL 无效"
        case .invalidResponse:
            "服务器响应无效"
        case .authenticationFailed:
            "登录失败，请检查账号和密码"
        case .httpStatus(let statusCode, _):
            "HTTP \(statusCode)"
        case .cloudflareChallenge:
            "需要 Cloudflare 验证"
        case .invalidTextEncoding:
            "页面编码解析失败"
        }
    }
}

final class HanaHTTPClient {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    let baseURL: URL

    private let session: URLSession
    private let sessionCookieStore: HanaSessionCookieStore

    init(
        baseURL: URL,
        sessionCookieStore: HanaSessionCookieStore,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.sessionCookieStore = sessionCookieStore
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.httpShouldSetCookies = true
            configuration.httpCookieAcceptPolicy = .always
            configuration.httpCookieStorage = .shared
            configuration.requestCachePolicy = .useProtocolCachePolicy
            configuration.connectionProxyDictionary = HanaNetworkProxySettings.current().connectionProxyDictionary
            configuration.urlCache = URLCache(
                memoryCapacity: 24 * 1024 * 1024,
                diskCapacity: 96 * 1024 * 1024
            )
            self.session = URLSession(configuration: configuration)
        }
    }

    func html(
        for endpoint: HanaEndpoint,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> String {
        let data = try await data(for: endpoint, cachePolicy: cachePolicy)
        guard let html = String(data: data, encoding: .utf8) else {
            throw HanaNetworkError.invalidTextEncoding
        }
        return html
    }

    func data(
        for endpoint: HanaEndpoint,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> Data {
        let url = try endpoint.url(relativeTo: baseURL)
        return try await data(from: url, cachePolicy: cachePolicy)
    }

    func data(
        from url: URL,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        timeoutInterval: TimeInterval = 20
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = cachePolicy
        pageHeaders(for: url).forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HanaNetworkError.invalidResponse
        }

        if isCloudflareChallenge(httpResponse) {
            throw HanaNetworkError.cloudflareChallenge(url)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HanaNetworkError.httpStatus(httpResponse.statusCode, url)
        }

        return data
    }

    func postForm(
        to endpoint: HanaEndpoint,
        fields: [String: String?],
        csrfToken: String? = nil,
        additionalSuccessStatusCodes: Set<Int> = []
    ) async throws -> Data {
        let url = try endpoint.url(relativeTo: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        pageHeaders(for: url).forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-TOKEN")
        }
        request.httpBody = formBody(from: fields)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HanaNetworkError.invalidResponse
        }

        if isCloudflareChallenge(httpResponse) {
            throw HanaNetworkError.cloudflareChallenge(url)
        }

        let isSuccess = (200..<300).contains(httpResponse.statusCode)
            || additionalSuccessStatusCodes.contains(httpResponse.statusCode)
        guard isSuccess else {
            throw HanaNetworkError.httpStatus(httpResponse.statusCode, url)
        }

        return data
    }

    func deleteJSON(
        to endpoint: HanaEndpoint,
        body: [String: String],
        csrfToken: String? = nil
    ) async throws -> Data {
        let url = try endpoint.url(relativeTo: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        pageHeaders(for: url).forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if let csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-TOKEN")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HanaNetworkError.invalidResponse
        }

        if isCloudflareChallenge(httpResponse) {
            throw HanaNetworkError.cloudflareChallenge(url)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HanaNetworkError.httpStatus(httpResponse.statusCode, url)
        }

        return data
    }

    func pageHeaders(for url: URL? = nil) -> [String: String] {
        var headers = [
            "User-Agent": Self.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": Locale.preferredLanguages.prefix(3).joined(separator: ",")
        ]
        if let url, let cookie = cookieHeader(for: url) {
            headers["Cookie"] = cookie
        }
        return headers
    }

    func imageURLRequest(
        for url: URL,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        timeoutInterval: TimeInterval = 20
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = cachePolicy
        imageHeaders(for: url).forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    func imageHeaders(for url: URL) -> [String: String] {
        var headers = [
            "User-Agent": Self.userAgent,
            "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
            "Accept-Language": Locale.preferredLanguages.prefix(3).joined(separator: ","),
            "Referer": baseURL.absoluteString
        ]
        if let cookie = cookieHeader(for: url) {
            headers["Cookie"] = cookie
        }
        return headers
    }

    func mediaHeaders(for url: URL) -> [String: String] {
        var headers = [
            "User-Agent": Self.userAgent,
            "Accept": "video/mp4,video/*;q=0.9,*/*;q=0.8",
            "Accept-Language": Locale.preferredLanguages.prefix(3).joined(separator: ","),
            "Referer": baseURL.absoluteString
        ]
        if let cookie = cookieHeader(for: url) {
            headers["Cookie"] = cookie
        }
        return headers
    }

    private func cookieHeader(for url: URL) -> String? {
        var names: Set<String> = []
        var pairs: [String] = []

        for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] where cookie.name != HanaVideoLanguagePreference.cookieName {
            names.insert(cookie.name)
            pairs.append("\(cookie.name)=\(cookie.value)")
        }

        if isSiteURL(url),
           let storedCookieHeader = sessionCookieStore.cookieHeader(for: baseURL) {
            for pair in cookiePairs(from: storedCookieHeader)
            where pair.name != HanaVideoLanguagePreference.cookieName && !names.contains(pair.name) {
                names.insert(pair.name)
                pairs.append("\(pair.name)=\(pair.value)")
            }
        }

        if isSiteURL(url),
           let language = HanaVideoLanguagePreference.cookieValue(
            for: UserDefaults.standard.string(forKey: HanaSettingsKey.videoLanguage)
           ) {
            pairs.append("\(HanaVideoLanguagePreference.cookieName)=\(language)")
        }

        return pairs.isEmpty ? nil : pairs.joined(separator: "; ")
    }

    private func cookiePairs(from header: String) -> [(name: String, value: String)] {
        header.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return (name: parts[0], value: parts[1])
        }
    }

    private func isSiteURL(_ url: URL) -> Bool {
        guard let requestHost = url.host(),
              let siteHost = baseURL.host() else {
            return false
        }
        return requestHost == siteHost || requestHost.hasSuffix(".\(siteHost)")
    }

    private func isCloudflareChallenge(_ response: HTTPURLResponse) -> Bool {
        guard response.statusCode == 403 else { return false }
        if response.value(forHTTPHeaderField: "cf-mitigated") == "challenge" {
            return true
        }
        return response.value(forHTTPHeaderField: "server")?
            .localizedCaseInsensitiveContains("cloudflare") == true
    }

    private func formBody(from fields: [String: String?]) -> Data? {
        var components = URLComponents()
        components.queryItems = fields.compactMap { key, value in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}
