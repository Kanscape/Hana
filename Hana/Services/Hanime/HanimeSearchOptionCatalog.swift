import Foundation

struct HanimeSearchOptionSection: Identifiable, Hashable, Sendable {
    var id: String { title }

    let title: String
    let options: [HanimeSearchOption]
}

enum HanimeSearchOptionCatalog {
    static let genres: [HanimeSearchOption] = nonEmpty(loadOptions(named: "genre"), fallback: fallbackGenres)
    static let sortOptions: [HanimeSearchOption] = nonEmpty(loadOptions(named: "sort_option"), fallback: fallbackSortOptions)
    static let dateOptions: [HanimeSearchOption] = nonEmpty(loadOptions(named: "release_date"), fallback: fallbackDateOptions)
    static let durationOptions: [HanimeSearchOption] = nonEmpty(loadOptions(named: "duration"), fallback: fallbackDurationOptions)
    static let tagSections: [HanimeSearchOptionSection] = loadTagSections()
    static let brandSections: [HanimeSearchOptionSection] = [
        HanimeSearchOptionSection(title: "厂商", options: loadOptions(named: "brands"))
    ]

    static func searchCriteria(forDetailTag label: String) -> HanimeSearchCriteria {
        let tag = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return .empty }

        if let searchKey = tagSearchKey(matching: tag) {
            return HanimeSearchCriteria(query: tag, tags: [searchKey])
        }
        return HanimeSearchCriteria(query: tag)
    }

    static func tagSearchKey(matching label: String?) -> String? {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty,
              label != "全部" else {
            return nil
        }

        return loadTagResources().first { resource in
            resource.matches(label)
        }?.searchKey
    }

    static func tagSearchKey(_ searchKey: String, matches label: String) -> Bool {
        let normalizedSearchKey = normalizedLookupText(searchKey)
        let normalizedLabel = normalizedLookupText(label)
        guard !normalizedSearchKey.isEmpty, !normalizedLabel.isEmpty else { return false }
        if normalizedSearchKey == normalizedLabel {
            return true
        }
        if let matchedSearchKey = tagSearchKey(matching: label) {
            return normalizedLookupText(matchedSearchKey) == normalizedSearchKey
        }
        return false
    }

    private static func nonEmpty(_ options: [HanimeSearchOption], fallback: [HanimeSearchOption]) -> [HanimeSearchOption] {
        options.isEmpty ? fallback : options
    }

    private static func loadTagSections() -> [HanimeSearchOptionSection] {
        guard let data = data(named: "tags") else { return [] }
        do {
            let resource = try JSONDecoder().decode([String: [SearchOptionResource]].self, from: data)
            return tagSectionOrder.compactMap { key, title in
                guard let options = resource[key] else { return nil }
                return HanimeSearchOptionSection(title: title, options: options.compactMap(\.option))
            }
        } catch {
            return []
        }
    }

    private static func loadTagResources() -> [SearchOptionResource] {
        guard let data = data(named: "tags") else { return [] }
        do {
            let resource = try JSONDecoder().decode([String: [SearchOptionResource]].self, from: data)
            return resource.values.flatMap { $0 }
        } catch {
            return []
        }
    }

    private static func loadOptions(named name: String) -> [HanimeSearchOption] {
        loadResources(named: name).compactMap(\.option)
    }

    static func genreSearchKey(matching label: String?) -> String? {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty,
              label != "全部" else {
            return nil
        }

        let resources = loadResources(named: "genre") + loadResources(named: "genre_av")
        if let match = resources.first(where: { $0.matches(label) }) {
            return match.searchKey ?? match.name
        }

        return (fallbackGenres + avFallbackGenres).first { option in
            option.title == label || option.value == label
        }?.value
    }

    private static func data(named name: String) -> Data? {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Resources/SearchOptions"),
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "SearchOptions"),
            Bundle.main.url(forResource: name, withExtension: "json")
        ]
        guard let url = candidates.compactMap({ $0 }).first else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func loadResources(named name: String) -> [SearchOptionResource] {
        guard let data = data(named: name) else { return [] }
        do {
            return try JSONDecoder().decode([SearchOptionResource].self, from: data)
        } catch {
            return []
        }
    }

    private static let tagSectionOrder: [(key: String, title: String)] = [
        ("video_attributes", "视频属性"),
        ("character_relationships", "角色关系"),
        ("characteristics", "角色特征"),
        ("appearance_and_figure", "外观身形"),
        ("story_plot", "故事剧情"),
        ("story_location", "故事场景"),
        ("sex_positions", "姿势")
    ]

    private static let fallbackGenres: [HanimeSearchOption] = [
        HanimeSearchOption(title: "里番", value: "裏番"),
        HanimeSearchOption(title: "泡面番", value: "泡麵番"),
        HanimeSearchOption(title: "Motion Anime", value: "Motion Anime"),
        HanimeSearchOption(title: "3D 动画", value: "3DCG"),
        HanimeSearchOption(title: "2.5D", value: "2.5D"),
        HanimeSearchOption(title: "2D 动画", value: "2D動畫"),
        HanimeSearchOption(title: "AI 生成", value: "AI生成"),
        HanimeSearchOption(title: "MMD", value: "MMD"),
        HanimeSearchOption(title: "Cosplay", value: "Cosplay")
    ]

    private static let avFallbackGenres: [HanimeSearchOption] = [
        HanimeSearchOption(title: "日本AV", value: "日本AV"),
        HanimeSearchOption(title: "素人业余", value: "素人業餘"),
        HanimeSearchOption(title: "高清无码", value: "高清無碼"),
        HanimeSearchOption(title: "AI解码", value: "AI解碼"),
        HanimeSearchOption(title: "国产AV", value: "國產AV"),
        HanimeSearchOption(title: "国产素人", value: "國產素人")
    ]

    private static let fallbackSortOptions: [HanimeSearchOption] = [
        HanimeSearchOption(title: "最新上市", value: "最新上市"),
        HanimeSearchOption(title: "最新上传", value: "最新上傳"),
        HanimeSearchOption(title: "本日排行", value: "本日排行"),
        HanimeSearchOption(title: "本周排行", value: "本週排行"),
        HanimeSearchOption(title: "本月排行", value: "本月排行"),
        HanimeSearchOption(title: "观看次数", value: "觀看次數"),
        HanimeSearchOption(title: "点赞比例", value: "讚好比例"),
        HanimeSearchOption(title: "他们在看", value: "他們在看"),
        HanimeSearchOption(title: "时长最长", value: "時長最長")
    ]

    private static let fallbackDateOptions: [HanimeSearchOption] = [
        HanimeSearchOption(title: "过去 24 小时", value: "過去 24 小時"),
        HanimeSearchOption(title: "过去 2 天", value: "過去 2 天"),
        HanimeSearchOption(title: "过去 1 周", value: "過去 1 週"),
        HanimeSearchOption(title: "过去 1 个月", value: "過去 1 個月"),
        HanimeSearchOption(title: "过去 3 个月", value: "過去 3 個月"),
        HanimeSearchOption(title: "过去 1 年", value: "過去 1 年")
    ]

    private static let fallbackDurationOptions: [HanimeSearchOption] = [
        HanimeSearchOption(title: "1 分钟以上", value: "1 分鐘 +"),
        HanimeSearchOption(title: "5 分钟以上", value: "5 分鐘 +"),
        HanimeSearchOption(title: "10 分钟以上", value: "10 分鐘 +"),
        HanimeSearchOption(title: "20 分钟以上", value: "20 分鐘 +"),
        HanimeSearchOption(title: "30 分钟以上", value: "30 分鐘 +"),
        HanimeSearchOption(title: "60 分钟以上", value: "60 分鐘 +"),
        HanimeSearchOption(title: "0 到 10 分钟", value: "0 - 10 分鐘"),
        HanimeSearchOption(title: "0 到 20 分钟", value: "0 - 20 分鐘")
    ]

    fileprivate static func normalizedLookupText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}

private struct SearchOptionResource: Decodable {
    let lang: Language?
    let name: String?
    let searchKey: String?

    enum CodingKeys: String, CodingKey {
        case lang
        case name
        case searchKey = "search_key"
    }

    var option: HanimeSearchOption? {
        let title = lang?.simplifiedChinese
            ?? lang?.traditionalChinese
            ?? lang?.english
            ?? name
            ?? searchKey
        guard let title, !title.isEmpty else { return nil }
        return HanimeSearchOption(title: title, value: searchKey ?? name ?? title)
    }

    func matches(_ value: String) -> Bool {
        let normalizedValue = HanimeSearchOptionCatalog.normalizedLookupText(value)
        return [
            lang?.simplifiedChinese,
            lang?.traditionalChinese,
            lang?.english,
            name,
            searchKey
        ].contains { candidate in
            guard let candidate else { return false }
            return HanimeSearchOptionCatalog.normalizedLookupText(candidate) == normalizedValue
        }
    }

    struct Language: Decodable {
        let simplifiedChinese: String?
        let traditionalChinese: String?
        let english: String?

        enum CodingKeys: String, CodingKey {
            case simplifiedChinese = "zh-rCN"
            case traditionalChinese = "zh-rTW"
            case english = "en"
        }
    }
}
