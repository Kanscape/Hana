import AVFoundation
import SwiftData
import SwiftUI

struct VideoHKeyframeControls: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HanaSettingsKey.hKeyframesEnabled) private var hKeyframesEnabled = true
    @AppStorage(HanaSettingsKey.sharedHKeyframesEnabled) private var sharedEnabled = true
    @AppStorage(HanaSettingsKey.sharedHKeyframesPreferred) private var sharedPreferred = false
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var localRecords: [HKeyframeRecord]
    let video: HanimeVideo
    let player: AVPlayer?
    @State private var isKeyframeEditorPresented = false
    @State private var pendingPositionMilliseconds: Int64?

    private var resolvedRecord: HKeyframeResolvedRecord? {
        HKeyframeResolver.resolve(
            videoCode: video.videoCode,
            localRecords: localRecords,
            sharedEnabled: sharedEnabled,
            sharedPreferred: sharedPreferred
        )
    }

    private var localRecord: HKeyframeRecord? {
        localRecords.first { $0.videoCode == video.videoCode }
    }

    var body: some View {
        Group {
            if hKeyframesEnabled {
                Menu {
                    Button {
                        prepareCurrentTime()
                    } label: {
                        Label("记录当前", systemImage: "plus.circle")
                    }
                    .disabled(player == nil)

                    if let resolvedRecord, !resolvedRecord.keyframes.isEmpty {
                        Section(resolvedRecord.sourceTitle) {
                            ForEach(resolvedRecord.keyframes) { keyframe in
                                Button {
                                    seek(to: keyframe)
                                } label: {
                                    Text(menuTitle(for: keyframe))
                                }
                            }
                        }
                    } else {
                        Text("当前视频暂无 HKeyframes")
                    }
                } label: {
                    Image(systemName: resolvedRecord?.isShared == true ? "person.2" : "bookmark")
                }
                .accessibilityLabel("HKeyframes")
                .simultaneousGesture(
                    TapGesture().onEnded {
                        HanaInterfaceOrientationController.cancelVideoFullscreenPreparation()
                    }
                )
                .sheet(isPresented: $isKeyframeEditorPresented) {
                    HKeyframeEditSheet(
                        title: "记录 HKeyframe",
                        initialPositionMilliseconds: pendingPositionMilliseconds ?? 0,
                        onSave: savePendingKeyframe
                    )
                }
            }
        }
    }

    private func menuTitle(for keyframe: HKeyframeEntry) -> String {
        if let prompt = keyframe.prompt?.nilIfEmpty {
            return "\(formatTime(keyframe.seconds))  \(prompt)"
        }
        return formatTime(keyframe.seconds)
    }

    private func prepareCurrentTime() {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite, seconds > 0 else {
            return
        }
        pendingPositionMilliseconds = Int64((seconds * 1_000).rounded())
        isKeyframeEditorPresented = true
    }

    private func savePendingKeyframe(_ keyframe: HKeyframeEntry) {
        guard pendingPositionMilliseconds != nil else { return }
        let record = localRecord ?? HKeyframeRecord(
            videoCode: video.videoCode,
            title: video.title,
            keyframes: []
        )
        if record.modelContext == nil {
            modelContext.insert(record)
        }
        record.title = video.title
        record.append(keyframe)
        try? modelContext.save()
        self.pendingPositionMilliseconds = nil
    }

    private func seek(to keyframe: HKeyframeEntry) {
        player?.seek(
            to: CMTime(seconds: keyframe.seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        player?.play()
    }
}

struct VideoHKeyframeCountdownOverlay: View {
    @AppStorage(HanaSettingsKey.hKeyframesEnabled) private var hKeyframesEnabled = true
    @AppStorage(HanaSettingsKey.hKeyframeCountdownSeconds) private var countdownSeconds = 10
    @AppStorage(HanaSettingsKey.hKeyframeShowPrompt) private var showPrompt = true
    @AppStorage(HanaSettingsKey.sharedHKeyframesEnabled) private var sharedEnabled = true
    @AppStorage(HanaSettingsKey.sharedHKeyframesPreferred) private var sharedPreferred = false
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var localRecords: [HKeyframeRecord]
    let videoCode: String
    let player: AVPlayer?
    var isSuppressed = false
    var size: HanaToastContentSize = .regular

    var body: some View {
        if hKeyframesEnabled && !isSuppressed {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                if let next = nextKeyframe() {
                    HanaToastContentView(
                        toastText(for: next),
                        style: .info,
                        systemImage: "timer",
                        size: size
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func toastText(
        for next: (record: HKeyframeResolvedRecord, keyframe: HKeyframeEntry, remaining: TimeInterval)
    ) -> String {
        let countdown = "\(Int(ceil(next.remaining))) 秒后到达 HKeyframe"
        guard showPrompt else {
            return countdown
        }
        let detail = next.keyframe.prompt?.nilIfEmpty ?? next.record.sourceTitle
        return "\(countdown)\n\(detail)"
    }

    private func nextKeyframe() -> (record: HKeyframeResolvedRecord, keyframe: HKeyframeEntry, remaining: TimeInterval)? {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return nil }
        guard let record = HKeyframeResolver.resolve(
            videoCode: videoCode,
            localRecords: localRecords,
            sharedEnabled: sharedEnabled,
            sharedPreferred: sharedPreferred
        ) else {
            return nil
        }
        return record.keyframes
            .map { ($0, $0.seconds - seconds) }
            .first { $0.1 >= 0 && $0.1 <= TimeInterval(countdownSeconds) }
            .map { (record, $0.0, $0.1) }
    }
}
