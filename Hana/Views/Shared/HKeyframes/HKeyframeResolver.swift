struct HKeyframeResolvedRecord {
    let videoCode: String
    let title: String
    let sourceTitle: String
    let isShared: Bool
    let keyframes: [HKeyframeEntry]
}

enum HKeyframeResolver {
    static func resolve(
        videoCode: String,
        localRecords: [HKeyframeRecord],
        sharedEnabled: Bool,
        sharedPreferred: Bool
    ) -> HKeyframeResolvedRecord? {
        let local = localRecords.first { $0.videoCode == videoCode }
        let shared = sharedEnabled ? HanaHKeyframeLibrary.sharedRecord(videoCode: videoCode) : nil

        if sharedPreferred, let shared {
            return HKeyframeResolvedRecord(
                videoCode: shared.videoCode,
                title: shared.title,
                sourceTitle: "共享库 · \(shared.author ?? "未知作者")",
                isShared: true,
                keyframes: shared.entries
            )
        }

        if let local {
            return HKeyframeResolvedRecord(
                videoCode: local.videoCode,
                title: local.title,
                sourceTitle: "本地记录",
                isShared: false,
                keyframes: local.keyframes
            )
        }

        if let shared {
            return HKeyframeResolvedRecord(
                videoCode: shared.videoCode,
                title: shared.title,
                sourceTitle: "共享库 · \(shared.author ?? "未知作者")",
                isShared: true,
                keyframes: shared.entries
            )
        }

        return nil
    }
}
