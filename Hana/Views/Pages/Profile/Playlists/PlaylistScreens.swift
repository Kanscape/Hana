import AVKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WatchLaterScreen: View {
    var body: some View {
        AccountVideoListScreen(
            kind: .watchLater,
            title: "稍后观看",
            emptyTitle: "稍后观看暂无内容",
            loginMessage: "登录后可查看稍后观看列表。"
        )
    }
}

private enum PlaylistListSort: String, CaseIterable, Identifiable {
    case siteOrder
    case title
    case total

    var id: String { rawValue }

    var title: String {
        switch self {
        case .siteOrder:
            "站点顺序"
        case .title:
            "名称"
        case .total:
            "视频数量"
        }
    }

    func sorted(_ playlists: [HanimePlaylistSummary]) -> [HanimePlaylistSummary] {
        switch self {
        case .siteOrder:
            playlists
        case .title:
            playlists.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .total:
            playlists.sorted { $0.total > $1.total }
        }
    }
}

struct PlaylistsScreen: View {
    @Environment(HanaServices.self) private var services
    @State private var state: LoadableState<HanimePlaylistsPage> = .idle
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var isMutating = false
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var isCreatePlaylistPresented = false
    @State private var filterText = ""
    @State private var sort = PlaylistListSort.siteOrder
    @State private var editMode: EditMode = .inactive
    @State private var selectedListCodes = Set<String>()
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
                    message: "登录后可查看和管理播放清单。",
                    actionTitle: "登录站点",
                    action: openLogin
                )
            }
        }
        .navigationTitle("播放清单")
        .searchable(text: $filterText, prompt: "筛选播放清单")
        .toolbar {
            if services.siteSession.isLoggedIn {
                ToolbarItemGroup(placement: .primaryAction) {
                    if isEditing {
                        HanaToolbarIconButton(title: "退出选择", systemImage: "xmark", action: toggleSelectionMode)

                        HanaToolbarIconButton(
                            title: areAllVisiblePlaylistsSelected ? "取消全选" : "全选",
                            systemImage: areAllVisiblePlaylistsSelected ? "circle" : "checkmark.circle"
                        ) {
                            toggleAll(currentVisiblePlaylists)
                        }
                        .disabled(currentVisiblePlaylists.isEmpty || isMutating)

                        HanaToolbarIconButton(title: "删除所选 \(selectedListCodes.count)", systemImage: "trash", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                        .disabled(selectedListCodes.isEmpty || isMutating)
                    } else {
                        Menu {
                            ForEach(PlaylistListSort.allCases) { value in
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
                        .disabled(services.siteSession.userID == nil || isMutating)

                        Button {
                            isCreatePlaylistPresented = true
                        } label: {
                            Label("创建", systemImage: "plus")
                        }
                        .disabled(services.siteSession.userID == nil || isMutating)
                    }

                }
            }
        }
        .environment(\.editMode, $editMode)
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .confirmationDialog("删除所选播放清单？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("删除 \(selectedListCodes.count) 个播放清单", role: .destructive) {
                Task { await deleteSelectedPlaylists() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清单里的视频不会从站点删除。")
        }
        .sheet(isPresented: $isCreatePlaylistPresented) {
            RemotePlaylistEditorSheet(
                title: "创建播放清单",
                actionTitle: "创建",
                isWorking: isMutating,
                onSubmit: { title, description in
                    Task { await createPlaylist(title: title, description: description) }
                }
            )
        }
        .task(id: services.siteSession.userID) {
            if services.siteSession.isLoggedIn, case .idle = state {
                await loadCurrent(page: 1, append: false)
            }
        }
        .onChange(of: services.siteSession.lastCookieSyncAt) {
            if services.siteSession.isLoggedIn {
                Task { await loadCurrent(page: 1, append: false) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("加载播放清单")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let page):
            let playlists = visiblePlaylists(from: page)
            if page.playlists.isEmpty {
                ContentUnavailableView("播放清单暂无内容", systemImage: "list.bullet.rectangle")
            } else if playlists.isEmpty {
                ContentUnavailableView("没有符合条件的播放清单", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                List(selection: $selectedListCodes) {
                    if isEditing {
                        ForEach(playlists) { playlist in
                            RemotePlaylistRow(playlist: playlist)
                                .tag(playlist.listCode)
                                .onAppear {
                                    preloadNextPlaylistPageIfNeeded(after: playlist, in: playlists, maxPage: page.maxPage)
                                }
                        }
                    } else {
                        ForEach(playlists) { playlist in
                            playlistRow(playlist)
                                .onAppear {
                                    preloadNextPlaylistPageIfNeeded(after: playlist, in: playlists, maxPage: page.maxPage)
                                }
                        }
                        .onDelete { offsets in
                            let playlistsToDelete = offsets.compactMap { index in
                                playlists.indices.contains(index) ? playlists[index] : nil
                            }
                            Task { await deletePlaylists(playlistsToDelete, from: page) }
                        }
                    }

                    HanaInfiniteScrollTrigger(
                        isActive: currentPage < page.maxPage,
                        isLoading: isLoadingMore
                    ) {
                        loadNextPlaylistPageIfNeeded(maxPage: page.maxPage)
                    }
                    .disabled(isMutating)
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

    @ViewBuilder
    private func playlistRow(_ playlist: HanimePlaylistSummary) -> some View {
        NavigationLink(value: HanaRoute.remotePlaylist(playlist)) {
            RemotePlaylistRow(playlist: playlist)
        }
    }

    private func visiblePlaylists(from page: HanimePlaylistsPage) -> [HanimePlaylistSummary] {
        let filter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlists: [HanimePlaylistSummary]
        if filter.isEmpty {
            playlists = page.playlists
        } else {
            playlists = page.playlists.filter { playlist in
                playlist.title.localizedCaseInsensitiveContains(filter)
                    || playlist.listCode.localizedCaseInsensitiveContains(filter)
            }
        }
        return sort.sorted(playlists)
    }

    private var isEditing: Bool {
        editMode.isEditing
    }

    private var currentVisiblePlaylists: [HanimePlaylistSummary] {
        guard case .loaded(let page) = state else { return [] }
        return visiblePlaylists(from: page)
    }

    private var areAllVisiblePlaylistsSelected: Bool {
        let codes = Set(currentVisiblePlaylists.map(\.listCode))
        return !codes.isEmpty && selectedListCodes.isSuperset(of: codes)
    }

    private func toggleSelectionMode() {
        if editMode.isEditing {
            editMode = .inactive
            selectedListCodes.removeAll()
        } else {
            editMode = .active
        }
    }

    private func toggleAll(_ playlists: [HanimePlaylistSummary]) {
        let codes = Set(playlists.map(\.listCode))
        if selectedListCodes.isSuperset(of: codes) {
            selectedListCodes.subtract(codes)
        } else {
            selectedListCodes.formUnion(codes)
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
        if append {
            guard !isLoadingMore else { return }
            isLoadingMore = true
        } else {
            state = .loading
        }
        defer { isLoadingMore = false }

        do {
            let newPage = try await services.repository.playlists(userID: userID, page: page)
            if append, case .loaded(let current) = state {
                state = .loaded(current.merging(newPage))
            } else {
                state = .loaded(newPage)
            }
            currentPage = page
        } catch {
            if services.siteSession.handle(error) {
                state = .failed("需要 Cloudflare 验证")
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func loadNextPlaylistPageIfNeeded(maxPage: Int) {
        guard currentPage < maxPage, !isLoadingMore, !isMutating else { return }
        Task { await loadCurrent(page: currentPage + 1, append: true) }
    }

    private func preloadNextPlaylistPageIfNeeded(
        after playlist: HanimePlaylistSummary,
        in playlists: [HanimePlaylistSummary],
        maxPage: Int
    ) {
        guard HanaInfiniteScrollPreload.shouldLoadNextPage(
            currentID: playlist.listCode,
            orderedIDs: playlists.map(\.listCode)
        ) else {
            return
        }
        loadNextPlaylistPageIfNeeded(maxPage: maxPage)
    }

    private func createPlaylist(title: String, description: String) async {
        guard case .loaded(let page) = state, let csrfToken = page.csrfToken else {
            alertMessage = .error("当前页面没有创建表单，请刷新后重试。")
            return
        }

        isMutating = true
        defer { isMutating = false }

        do {
            try await services.repository.createPlaylist(
                title: title,
                description: description,
                csrfToken: csrfToken
            )
            isCreatePlaylistPresented = false
            await loadCurrent(page: 1, append: false)
            toastMessage = .success("已创建播放清单")
        } catch {
            if services.siteSession.handle(error) {
                alertMessage = .error("需要 Cloudflare 验证")
            } else {
                alertMessage = .error(error.localizedDescription)
            }
        }
    }

    private func deletePlaylists(_ playlists: [HanimePlaylistSummary], from page: HanimePlaylistsPage) async {
        guard let csrfToken = page.csrfToken else {
            alertMessage = .error("当前页面没有删除表单，请刷新后重试。")
            return
        }
        guard !playlists.isEmpty else { return }

        isMutating = true
        defer { isMutating = false }

        do {
            for playlist in playlists {
                try await services.repository.modifyPlaylist(
                    listCode: playlist.listCode,
                    title: playlist.title,
                    description: "",
                    delete: true,
                    csrfToken: csrfToken
                )
            }
            let removedCodes = Set(playlists.map(\.listCode))
            state = .loaded(HanimePlaylistsPage(
                playlists: page.playlists.filter { !removedCodes.contains($0.listCode) },
                csrfToken: page.csrfToken,
                maxPage: page.maxPage
            ))
            selectedListCodes.subtract(removedCodes)
            toastMessage = .success("已删除 \(removedCodes.count) 个播放清单")
        } catch {
            if services.siteSession.handle(error) {
                alertMessage = .error("需要 Cloudflare 验证")
            } else {
                alertMessage = .error(error.localizedDescription)
            }
        }
    }

    private func deleteSelectedPlaylists() async {
        guard case .loaded(let page) = state else { return }
        let playlists = page.playlists.filter { selectedListCodes.contains($0.listCode) }
        await deletePlaylists(playlists, from: page)
    }
}

private struct PlaylistRow: View {
    let playlist: PlaylistRecord
    let count: Int

    private var coverURL: URL? {
        guard let coverURLString = playlist.coverURLString else { return nil }
        return URL(string: coverURLString)
    }

    var body: some View {
        HStack(spacing: 12) {
            CoverView(url: coverURL)
                .frame(width: 72, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(count) 个视频")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RemotePlaylistRow: View {
    let playlist: HanimePlaylistSummary

    var body: some View {
        HStack(spacing: 12) {
            CoverView(url: playlist.coverURL)
                .frame(width: 72, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(playlist.total) 个视频")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RemotePlaylistEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionTitle: String
    let isWorking: Bool
    let onSubmit: (String, String) -> Void
    @State private var playlistTitle = ""
    @State private var playlistDescription = ""

    init(
        title: String,
        actionTitle: String,
        initialTitle: String = "",
        initialDescription: String = "",
        isWorking: Bool,
        onSubmit: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.isWorking = isWorking
        self.onSubmit = onSubmit
        _playlistTitle = State(initialValue: initialTitle)
        _playlistDescription = State(initialValue: initialDescription)
    }

    private var canSubmit: Bool {
        !playlistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $playlistTitle)
                    TextField("简介", text: $playlistDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "取消", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: actionTitle, systemImage: "checkmark") {
                        onSubmit(
                            playlistTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                            playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }
}

struct PlaylistDetailScreen: View {
    @Environment(\.modelContext) private var modelContext
    let playlist: PlaylistRecord
    @Query private var items: [PlaylistItemRecord]

    init(playlist: PlaylistRecord) {
        self.playlist = playlist
        let playlistID = playlist.id
        _items = Query(
            filter: #Predicate<PlaylistItemRecord> { item in
                item.playlistID == playlistID
            },
            sort: \PlaylistItemRecord.createdAt,
            order: .reverse
        )
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("清单暂无视频", systemImage: "list.bullet.rectangle")
            } else {
                ForEach(items) { item in
                    NavigationLink(value: HanaRoute.video(item.videoCode)) {
                        SavedVideoRow(
                            title: item.title,
                            videoCode: item.videoCode,
                            coverURLString: item.coverURLString,
                            detail: item.createdAt.hanaChineseDateTimeText
                        )
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle(playlist.title)
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
        playlist.updatedAt = .now
        try? modelContext.save()
    }
}

struct RemotePlaylistDetailScreen: View {
    @Environment(HanaServices.self) private var services
    let playlist: HanimePlaylistSummary
    @State private var state: LoadableState<HanimeAccountVideoList> = .idle
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var isDeleting = false
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var currentTitle: String
    @State private var currentDescription = ""
    @State private var isEditorPresented = false
    @State private var filterText = ""
    @State private var sort = AccountVideoListSort.siteOrder
    @State private var editMode: EditMode = .inactive
    @State private var selectedVideoCodes = Set<String>()
    @State private var isDeleteConfirmationPresented = false

    init(playlist: HanimePlaylistSummary) {
        self.playlist = playlist
        _currentTitle = State(initialValue: playlist.title)
    }

    var body: some View {
        content
            .navigationTitle(currentTitle)
            .searchable(text: $filterText, prompt: "筛选清单视频")
            .toolbar {
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
                        .disabled(isDeleting)

                        Button {
                            toggleSelectionMode()
                        } label: {
                            Label("选择", systemImage: "checklist")
                        }
                        .disabled(isDeleting)

                        Button {
                            isEditorPresented = true
                        } label: {
                            Label("编辑", systemImage: "square.and.pencil")
                        }
                        .disabled(isDeleting)
                    }

                }
            }
            .environment(\.editMode, $editMode)
            .hanaToast($toastMessage)
            .hanaFeedbackAlert($alertMessage)
            .confirmationDialog("从播放清单移除所选视频？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
                Button("移除 \(selectedVideoCodes.count) 个视频", role: .destructive) {
                    Task { await deleteSelectedVideos() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("视频本身不会从站点删除。")
            }
            .sheet(isPresented: $isEditorPresented) {
                RemotePlaylistEditorSheet(
                    title: "编辑播放清单",
                    actionTitle: "保存",
                    initialTitle: currentTitle,
                    initialDescription: currentDescription,
                    isWorking: isDeleting,
                    onSubmit: { title, description in
                        Task { await updatePlaylist(title: title, description: description) }
                    }
                )
            }
            .task {
                if case .idle = state {
                    await load(page: 1, append: false)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("加载清单")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let page):
            let videos = visibleVideos(from: page)
            if page.videos.isEmpty {
                ContentUnavailableView("清单暂无视频", systemImage: "list.bullet.rectangle")
            } else if videos.isEmpty {
                ContentUnavailableView("没有符合条件的视频", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                List(selection: $selectedVideoCodes) {
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
                                playlistVideoSelectionRow(video)
                                    .tag(video.videoCode)
                                    .onAppear {
                                        preloadNextPlaylistItemPageIfNeeded(after: video, in: videos, maxPage: page.maxPage)
                                    }
                            }
                        } else {
                            let portraitVideos = videos.filter { $0.style == .compact }
                            let normalVideos = videos.filter { $0.style == .normal }

                            if !portraitVideos.isEmpty {
                                HanaVideoGridLinks(videos: portraitVideos) { video in
                                    preloadNextPlaylistItemPageIfNeeded(after: video, in: videos, maxPage: page.maxPage)
                                }
                                    .padding(.vertical, 4)
                                    .listRowSeparator(.hidden)
                            }

                            ForEach(normalVideos) { video in
                                playlistVideoRow(video)
                                    .onAppear {
                                        preloadNextPlaylistItemPageIfNeeded(after: video, in: videos, maxPage: page.maxPage)
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
                            loadNextPlaylistItemPageIfNeeded(maxPage: page.maxPage)
                        }
                        .disabled(isDeleting)
                    }
                }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label(message, systemImage: "exclamationmark.triangle")
            } actions: {
                Button("重试") {
                    Task { await load(page: 1, append: false) }
                }
            }
        }
    }

    private func load(page: Int, append: Bool) async {
        if append {
            guard !isLoadingMore else { return }
            isLoadingMore = true
        } else {
            state = .loading
        }
        defer { isLoadingMore = false }

        do {
            let newPage = try await services.repository.playlistItems(listCode: playlist.listCode, page: page)
            if append, case .loaded(let current) = state {
                state = .loaded(current.merging(newPage))
            } else {
                state = .loaded(newPage)
            }
            currentDescription = newPage.description ?? ""
            currentPage = page
        } catch {
            if services.siteSession.handle(error) {
                state = .failed("需要 Cloudflare 验证")
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func loadNextPlaylistItemPageIfNeeded(maxPage: Int) {
        guard currentPage < maxPage, !isLoadingMore, !isDeleting else { return }
        Task { await load(page: currentPage + 1, append: true) }
    }

    private func preloadNextPlaylistItemPageIfNeeded(after video: HanimeInfo, in videos: [HanimeInfo], maxPage: Int) {
        guard HanaInfiniteScrollPreload.shouldLoadNextPage(
            currentID: video.videoCode,
            orderedIDs: videos.map(\.videoCode)
        ) else {
            return
        }
        loadNextPlaylistItemPageIfNeeded(maxPage: maxPage)
    }

    @ViewBuilder
    private func playlistVideoRow(_ video: HanimeInfo) -> some View {
        NavigationLink(value: HanaRoute.video(video.videoCode)) {
            HanaVideoListRow(info: video)
        }
    }

    @ViewBuilder
    private func playlistVideoSelectionRow(_ video: HanimeInfo) -> some View {
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
        let filter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let videos: [HanimeInfo]
        if filter.isEmpty {
            videos = page.videos
        } else {
            videos = page.videos.filter { video in
                video.title.localizedCaseInsensitiveContains(filter)
                    || video.videoCode.localizedCaseInsensitiveContains(filter)
                    || (video.artist?.localizedCaseInsensitiveContains(filter) == true)
            }
        }
        return sort.sorted(videos)
    }

    private var isEditing: Bool {
        editMode.isEditing
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
        if editMode.isEditing {
            editMode = .inactive
            selectedVideoCodes.removeAll()
        } else {
            editMode = .active
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

    private func updatePlaylist(title: String, description: String) async {
        guard let csrfToken = currentPageCSRFToken else {
            alertMessage = .error("当前页面没有编辑表单，请刷新后重试。")
            return
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            try await services.repository.modifyPlaylist(
                listCode: playlist.listCode,
                title: title,
                description: description,
                delete: false,
                csrfToken: csrfToken
            )
            currentTitle = title
            currentDescription = description
            isEditorPresented = false
            toastMessage = .success("已保存播放清单")
        } catch {
            if services.siteSession.handle(error) {
                alertMessage = .error("需要 Cloudflare 验证")
            } else {
                alertMessage = .error(error.localizedDescription)
            }
        }
    }

    private var currentPageCSRFToken: String? {
        if case .loaded(let page) = state {
            return page.csrfToken
        }
        return nil
    }

    private func deleteVideos(_ videos: [HanimeInfo], from page: HanimeAccountVideoList) async {
        guard let csrfToken = page.csrfToken else {
            alertMessage = .error("当前页面没有删除表单，请刷新后重试。")
            return
        }
        guard !videos.isEmpty else { return }

        isDeleting = true
        defer { isDeleting = false }

        do {
            for video in videos {
                try await services.repository.deletePlaylistItem(
                    listCode: playlist.listCode,
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
            toastMessage = .success("已移除 \(removedCodes.count) 个视频")
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

private struct SavedVideoRow: View {
    let title: String
    let videoCode: String
    let coverURLString: String?
    let detail: String

    private var coverURL: URL? {
        guard let coverURLString else { return nil }
        return URL(string: coverURLString)
    }

    var body: some View {
        HanaVideoListRow(
            title: title,
            videoCode: videoCode,
            coverURL: coverURL,
            metadataItems: [
                HanaVideoMetadataItem(videoCode, systemImage: "number"),
                HanaVideoMetadataItem(detail)
            ]
        )
    }
}
