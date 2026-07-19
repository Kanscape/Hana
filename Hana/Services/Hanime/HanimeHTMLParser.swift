import Foundation
import SwiftSoup

enum HanimeParseError: LocalizedError {
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            "页面缺少必要字段：\(field)"
        }
    }
}

struct HanimeHTMLParser {
    private struct HomeRecommendationDescriptor {
        let key: String
        let title: String
        let sourceIndex: Int
    }

    private static let homeRecommendationDescriptors = [
        HomeRecommendationDescriptor(key: "latest_hanime", title: "最新里番", sourceIndex: 2),
        HomeRecommendationDescriptor(key: "latest_release", title: "最新上市", sourceIndex: 0),
        HomeRecommendationDescriptor(key: "latest_upload", title: "最新上传", sourceIndex: 1),
        HomeRecommendationDescriptor(key: "watching_now", title: "他们在看", sourceIndex: 13),
        HomeRecommendationDescriptor(key: "short_episode", title: "泡面番", sourceIndex: 3),
        HomeRecommendationDescriptor(key: "motion_anime", title: "动态动画", sourceIndex: 5),
        HomeRecommendationDescriptor(key: "3d_cg", title: "3D作品", sourceIndex: 6),
        HomeRecommendationDescriptor(key: "2_5d", title: "2.5D", sourceIndex: 7),
        HomeRecommendationDescriptor(key: "2d_anime", title: "2D动画", sourceIndex: 8),
        HomeRecommendationDescriptor(key: "ai_generated", title: "AI生成", sourceIndex: 10),
        HomeRecommendationDescriptor(key: "mmd", title: "MMD", sourceIndex: 11),
        HomeRecommendationDescriptor(key: "cosplay", title: "Cosplay", sourceIndex: 12)
    ]

    let baseURL: URL

    func parseHome(_ html: String) throws -> HanimeHomePage {
        let body = try documentBody(from: html)
        let banner = try parseBanner(from: body)
        let rowElements = try body.select("div[id=home-rows-wrapper] > div").array()

        let sections = try Self.homeRecommendationDescriptors.compactMap { descriptor -> HanimeHomeSection? in
            guard rowElements.indices.contains(descriptor.sourceIndex) else { return nil }
            let element = rowElements[descriptor.sourceIndex]
            let videos = try parseVideoCards(in: element)
            guard !videos.isEmpty else { return nil }
            return HanimeHomeSection(
                key: descriptor.key,
                title: descriptor.title,
                videos: videos
            )
        }

        guard !sections.isEmpty else {
            throw HanimeParseError.missingRequiredField("home recommendations")
        }

        return HanimeHomePage(banner: banner, sections: sections)
    }

    func parseSearch(_ html: String) throws -> [HanimeInfo] {
        let body = try documentBody(from: html)
        if let normalRoot = try body.select("div.content-padding-new").first() {
            return try parseNormalCards(in: normalRoot)
        }
        if let simplifiedRoot = try body.select("div.home-rows-videos-wrapper").first() {
            return try parseSimplifiedCards(in: simplifiedRoot)
        }
        return []
    }

    func parseCurrentUser(_ html: String) throws -> HanimeUserProfile? {
        let body = try documentBody(from: html)
        guard let userInfo = try body.select("div#user-modal-dp-wrapper").first(),
              let username = try userInfo.select("#user-modal-name").first()?.text().trimmedNonEmpty(),
              let profileLink = try body.select("#user-modal-trigger").first()?.attr("href"),
              let id = userID(from: profileLink) else {
            return nil
        }

        return HanimeUserProfile(
            id: id,
            username: username,
            avatarURL: try firstURL(from: userInfo.select("img").first(), attribute: "src")
        )
    }

    func parseCSRFToken(_ html: String) throws -> String? {
        let body = try documentBody(from: html)
        return try body.select("input[name=_token]").first()?.attr("value").trimmedNonEmpty()
    }

    func parseAccountVideoList(_ html: String) throws -> HanimeAccountVideoList {
        let body = try documentBody(from: html)
        let csrfToken = try body.select("input[name=_token]").first()?.attr("value").trimmedNonEmpty()
        let description = try body.getElementById("playlist-show-description")?.ownText().trimmedNonEmpty()
        let root = try body.select(".horizontal-row").first() ?? body
        let videos = try parseAccountCards(in: root, selector: "div[class^=user-tab-item-wrapper]")
        return HanimeAccountVideoList(
            videos: videos,
            description: description,
            csrfToken: csrfToken,
            maxPage: try parseMaxPage(from: body)
        )
    }

