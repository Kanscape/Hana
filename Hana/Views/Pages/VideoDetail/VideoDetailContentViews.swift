import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct VideoDetailHeader: View {
    let video: HanimeVideo

    private var secondaryTitle: String? {
        guard let chineseTitle = video.chineseTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        guard normalizedTitle(chineseTitle) != normalizedTitle(video.title) else {
            return nil
        }
        return chineseTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(video.title)
                .font(.title2.weight(.semibold))
            if let chineseTitle = secondaryTitle {
                Text(chineseTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label(video.videoCode, systemImage: "number")
                if let views = video.views {
                    Label(views, systemImage: "eye")
                }
                if let uploadTime = video.uploadTime {
                    Label(uploadTime.hanaChineseDateText, systemImage: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func normalizedTitle(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

struct VideoIntroductionPreview: View {
    let introduction: String?
    @State private var isExpanded = false

    private var text: String? {
        introduction?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var body: some View {
        if let text {
            DetailSection(title: "简介") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .lineLimit(isExpanded ? nil : 4)
                        .textSelection(.enabled)

                    if text.count > 120 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Label(
                                isExpanded ? "收起" : "展开",
                                systemImage: isExpanded ? "chevron.up" : "chevron.down"
                            )
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.borderless)
                    }
                }
            }
            .onChange(of: text) {
                isExpanded = false
            }
        }
    }
}

struct VideoArtistSection: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    let video: HanimeVideo
    @State private var artist: HanimeArtist?
    @State private var isWorking = false
    @State private var alertMessage: HanaAlertMessage?
    @State private var isUnsubscribeConfirmationPresented = false

    private var currentArtist: HanimeArtist? {
        artist ?? video.artist
    }

    var body: some View {
        Group {
            if let artist = currentArtist {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        NavigationLink(value: HanaRoute.lockedSearch(.artist(
                            name: artist.name,
                            genre: HanimeSearchOptionCatalog.genreSearchKey(matching: artist.genre)
                        ))) {
                            HStack(spacing: 12) {
                                CoverView(url: artist.avatarURL, blurInDemoMode: false)
                                    .frame(width: 52, height: 52)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(artist.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(artist.genre)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 12)

                        subscriptionButton(artist: artist)
                    }
                }
            }
        }
        .hanaFeedbackAlert($alertMessage)
        .task(id: video.videoCode) {
            artist = video.artist
            alertMessage = nil
        }
        .alert("取消订阅", isPresented: $isUnsubscribeConfirmationPresented) {
            Button("取消订阅", role: .destructive) {
                setSubscribed(false)
            }
            Button("保留", role: .cancel) {}
        } message: {
            Text("确定取消订阅 \(currentArtist?.name ?? "")？")
        }
    }

    @ViewBuilder
    private func subscriptionButton(artist: HanimeArtist) -> some View {
        Button {
            handleSubscribeTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: artist.isSubscribed ? "bell.fill" : "plus")
                    .imageScale(.small)
                    .symbolEffect(.bounce, value: artist.isSubscribed)

                Text(artist.isSubscribed ? "已订阅" : "订阅")
                    .contentTransition(.opacity)
            }
            .font(.headline.weight(.semibold))
            .frame(minWidth: 84)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(artist.isSubscribed ? Color.secondary.opacity(0.25) : Color.primary)
        .foregroundStyle(artist.isSubscribed ? Color.primary : unsubscribedButtonForeground)
        .animation(.snappy(duration: 0.22), value: artist.isSubscribed)
        .sensoryFeedback(.selection, trigger: artist.isSubscribed)
        .accessibilityLabel(artist.isSubscribed ? "已订阅，点按可取消订阅" : "订阅")
        .disabled(isWorking)
    }

    private var unsubscribedButtonForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    private func handleSubscribeTap() {
        guard services.siteSession.isLoggedIn else {
            services.siteSession.requestLogin()
            return
        }
        guard let currentArtist else { return }
        guard currentArtist.subscription != nil, video.csrfToken != nil else {
            alertMessage = .error("当前页面没有订阅表单，请刷新详情页。")
            return
        }
        if currentArtist.isSubscribed {
            isUnsubscribeConfirmationPresented = true
        } else {
            setSubscribed(true)
        }
    }

    private func setSubscribed(_ shouldSubscribe: Bool) {
        guard let currentArtist else { return }
        isWorking = true
        let previous = artist
        var next = currentArtist
        next.subscription?.isSubscribed = shouldSubscribe
        withAnimation(.snappy(duration: 0.22)) {
            artist = next
            alertMessage = nil
        }

        Task {
            do {
                try await services.repository.setArtistSubscribed(
                    artist: currentArtist,
                    shouldSubscribe: shouldSubscribe,
                    csrfToken: video.csrfToken
                )
                alertMessage = nil
            } catch {
                withAnimation(.snappy(duration: 0.22)) {
                    artist = previous ?? video.artist
                }
                if services.siteSession.handle(error) {
                    alertMessage = .error("需要 Cloudflare 验证")
                } else {
                    alertMessage = .error(error.localizedDescription)
                }
            }
            isWorking = false
        }
    }
}

struct VideoLibraryActionsView: View {
    @Environment(HanaServices.self) private var services
    let video: HanimeVideo
    @State private var isFavorite = false
    @State private var favoriteCount: Int?
    @State private var isWatchLater = false
    @State private var playlists: [HanimeVideoListState.Playlist] = []
    @State private var isWorking = false
    @State private var actionErrorMessage: String?
    @State private var isPlaylistSheetPresented = false

    private var hasSelectedPlaylist: Bool {
        playlists.contains { $0.isSelected }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                interactionButton(
                    title: favoriteCount.map(String.init) ?? "喜欢",
                    systemImage: isFavorite ? "heart.fill" : "heart",
                    isActive: isFavorite,
                    action: toggleFavorite
                )

                interactionButton(
                    title: isWatchLater ? "已稍后" : "稍后",
                    systemImage: "text.badge.plus",
                    isActive: isWatchLater,
                    action: toggleWatchLater
                )

                interactionButton(
                    title: "清单",
                    systemImage: "list.bullet.rectangle",
                    isActive: hasSelectedPlaylist,
                    action: presentPlaylistSheet
                )

                ShareLink(item: URL(string: "https://hanime1.me/watch?v=\(video.videoCode)")!) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 48, height: 48)
                            .background(.thinMaterial, in: Circle())
                        Text("分享")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $isPlaylistSheetPresented) {
            VideoPlaylistPickerSheet(
                playlists: playlists,
                isWorking: isWorking,
                onApply: applyPlaylistChanges,
                onCreate: createPlaylist
            )
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        actionErrorMessage = nil
                    }
                }
            )
        ) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "")
        }
        .task(id: video.videoCode) {
            isFavorite = video.isFavorite
            favoriteCount = video.favoriteCount
            isWatchLater = video.listState?.isWatchLater ?? false
            playlists = video.listState?.playlists ?? []
            actionErrorMessage = nil
        }
    }

    private func openLogin() {
        services.siteSession.requestLogin()
    }

    private func interactionButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if isWorking {
                    ProgressView()
                        .frame(width: 48, height: 48)
                        .background(.thinMaterial, in: Circle())
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                        .frame(width: 48, height: 48)
                        .background(.thinMaterial, in: Circle())
                }
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private func toggleFavorite() {
        guard services.siteSession.isLoggedIn else {
            openLogin()
            return
        }
        guard video.csrfToken != nil, video.currentUserID != nil else {
            actionErrorMessage = "当前页面没有点赞表单，请刷新详情页。"
            return
        }
        isWorking = true
        let previousFavorite = isFavorite
        let previousCount = favoriteCount
        isFavorite.toggle()
        favoriteCount = favoriteCount.map { max($0 + (isFavorite ? 1 : -1), 0) }
        Task {
            do {
                try await services.repository.setVideoFavorite(video: video, shouldFavorite: isFavorite)
            } catch {
                isFavorite = previousFavorite
                favoriteCount = previousCount
                if services.siteSession.handle(error) {
                    actionErrorMessage = "需要 Cloudflare 验证"
                } else {
                    actionErrorMessage = error.localizedDescription
                }
            }
            isWorking = false
        }
    }

    private func toggleWatchLater() {
        guard services.siteSession.isLoggedIn else {
            openLogin()
            return
        }
        guard video.csrfToken != nil else {
            actionErrorMessage = "当前页面没有稍后观看表单，请刷新详情页。"
            return
        }

        isWorking = true
        let previous = isWatchLater
        isWatchLater.toggle()
        Task {
            do {
                try await services.repository.setVideoWatchLater(video: video, shouldSave: isWatchLater)
            } catch {
                isWatchLater = previous
                handleActionError(error)
            }
            isWorking = false
        }
    }

    private func presentPlaylistSheet() {
        guard services.siteSession.isLoggedIn else {
            openLogin()
            return
        }
        guard video.csrfToken != nil else {
            actionErrorMessage = "当前页面没有播放清单表单，请刷新详情页。"
            return
        }
        isPlaylistSheetPresented = true
    }

    private func applyPlaylistChanges(_ desiredPlaylists: [HanimeVideoListState.Playlist]) {
        let changes = desiredPlaylists.compactMap { desiredPlaylist -> HanimeVideoListState.Playlist? in
            guard let currentPlaylist = playlists.first(where: { $0.code == desiredPlaylist.code }),
                  currentPlaylist.isSelected != desiredPlaylist.isSelected else {
                return nil
            }
            return desiredPlaylist
        }

        guard !changes.isEmpty else {
            isPlaylistSheetPresented = false
            return
        }

        isWorking = true
        Task {
            do {
                for playlist in changes {
                    try await services.repository.setVideoPlaylist(
                        video: video,
                        listCode: playlist.code,
                        shouldAdd: playlist.isSelected
                    )

                    if let index = playlists.firstIndex(where: { $0.code == playlist.code }) {
                        playlists[index].isSelected = playlist.isSelected
                    }
                }
                isPlaylistSheetPresented = false
            } catch {
                handleActionError(error)
            }
            isWorking = false
        }
    }

    private func createPlaylist(title: String, description: String) {
        guard video.csrfToken != nil else {
            actionErrorMessage = "当前页面没有创建清单表单，请刷新详情页。"
            return
        }
        isWorking = true
        Task {
            do {
                try await services.repository.createPlaylist(
                    video: video,
                    title: title,
                    description: description
                )
                isPlaylistSheetPresented = false
            } catch {
                handleActionError(error)
            }
            isWorking = false
        }
    }

    private func handleActionError(_ error: Error) {
        if services.siteSession.handle(error) {
            actionErrorMessage = "需要 Cloudflare 验证"
        } else {
            actionErrorMessage = error.localizedDescription
        }
    }
}

