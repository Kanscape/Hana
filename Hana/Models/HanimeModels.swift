import Foundation

enum HanaRoute: Hashable {
    case video(String)
    case search(HanimeSearchCriteria)
    case lockedSearch(HanimeSearchCriteria)
    case profileDetail
    case watchHistory
    case watchLater
    case playlists
    case remotePlaylist(HanimePlaylistSummary)
    case hKeyframes
    case downloads
    case settings
}

struct HanimeSearchOption: Identifiable, Hashable, Sendable {
    var id: String { value ?? title }

    let title: String
    let value: String?
}

struct HanimeSearchCriteria: Hashable, Codable, Sendable {
    var query: String = ""
    var genre: String?
    var sort: String?
    var date: String?
    var releaseYear: Int?
    var releaseMonth: Int?
    var duration: String?
    var tags: [String] = []
    var brands: [String] = []

    static let empty = HanimeSearchCriteria()

    static func tag(_ tag: String) -> HanimeSearchCriteria {
        HanimeSearchCriteria(tags: [tag])
    }

    static func artist(name: String, genre: String?) -> HanimeSearchCriteria {
        HanimeSearchCriteria(query: name, genre: genre)
    }

    static func genre(_ genre: String) -> HanimeSearchCriteria {
        HanimeSearchCriteria(genre: genre)
    }

    var isEmpty: Bool {
        normalized().query.isEmpty
            && normalized().genre == nil
            && normalized().sort == nil
            && normalized().date == nil
            && normalized().duration == nil
            && normalized().tags.isEmpty
            && normalized().brands.isEmpty
    }

    var summary: String {
        let items = activeFilters
        if items.isEmpty {
            return "搜索"
        }
        return items.joined(separator: " · ")
    }

    var historyKey: String {
        encodedJSONString() ?? summary
    }

    var activeFilters: [String] {
        let criteria = normalized()
        var items: [String] = []
        if !criteria.query.isEmpty {
            items.append(criteria.query)
        }
        if let genre = criteria.genre {
            items.append("类型：\(genre)")
        }
        if let sort = criteria.sort {
            items.append("排序：\(sort)")
        }
        if let date = criteria.date {
            items.append("日期：\(date)")
        } else if let releaseDateText = criteria.releaseDateText {
            items.append("日期：\(releaseDateText)")
        }
        if let duration = criteria.duration {
            items.append("时长：\(duration)")
        }
        let visibleTags = criteria.tags.filter { tag in
            criteria.query.isEmpty || !HanimeSearchOptionCatalog.tagSearchKey(tag, matches: criteria.query)
        }
        if !visibleTags.isEmpty {
            items.append("标签：\(visibleTags.joined(separator: "、"))")
        }
        if !criteria.brands.isEmpty {
            items.append("厂商：\(criteria.brands.joined(separator: "、"))")
        }
        return items
    }

    var hasNonQueryFilters: Bool {
        let criteria = normalized()
        return criteria.genre != nil
            || criteria.sort != nil
            || criteria.date != nil
            || criteria.releaseYear != nil
            || criteria.releaseMonth != nil
            || criteria.duration != nil
            || !criteria.tags.isEmpty
            || !criteria.brands.isEmpty
    }

    func applyingLockedQuery(_ lockedQuery: String?) -> HanimeSearchCriteria {
        guard let lockedQuery else { return normalized() }
        var criteria = normalized()
        criteria.query = lockedQuery
        return criteria.normalized()
    }

    func normalized() -> HanimeSearchCriteria {
        HanimeSearchCriteria(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            genre: normalizedOptional(genre),
            sort: normalizedOptional(sort),
            date: normalizedOptional(date),
            releaseYear: normalizedReleaseYear(date: date, year: releaseYear),
            releaseMonth: normalizedReleaseMonth(date: date, year: releaseYear, month: releaseMonth),
            duration: normalizedOptional(duration),
            tags: normalizedList(tags),
            brands: normalizedList(brands)
        )
    }

    var dateQueryValue: String? {
        let criteria = normalized()
        if let date = criteria.date {
            return date
        }
        return criteria.releaseDateText
    }