    func parsePlaylistItems(_ html: String) throws -> HanimeAccountVideoList {
        let body = try documentBody(from: html)
        let csrfToken = try body.select("input[name=_token]").first()?.attr("value").trimmedNonEmpty()
        let description = try body.select("p.playlist-description").first()?.text().trimmedNonEmpty()
        let root = try body.select(".playlist-video-list").first() ?? body
        let videos = try parseAccountCards(in: root, selector: "div[class^=user-tab-item-wrapper]")
        return HanimeAccountVideoList(
            videos: videos,
            description: description,
            csrfToken: csrfToken,
            maxPage: try parseMaxPage(from: body)
        )
    }

    func parsePlaylists(_ html: String) throws -> HanimePlaylistsPage {
        let body = try documentBody(from: html)
        let csrfToken = try body.select("input[name=_token]").first()?.attr("value").trimmedNonEmpty()
        let playlists = try body.select("div[class^=user-tab-item-wrapper]").array().compactMap { element in
            try parsePlaylistSummary(from: element)
        }
        return HanimePlaylistsPage(
            playlists: playlists,
            csrfToken: csrfToken,
            maxPage: try parseMaxPage(from: body)
        )
    }

    func parseSubscriptions(_ html: String) throws -> HanimeSubscriptionsPage {
        let body = try documentBody(from: html)
        let csrfToken = try body.select("input[name=_token]").first()?.attr("value").trimmedNonEmpty()
        let artists = try body.select("div.subscriptions-nav div.subscriptions-artist-card").array().compactMap { card in
            try parseSubscriptionArtist(from: card)
        }
        let videoRoot = try body.select("div.content-padding-new").first() ?? body
        let videos = try parseAccountCards(in: videoRoot, selector: "div[class^=video-item-container]")
        return HanimeSubscriptionsPage(
            artists: artists,
            videos: videos,
            csrfToken: csrfToken,
            maxPage: try parseMaxPage(from: body)
        )
    }

    func parseVideo(_ html: String, videoCode: String) throws -> HanimeVideo {
        let body = try documentBody(from: html)
        let documentTitle = try body.ownerDocument()?.title().trimmedNonEmpty()
        let title = try body.select("#shareBtn-title").first()?.text().trimmedNonEmpty()
            ?? documentTitle
            ?? {
                throw HanimeParseError.missingRequiredField("title")
            }()

        let videoElement = try body.select("video#player").first()
        var coverURL = try firstURL(from: videoElement, attribute: "poster")
        if coverURL == nil {
            coverURL = try firstURL(from: body.select("meta[property=og:image]").first(), attribute: "content")
        }

        let details = try body.select("div[class=video-details-wrapper]").first()
        let caption = try details?.select("div[class^=video-caption-text]").first()
        let legacyChineseTitle = try caption?.previousElementSibling()?.ownText().trimmedNonEmpty()
            ?? details?.select("h3, h4").first()?.ownText().trimmedNonEmpty()
        let chineseTitle = legacyChineseTitle
        let introduction = normalizeVideoIntroduction(try caption?.text())
        let detailText = try details?.select("div > div > div").first()?.text()
        let (views, uploadTime) = parseViewsAndUploadTime(from: detailText)

        let tags = try body.select("div.single-video-tag > a[href]").array().compactMap { element in
            try element.text()
                .replacingOccurrences(of: "#", with: "")
                .components(separatedBy: " (")
                .first?
                .trimmedNonEmpty()
        }

        let resolutions = try parseResolutionLinks(from: body)
        let relatedVideos = try parseRelatedVideos(from: body)
        let csrfToken = try body.select("input[name=_token]").first()?.attr("value").trimmedNonEmpty()
        let currentUserID = try body.select("input[name=like-user-id]").first()?.attr("value").trimmedNonEmpty()
        let likeStatus = try body.select("[name=like-status]").first()?.attr("value").trimmedNonEmpty()
        let favoriteCount = try body.select("input[name=likes-count]").first()?.attr("value").trimmedNonEmpty().flatMap(Int.init)
        let artist = try parseArtist(from: body)
        let listState = try parseVideoListState(from: body)
        let originalComicURL = try firstURL(from: body.select("a.video-comic-btn").first(), attribute: "href")

        return HanimeVideo(
            videoCode: videoCode,
            title: title,
            coverURL: coverURL,
            chineseTitle: chineseTitle,
            introduction: introduction,
            uploadTime: uploadTime,
            views: views,
            tags: tags,
            resolutions: resolutions,
            relatedVideos: relatedVideos,
            originalComicURL: originalComicURL,
            favoriteCount: favoriteCount,
            isFavorite: likeStatus != nil,
            csrfToken: csrfToken,
            currentUserID: currentUserID,
            artist: artist,
            listState: listState
        )
    }

