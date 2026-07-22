import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum AccountVideoListSort: String, CaseIterable, Identifiable {
    case siteOrder
    case title
    case videoCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .siteOrder:
            "站点顺序"
        case .title:
            "标题"
        case .videoCode:
            "视频编号"
        }
    }

    func sorted(_ videos: [HanimeInfo]) -> [HanimeInfo] {
        switch self {
        case .siteOrder:
            videos
        case .title:
            videos.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .videoCode:
            videos.sorted { $0.videoCode.localizedStandardCompare($1.videoCode) == .orderedAscending }
        }
    }
}

struct AccountVideoListScreen: View {
    @Environment(HanaServices.self) private var services
    let kind: HanimeMyListKind
    let title: String
    let emptyTitle: String
    let loginMessage: String
    @State private var state: LoadableState<HanimeAccountVideoList> = .idle
    @State private var currentPage = 1
    @State private var isRefreshing = false
    @State private var isLoadingMore = false
    @State private var isDeleting = false
    @State private var hasPendingFavoriteRefresh = false
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var filterText = ""
    @State private var sort = AccountVideoListSort.siteOrder
    @State private var isSelectionModeActive = false
    @State private var selectedVideoCodes = Set<String>()
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        Group {
            if services.siteSession.isLoggedIn {
                if services.siteSession.userID == nil {
                    AccountIdentityUnavailableView(action: refreshAccount)
                } else {
                    content
                }
            } else {
                LoginRequiredView(
                    title: "需要登录",
                    message: loginMessage,
                    actionTitle: "登录站点",
                    action: openLogin
                )
            }
        }
        .navigationTitle(title)
        .searchable(text: $filterText, prompt: "筛选\(title)")
        .toolbar {
            if services.siteSession.isLoggedIn {
                ToolbarItemGroup(placement: .primaryAction) {
                    if isEditing {
                        HanaToolbarIconButton(title: "退出选择", systemImage: "xmark", action: toggleSelectionMode)

                        HanaToolbarIconButton(
                            title: areAllVisibleVideosSelected ? "取消全选" : "全选",
                            systemImage: areAllVisibleVideosSelected ? "circle" : "checkmark.circle"
                        ) {
                            toggleAll(currentVisibleVideos)
                        }
                        .disabled(currentVisibleVideos.isEmpty || isDeleting)

                        HanaToolbarIconButton(title: "删除所选 \(selectedVideoCodes.count)", systemImage: "trash", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                        .disabled(selectedVideoCodes.isEmpty || isDeleting)
                    } else {
                        Menu {
                            ForEach(AccountVideoListSort.allCases) { value in
                                Button {
                                    sort = value
                                } label: {
                                    if sort == value {
                                        Label(value.title, systemImage: "checkmark")
                                    } else {
                                        Text(value.title)
                                    }
                                }
                            }
                        } label: {
                            Label("排序", systemImage: "arrow.up.arrow.down")
                        }
                        .disabled(services.siteSession.userID == nil)

                        Button {
                            toggleSelectionMode()
                        } label: {
                            Label("选择", systemImage: "checklist")
                        }
                        .disabled(services.siteSession.userID == nil)
                    }

                }
            }
        }
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .confirmationDialog("删除所选视频？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("删除 \(selectedVideoCodes.count) 个视频", role: .destructive) {
                Task { await deleteSelectedVideos() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会从当前列表移除。")
        }
        .task(id: services.siteSession.userID) {
            if services.siteSession.isLoggedIn {
                await loadCurrent(page: 1, append: false)
            }
        }
        .onChange(of: services.siteSession.lastCookieSyncAt) {
            if services.siteSession.isLoggedIn {
                Task { await loadCurrent(page: 1, append: false) }
            }
        }
        .onAppear {
            refreshWhenVisible()
        }
        .onChange(of: services.repository.favoriteRevision) { _, _ in
            guard kind == .favorites else { return }
            hasPendingFavoriteRefresh = true
            schedulePendingFavoriteRefreshIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("加载\(title)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let page):
            let videos = visibleVideos(from: page)
            if page.videos.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "rectangle.stack.badge.play")
            } else if videos.isEmpty {
                ContentUnavailableView("没有符合条件的内容", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                List {
                    if let description = page.description {
                        Section {
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        if isEditing {
                            ForEach(videos) { video in
                                HanaSelectableRow(
                                    isSelected: selectedVideoCodes.contains(video.videoCode),
                                    accessibilityLabel: video.title
                                ) {
                                    toggleSelection(video.videoCode)
                                } content: {
                                    accountVideoSelectionRow(video)
                                }
                                .onAppear {
                                    preloadNextPageIfNeeded(after: video, in: videos, maxPage: page.maxPage)
                                }
                            }
                        } else {
                            let portraitVideos = videos.filter { $0.style == .compact }
                            let normalVideos = videos.filter { $0.style == .normal }

                            if !portraitVideos.isEmpty {
                                HanaVideoGridLinks(videos: portraitVideos) { video in
                                    preloadNextPageIfNeeded(after: video, in: videos, maxPage: page.maxPage)
                                }
                                    .padding(.vertical, 4)
                                    .listRowSeparator(.hidden)
                            }

                            ForEach(normalVideos) { video in
                                accountVideoRow(video)
                                    .onAppear {
                                        preloadNextPageIfNeeded(after: video, in: videos, maxPage: page.maxPage)
                                    }
                            }
                            .onDelete { offsets in
                                let videosToDelete = offsets.compactMap { index in
                                    normalVideos.indices.contains(index) ? normalVideos[index] : nil
                                }
                                Task { await deleteVideos(videosToDelete, from: page) }
                            }
                        }

                        HanaInfiniteScrollTrigger(
                            isActive: currentPage < page.maxPage,
                            isLoading: isLoadingMore
                        ) {
                            loadNextPageIfNeeded(maxPage: page.maxPage)
                        }
                    }
                }
                .refreshable {
                    await loadCurrent(page: 1, append: false)
                }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label(message, systemImage: "exclamationmark.triangle")
            } actions: {
                Button("重试") {
                    Task { await loadCurrent(page: 1, append: false) }
                }
            }
        }
    }

    private func openLogin() {
        services.siteSession.requestLogin()
    }

    private func refreshWhenVisible() {
        guard services.siteSession.isLoggedIn,
              services.siteSession.userID != nil,
              case .loaded = state else {
            return
        }
        Task { await loadCurrent(page: 1, append: false) }
    }

    private func schedulePendingFavoriteRefreshIfNeeded() {
        guard kind == .favorites,
              hasPendingFavoriteRefresh,
              !isRefreshing,
              !isLoadingMore,
              !isDeleting,
              case .loaded = state else {
            return
        }
        Task { await loadCurrent(page: 1, append: false) }
    }

    @ViewBuilder
    private func accountVideoRow(_ video: HanimeInfo) -> some View {
        NavigationLink(value: HanaRoute.video(video.videoCode)) {
            HanaVideoListRow(info: video)
        }
    }

    @ViewBuilder
    private func accountVideoSelectionRow(_ video: HanimeInfo) -> some View {
        switch video.style {
        case .normal:
            HanaVideoListRow(info: video)
        case .compact:
            HanaVideoGridCard(info: video)
                .frame(width: HanaVideoGridCard.preferredWidth(for: video))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    private func visibleVideos(from page: HanimeAccountVideoList) -> [HanimeInfo] {
        let filtered = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let videos: [HanimeInfo]
        if filtered.isEmpty {
            videos = page.videos
        } else {
            videos = page.videos.filter { video in
                video.title.localizedCaseInsensitiveContains(filtered)
                    || video.videoCode.localizedCaseInsensitiveContains(filtered)
                    || (video.artist?.localizedCaseInsensitiveContains(filtered) == true)
            }
        }
        return sort.sorted(videos)
    }

    private var isEditing: Bool {
        isSelectionModeActive
    }

    private var currentVisibleVideos: [HanimeInfo] {
        guard case .loaded(let page) = state else { return [] }
        return visibleVideos(from: page)
    }

    private var areAllVisibleVideosSelected: Bool {
        let codes = Set(currentVisibleVideos.map(\.videoCode))
        return !codes.isEmpty && selectedVideoCodes.isSuperset(of: codes)
    }

    private func toggleSelectionMode() {
        if isSelectionModeActive {
            isSelectionModeActive = false
            selectedVideoCodes.removeAll()
        } else {
            isSelectionModeActive = true
        }
    }

    private func toggleSelection(_ videoCode: String) {
        if selectedVideoCodes.contains(videoCode) {
            selectedVideoCodes.remove(videoCode)
        } else {
            selectedVideoCodes.insert(videoCode)
        }
    }

    private func toggleAll(_ videos: [HanimeInfo]) {
        let codes = Set(videos.map(\.videoCode))
        if selectedVideoCodes.isSuperset(of: codes) {
            selectedVideoCodes.subtract(codes)
        } else {
            selectedVideoCodes.formUnion(codes)
        }
    }

    private func refreshAccount() {
        Task {
            await services.siteSession.syncDefaultWebCookies()
            do {
                let user = try await services.repository.currentUser()
                await services.applyLoginState(user: user)
                await loadCurrent(page: 1, append: false)
            } catch {
                if services.siteSession.handle(error) {
                    state = .failed("需要 Cloudflare 验证")
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func loadCurrent(page: Int, append: Bool) async {
        guard let userID = services.siteSession.userID else { return }
        await load(userID: userID, page: page, append: append)
    }

    private func load(userID: String, page: Int, append: Bool) async {
        let previousState = state
        if append {
            guard !isLoadingMore, !isRefreshing, !isDeleting else { return }
            isLoadingMore = true
        } else {
            guard !isRefreshing, !isLoadingMore, !isDeleting else { return }
            isRefreshing = true
            if kind == .favorites {
                hasPendingFavoriteRefresh = false
            }
            if case .loaded = state {
                // Keep the current page visible while a refresh replaces it.
            } else {
                state = .loading
            }
        }
        defer {
            if append {
                isLoadingMore = false
            } else {
                isRefreshing = false
            }
            schedulePendingFavoriteRefreshIfNeeded()
        }

        do {
            let newPage = try await services.repository.accountVideos(kind: kind, userID: userID, page: page)
            if append, case .loaded(let current) = state {
                state = .loaded(current.merging(newPage))
            } else {
                state = .loaded(newPage)
            }
            currentPage = page
        } catch is CancellationError {
            return
        } catch {
            if !append, case .loaded = previousState {
                state = previousState
                if services.siteSession.handle(error) {
                    alertMessage = .error("需要 Cloudflare 验证")
                } else {
                    alertMessage = .error(error.localizedDescription)
                }
            } else {
                if services.siteSession.handle(error) {
                    state = .failed("需要 Cloudflare 验证")
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func loadNextPageIfNeeded(maxPage: Int) {
        guard currentPage < maxPage, !isLoadingMore, !isRefreshing else { return }
        Task { await loadCurrent(page: currentPage + 1, append: true) }
    }

    private func preloadNextPageIfNeeded(after video: HanimeInfo, in videos: [HanimeInfo], maxPage: Int) {
        guard HanaInfiniteScrollPreload.shouldLoadNextPage(
            currentID: video.videoCode,
            orderedIDs: videos.map(\.videoCode)
        ) else {
            return
        }
        loadNextPageIfNeeded(maxPage: maxPage)
    }

    private func deleteVideos(_ videos: [HanimeInfo], from page: HanimeAccountVideoList) async {
        guard let csrfToken = page.csrfToken else {
            alertMessage = .error("当前页面没有删除表单，请刷新后重试。")
            return
        }
        guard !videos.isEmpty else { return }

        isDeleting = true
        defer {
            isDeleting = false
            schedulePendingFavoriteRefreshIfNeeded()
        }

        do {
            for video in videos {
                try await services.repository.deleteAccountVideo(
                    kind: kind,
                    videoCode: video.videoCode,
                    csrfToken: csrfToken
                )
            }
            let removedCodes = Set(videos.map(\.videoCode))
            state = .loaded(HanimeAccountVideoList(
                videos: page.videos.filter { !removedCodes.contains($0.videoCode) },
                description: page.description,
                csrfToken: page.csrfToken,
                maxPage: page.maxPage
            ))
            selectedVideoCodes.subtract(removedCodes)
            toastMessage = .success("已删除 \(removedCodes.count) 个视频")
        } catch {
            if services.siteSession.handle(error) {
                alertMessage = .error("需要 Cloudflare 验证")
            } else {
                alertMessage = .error(error.localizedDescription)
            }
        }
    }

    private func deleteSelectedVideos() async {
        guard case .loaded(let page) = state else { return }
        let videos = page.videos.filter { selectedVideoCodes.contains($0.videoCode) }
        await deleteVideos(videos, from: page)
    }
}

struct AccountIdentityUnavailableView: View {
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("需要重新识别账号", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("已保存站点 Cookie，但当前缺少用户 ID。")
        } actions: {
            Button("重新识别账号", action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct SubscriptionArtistPill: View {
    let artist: HanimeSubscriptionArtist
    var isSelected = false
    var showsManagementState = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                CoverView(url: artist.avatarURL, blurInDemoMode: false)
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())

                if showsManagementState {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .background(.background, in: Circle())
                }
            }
            Text(artist.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 72)
        }
        .accessibilityElement(children: .combine)
    }
}