    var releaseDateText: String? {
        guard let releaseYear else { return nil }
        if let releaseMonth {
            return "\(releaseYear) 年 \(releaseMonth) 月"
        }
        return "\(releaseYear) 年"
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text != "全部" else {
            return nil
        }
        return text
    }

    private func normalizedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text).inserted else { return nil }
            return text
        }
    }

    private func normalizedReleaseYear(date: String?, year: Int?) -> Int? {
        guard normalizedOptional(date) == nil else { return nil }
        guard let year, (1990...Calendar.current.component(.year, from: .now) + 1).contains(year) else {
            return nil
        }
        return year
    }

    private func normalizedReleaseMonth(date: String?, year: Int?, month: Int?) -> Int? {
        guard normalizedReleaseYear(date: date, year: year) != nil else { return nil }
        guard let month, (1...12).contains(month) else { return nil }
        return month
    }

    func encodedJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(normalized()) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decoded(from json: String) -> HanimeSearchCriteria? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HanimeSearchCriteria.self, from: data).normalized()
    }
}

extension HanimeSearchOption {
    static let genres: [HanimeSearchOption] = HanimeSearchOptionCatalog.genres
    static let sortOptions: [HanimeSearchOption] = HanimeSearchOptionCatalog.sortOptions
    static let dateOptions: [HanimeSearchOption] = HanimeSearchOptionCatalog.dateOptions
    static let durationOptions: [HanimeSearchOption] = HanimeSearchOptionCatalog.durationOptions
}

struct HanimeBanner: Identifiable, Hashable, Sendable {
    var id: String { videoCode ?? title }

    let title: String
    let description: String?
    let coverURL: URL?
    let videoCode: String?
}

struct HanimeHomeSection: Identifiable, Hashable, Sendable {
    var id: String { key }

    let key: String
    let title: String
    let videos: [HanimeInfo]
}

struct HanimeHomePage: Hashable, Sendable {
    let banner: HanimeBanner?
    let sections: [HanimeHomeSection]
}

struct HanimeUserProfile: Hashable, Sendable {
    let id: String
    let username: String
    let avatarURL: URL?
}

enum HanimeMyListKind: String, Hashable, Sendable {
    case favorites = "likes"
    case watchLater = "saves"
}

struct HanimeInfo: Identifiable, Hashable, Sendable {
    enum Style: String, Codable, Sendable {
        case normal
        case compact
    }

    var id: String { videoCode }

    let title: String
    let coverURL: URL?
    let videoCode: String
    let duration: String?
    let views: String?
    let uploadTime: String?
    let artist: String?
    let style: Style

    static let placeholders: [HanimeInfo] = [
        HanimeInfo(
            title: "等待首页解析",
            coverURL: nil,
            videoCode: "placeholder-home",
            duration: nil,
            views: nil,
            uploadTime: nil,
            artist: nil,
            style: .normal
        )
    ]
}

extension Sequence where Element == HanimeInfo {
    func deduplicatedByVideoCode() -> [HanimeInfo] {
        var seen = Set<String>()
        return filter { seen.insert($0.videoCode).inserted }
    }
}

struct HanimeAccountVideoList: Hashable, Sendable {
    let videos: [HanimeInfo]
    let description: String?
    let csrfToken: String?
    let maxPage: Int
}

struct HanimePlaylistSummary: Identifiable, Hashable, Sendable {
    var id: String { listCode }

    let listCode: String
    let title: String
    let total: Int
    let coverURL: URL?
}

struct HanimePlaylistsPage: Hashable, Sendable {
    let playlists: [HanimePlaylistSummary]
    let csrfToken: String?
    let maxPage: Int
}

struct HanimeSubscriptionArtist: Identifiable, Hashable, Sendable {
    var id: String { artistID ?? name }

    let name: String
    let avatarURL: URL?
    let userID: String?
    let artistID: String?

    var canManageSubscription: Bool {
        userID?.isEmpty == false && artistID?.isEmpty == false
    }
}

struct HanimeSubscriptionsPage: Hashable, Sendable {
    let artists: [HanimeSubscriptionArtist]
    let videos: [HanimeInfo]
    let csrfToken: String?
    let maxPage: Int
}