    func parseComments(_ json: String) throws -> HanimeCommentsPage {
        let html = try htmlFragment(from: json, key: "comments")
        let body = try documentBody(from: html)
        let csrfToken = try body.select("input[name=_token]").first()?.attr("value").trimmedNonEmpty()
        let currentUserID = try body.select("input[name=comment-user-id]").first()?.attr("value").trimmedNonEmpty()
        let root = try body.getElementById("comment-start")
        let children = root?.children().array() ?? []
        let comments = try stride(from: 0, to: children.count, by: 4).compactMap { index in
            let end = min(index + 4, children.count)
            let groupHTML = try children[index..<end].map { try $0.outerHtml() }.joined()
            return try parseCommentGroup(groupHTML, isChildComment: false)
        }
        return HanimeCommentsPage(comments: comments, currentUserID: currentUserID, csrfToken: csrfToken)
    }

    func parseCommentReplies(_ json: String) throws -> HanimeCommentsPage {
        let html = try htmlFragment(from: json, key: "replies")
        let body = try documentBody(from: html)
        let root = try body.select("div[id^=reply-start]").first()
        let children = root?.children().array() ?? []
        let comments = try stride(from: 0, to: children.count, by: 2).compactMap { index in
            let end = min(index + 2, children.count)
            let groupHTML = try children[index..<end].map { try $0.outerHtml() }.joined()
            return try parseCommentGroup(groupHTML, isChildComment: true)
        }
        return HanimeCommentsPage(comments: comments, currentUserID: nil, csrfToken: nil)
    }

    private func documentBody(from html: String) throws -> Element {
        guard let body = try SwiftSoup.parse(html, baseURL.absoluteString).body() else {
            throw HanimeParseError.missingRequiredField("body")
        }
        return body
    }

    private func parseBanner(from body: Element) throws -> HanimeBanner? {
        guard let bannerWrapper = try body.select("div[id=home-banner-wrapper]").first() else {
            return nil
        }

        let bannerImageRoot = try bannerWrapper.previousElementSibling()
        let imageElements = try bannerImageRoot?.select("img").array() ?? []
        let imageElement = imageElements.dropFirst().first ?? imageElements.first
        let title = try imageElement?.attr("alt").trimmedNonEmpty()
        let coverURL = try firstURL(from: imageElement, attribute: "src")
        let headingDescription = try bannerWrapper.select("h4").first()?.ownText().trimmedNonEmpty()
        let description = bannerWrapper.ownText().trimmedNonEmpty() ?? headingDescription

        let scriptVideoCode = try body.select("script").array()
            .lazy
            .map { $0.data() }
            .first { $0.contains("watch?v=") }
            .flatMap(videoCode(from:))
        let linkVideoCode = try bannerWrapper.select("a[href]").array()
            .lazy
            .compactMap { try? $0.attr("abs:href") }
            .compactMap(videoCode(from:))
            .first

        guard let title, coverURL != nil else { return nil }
        return HanimeBanner(
            title: title,
            description: description,
            coverURL: coverURL,
            videoCode: scriptVideoCode ?? linkVideoCode
        )
    }

    private func parseVideoCards(in element: Element) throws -> [HanimeInfo] {
        let normalCards = try parseNormalCards(in: element)
        if !normalCards.isEmpty {
            return normalCards.deduplicatedByVideoCode()
        }
        return try parseSimplifiedCards(in: element).deduplicatedByVideoCode()
    }

    private func parseNormalCards(in root: Element) throws -> [HanimeInfo] {
        try root.select("div[class^=horizontal-card]").array().compactMap(parseNormalCard)
    }

    private func parseAccountCards(in root: Element, selector: String) throws -> [HanimeInfo] {
        try root.select(selector).array().compactMap(parseNormalCard)
    }

    private func parseSimplifiedCards(in root: Element) throws -> [HanimeInfo] {
        var videos = [HanimeInfo]()
        for link in try root.select("a[href]").array() {
            guard try link.select("div.home-rows-videos-div").first() != nil,
                  let info = try parseSimplifiedCard(from: link) else {
                continue
            }
            videos.append(info)
        }
        return videos
    }

