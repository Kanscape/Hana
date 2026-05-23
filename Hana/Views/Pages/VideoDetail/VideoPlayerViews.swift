import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct VideoPlayerPanel: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HanaSettingsKey.allowResumePlayback) private var allowResumePlayback = true
    @AppStorage(HanaSettingsKey.pictureInPictureEnabled) private var pictureInPictureEnabled = true
    @AppStorage(HanaSettingsKey.loopPlaybackEnabled) private var loopPlaybackEnabled = false
    @AppStorage(HanaSettingsKey.playerLongPressRate) private var playerLongPressRate = HanaPlaybackSpeedCatalog.defaultLongPressRate
    let video: HanimeVideo
    @Binding var selectedLinkID: String
    @Binding var activePlayer: AVPlayer?
    @Binding var isFullscreenPresented: Bool
    @State private var player: AVPlayer?
    @State private var progressTask: Task<Void, Never>?
    @State private var orientationTask: Task<Void, Never>?
    @State private var teardownTask: Task<Void, Never>?
    @State private var playerReadinessTask: Task<Void, Never>?
    @State private var fullscreenOrientation: HanaVideoFullscreenOrientation = .landscape
    @State private var isFullscreenLifecycleActive = false
    @State private var isPlayerReady = false
    @State private var configuredLinkID = ""
    @State private var restoredProgress: TimeInterval = 0
    @State private var fullscreenLifecycleTask: Task<Void, Never>?
    @State private var isPlaybackActive = false
    @State private var playbackLoopController = HanaPlaybackLoopController()

    private var selectedLink: ResolutionLink? {
        video.resolutions.first { $0.id == selectedLinkID } ?? video.resolutions.first
    }

    private var shouldSuppressHKeyframeCountdown: Bool {
        !isPlaybackActive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if video.resolutions.isEmpty {
                ContentUnavailableView("未解析到播放地址", systemImage: "play.slash")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ZStack(alignment: .topLeading) {
                    HanaAVPlayerView(
                        player: player,
                        allowsPictureInPicture: pictureInPictureEnabled,
                        exitsFullScreenWhenPlaybackEnds: !loopPlaybackEnabled,
                        gestureConfiguration: HanaPlayerGestureConfiguration(
                            longPressRate: playerLongPressRate
                        ),
                        fullscreenStatusOverlay: AnyView(
                            VideoHKeyframeCountdownOverlay(
                                videoCode: video.videoCode,
                                player: player,
                                isSuppressed: shouldSuppressHKeyframeCountdown
                            )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .padding(.top, 10)
                                .padding(.horizontal, 20)
                                .allowsHitTesting(false)
                                .modelContext(modelContext)
                        ),
                        onFullscreenChange: handleFullscreenChange,
                        onPotentialFullscreenIntent: prepareFullscreenOrientation
                    )

                    if !isPlayerReady {
                        VideoPlayerCoverOverlay(coverURL: video.coverURL)
                            .transition(.opacity)
                            .zIndex(4)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(.black, in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.smooth(duration: 0.24), value: isPlayerReady)

                if restoredProgress > 1 || !isPlayerReady {
                    VStack(alignment: .leading, spacing: 4) {
                        if restoredProgress > 1 {
                            Label("从 \(formatTime(restoredProgress)) 继续", systemImage: "clock.arrow.circlepath")
                        }
                        if !isPlayerReady {
                            Label("首帧加载中", systemImage: "hourglass")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            if selectedLinkID.isEmpty {
                selectedLinkID = video.resolutions.first?.id ?? ""
            }
            teardownTask?.cancel()
            configurePlayerIfNeeded()
        }
        .onChange(of: selectedLinkID) {
            guard !selectedLinkID.isEmpty, configuredLinkID != selectedLinkID else { return }
            savePlaybackProgress()
            configurePlayer(force: true)
        }
        .onChange(of: loopPlaybackEnabled) {
            configurePlaybackLoop(player: player, item: player?.currentItem)
        }
        .onDisappear {
            scheduleTeardown()
        }
    }

    private func configurePlayerIfNeeded() {
        configurePlayer(force: false)
    }

    private func configurePlayer(force: Bool = false) {
        progressTask?.cancel()
        guard let selectedLink else {
            configuredLinkID = ""
            player = nil
            activePlayer = nil
            isPlayerReady = false
            isPlaybackActive = false
            playbackLoopController.invalidate()
            return
        }
        guard force || configuredLinkID != selectedLink.id || player?.currentItem == nil else {
            activePlayer = player
            configurePlaybackLoop(player: player, item: player?.currentItem)
            startProgressTracking()
            return
        }
        HanaPlaybackAudioSession.activateForVideoPlayback()
        configuredLinkID = selectedLink.id
        let resumeTime = savedProgress()
        let playback = services.videoPlaybackStore.entry(
            videoCode: video.videoCode,
            link: selectedLink,
            headers: services.httpClient.mediaHeaders(for: selectedLink.url),
            resumeTime: resumeTime
        )
        updateFullscreenOrientation(asset: playback.entry.asset, linkID: selectedLink.id)
        observePlayerReadiness(playback.entry.item, linkID: selectedLink.id)
        restoredProgress = playback.isReused ? 0 : resumeTime
        player = playback.entry.player
        activePlayer = playback.entry.player
        configurePlaybackLoop(player: playback.entry.player, item: playback.entry.item)
        updatePlaybackSnapshot()
        startProgressTracking()
    }

    private func configurePlaybackLoop(player: AVPlayer?, item: AVPlayerItem?) {
        playbackLoopController.configure(
            player: player,
            item: item,
            isLoopingEnabled: loopPlaybackEnabled,
            onPlaybackEnded: savePlaybackProgress
        )
    }

    private func scheduleTeardown() {
        savePlaybackProgress()
        teardownTask?.cancel()
        teardownTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !HanaAVPlayerFullscreenState.isActive,
                  !isFullscreenPresented,
                  !isFullscreenLifecycleActive else { return }
            progressTask?.cancel()
            orientationTask?.cancel()
            playerReadinessTask?.cancel()
            player?.pause()
            HanaPlaybackAudioSession.deactivateAfterPlayback()
        }
    }

    private func observePlayerReadiness(_ item: AVPlayerItem, linkID: String) {
        playerReadinessTask?.cancel()
        if item.status == .readyToPlay {
            isPlayerReady = true
            return
        }
        isPlayerReady = false
        playerReadinessTask = Task { @MainActor in
            while !Task.isCancelled {
                guard configuredLinkID == linkID else { return }
                switch item.status {
                case .readyToPlay:
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled, configuredLinkID == linkID else { return }
                    withAnimation(.smooth(duration: 0.24)) {
                        isPlayerReady = true
                    }
                    return
                case .failed:
                    return
                case .unknown:
                    try? await Task.sleep(for: .milliseconds(80))
                @unknown default:
                    return
                }
            }
        }
    }

    private func handleFullscreenChange(_ isFullscreen: Bool) {
        isFullscreenPresented = isFullscreen
        fullscreenLifecycleTask?.cancel()
        if isFullscreen {
            isFullscreenLifecycleActive = true
            teardownTask?.cancel()
            HanaInterfaceOrientationController.enterVideoFullscreen(fullscreenOrientation.interfaceMask)
        } else {
            HanaInterfaceOrientationController.exitVideoFullscreen()
            fullscreenLifecycleTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                isFullscreenLifecycleActive = false
            }
        }
    }

    private func prepareFullscreenOrientation() {
        HanaInterfaceOrientationController.prepareVideoFullscreen(fullscreenOrientation.interfaceMask)
    }

    private func updateFullscreenOrientation(asset: AVAsset, linkID: String) {
        orientationTask?.cancel()
        orientationTask = Task {
            let orientation = await HanaVideoFullscreenOrientation.resolved(for: asset)
            await MainActor.run {
                if selectedLinkID == linkID {
                    fullscreenOrientation = orientation
                }
            }
        }
    }

    private func startProgressTracking() {
        progressTask = Task { @MainActor in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick += 1
                updatePlaybackSnapshot()
                if tick.isMultiple(of: 5) {
                    savePlaybackProgress()
                }
            }
        }
    }

    private func updatePlaybackSnapshot() {
        let nextValue: Bool
        if let player {
            nextValue = player.timeControlStatus == .playing || player.rate > 0
        } else {
            nextValue = false
        }
        if isPlaybackActive != nextValue {
            isPlaybackActive = nextValue
        }
    }

    private func savePlaybackProgress() {
        guard let player,
              let duration = player.currentItem?.duration.seconds,
              duration.isFinite,
              duration > 0 else {
            return
        }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 0 else {
            return
        }
        let ratio = min(max(seconds / duration, 0), 1)
        let existingRecord = watchHistoryRecord()
        guard ratio >= WatchHistoryRecord.historyEntryRatio else {
            return
        }

        let record = existingRecord ?? WatchHistoryRecord(
            videoCode: video.videoCode,
            title: video.title,
            coverURLString: video.coverURL?.absoluteString,
            releaseDate: video.uploadTime,
            duration: duration
        )
        if record.modelContext == nil {
            modelContext.insert(record)
        }
        record.title = video.title
        record.coverURLString = video.coverURL?.absoluteString
        record.releaseDate = video.uploadTime
        record.watchDate = .now
        record.progress = seconds
        record.duration = duration
        if ratio >= WatchHistoryRecord.watchedRatio, record.watchedAt == nil {
            record.watchedAt = .now
        }
        try? modelContext.save()
    }

    private func savedProgress() -> TimeInterval {
        guard allowResumePlayback else { return 0 }
        return watchHistoryRecord()?.progress ?? 0
    }

    private func watchHistoryRecord() -> WatchHistoryRecord? {
        let code = video.videoCode
        var descriptor = FetchDescriptor<WatchHistoryRecord>(
            predicate: #Predicate<WatchHistoryRecord> { record in
                record.videoCode == code
            }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

}

struct VideoPlayerCoverOverlay: View {
    let coverURL: URL?

    var body: some View {
        CoverView(url: coverURL, fallbackSystemImage: "play.rectangle")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .allowsHitTesting(false)
    }
}
