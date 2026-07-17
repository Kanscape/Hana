import Foundation

nonisolated struct HanaBackupArchive: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String
    var buildNumber: String
    var settings: HanaBackupSettings
    var watchHistory: [HanaBackupWatchHistory]
    var searchHistory: [HanaBackupSearchHistory]
    var advancedSearchHistory: [HanaBackupAdvancedSearchHistory]
    var favorites: [HanaBackupFavorite]
    var watchLater: [HanaBackupWatchLater]
    var playlists: [HanaBackupPlaylist]
    var playlistItems: [HanaBackupPlaylistItem]
    var downloadQueue: [HanaBackupDownload]
    var downloadGroups: [HanaBackupDownloadGroup]
    var hKeyframes: [HanaBackupHKeyframe]

    static func encode(_ archive: HanaBackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> HanaBackupArchive {
        do {
            let header = try JSONDecoder().decode(HanaBackupHeader.self, from: data)
            guard header.schemaVersion == currentSchemaVersion else {
                throw HanaBackupError.unsupportedSchemaVersion(header.schemaVersion)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(HanaBackupArchive.self, from: data)
        } catch let error as HanaBackupError {
            throw error
        } catch {
            throw HanaBackupError.invalidArchive(error.localizedDescription)
        }
    }
}

nonisolated private struct HanaBackupHeader: Decodable {
    let schemaVersion: Int
}

nonisolated struct HanaBackupSettings: Codable, Equatable, Sendable {
    var siteBaseURL: String
    var appearanceMode: String
    var themeColor: String
    var demoModeEnabled: Bool
    var defaultVideoQuality: String
    var allowResumePlayback: Bool
    var showPlayedIndicator: Bool
    var videoLanguage: String
    var pictureInPictureEnabled: Bool
    var loopPlaybackEnabled: Bool
    var playerLongPressRate: Double
    var hKeyframesEnabled: Bool
    var hKeyframeCountdownSeconds: Int
    var hKeyframeShowPrompt: Bool
    var sharedHKeyframesEnabled: Bool
    var sharedHKeyframesPreferred: Bool
    var defaultDownloadQuality: String
    var downloadConcurrency: Int
    var warnBeforeMobileDataDownload: Bool
    var autoCheckForUpdates: Bool
    var updateLinkDestination: String
    var disciplineModeConfiguration: DisciplineModeConfiguration?
}

nonisolated struct HanaBackupWatchHistory: Codable, Equatable, Sendable {
    var videoCode: String
    var title: String
    var coverURLString: String?
    var releaseDate: Date?
    var watchDate: Date
    var progress: TimeInterval
    var duration: TimeInterval?
    var watchedAt: Date?
}

nonisolated struct HanaBackupSearchHistory: Codable, Equatable, Sendable {
    var query: String
    var createdAt: Date
}

nonisolated struct HanaBackupAdvancedSearchHistory: Codable, Equatable, Sendable {
    var criteriaKey: String
    var summary: String
    var criteriaJSON: String
    var createdAt: Date
}

nonisolated struct HanaBackupFavorite: Codable, Equatable, Sendable {
    var videoCode: String
    var title: String
    var coverURLString: String?
    var createdAt: Date
}

nonisolated struct HanaBackupWatchLater: Codable, Equatable, Sendable {
    var videoCode: String
    var title: String
    var coverURLString: String?
    var createdAt: Date
}

nonisolated struct HanaBackupPlaylist: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var detail: String
    var coverURLString: String?
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct HanaBackupPlaylistItem: Codable, Equatable, Sendable {
    var playlistID: String
    var videoCode: String
    var title: String
    var coverURLString: String?
    var createdAt: Date

    var identity: String {
        "\(playlistID)-\(videoCode)"
    }
}

nonisolated struct HanaBackupDownload: Codable, Equatable, Sendable {
    var videoCode: String
    var title: String
    var coverURLString: String?
    var quality: String
    var downloadGroupName: String
    var createdAt: Date

    var identity: String {
        "\(videoCode)\u{1F}\(quality)"
    }
}

nonisolated struct HanaBackupDownloadGroup: Codable, Equatable, Sendable {
    var name: String
    var createdAt: Date
}

nonisolated struct HanaBackupHKeyframe: Codable, Equatable, Sendable {
    var videoCode: String
    var title: String
    var groupTitle: String?
    var episode: Int
    var author: String?
    var keyframes: [HKeyframeEntry]
    var createdAt: Date
    var updatedAt: Date
}

enum HanaBackupError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidArchive(String)
    case invalidField(String)
    case duplicateRecord(String)
    case invalidReference(String)
    case missingFileData
    case activeDownloads

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "不支持备份版本 \(version)，请更新 Hana 后重试。"
        case .invalidArchive(let detail):
            "备份文件无法解析：\(detail)"
        case .invalidField(let field):
            "备份中的 \(field) 无效。"
        case .duplicateRecord(let record):
            "备份中存在重复记录：\(record)。"
        case .invalidReference(let reference):
            "备份中的引用无效：\(reference)。"
        case .missingFileData:
            "备份文件没有可读取的数据。"
        case .activeDownloads:
            "有下载正在进行，请完成或取消后再恢复备份。"
        }
    }
}