    private func parseNormalCard(from element: Element) throws -> HanimeInfo? {
        let title = try element.select("div.title, h4.video-title").first()?.text().trimmedNonEmpty()
            ?? (try element.select("img").first()?.attr("alt").trimmedNonEmpty())
            ?? (try element.attr("title").trimmedNonEmpty())
        let coverURL = try firstURL(from: element.select("img").first(), attribute: "src")
        let link = try primaryVideoLink(in: element)
        let code = link.flatMap(videoCode(from:))

        guard let title, let code else { return nil }

        let thumbContainer = try element.select("div[class^=thumb-container]")
        let duration = try thumbContainer.select("div[class^=duration]").text().trimmedNonEmpty()
        let stats = try thumbContainer.select("div[class^=stat-item]").array()
        let views = try stats.dropFirst().first?.text().trimmedNonEmpty()

        let artistAndUploadTime = try element.select("div.subtitle a, div.video-meta-data a")
            .first()?
            .text()
            .trimmedNonEmpty()
        let parts = artistAndUploadTime?
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let artist = parts?.first?.trimmedNonEmpty()
        let uploadTime = parts?.dropFirst().first?.trimmedNonEmpty()

        return HanimeInfo(
            title: title,
            coverURL: coverURL,
            videoCode: code,
            duration: duration,
            views: views,
            uploadTime: uploadTime,
            artist: artist,
            style: .normal
        )
    }

    private func primaryVideoLink(in element: Element) throws -> String? {
        let links = try element.select("a[href]").array().compactMap { link in
            try link.attr("abs:href").trimmedNonEmpty()
        }
        if let primaryLink = links.first, videoCode(from: primaryLink) != nil {
            return primaryLink
        }
        return links.first { videoCode(from: $0) != nil }
    }

    private func parsePlaylistSummary(from element: Element) throws -> HanimePlaylistSummary? {
        let link = try element.select("a.video-link, a[href]").array()
            .lazy
            .compactMap { try? $0.attr("abs:href") }
            .first { $0.contains("list=") }
        guard let listCode = link.flatMap(playlistCode(from:)) else { return nil }

        let title = try element.select("div.title").first()?.ownText().trimmedNonEmpty()
            ?? element.select("div.title").first()?.text().trimmedNonEmpty()
            ?? element.select("img").first()?.attr("alt").trimmedNonEmpty()
        guard let title else { return nil }

        let totalText = try element.select("div.stat-item").first()?.text()
        let totalDigits = totalText?.filter { $0.isNumber }
        let total = totalDigits.flatMap(Int.init) ?? 0
        return HanimePlaylistSummary(
            listCode: listCode,
            title: title,
            total: total,
            coverURL: try firstURL(from: element.select("img.main-thumb, img").first(), attribute: "src")
        )
    }

    private func parseSubscriptionArtist(from element: Element) throws -> HanimeSubscriptionArtist? {
        guard let name = try element.select("div.card-mobile-title").first()?.text().trimmedNonEmpty() else {
            return nil
        }
        let images = try element.select("img").array()
        let avatarElement = images.dropFirst().first ?? images.first
        let userID = try element.select("input[name=subscribe-user-id]").first()?.attr("value").trimmedNonEmpty()
            ?? element.attr("data-user-id").trimmedNonEmpty()
        let artistID = try element.select("input[name=subscribe-artist-id]").first()?.attr("value").trimmedNonEmpty()
            ?? element.attr("data-artist-id").trimmedNonEmpty()
        return HanimeSubscriptionArtist(
            name: name,
            avatarURL: try firstURL(from: avatarElement, attribute: "src"),
            userID: userID,
            artistID: artistID
        )
    }

    private func parseSimplifiedCard(from link: Element) throws -> HanimeInfo? {
        let href = try link.attr("abs:href")
        guard let code = videoCode(from: href) else { return nil }

        let image = try link.select("img").first()
        let coverURL = try firstURL(from: image, attribute: "src")
        let title = try link.select("div.home-rows-videos-title, div[class$=title]").first()?.text().trimmedNonEmpty()
            ?? image?.attr("alt").trimmedNonEmpty()

        guard let title else { return nil }
        return HanimeInfo(
            title: title,
            coverURL: coverURL,
            videoCode: code,
            duration: nil,
            views: nil,
            uploadTime: nil,
            artist: nil,
            style: .compact
        )
    }