struct VideoPlaylistPickerSheet: View {
    let playlists: [HanimeVideoListState.Playlist]
    let isWorking: Bool
    let onApply: ([HanimeVideoListState.Playlist]) -> Void
    let onCreate: (String, String) -> Void
    @State private var draftPlaylists: [HanimeVideoListState.Playlist]
#if os(macOS)
    @State private var macOSPage = VideoPlaylistMacOSPage.playlists
#endif

    init(
        playlists: [HanimeVideoListState.Playlist],
        isWorking: Bool,
        onApply: @escaping ([HanimeVideoListState.Playlist]) -> Void,
        onCreate: @escaping (String, String) -> Void
    ) {
        self.playlists = playlists
        self.isWorking = isWorking
        self.onApply = onApply
        self.onCreate = onCreate
        _draftPlaylists = State(initialValue: playlists)
    }

    @ViewBuilder
    var body: some View {
#if os(macOS)
        macOSBody
#else
        mobileBody
#endif
    }

    private var mobileBody: some View {
        NavigationStack {
            Form {
                if playlists.isEmpty {
                    Text("暂无可选播放清单")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(draftPlaylists) { playlist in
                        playlistRow(playlist)
                    }
                }
            }
            .navigationTitle("播放清单")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        VideoPlaylistCreationPage(
                            isWorking: isWorking,
                            onCreate: onCreate
                        )
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建播放清单")
                    .disabled(isWorking)
                }

                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "完成", systemImage: "checkmark") {
                        onApply(draftPlaylists)
                    }
                    .disabled(isWorking)
                }
            }
        }
    }

