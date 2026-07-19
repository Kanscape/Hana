import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct VideoDetailScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(HanaSettingsKey.defaultVideoQuality) private var defaultVideoQuality = HanaVideoQualityPreference.defaultValue.rawValue
    @AppStorage(HanaSettingsKey.startDownloadsImmediately) private var startDownloadsImmediately = true
    @AppStorage(HanaSettingsKey.warnBeforeMobileDataDownload) private var warnBeforeMobileDataDownload = true
    let videoCode: String
    var isNavigationTop = true
    @State private var state: LoadableState<HanimeVideo> = .idle
    @State private var loadingVideoCode: String?
    @State private var selectedTopTab: HanaVideoDetailTopTab = .details
    @State private var selectedPlaybackLinkID = ""
    @State private var activePlayer: AVPlayer?
    @State private var isPlayerFullscreenPresented = false
    @State private var addedDownloadLinkID: String?
    @State private var pendingAutomaticDownload: DownloadQueueRecord?

    private var displayVideo: HanimeVideo? {
        switch state {
        case .loaded(let video):
            video
        case .idle, .loading, .failed:
            services.repository.cachedVideo(code: videoCode)
        }
    }

    var body: some View {
        Group {
            if let video = displayVideo {
                loadedView(video)
            } else if case .failed(let message) = state {
                ContentUnavailableView {
                    Label(message, systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("重试") {
                        Task { await loadVideo(forceRefresh: true) }
                    }
                }
            } else {
                ProgressView("加载视频")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("详情")
        .hanaInlineNavigationTitleDisplayMode()
        .toolbar {
            videoQualityToolbar
        }
        .task(id: videoCode) {
            await loadVideoIfNeeded()
        }
        .onChange(of: videoCode) {
            loadingVideoCode = nil
            selectedTopTab = .details
            selectedPlaybackLinkID = ""
            activePlayer = nil
            isPlayerFullscreenPresented = false
            addedDownloadLinkID = nil
            pendingAutomaticDownload = nil
            Task { await loadVideoIfNeeded() }
        }
        .onChange(of: services.siteSession.lastCookieSyncAt) {
            Task { await reloadAfterCookieSyncIfNeeded() }
        }
        .alert("当前网络可能按流量计费", isPresented: automaticDownloadMobileDataAlertBinding) {
            Button("继续下载") {
                continueAutomaticDownload()
            }
            Button("稍后下载", role: .cancel) {
                pendingAutomaticDownload = nil
            }
        } message: {
            Text("设置里开启了蜂窝网络下载前提醒。")
        }
    }

    private func loadedView(_ video: HanimeVideo) -> some View {
        GeometryReader { proxy in
            let layout = HanaVideoDetailAdaptiveLayout(
                containerWidth: proxy.size.width,
                containerHeight: proxy.size.height,
                horizontalSizeClass: horizontalSizeClass
            )
            let columnHeight = max(proxy.size.height - layout.verticalPadding * 2, 0)

            if layout.usesSideBySideLayout {
                HStack(alignment: .top, spacing: layout.columnSpacing) {
                    ScrollView(.vertical, showsIndicators: false) {
                        primaryColumn(video)
                            .padding(.bottom, layout.bottomContentPadding)
                            .frame(width: layout.playerColumnWidth, alignment: .topLeading)
                    }
                    .refreshable {
                        await loadVideo(forceRefresh: true)
                    }
                    .frame(width: layout.playerColumnWidth, height: columnHeight, alignment: .topLeading)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            topSwitchBar(mode: .secondary)
                            secondaryColumn(video)
                        }
                        .padding(.bottom, layout.bottomContentPadding)
                        .frame(width: layout.sideColumnWidth, alignment: .topLeading)
                    }
                    .refreshable {
                        await loadVideo(forceRefresh: true)
                    }
                    .frame(width: layout.sideColumnWidth, height: columnHeight, alignment: .topLeading)
                }
                .frame(width: layout.contentWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.verticalPadding)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        primaryColumn(video)
                        topSwitchBar(mode: .detail)
                        secondaryColumn(video)
                    }
                    .frame(width: layout.contentWidth, alignment: .topLeading)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.vertical, layout.verticalPadding)
                }
                .refreshable {
                    await loadVideo(forceRefresh: true)
                }
            }
        }
        .overlay(alignment: .bottom) {
            VideoHKeyframeCountdownOverlay(
                videoCode: video.videoCode,
                player: activePlayer,
                isSuppressed: isPlayerFullscreenPresented,
                size: .compact
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(10)
        }
    }

    private func primaryColumn(_ video: HanimeVideo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VideoPlayerPanel(
                video: video,
                selectedLinkID: $selectedPlaybackLinkID,
                activePlayer: $activePlayer,
                isFullscreenPresented: $isPlayerFullscreenPresented,
                isActive: isNavigationTop
            )
            VideoArtistSection(video: video)
            VideoDetailHeader(video: video)
            VideoIntroductionPreview(introduction: video.introduction)
            VideoLibraryActionsView(video: video)
            VideoTagStrip(tags: video.tags)
            detailSections(video)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func detailSections(_ video: HanimeVideo) -> some View {
        if let series = video.series {
            VideoSeriesSection(series: series)
        }

        if let originalComicURL = video.originalComicURL {
            DetailSection(title: "原作漫画") {
                Link(destination: originalComicURL) {
                    Label("打开原作漫画", systemImage: "book")
                }
                .buttonStyle(.bordered)
            }
        }

    }

    @ToolbarContentBuilder
    private var videoQualityToolbar: some ToolbarContent {
        if let video = displayVideo, !video.resolutions.isEmpty {
            ToolbarItemGroup(placement: .primaryAction) {
                VideoHKeyframeControls(video: video, player: activePlayer)

                Menu {
                    Section("播放清晰度") {
                        ForEach(video.resolutions) { link in
                            Button {
                                selectedPlaybackLinkID = link.id
                            } label: {
                                Label(
                                    link.quality,
                                    systemImage: selectedPlaybackLinkID == link.id ? "checkmark.circle.fill" : "circle"
                                )
                            }
                        }
                    }
                } label: {
                    Image(systemName: "play.rectangle")
                }
                .accessibilityLabel("播放清晰度：\(playbackQualityTitle(for: video))")

                Menu {
                    Section("下载清晰度") {
                        ForEach(video.resolutions) { link in
                            Button {
                                enqueueDownload(video: video, link: link)
                                addedDownloadLinkID = link.id
                            } label: {
                                Label(
                                    link.quality,
                                    systemImage: addedDownloadLinkID == link.id ? "checkmark.circle.fill" : "arrow.down.circle"
                                )
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .accessibilityLabel("下载清晰度")
            }
        }
    }

    private func reloadAfterCookieSyncIfNeeded() async {
        switch state {
        case .failed:
            await loadVideo(forceRefresh: true)
        case .idle, .loading:
            await loadVideoIfNeeded()
        case .loaded:
            return
        }
    }

    @ViewBuilder
    private func secondaryColumn(_ video: HanimeVideo) -> some View {
        switch selectedTopTab {
        case .details:
            RelatedVideosSection(videos: video.relatedVideos)
        case .comments:
            HanimeCommentsSection(videoCode: video.videoCode, title: video.title)
        }
    }

    private func topSwitchBar(mode: HanaVideoDetailTopSwitchMode) -> some View {
        HStack(spacing: 8) {
            Picker("内容", selection: $selectedTopTab) {
                ForEach(HanaVideoDetailTopTab.allCases) { tab in
                    Text(tab.title(for: mode)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)
        }
    }

    private func loadVideoIfNeeded() async {
        guard loadingVideoCode != videoCode else { return }
        switch state {
        case .idle, .loading:
            if restoreCachedVideoIfAvailable() { return }
            await loadVideo(forceRefresh: false)
        case .loaded(let video) where video.videoCode != videoCode:
            if restoreCachedVideoIfAvailable() { return }
            await loadVideo(forceRefresh: false)
        case .loaded, .failed:
            return
        }
    }

    private func restoreCachedVideoIfAvailable() -> Bool {
        guard let cached = services.repository.cachedVideo(code: videoCode) else {
            return false
        }
        syncPlaybackSelection(for: cached)
        state = .loaded(cached)
        loadingVideoCode = nil
        return true
    }

    private func loadVideo(forceRefresh: Bool = true, retriesAfterCancellation: Int = 1) async {
        let requestedCode = videoCode
        guard loadingVideoCode != requestedCode else { return }
        loadingVideoCode = requestedCode
        let previousState = state
        state = .loading
        do {
            let video = try await services.repository.video(
                code: requestedCode,
                cachePolicy: forceRefresh ? .reloadIgnoringCache : .returnCacheDataElseLoad
            )
            guard loadingVideoCode == requestedCode else { return }
            syncPlaybackSelection(for: video)
            state = .loaded(video)
            loadingVideoCode = nil
        } catch {
            guard loadingVideoCode == requestedCode else { return }
            if isCancellation(error) {
                state = stateAfterCancelledLoad(previousState)
                loadingVideoCode = nil
                if !Task.isCancelled, retriesAfterCancellation > 0 {
                    await loadVideo(
                        forceRefresh: forceRefresh,
                        retriesAfterCancellation: retriesAfterCancellation - 1
                    )
                }
                return
            }

            if services.siteSession.handle(error) {
                state = .failed("需要 Cloudflare 验证")
            } else {
                state = .failed(error.localizedDescription)
            }
            loadingVideoCode = nil
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func stateAfterCancelledLoad(_ previousState: LoadableState<HanimeVideo>) -> LoadableState<HanimeVideo> {
        switch previousState {
        case .loaded:
            previousState
        case .idle, .loading, .failed:
            .idle
        }
    }

    private func syncPlaybackSelection(for video: HanimeVideo) {
        guard !video.resolutions.isEmpty else {
            selectedPlaybackLinkID = ""
            return
        }
        if video.resolutions.contains(where: { $0.id == selectedPlaybackLinkID }) {
            return
        }
        selectedPlaybackLinkID = preferredPlaybackLink(in: video)?.id ?? video.resolutions.first?.id ?? ""
    }

    private func preferredPlaybackLink(in video: HanimeVideo) -> ResolutionLink? {
        preferredLink(in: video, preferenceRawValue: defaultVideoQuality)
    }

    private func preferredLink(in video: HanimeVideo, preferenceRawValue: String) -> ResolutionLink? {
        let normalizedPreference = HanaVideoQualityPreference.normalizedRawValue(preferenceRawValue)
        guard let preference = HanaVideoQualityPreference(rawValue: normalizedPreference),
              let match = video.resolutions.first(where: { $0.quality.localizedCaseInsensitiveContains(preference.qualityText) }) else {
            return video.resolutions.first
        }
        return match
    }

    private func playbackQualityTitle(for video: HanimeVideo) -> String {
        video.resolutions.first { $0.id == selectedPlaybackLinkID }?.quality ?? "播放"
    }

    private func enqueueDownload(video: HanimeVideo, link: ResolutionLink) {
        let record = DownloadQueueRecord(
            videoCode: video.videoCode,
            title: video.title,
            coverURLString: video.coverURL?.absoluteString,
            quality: link.quality,
            mediaURLString: link.url.absoluteString
        )
        let videoCode = video.videoCode
        let quality = link.quality
        try? modelContext.delete(
            model: DownloadQueueRecord.self,
            where: #Predicate<DownloadQueueRecord> { item in
                item.videoCode == videoCode && item.quality == quality
            }
        )
        modelContext.insert(record)
        try? modelContext.save()

        guard startDownloadsImmediately else { return }
        startAutomaticDownload(record)
    }

    private func startAutomaticDownload(_ record: DownloadQueueRecord) {
        if warnBeforeMobileDataDownload && services.networkMonitor.shouldTreatAsMetered {
            pendingAutomaticDownload = record
            return
        }
        Task { await startDownload(record) }
    }

    private func continueAutomaticDownload() {
        guard let record = pendingAutomaticDownload else { return }
        pendingAutomaticDownload = nil
        Task { await startDownload(record) }
    }

    private func startDownload(_ record: DownloadQueueRecord) async {
        await HanaDownloadStarter.start(
            record,
            downloadClient: services.downloadClient,
            siteSession: services.siteSession,
            modelContext: modelContext
        )
    }

    private var automaticDownloadMobileDataAlertBinding: Binding<Bool> {
        Binding {
            pendingAutomaticDownload != nil
        } set: { isPresented in
            if !isPresented {
                pendingAutomaticDownload = nil
            }
        }
    }
}

private enum HanaVideoDetailTopTab: String, CaseIterable, Identifiable, Hashable {
    case details
    case comments

    var id: String { rawValue }

    func title(for mode: HanaVideoDetailTopSwitchMode) -> String {
        switch self {
        case .details:
            switch mode {
            case .detail:
                "详情"
            case .secondary:
                "相关"
            }
        case .comments:
            "评论"
        }
    }
}

private enum HanaVideoDetailTopSwitchMode {
    case detail
    case secondary
}

private struct HanaVideoDetailAdaptiveLayout {
    let containerWidth: CGFloat
    let containerHeight: CGFloat
    let horizontalSizeClass: UserInterfaceSizeClass?

    private let compactHorizontalPadding: CGFloat = 20
    private let sideHorizontalPadding: CGFloat = 24
    private let sideColumnSpacing: CGFloat = 28
    private let minimumPlayerWidth: CGFloat = 620
    private let minimumSideColumnWidth: CGFloat = 300
    private let maximumSideColumnWidth: CGFloat = 520

    var usesSideBySideLayout: Bool {
        horizontalSizeClass != .compact && sideBySideDecisionWidth >= minimumPlayerWidth + minimumSideColumnWidth
    }

    var horizontalPadding: CGFloat {
        usesSideBySideLayout ? sideHorizontalPadding : compactHorizontalPadding
    }

    var verticalPadding: CGFloat {
        usesSideBySideLayout ? 0 : 16
    }

    var bottomContentPadding: CGFloat {
        usesSideBySideLayout ? 24 : 0
    }

    var columnSpacing: CGFloat {
        usesSideBySideLayout ? sideColumnSpacing : 0
    }

    var contentWidth: CGFloat {
        max(containerWidth - horizontalPadding * 2, 0)
    }

    var playerColumnWidth: CGFloat {
        guard usesSideBySideLayout else { return contentWidth }
        return sideBySideColumnWidths.player
    }

    var sideColumnWidth: CGFloat {
        guard usesSideBySideLayout else { return contentWidth }
        return sideBySideColumnWidths.side
    }

    private var sideBySideAvailableWidth: CGFloat {
        max(containerWidth - horizontalPadding * 2 - columnSpacing, 0)
    }

    private var sideBySideColumnWidths: (player: CGFloat, side: CGFloat) {
        let sideWidth = min(
            max(sideBySideAvailableWidth * 0.34, minimumSideColumnWidth),
            maximumSideColumnWidth
        )
        return (max(sideBySideAvailableWidth - sideWidth, 0), sideWidth)
    }

    private var sideBySideDecisionWidth: CGFloat {
        max(containerWidth - sideHorizontalPadding * 2 - sideColumnSpacing, 0)
    }
}