    private func parseResolutionLinks(from body: Element) throws -> [ResolutionLink] {
        var links = [ResolutionLink]()
        let sources = try body.select("video#player source[src]").array()
        for source in sources {
            let size = try source.attr("size").trimmedNonEmpty()
            let quality = size.map { "\($0)P" } ?? "Unknown"
            guard let url = try firstURL(from: source, attribute: "src") else { continue }
            links.append(ResolutionLink(
                quality: quality,
                url: url,
                mimeType: try source.attr("type").trimmedNonEmpty()
            ))
        }

        if links.isEmpty,
           let source = try body.select("div[id=player-div-wrapper] script").array()
            .lazy
            .map({ $0.data() })
            .compactMap(scriptSource(from:))
            .first,
           let url = resolvedURL(from: source) {
            links.append(ResolutionLink(quality: "Unknown", url: url, mimeType: nil))
        }

        let qualityOrder = ["1080P": 0, "720P": 1, "480P": 2, "240P": 3, "Unknown": 4]
        return links.sorted {
            qualityOrder[$0.quality, default: 99] < qualityOrder[$1.quality, default: 99]
        }
    }

    private func parseRelatedVideos(from body: Element) throws -> [HanimeInfo] {
        guard let relatedRoot = try body.select("#related-tabcontent").first() else {
            return []
        }
        return try parseVideoCards(in: relatedRoot)
    }

    private func parseArtist(from body: Element) throws -> HanimeArtist? {
        let nameElement = try body.getElementById("video-artist-name")
        guard let name = try nameElement?.text().trimmedNonEmpty(),
              let genre = try nameElement?.nextElementSibling()?.text().trimmedNonEmpty() else {
            return nil
        }

        let avatarURL = try firstURL(
            from: body.select("div.video-details-wrapper > div > a > div > img[style*='position: absolute'][style*='border-radius: 50%']").first(),
            attribute: "src"
        )
        let subscriptionRoot = try body.getElementById("video-subscribe-form") ?? body
        let userID = try subscriptionRoot.select("input[name=subscribe-user-id]").first()?.attr("value").trimmedNonEmpty()
        let artistID = try subscriptionRoot.select("input[name=subscribe-artist-id]").first()?.attr("value").trimmedNonEmpty()
        let subscribeStatusElement = try subscriptionRoot.select("input[name=subscribe-status]").first()
        let subscribeStatus = try subscribeStatusElement?.attr("value").trimmingCharacters(in: .whitespacesAndNewlines)
        var subscription: HanimeArtist.Subscription?
        if let userID, let artistID, let subscribeStatus {
            subscription = HanimeArtist.Subscription(
                userID: userID,
                artistID: artistID,
                isSubscribed: subscribeStatus == "1"
            )
        }

        return HanimeArtist(
            name: name,
            avatarURL: avatarURL,
            genre: genre,
            subscription: subscription
        )
    }

    private func parseVideoListState(from body: Element) throws -> HanimeVideoListState? {
        let playlists = try body.select("div[class~=playlist-checkbox-wrapper]").array().compactMap { element -> HanimeVideoListState.Playlist? in
            let title = try element.select("span").first()?.ownText().trimmedNonEmpty()
            let input = try element.select("input").first()
            let code = try input?.attr("id").trimmedNonEmpty()
            guard let title, let code else { return nil }
            return HanimeVideoListState.Playlist(
                code: code,
                title: title,
                isSelected: input?.hasAttr("checked") == true
            )
        }
        let watchLaterInput = try body.getElementById("playlist-save-checkbox")?
            .select("input")
            .first()
        let isWatchLater = watchLaterInput?.hasAttr("checked") == true
        let watchLaterCode = try watchLaterInput?.attr("id").trimmedNonEmpty()
        guard isWatchLater || !playlists.isEmpty else { return nil }
        return HanimeVideoListState(isWatchLater: isWatchLater, watchLaterCode: watchLaterCode, playlists: playlists)
    }

    private func htmlFragment(from json: String, key: String) throws -> String {
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let value = dictionary[key] else {
            throw HanimeParseError.missingRequiredField(key)
        }
        if let html = value as? String {
            return html
        }
        return String(describing: value)
    }

