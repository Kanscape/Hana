import Foundation

struct HanaEndpoint: Hashable, Sendable {
    var path: String
    var queryItems: [URLQueryItem] = []

    static func home() -> HanaEndpoint {
        HanaEndpoint(path: "/")
    }

    static func login() -> HanaEndpoint {
        HanaEndpoint(path: "login")
    }

    static func search(query: String?, page: Int = 1) -> HanaEndpoint {
        search(criteria: HanimeSearchCriteria(query: query ?? ""), page: page)
    }

    static func search(criteria: HanimeSearchCriteria, page: Int = 1) -> HanaEndpoint {
        let criteria = criteria.normalized()
        var items = [URLQueryItem(name: "page", value: String(page))]
        if !criteria.query.isEmpty {
            items.append(URLQueryItem(name: "query", value: criteria.query))
        }
        if let genre = criteria.genre {
            items.append(URLQueryItem(name: "genre", value: genre))
        }
        if let sort = criteria.sort {
            items.append(URLQueryItem(name: "sort", value: sort))
        }
        if let date = criteria.dateQueryValue {
            items.append(URLQueryItem(name: "date", value: date))
        }
        if let duration = criteria.duration {
            items.append(URLQueryItem(name: "duration", value: duration))
        }
        for tag in criteria.tags {
            items.append(URLQueryItem(name: "tags[]", value: tag))
        }
        for brand in criteria.brands {
            items.append(URLQueryItem(name: "brands[]", value: brand))
        }
        return HanaEndpoint(path: "search", queryItems: items)
    }

    static func video(code: String) -> HanaEndpoint {
        HanaEndpoint(path: "watch", queryItems: [
            URLQueryItem(name: "v", value: code)
        ])
    }

    static func accountList(userID: String, kind: HanimeMyListKind, page: Int = 1) -> HanaEndpoint {
        HanaEndpoint(path: "user/\(userID)/\(kind.rawValue)", queryItems: [
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    static func playlists(userID: String, page: Int = 1) -> HanaEndpoint {
        HanaEndpoint(path: "user/\(userID)/playlists", queryItems: [
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    static func playlistItems(listCode: String, page: Int = 1) -> HanaEndpoint {
        HanaEndpoint(path: "playlist", queryItems: [
            URLQueryItem(name: "list", value: listCode),
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    static func subscriptions(page: Int = 1) -> HanaEndpoint {
        HanaEndpoint(path: "subscriptions", queryItems: [
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    static func comments(type: String = "video", code: String) -> HanaEndpoint {
        HanaEndpoint(path: "loadComment", queryItems: [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "id", value: code)
        ])
    }

    static func commentReplies(commentID: String) -> HanaEndpoint {
        HanaEndpoint(path: "loadReplies", queryItems: [
            URLQueryItem(name: "id", value: commentID)
        ])
    }

    static func likeVideo() -> HanaEndpoint {
        HanaEndpoint(path: "like")
    }

    static func saveVideoToList() -> HanaEndpoint {
        HanaEndpoint(path: "save")
    }

    static func createPlaylist() -> HanaEndpoint {
        HanaEndpoint(path: "createPlaylist")
    }

    static func modifyPlaylist(listCode: String) -> HanaEndpoint {
        HanaEndpoint(path: "playlist/\(listCode)")
    }

    static func deletePlaylistItem() -> HanaEndpoint {
        HanaEndpoint(path: "deletePlayitem")
    }

    static func deleteUserTabItem(videoCode: String) -> HanaEndpoint {
        HanaEndpoint(path: "user/tab-item/\(videoCode)")
    }

    static func subscribeArtist() -> HanaEndpoint {
        HanaEndpoint(path: "subscribe")
    }

    static func createComment() -> HanaEndpoint {
        HanaEndpoint(path: "createComment")
    }

    static func replyComment() -> HanaEndpoint {
        HanaEndpoint(path: "replyComment")
    }

    static func commentLike() -> HanaEndpoint {
        HanaEndpoint(path: "commentLike")
    }

    static func report(userID: String) -> HanaEndpoint {
        HanaEndpoint(path: "user/\(userID)/report")
    }

    func url(relativeTo baseURL: URL) throws -> URL {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw HanaNetworkError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw HanaNetworkError.invalidURL
        }
        return url
    }
}