extension HanaBackupArchive {
    @MainActor
    func validated() throws -> HanaBackupArchive {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw HanaBackupError.unsupportedSchemaVersion(schemaVersion)
        }

        var archive = self
        archive.settings = try settings.validated()

        guard !appVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HanaBackupError.invalidField("应用版本")
        }
        guard !buildNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HanaBackupError.invalidField("构建号")
        }

        try validateUnique(watchHistory, label: "观看历史", identity: \HanaBackupWatchHistory.videoCode)
        try validateUnique(searchHistory, label: "搜索历史", identity: \HanaBackupSearchHistory.query)
        try validateUnique(
            advancedSearchHistory, label: "高级搜索历史", identity: \HanaBackupAdvancedSearchHistory.criteriaKey
        )
        try validateUnique(favorites, label: "收藏", identity: \HanaBackupFavorite.videoCode)
        try validateUnique(watchLater, label: "稍后观看", identity: \HanaBackupWatchLater.videoCode)
        try validateUnique(playlists, label: "播放清单", identity: \HanaBackupPlaylist.id)
        try validateUnique(playlistItems, label: "播放清单项目", identity: \HanaBackupPlaylistItem.identity)
        try validateUnique(downloadQueue, label: "下载记录", identity: \HanaBackupDownload.identity)
        try validateUnique(downloadGroups, label: "下载分组", identity: \HanaBackupDownloadGroup.name)
        try validateUnique(hKeyframes, label: "HKeyframes", identity: \HanaBackupHKeyframe.videoCode)

        for record in watchHistory {
            try validateRequired(record.videoCode, field: "观看历史视频编号")
            try validateRequired(record.title, field: "观看历史标题")
            guard record.progress.isFinite, record.progress >= 0 else {
                throw HanaBackupError.invalidField("观看进度")
            }
            if let duration = record.duration, !duration.isFinite || duration < 0 {
                throw HanaBackupError.invalidField("视频时长")
            }
        }

        for record in searchHistory {
            try validateRequired(record.query, field: "搜索词")
        }

        for record in advancedSearchHistory {
            try validateRequired(record.criteriaKey, field: "高级搜索身份")
            guard let criteria = HanimeSearchCriteria.decoded(from: record.criteriaJSON),
                criteria.historyKey == record.criteriaKey
            else {
                throw HanaBackupError.invalidField("高级搜索条件")
            }
        }

        for record in favorites {
            try validateRequired(record.videoCode, field: "收藏视频编号")
            try validateRequired(record.title, field: "收藏标题")
        }
        for record in watchLater {
            try validateRequired(record.videoCode, field: "稍后观看视频编号")
            try validateRequired(record.title, field: "稍后观看标题")
        }
        for record in playlists {
            try validateRequired(record.id, field: "播放清单身份")
            try validateRequired(record.title, field: "播放清单标题")
        }

        let playlistIDs = Set(playlists.map(\.id))
        for item in playlistItems {
            try validateRequired(item.playlistID, field: "播放清单引用")
            try validateRequired(item.videoCode, field: "播放清单视频编号")
            try validateRequired(item.title, field: "播放清单项目标题")
            guard playlistIDs.contains(item.playlistID) else {
                throw HanaBackupError.invalidReference("播放清单 \(item.playlistID)")
            }
        }

        for record in downloadQueue {
            try validateRequired(record.videoCode, field: "下载视频编号")
            try validateRequired(record.title, field: "下载标题")
            try validateRequired(record.quality, field: "下载清晰度")
        }
        for group in downloadGroups {
            try validateRequired(group.name, field: "下载分组名称")
        }

        for record in hKeyframes {
            try validateRequired(record.videoCode, field: "HKeyframe 视频编号")
            try validateRequired(record.title, field: "HKeyframe 标题")
            guard record.episode >= 0 else {
                throw HanaBackupError.invalidField("HKeyframe 集数")
            }
            var keyframeIDs = Set<String>()
            for keyframe in record.keyframes {
                guard keyframe.positionMilliseconds >= 0 else {
                    throw HanaBackupError.invalidField("HKeyframe 时间")
                }
                guard keyframeIDs.insert(keyframe.id).inserted else {
                    throw HanaBackupError.duplicateRecord("\(record.videoCode) 的 HKeyframe")
                }
            }
        }

        return archive
    }

    @MainActor
    private func validateUnique<Item>(
        _ items: [Item],
        label: String,
        identity: KeyPath<Item, String>
    ) throws {
        var identities = Set<String>()
        for item in items {
            let value = item[keyPath: identity]
            guard identities.insert(value).inserted else {
                throw HanaBackupError.duplicateRecord("\(label) \(value)")
            }
        }
    }

    @MainActor
    private func validateRequired(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HanaBackupError.invalidField(field)
        }
    }
}

