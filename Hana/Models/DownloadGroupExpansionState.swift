import Foundation

nonisolated enum DownloadGroupExpansionState {
    static func collapsedGroupIDs(from rawValue: String) -> Set<String> {
        guard let data = rawValue.data(using: .utf8),
              let groupIDs = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(groupIDs)
    }

    static func rawValue(for collapsedGroupIDs: Set<String>) -> String {
        let groupIDs = collapsedGroupIDs.sorted()
        guard let data = try? JSONEncoder().encode(groupIDs),
              let rawValue = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return rawValue
    }

    static func pruning(_ rawValue: String, validGroupIDs: Set<String>) -> String {
        let collapsedGroupIDs = collapsedGroupIDs(from: rawValue)
            .intersection(validGroupIDs)
        return self.rawValue(for: collapsedGroupIDs)
    }
}
