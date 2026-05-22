import Foundation

nonisolated struct HanaSharedHKeyframeRecord: Codable, Hashable, Identifiable {
    nonisolated struct SharedKeyframe: Codable, Hashable {
        let position: Int64
        let prompt: String?

        var entry: HKeyframeEntry {
            HKeyframeEntry(positionMilliseconds: position, prompt: prompt)
        }
    }

    let videoCode: String
    let group: String?
    let title: String
    let episode: Int?
    let author: String?
    let keyframes: [SharedKeyframe]

    var id: String { videoCode }

    var entries: [HKeyframeEntry] {
        keyframes.map(\.entry).sorted { $0.positionMilliseconds < $1.positionMilliseconds }
    }

    var record: HKeyframeRecord {
        HKeyframeRecord(
            videoCode: videoCode,
            title: title,
            groupTitle: group,
            episode: episode ?? 0,
            author: author,
            keyframes: entries
        )
    }
}

enum HanaHKeyframeLibrary {
    private static let cachedSharedRecords: [HanaSharedHKeyframeRecord] = {
        sharedResourceURLs()
            .compactMap(decodeSharedRecord)
            .sorted {
                let lhsGroup = $0.group ?? ""
                let rhsGroup = $1.group ?? ""
                if lhsGroup != rhsGroup {
                    return lhsGroup.localizedStandardCompare(rhsGroup) == .orderedAscending
                }
                if ($0.episode ?? 0) != ($1.episode ?? 0) {
                    return ($0.episode ?? 0) < ($1.episode ?? 0)
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }()

    static func allSharedRecords() -> [HanaSharedHKeyframeRecord] {
        cachedSharedRecords
    }

    static func sharedRecord(videoCode: String) -> HanaSharedHKeyframeRecord? {
        allSharedRecords().first { $0.videoCode == videoCode }
    }

    static func decodeShareText(_ text: String) throws -> HKeyframeRecord {
        guard let base64 = sharePayload(in: text),
              let data = Data(base64Encoded: base64) else {
            throw HanaHKeyframeImportError.invalidShareText
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(HanaSharedHKeyframeRecord.self, from: data).record
        } catch {
            return try decoder.decode(HKeyframeSharePayload.self, from: data).record
        }
    }

    static func shareText(for record: HKeyframeRecord) throws -> String {
        let payload = HKeyframeSharePayload(record: record)
        let data = try JSONEncoder().encode(payload)
        return ">>>\(data.base64EncodedString())<<<"
    }

    nonisolated private static func decodeSharedRecord(url: URL) -> HanaSharedHKeyframeRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HanaSharedHKeyframeRecord.self, from: data)
    }

    nonisolated private static func sharedResourceURLs() -> [URL] {
        let subdirectories = [
            "HKeyframes",
            "Resources/HKeyframes",
            "h_keyframes",
            "Resources/h_keyframes"
        ]
        var urls = [URL]()
        for subdirectory in subdirectories {
            urls.append(contentsOf: Bundle.main.urls(
                forResourcesWithExtension: "json",
                subdirectory: subdirectory
            ) ?? [])
        }
        urls.append(contentsOf: Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted && $0.lastPathComponent != "Contents.json" }
    }

    private static func sharePayload(in text: String) -> String? {
        guard let start = text.range(of: ">>>"),
              let end = text.range(of: "<<<", range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum HanaHKeyframeImportError: LocalizedError {
    case invalidShareText

    var errorDescription: String? {
        switch self {
        case .invalidShareText:
            "剪贴板里没有可导入的 HKeyframes"
        }
    }
}

private struct HKeyframeSharePayload: Codable {
    let videoCode: String
    let title: String
    let group: String?
    let episode: Int
    let author: String?
    let keyframes: [HanaSharedHKeyframeRecord.SharedKeyframe]

    init(record: HKeyframeRecord) {
        self.videoCode = record.videoCode
        self.title = record.title
        self.group = record.groupTitle
        self.episode = record.episode
        self.author = record.author
        self.keyframes = record.keyframes.map {
            HanaSharedHKeyframeRecord.SharedKeyframe(
                position: $0.positionMilliseconds,
                prompt: $0.prompt
            )
        }
    }

    var record: HKeyframeRecord {
        HKeyframeRecord(
            videoCode: videoCode,
            title: title,
            groupTitle: group,
            episode: episode,
            author: author,
            keyframes: keyframes.map(\.entry)
        )
    }
}