#if os(macOS)
    private var macOSBody: some View {
        Group {
            switch macOSPage {
            case .playlists:
                macOSPlaylistPage
            case .creation:
                VideoPlaylistCreationPage(
                    isWorking: isWorking,
                    onBack: { macOSPage = .playlists },
                    onCreate: onCreate
                )
            }
        }
        .frame(width: 520, height: 360)
    }

    private var macOSPlaylistPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("播放清单")
                    .font(.headline)

                Spacer()

                Button {
                    macOSPage = .creation
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("新建播放清单")
                .disabled(isWorking)

                HanaToolbarIconButton(title: "完成", systemImage: "checkmark") {
                    onApply(draftPlaylists)
                }
                .disabled(isWorking)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if draftPlaylists.isEmpty {
                        Text("暂无可选播放清单")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(draftPlaylists) { playlist in
                            playlistRow(playlist)
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)

                            if playlist.id != draftPlaylists.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
    }
#endif

    private func playlistRow(_ playlist: HanimeVideoListState.Playlist) -> some View {
        Button {
            guard let index = draftPlaylists.firstIndex(where: { $0.code == playlist.code }) else { return }
            draftPlaylists[index].isSelected.toggle()
        } label: {
            HStack {
                Label(
                    playlist.title,
                    systemImage: playlist.isSelected ? "checkmark.circle.fill" : "circle"
                )
                Spacer()
            }
        }
        .disabled(isWorking)
    }
}