    private func parseCommentGroup(_ html: String, isChildComment: Bool) throws -> HanimeComment? {
        guard let body = try SwiftSoup.parse(html, baseURL.absoluteString).body() else {
            return nil
        }
        let textClasses = try body.getElementsByClass("comment-index-text").array()
        let nameAndDate = textClasses.first
        let username = try nameAndDate?.select("a").first()?.ownText().trimmedNonEmpty()
        let date = try nameAndDate?.select("span").first()?.ownText().trimmedNonEmpty()
        let content = try textClasses.dropFirst().first?.text().trimmedNonEmpty()
        guard let username, let date, let content else { return nil }

        let commentID = try body.select("div[id^=reply-section-wrapper]").first()?.id()
            .components(separatedBy: "-")
            .last?
            .trimmedNonEmpty()
        let replyCountText = try body.select("div.load-replies-btn").text()
        let post = try HanimeCommentPost(
            foreignID: body.getElementById("foreign_id")?.attr("value").trimmedNonEmpty(),
            isPositive: body.getElementById("is_positive")?.attr("value") == "1",
            likeUserID: body.select("input[name=comment-like-user-id]").first()?.attr("value").trimmedNonEmpty(),
            commentLikesCount: body.select("input[name=comment-likes-count]").first()?.attr("value").trimmedNonEmpty().flatMap(Int.init),
            commentLikesSum: body.select("input[name=comment-likes-sum]").first()?.attr("value").trimmedNonEmpty().flatMap(Int.init),
            likeCommentStatus: body.select("input[name=like-comment-status]").first()?.attr("value") == "1",
            unlikeCommentStatus: body.select("input[name=unlike-comment-status]").first()?.attr("value") == "1"
        )

        return HanimeComment(
            avatarURL: try firstURL(from: body.select("img").first(), attribute: "src"),
            username: username,
            date: date,
            content: content,
            thumbUp: try body.getElementById("comment-like-form-wrapper")?
                .select("span[style]")
                .array()
                .dropFirst()
                .first?
                .text()
                .trimmedNonEmpty()
                .flatMap(Int.init),
            isChildComment: isChildComment,
            hasMoreReplies: (try body.select("div[class^=load-replies-btn]").first()) != nil,
            replyCount: firstCapture(in: replyCountText, pattern: #"(\d+)"#).flatMap(Int.init),
            commentID: commentID,
            post: post,
            reportableID: try body.select("span.report-btn").first()?.attr("data-reportable-id").trimmedNonEmpty(),
            reportableType: try body.select("span.report-btn").first()?.attr("data-reportable-type").trimmedNonEmpty()
        )
    }

    private func firstURL(from element: Element?, attribute: String) throws -> URL? {
        guard let element else { return nil }
        let absolute = try element.attr("abs:\(attribute)")
        if let url = resolvedURL(from: absolute) {
            return url
        }
        return try resolvedURL(from: element.attr(attribute))
    }

    private func resolvedURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private func videoCode(from value: String) -> String? {
        firstCapture(in: value, pattern: #"watch\?v=(\d+)"#)
    }

    private func playlistCode(from value: String) -> String? {
        firstCapture(in: value, pattern: #"[?&]list=([^&#]+)"#)
    }

    private func userID(from value: String) -> String? {
        firstCapture(in: value, pattern: #"/user/(\d+)"#)
    }

    private func scriptSource(from value: String) -> String? {
        firstCapture(in: value, pattern: #"const source = '(.+)'"#)
    }

    private func parseViewsAndUploadTime(from value: String?) -> (String?, Date?) {
        guard let value else { return (nil, nil) }
        let pattern = #"(觀看次數|观看次数)\s*[：:]\s*(.+?次)\s*(\d{4}-\d{2}-\d{2})"#
        let views = firstCapture(in: value, pattern: pattern, captureIndex: 2)?.trimmedNonEmpty()
        let dateText = firstCapture(in: value, pattern: pattern, captureIndex: 3)
        let date = dateText.flatMap(Self.dateFormatter.date(from:))
        return (views, date)
    }

    private func normalizeVideoIntroduction(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^由\s*(.+?)\s*(上傳|上传)(?=\s|·|$)"#,
                with: #"由 $1 $2"#,
                options: .regularExpression
            )
            .trimmedNonEmpty()
    }

    private func parseMaxPage(from body: Element) throws -> Int {
        let values = try body.select("ul.pagination a[href], ul.pagination span").array().compactMap { element in
            try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap(Int.init)
                .max()
        }
        return max(values.max() ?? 1, 1)
    }

    private func firstCapture(in value: String, pattern: String, captureIndex: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > captureIndex,
              let captureRange = Range(match.range(at: captureIndex), in: value) else {
            return nil
        }
        return String(value[captureRange])
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

}

private extension String {
    func trimmedNonEmpty() -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