struct HanimeArtist: Identifiable, Hashable, Sendable {
    struct Subscription: Hashable, Sendable {
        let userID: String
        let artistID: String
        var isSubscribed: Bool
    }

    var id: String { name }

    let name: String
    let avatarURL: URL?
    let genre: String
    var subscription: Subscription?

    var isSubscribed: Bool {
        subscription?.isSubscribed == true
    }
}

struct HanimeVideoListState: Hashable, Sendable {
    struct Playlist: Identifiable, Hashable, Sendable {
        var id: String { code }

        let code: String
        let title: String
        var isSelected: Bool
    }

    var isWatchLater: Bool
    var watchLaterCode: String?
    var playlists: [Playlist]
}

struct HanimeVideoSeries: Hashable, Sendable {
    let title: String?
    let videos: [HanimeSeriesVideo]

    var currentVideoCode: String? {
        videos.first(where: \.isCurrent)?.videoCode
    }
}

struct HanimeSeriesVideo: Identifiable, Hashable, Sendable {
    var id: String { videoCode }

    let videoCode: String
    let title: String
    let coverURL: URL?
    let duration: String?
    let views: String?
    let rating: String?
    let author: String?
    let category: String?
    let uploadTime: String?
    let isCurrent: Bool
}

struct ResolutionLink: Identifiable, Hashable, Sendable {
    var id: String { "\(quality)-\(url.absoluteString)" }

    let quality: String
    let url: URL
    let mimeType: String?
}

struct HanimeVideo: Identifiable, Hashable, Sendable {
    var id: String { videoCode }

    let videoCode: String
    let title: String
    let coverURL: URL?
    let chineseTitle: String?
    let introduction: String?
    let uploadTime: Date?
    let views: String?
    let tags: [String]
    let resolutions: [ResolutionLink]
    let relatedVideos: [HanimeInfo]
    let series: HanimeVideoSeries?
    let originalComicURL: URL?
    let favoriteCount: Int?
    let isFavorite: Bool
    let csrfToken: String?
    let currentUserID: String?
    let artist: HanimeArtist?
    let listState: HanimeVideoListState?
}

struct HanimeCommentPost: Hashable, Sendable {
    let foreignID: String?
    let isPositive: Bool
    let likeUserID: String?
    let commentLikesCount: Int?
    let commentLikesSum: Int?
    var likeCommentStatus: Bool
    var unlikeCommentStatus: Bool
}

struct HanimeComment: Identifiable, Hashable, Sendable {
    var id: String {
        commentID ?? post.foreignID ?? "\(username)-\(date)-\(content)"
    }

    let avatarURL: URL?
    let username: String
    let date: String
    let content: String
    var thumbUp: Int?
    let isChildComment: Bool
    let hasMoreReplies: Bool
    let replyCount: Int?
    let commentID: String?
    var post: HanimeCommentPost
    let reportableID: String?
    let reportableType: String?

    var isLiked: Bool { post.likeCommentStatus }
    var isDisliked: Bool { post.unlikeCommentStatus }

    func toggledLike() -> HanimeComment {
        toggledReaction(isPositive: true)
    }

    func toggledDislike() -> HanimeComment {
        toggledReaction(isPositive: false)
    }

    private func toggledReaction(isPositive: Bool) -> HanimeComment {
        var copy = self
        let count = copy.thumbUp ?? 0
        if isPositive {
            if copy.post.likeCommentStatus {
                copy.post.likeCommentStatus = false
                copy.thumbUp = count - 1
            } else {
                copy.post.likeCommentStatus = true
                copy.post.unlikeCommentStatus = false
                copy.thumbUp = count + 1
            }
        } else {
            if copy.post.unlikeCommentStatus {
                copy.post.unlikeCommentStatus = false
                copy.thumbUp = count + 1
            } else {
                copy.post.likeCommentStatus = false
                copy.post.unlikeCommentStatus = true
                copy.thumbUp = count - 1
            }
        }
        return copy
    }
}

struct HanimeCommentsPage: Hashable, Sendable {
    let comments: [HanimeComment]
    let currentUserID: String?
    let csrfToken: String?
}

enum LoadableState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}
