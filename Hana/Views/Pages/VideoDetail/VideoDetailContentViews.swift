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
        .confirmationDialog("取消订阅", isPresented: $isUnsubscribeConfirmationPresented) {
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
        .tint(artist.isSubscribed ? Color.secondary.opacity(0.25) : .white)
        .foregroundStyle(artist.isSubscribed ? Color.primary : Color.black)
        .animation(.snappy(duration: 0.22), value: artist.isSubscribed)
        .sensoryFeedback(.selection, trigger: artist.isSubscribed)
        .accessibilityLabel(artist.isSubscribed ? "已订阅，点按可取消订阅" : "订阅")
        .disabled(isWorking)
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
                playlists: $playlists,
                isWorking: isWorking,
                onToggle: togglePlaylist,
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

    private func togglePlaylist(_ playlist: HanimeVideoListState.Playlist) {
        guard let index = playlists.firstIndex(where: { $0.code == playlist.code }) else { return }
        isWorking = true
        let previous = playlists
        playlists[index].isSelected.toggle()
        Task {
            do {
                try await services.repository.setVideoPlaylist(
                    video: video,
                    listCode: playlist.code,
                    shouldAdd: playlists[index].isSelected
                )
            } catch {
                playlists = previous
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
    @Environment(\.dismiss) private var dismiss
    @Binding var playlists: [HanimeVideoListState.Playlist]
    let isWorking: Bool
    let onToggle: (HanimeVideoListState.Playlist) -> Void
    let onCreate: (String, String) -> Void
    @State private var playlistTitle = ""
    @State private var playlistDescription = ""

    private var canCreate: Bool {
        !playlistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("已有清单") {
                    if playlists.isEmpty {
                        Text("暂无可选播放清单")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(playlists) { playlist in
                            Button {
                                onToggle(playlist)
                            } label: {
                                HStack {
                                    Label(playlist.title, systemImage: playlist.isSelected ? "checkmark.circle.fill" : "circle")
                                    Spacer()
                                }
                            }
                            .disabled(isWorking)
                        }
                    }
                }

                Section("新建清单") {
                    TextField("名称", text: $playlistTitle)
                    TextField("简介", text: $playlistDescription, axis: .vertical)
                        .lineLimit(3...6)
                    Button("创建并加入当前视频") {
                        onCreate(
                            playlistTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                            playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                    .disabled(!canCreate)
                }
            }
            .navigationTitle("播放清单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "完成", systemImage: "checkmark") {
                        dismiss()
                    }
                    .disabled(isWorking)
                }
            }
        }
    }
}

struct RelatedVideosSection: View {
    let videos: [HanimeInfo]

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
                    videos: videos,
                    normalMinimumWidth: 150,
                    portraitMinimumWidth: 150
                )
            }
        }
    }
}
