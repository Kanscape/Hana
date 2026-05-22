import Foundation

enum HanimeVideoCachePolicy: Equatable {
    case returnCacheDataElseLoad
    case reloadIgnoringCache
}

final class HanimeRepository {
    private struct CachedVideo {
        let video: HanimeVideo
        var lastAccessedAt: Date
    }

    private static let maximumVideoCacheCount = 12

    private let httpClient: HanaHTTPClient
    private let parser: HanimeHTMLParser
    private var videoCache: [String: CachedVideo] = [:]

    init(httpClient: HanaHTTPClient, parser: HanimeHTMLParser) {
        self.httpClient = httpClient
        self.parser = parser
    }

    func homePage() async throws -> HanimeHomePage {
        let html = try await httpClient.html(for: .home())
        return try parser.parseHome(html)
    }

    func currentUser() async throws -> HanimeUserProfile? {
        let html = try await httpClient.html(for: .home(), cachePolicy: .reloadIgnoringLocalCacheData)
        return try parser.parseCurrentUser(html)
    }

    func login(email: String, password: String) async throws -> HanimeUserProfile {
        let loginHTML = try await httpClient.html(for: .login(), cachePolicy: .reloadIgnoringLocalCacheData)
        let csrfToken = try parser.parseCSRFToken(loginHTML)
        _ = try await httpClient.postForm(
            to: .login(),
            fields: [
                "_token": csrfToken,
                "email": email,
                "password": password
            ],
            csrfToken: csrfToken,
            additionalSuccessStatusCodes: [302]
        )

        guard let user = try await currentUser() else {
            throw HanaNetworkError.authenticationFailed
        }
        return user
    }

    func search(query: String, page: Int = 1) async throws -> [HanimeInfo] {
        try await search(criteria: HanimeSearchCriteria(query: query), page: page)
    }

    func search(criteria: HanimeSearchCriteria, page: Int = 1) async throws -> [HanimeInfo] {
        let html = try await httpClient.html(for: .search(criteria: criteria, page: page))
        return try parser.parseSearch(html)
    }

    func cachedVideo(code: String) -> HanimeVideo? {
        guard var cached = videoCache[code] else { return nil }
        cached.lastAccessedAt = .now
        videoCache[code] = cached
        return cached.video
    }

    func video(
        code: String,
        cachePolicy: HanimeVideoCachePolicy = .returnCacheDataElseLoad
    ) async throws -> HanimeVideo {
        if cachePolicy == .returnCacheDataElseLoad, let cached = cachedVideo(code: code) {
            return cached
        }
        let html = try await httpClient.html(for: .video(code: code))
        let video = try parser.parseVideo(html, videoCode: code)
        storeCachedVideo(video, code: code)
        return video
    }

    func clearVideoCache() {
        videoCache.removeAll()
    }

    private func storeCachedVideo(_ video: HanimeVideo, code: String) {
        videoCache[code] = CachedVideo(video: video, lastAccessedAt: .now)
        removeOldCachedVideosIfNeeded(excluding: code)
    }