#if os(macOS)
private enum VideoPlaylistMacOSPage {
    case playlists
    case creation
}
#endif

private struct VideoPlaylistCreationPage: View {
    let isWorking: Bool
    let onBack: (() -> Void)?
    let onCreate: (String, String) -> Void
    @State private var playlistTitle = ""
    @State private var playlistDescription = ""

    init(
        isWorking: Bool,
        onBack: (() -> Void)? = nil,
        onCreate: @escaping (String, String) -> Void
    ) {
        self.isWorking = isWorking
        self.onBack = onBack
        self.onCreate = onCreate
    }

    private var canCreate: Bool {
        !playlistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    @ViewBuilder
    var body: some View {
#if os(macOS)
        macOSBody
#else
        mobileBody
#endif
    }

    private var mobileBody: some View {
        Form {
            Section {
                TextField("名称", text: $playlistTitle)
                TextField("简介", text: $playlistDescription, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("新建播放清单")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                HanaToolbarIconButton(
                    title: "创建并加入当前视频",
                    systemImage: "checkmark"
                ) {
                    submit()
                }
                .disabled(!canCreate)
            }
        }
    }

#if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HanaToolbarIconButton(title: "返回", systemImage: "chevron.left") {
                    onBack?()
                }

                Text("新建播放清单")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    macOSFieldLabel("名称")
                    TextField("输入名称", text: $playlistTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }

                GridRow {
                    macOSFieldLabel("简介")
                    TextField("可选", text: $playlistDescription, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(4...7)
                        .frame(minHeight: 96, maxHeight: 140)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            Divider()

            HStack {
                Spacer()

                Button {
                    submit()
                } label: {
                    Label("创建并加入", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("创建并加入当前视频")
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func macOSFieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .trailing)
    }
#endif

    private func submit() {
        onCreate(
            playlistTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct RelatedVideosSection: View {
    let videos: [HanimeInfo]
    @State private var availableWidth: CGFloat = 0

    private let minimumCardWidth: CGFloat = 150
    private let columnSpacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if videos.isEmpty {
                ContentUnavailableView("暂无相关影片", systemImage: "play.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else {
                Text("相关影片")
                    .font(.headline)

                HanaVideoGridLinks(
                    videos: visibleVideos,
                    normalMinimumWidth: minimumCardWidth,
                    portraitMinimumWidth: minimumCardWidth
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { newWidth in
            availableWidth = newWidth
        }
    }

    private var visibleVideos: [HanimeInfo] {
        let visibleCount = HanaCompleteGridRows.visibleItemCount(
            totalCount: videos.count,
            availableWidth: availableWidth,
            minimumItemWidth: minimumCardWidth,
            spacing: columnSpacing
        )
        return Array(videos.prefix(visibleCount))
    }
}

struct HanaCompleteGridRows {
    static func visibleItemCount(
        totalCount: Int,
        availableWidth: CGFloat,
        minimumItemWidth: CGFloat,
        spacing: CGFloat
    ) -> Int {
        guard totalCount > 0 else { return 0 }

        let minimumItemWidth = max(minimumItemWidth, 1)
        let spacing = max(spacing, 0)
        let columnCount = max(
            Int((max(availableWidth, 0) + spacing) / (minimumItemWidth + spacing)),
            1
        )
        guard totalCount > columnCount else { return totalCount }

        return totalCount - totalCount % columnCount
    }
}
