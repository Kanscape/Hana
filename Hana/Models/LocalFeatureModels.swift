import Foundation
import SwiftData

nonisolated struct HKeyframeEntry: Codable, Hashable, Identifiable {
    var positionMilliseconds: Int64
    var prompt: String?

    var id: String {
        "\(positionMilliseconds)-\(prompt ?? "")"
    }

    var seconds: TimeInterval {
        TimeInterval(positionMilliseconds) / 1_000
    }

    init(positionMilliseconds: Int64, prompt: String? = nil) {
        self.positionMilliseconds = positionMilliseconds
        self.prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

@Model
final class HKeyframeRecord {
    @Attribute(.unique) var videoCode: String
    var title: String
    var groupTitle: String?
    var episode: Int
    var author: String?
    var keyframesJSON: String
    var createdAt: Date
    var updatedAt: Date

    init(
        videoCode: String,
        title: String,
        groupTitle: String? = nil,
        episode: Int = 0,
        author: String? = nil,
        keyframes: [HKeyframeEntry] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.videoCode = videoCode
        self.title = title
        self.groupTitle = groupTitle?.nilIfEmpty
        self.episode = episode
        self.author = author?.nilIfEmpty
        self.keyframesJSON = HKeyframeRecord.encode(keyframes)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var keyframes: [HKeyframeEntry] {
        get { Self.decode(keyframesJSON) }
        set {
            keyframesJSON = Self.encode(newValue.sorted { $0.positionMilliseconds < $1.positionMilliseconds })
            updatedAt = .now
        }
    }

    func append(_ keyframe: HKeyframeEntry) {
        var items = keyframes
        items.removeAll { abs($0.positionMilliseconds - keyframe.positionMilliseconds) < 500 }
        items.append(keyframe)
        keyframes = items
    }

    func remove(_ keyframe: HKeyframeEntry) {
        keyframes = keyframes.filter { $0.id != keyframe.id }
    }

    func replace(_ oldKeyframe: HKeyframeEntry, with newKeyframe: HKeyframeEntry) {
        var items = keyframes.filter { $0.id != oldKeyframe.id }
        items.removeAll { abs($0.positionMilliseconds - newKeyframe.positionMilliseconds) < 500 }
        items.append(newKeyframe)
        keyframes = items
    }

    private static func decode(_ text: String) -> [HKeyframeEntry] {
        guard let data = text.data(using: .utf8),
              let entries = try? JSONDecoder().decode([HKeyframeEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.positionMilliseconds < $1.positionMilliseconds }
    }

    private static func encode(_ entries: [HKeyframeEntry]) -> String {
        let sorted = entries.sorted { $0.positionMilliseconds < $1.positionMilliseconds }
        guard let data = try? JSONEncoder().encode(sorted),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }
}

extension String {
    nonisolated var nilIfEmpty: String? {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