    private func removeOldCachedVideosIfNeeded(excluding currentCode: String) {
        while videoCache.count > Self.maximumVideoCacheCount {
            guard let oldest = videoCache
                .filter({ $0.key != currentCode })
                .min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })?
                .key else {
                return
            }
            videoCache.removeValue(forKey: oldest)
        }
    }

    func preview(monthCode: String) async throws -> HanimePreviewPage {
        let html = try await httpClient.html(for: .previews(monthCode: monthCode))
        return try parser.parsePreview(html, monthCode: monthCode)
    }

    func accountVideos(kind: HanimeMyListKind, userID: String, page: Int = 1) async throws -> HanimeAccountVideoList {
        let html = try await httpClient.html(
            for: .accountList(userID: userID, kind: kind, page: page),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try parser.parseAccountVideoList(html)
    }

    func playlists(userID: String, page: Int = 1) async throws -> HanimePlaylistsPage {
        let html = try await httpClient.html(
            for: .playlists(userID: userID, page: page),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try parser.parsePlaylists(html)
    }

    func playlistItems(listCode: String, page: Int = 1) async throws -> HanimeAccountVideoList {
        let html = try await httpClient.html(
            for: .playlistItems(listCode: listCode, page: page),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try parser.parsePlaylistItems(html)
    }

    func subscriptions(page: Int = 1) async throws -> HanimeSubscriptionsPage {
        let html = try await httpClient.html(
            for: .subscriptions(page: page),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try parser.parseSubscriptions(html)
    }

    func comments(type: String = "video", code: String) async throws -> HanimeCommentsPage {
        let html = try await httpClient.html(
            for: .comments(type: type, code: code),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try parser.parseComments(html)
    }

    func comments(videoCode: String) async throws -> HanimeCommentsPage {
        try await comments(type: "video", code: videoCode)
    }

    func commentReplies(commentID: String) async throws -> HanimeCommentsPage {
        let html = try await httpClient.html(
            for: .commentReplies(commentID: commentID),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try parser.parseCommentReplies(html)
    }

    func setVideoFavorite(video: HanimeVideo, shouldFavorite: Bool) async throws {
        let currentUserID = video.currentUserID ?? ""
        _ = try await httpClient.postForm(
            to: .likeVideo(),
            fields: [
                "like-foreign-id": video.videoCode,
                "like-status": shouldFavorite ? "" : "1",
                "_token": video.csrfToken,
                "like-user-id": currentUserID,
                "like-is-positive": "1"
            ],
            csrfToken: video.csrfToken
        )
    }

    func setVideoWatchLater(video: HanimeVideo, shouldSave: Bool) async throws {
        let listCode = video.listState?.watchLaterCode ?? HanimeMyListKind.watchLater.rawValue
        try await saveVideoToList(
            videoCode: video.videoCode,
            listCode: listCode,
            isSelected: shouldSave,
            userID: video.currentUserID ?? "",
            csrfToken: video.csrfToken
        )
    }

    func setVideoPlaylist(video: HanimeVideo, listCode: String, shouldAdd: Bool) async throws {
        try await saveVideoToList(
            videoCode: video.videoCode,
            listCode: listCode,
            isSelected: shouldAdd,
            userID: video.currentUserID ?? "",
            csrfToken: video.csrfToken
        )
    }

    func createPlaylist(videoCode: String = "", title: String, description: String, csrfToken: String?) async throws {
        _ = try await httpClient.postForm(
            to: .createPlaylist(),
            fields: [
                "_token": csrfToken,
                "create-playlist-video-id": videoCode,
                "playlist-title": title,
                "playlist-description": description
            ],
            csrfToken: csrfToken,
            additionalSuccessStatusCodes: [500]
        )
    }

    func createPlaylist(video: HanimeVideo, title: String, description: String) async throws {
        try await createPlaylist(
            videoCode: video.videoCode,
            title: title,
            description: description,
            csrfToken: video.csrfToken
        )
    }

    func modifyPlaylist(
        listCode: String,
        title: String,
        description: String,
        delete: Bool,
        csrfToken: String?
    ) async throws {
        _ = try await httpClient.postForm(
            to: .modifyPlaylist(listCode: listCode),
            fields: [
                "playlist-title": title,
                "playlist-description": description,
                "playlist-delete": delete ? "on" : nil,
                "_token": csrfToken,
                "_method": "PUT"
            ],
            csrfToken: csrfToken,
            additionalSuccessStatusCodes: [302]
        )
    }

    func deletePlaylistItem(listCode: String, videoCode: String, csrfToken: String?) async throws {
        let data = try await httpClient.deleteJSON(
            to: .deleteUserTabItem(videoCode: videoCode),
            body: ["tab": listCode],
            csrfToken: csrfToken
        )
        guard let response = try? JSONDecoder().decode(HanimeDeletePlaylistItemResponse.self, from: data),
              response.success else {
            throw HanaNetworkError.invalidResponse
        }
    }

    func deleteAccountVideo(kind: HanimeMyListKind, videoCode: String, csrfToken: String?) async throws {
        try await deletePlaylistItem(listCode: kind.rawValue, videoCode: videoCode, csrfToken: csrfToken)
    }

    func setArtistSubscribed(artist: HanimeArtist, shouldSubscribe: Bool, csrfToken: String?) async throws {
        guard let subscription = artist.subscription else {
            throw HanaNetworkError.invalidResponse
        }
        try await setArtistSubscribed(
            userID: subscription.userID,
            artistID: subscription.artistID,
            shouldSubscribe: shouldSubscribe,
            csrfToken: csrfToken
        )
    }

    func setArtistSubscribed(
        userID: String,
        artistID: String,
        shouldSubscribe: Bool,
        csrfToken: String?
    ) async throws {
        _ = try await httpClient.postForm(
            to: .subscribeArtist(),
            fields: [
                "_token": csrfToken,
                "subscribe-user-id": userID,
                "subscribe-artist-id": artistID,
                "subscribe-status": shouldSubscribe ? "" : "1"
            ],
            csrfToken: csrfToken
        )
    }

    private func saveVideoToList(
        videoCode: String,
        listCode: String,
        isSelected: Bool,
        userID: String,
        csrfToken: String?
    ) async throws {
        _ = try await httpClient.postForm(
            to: .saveVideoToList(),
            fields: [
                "_token": csrfToken,
                "input_id": listCode,
                "video_id": videoCode,
                "is_checked": isSelected ? "true" : "false",
                "user_id": userID
            ],
            csrfToken: csrfToken
        )
    }

    func postComment(type: String = "video", code: String, text: String, commentsPage: HanimeCommentsPage) async throws {
        guard let currentUserID = commentsPage.currentUserID else {
            throw HanaNetworkError.invalidResponse
        }
        _ = try await httpClient.postForm(
            to: .createComment(),
            fields: [
                "_token": commentsPage.csrfToken,
                "comment-user-id": currentUserID,
                "comment-type": type,
                "comment-foreign-id": code,
                "comment-text": text,
                "comment-count": "1",
                "comment-is-political": "0"
            ],
            csrfToken: commentsPage.csrfToken
        )
    }

    func postComment(videoCode: String, text: String, commentsPage: HanimeCommentsPage) async throws {
        try await postComment(type: "video", code: videoCode, text: text, commentsPage: commentsPage)
    }

    func postCommentReply(commentID: String, text: String, csrfToken: String?) async throws {
        _ = try await httpClient.postForm(
            to: .replyComment(),
            fields: [
                "_token": csrfToken,
                "reply-comment-id": commentID,
                "reply-comment-text": text
            ],
            csrfToken: csrfToken
        )
    }

    func setCommentLike(_ comment: HanimeComment, isPositive: Bool, csrfToken: String?) async throws {
        _ = try await httpClient.postForm(
            to: .commentLike(),
            fields: [
                "_token": csrfToken,
                "foreign_type": comment.isChildComment ? "reply" : "comment",
                "foreign_id": comment.post.foreignID,
                "is_positive": isPositive ? "1" : "0",
                "comment-like-user-id": comment.post.likeUserID,
                "comment-likes-count": String(comment.post.commentLikesCount ?? comment.thumbUp ?? 0),
                "comment-likes-sum": String(comment.post.commentLikesSum ?? 0),
                "like-comment-status": comment.post.likeCommentStatus ? "1" : "0",
                "unlike-comment-status": comment.post.unlikeCommentStatus ? "1" : "0"
            ],
            csrfToken: csrfToken
        )
    }

    func reportComment(
        _ comment: HanimeComment,
        reason: String,
        currentUserID: String,
        redirectURL: String,
        csrfToken: String?
    ) async throws {
        _ = try await httpClient.postForm(
            to: .report(userID: currentUserID),
            fields: [
                "_token": csrfToken,
                "redirect-url": redirectURL,
                "reportable-id": comment.reportableID,
                "reportable-type": comment.reportableType,
                "reason": reason
            ],
            csrfToken: csrfToken
        )
    }
}

private struct HanimeDeletePlaylistItemResponse: Decodable {
    let success: Bool
}