extension HanaBackupSettings {
    @MainActor
    fileprivate func validated() throws -> HanaBackupSettings {
        var settings = self

        guard let normalizedURL = HanaSiteBaseURL.normalized(siteBaseURL) else {
            throw HanaBackupError.invalidField("站点地址")
        }
        settings.siteBaseURL = normalizedURL

        guard HanaAppearanceMode(rawValue: appearanceMode) != nil else {
            throw HanaBackupError.invalidField("外观模式")
        }
        guard HanaThemeColor(rawValue: themeColor) != nil else {
            throw HanaBackupError.invalidField("主题色")
        }
        guard HanaVideoQualityPreference(rawValue: defaultVideoQuality) != nil else {
            throw HanaBackupError.invalidField("默认播放清晰度")
        }
        settings.videoLanguage = HanaVideoLanguagePreference.normalizedRawValue(videoLanguage)
        guard HanaVideoLanguagePreference(rawValue: settings.videoLanguage) != nil else {
            throw HanaBackupError.invalidField("字幕语言")
        }
        guard playerLongPressRate.isFinite, playerLongPressRate > 1, playerLongPressRate <= 4 else {
            throw HanaBackupError.invalidField("长按倍速")
        }
        settings.playerLongPressRate = HanaPlaybackSpeedCatalog.normalizedLongPressRate(
            playerLongPressRate)
        guard (5...30).contains(hKeyframeCountdownSeconds), hKeyframeCountdownSeconds.isMultiple(of: 5)
        else {
            throw HanaBackupError.invalidField("HKeyframe 倒计时")
        }
        guard HanaVideoQualityPreference(rawValue: defaultDownloadQuality) != nil else {
            throw HanaBackupError.invalidField("默认下载清晰度")
        }
        guard (1...5).contains(downloadConcurrency) else {
            throw HanaBackupError.invalidField("下载并发数")
        }
        guard HanaUpdateLinkDestination(rawValue: updateLinkDestination) != nil else {
            throw HanaBackupError.invalidField("更新链接目标")
        }
        if let configuration = disciplineModeConfiguration {
            try configuration.validateForBackup()
        }
        return settings
    }
}

extension DisciplineModeConfiguration {
    fileprivate func validateForBackup() throws {
        switch mode {
        case .single:
            break
        case .recurring(let configuration):
            guard configuration.isValid else {
                throw HanaBackupError.invalidField("Discipline Mode 循环配置")
            }
        case .weekly(let configuration):
            guard configuration.isValid else {
                throw HanaBackupError.invalidField("Discipline Mode 每周配置")
            }
        }
    }
}
