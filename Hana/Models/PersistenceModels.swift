import Foundation
import SwiftData

@Model
final class WatchHistoryRecord {
    @Attribute(.unique) var videoCode: String
    var title: String
    var coverURLString: String?
    var releaseDate: Date?
    var watchDate: Date
    var progress: TimeInterval
    var duration: TimeInterval?
    var watchedAt: Date?

    init(
        videoCode: String,
        title: String,
        coverURLString: String? = nil,
        releaseDate: Date? = nil,
        watchDate: Date = .now,
        progress: TimeInterval = 0,
        duration: TimeInterval? = nil,
        watchedAt: Date? = nil
    ) {
        self.videoCode = videoCode
        self.title = title
        self.coverURLString = coverURLString
        self.releaseDate = releaseDate
        self.watchDate = watchDate
        self.progress = progress
        self.duration = duration
        self.watchedAt = watchedAt
    }
}

extension WatchHistoryRecord {
    static let historyEntryRatio = 0.10
    static let watchedRatio = 0.80

    var playbackRatio: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(max(progress / duration, 0), 1)
    }

    var isHistoryEligible: Bool {
        playbackRatio >= Self.historyEntryRatio
    }

    var isWatched: Bool {
        watchedAt != nil || playbackRatio >= Self.watchedRatio
    }
}

@Model
final class SearchHistoryRecord {
    @Attribute(.unique) var query: String
    var createdAt: Date

    init(query: String, createdAt: Date = .now) {
        self.query = query
        self.createdAt = createdAt
    }
}

@Model
final class AdvancedSearchHistoryRecord {
    @Attribute(.unique) var criteriaKey: String
    var summary: String
    var criteriaJSON: String
    var createdAt: Date

    init(criteria: HanimeSearchCriteria, createdAt: Date = .now) {
        let criteria = criteria.normalized()
        self.criteriaKey = criteria.historyKey
        self.summary = criteria.summary
        self.criteriaJSON = criteria.encodedJSONString() ?? "{}"
        self.createdAt = createdAt
    }

    var criteria: HanimeSearchCriteria {
        HanimeSearchCriteria.decoded(from: criteriaJSON) ?? .empty
    }
}

@Model
final class FavoriteVideoRecord {
    @Attribute(.unique) var videoCode: String
    var title: String
    var coverURLString: String?
    var createdAt: Date

    init(
        videoCode: String,
        title: String,
        coverURLString: String? = nil,
        createdAt: Date = .now
    ) {
        self.videoCode = videoCode
        self.title = title
        self.coverURLString = coverURLString
        self.createdAt = createdAt
    }
}

@Model
final class WatchLaterRecord {
    @Attribute(.unique) var videoCode: String
    var title: String
    var coverURLString: String?
    var createdAt: Date

    init(
        videoCode: String,
        title: String,
        coverURLString: String? = nil,
        createdAt: Date = .now
    ) {
        self.videoCode = videoCode
        self.title = title
        self.coverURLString = coverURLString
        self.createdAt = createdAt
    }
}

@Model
final class PlaylistRecord {
    @Attribute(.unique) var id: String
    var title: String
    var detail: String
    var coverURLString: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        detail: String = "",
        coverURLString: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.coverURLString = coverURLString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PlaylistItemRecord {
    @Attribute(.unique) var id: String
    var playlistID: String
    var videoCode: String
    var title: String
    var coverURLString: String?
    var createdAt: Date

    init(
        playlistID: String,
        videoCode: String,
        title: String,
        coverURLString: String? = nil,
        createdAt: Date = .now
    ) {
        self.playlistID = playlistID
        self.videoCode = videoCode
        self.title = title
        self.coverURLString = coverURLString
        self.createdAt = createdAt
        self.id = "\(playlistID)-\(videoCode)"
    }
}

@Model
final class DownloadQueueRecord {
    @Attribute(.unique) var id: String
    var videoCode: String
    var title: String
    var coverURLString: String?
    var quality: String
    var mediaURLString: String
    var downloadGroupName: String = "默认分组"
    var createdAt: Date
    var status: String
    var localFileURLString: String?
    var errorMessage: String?
    var completedAt: Date?
    var progress: Double
    var retryCount: Int
    var backgroundSessionIdentifier: String?
    var backgroundTaskIdentifier: Int?
    var backgroundTaskStartedAt: Date?
    var backgroundTaskUpdatedAt: Date?
    var downloadedByteCount: Int64?
    var expectedByteCount: Int64?
    var completionNotificationSentAt: Date?

    init(
        videoCode: String,
        title: String,
        coverURLString: String?,
        quality: String,
        mediaURLString: String,
        createdAt: Date = .now,
        status: String = "等待下载"
    ) {
        self.videoCode = videoCode
        self.title = title
        self.coverURLString = coverURLString
        self.quality = quality
        self.mediaURLString = mediaURLString
        self.downloadGroupName = "默认分组"
        self.createdAt = createdAt
        self.status = status
        self.localFileURLString = nil
        self.errorMessage = nil
        self.completedAt = nil
        self.progress = 0
        self.retryCount = 0
        self.backgroundSessionIdentifier = nil
        self.backgroundTaskIdentifier = nil
        self.backgroundTaskStartedAt = nil
        self.backgroundTaskUpdatedAt = nil
        self.downloadedByteCount = nil
        self.expectedByteCount = nil
        self.completionNotificationSentAt = nil
        self.id = "\(videoCode)-\(quality)-\(mediaURLString)"
    }
}

@Model
final class DownloadGroupRecord {
    @Attribute(.unique) var name: String
    var createdAt: Date

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}
