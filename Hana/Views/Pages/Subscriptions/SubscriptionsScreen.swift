import AVKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SubscriptionsScreen: View {
    @Environment(HanaServices.self) private var services
    @State private var state: LoadableState<HanimeSubscriptionsPage> = .idle
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var filterText = ""
    @State private var sort = AccountVideoListSort.siteOrder
    @State private var isSelectionMode = false
    @State private var selectedArtistIDs = Set<String>()
    @State private var isUnsubscribing = false
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?

    var body: some View {
        Group {
            if services.siteSession.isLoggedIn {
                content
            } else {
                LoginRequiredView(
                    title: "需要登录",
                    message: "登录后可查看订阅的作者和更新。",
                    actionTitle: "登录站点",
                    action: openLogin
                )
            }
        }
        .navigationTitle("订阅")
        .searchable(text: $filterText, prompt: "筛选订阅")
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .toolbar {
            if services.siteSession.isLoggedIn {
                ToolbarItemGroup(placement: .primaryAction) {
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

                    Button {
                        isSelectionMode.toggle()
                        if !isSelectionMode {
                            selectedArtistIDs.removeAll()
                        }
                    } label: {
                        Label(isSelectionMode ? "完成" : "管理", systemImage: "checklist")
                    }

                }
            }
        }
        .task {
            if services.siteSession.isLoggedIn, case .idle = state {
                await loadSubscriptions(page: 1, append: false)
            }
        }
        .onChange(of: services.siteSession.lastCookieSyncAt) {
            if services.siteSession.isLoggedIn {
                Task { await loadSubscriptions(page: 1, append: false) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("加载订阅")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let page):
            let artists = visibleArtists(from: page)
            let videos = visibleVideos(from: page)
            if page.artists.isEmpty, page.videos.isEmpty {
                ContentUnavailableView("订阅暂无内容", systemImage: "rectangle.stack.badge.play")
            } else if artists.isEmpty, videos.isEmpty {
                ContentUnavailableView("没有符合条件的订阅", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                List {
                    if !artists.isEmpty {
                        Section("订阅作者") {
                            if isSelectionMode {
                                HStack {
                                    let visibleArtistIDs = Set(artists.map(\.id))
                                    let isAllVisibleSelected = !visibleArtistIDs.isEmpty
                                        && visibleArtistIDs.isSubset(of: selectedArtistIDs)

                                    Button(isAllVisibleSelected ? "取消全选" : "全选") {
                                        if isAllVisibleSelected {
                                            selectedArtistIDs.subtract(visibleArtistIDs)
                                        } else {
                                            selectedArtistIDs.formUnion(visibleArtistIDs)
                                        }
                                    }
                                    .disabled(artists.isEmpty)

                                    Spacer()

                                    Button(role: .destructive) {
                                        Task { await unsubscribeSelectedArtists(from: page) }
                                    } label: {
                                        Text("取消订阅")
                                    }
                                    .disabled(isUnsubscribing || selectedArtistIDs.isEmpty)
                                }
                                .buttonStyle(.borderless)
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(artists) { artist in
                                        if isSelectionMode {
                                            Button {
                                                toggleArtistSelection(artist)
                                            } label: {
                                                SubscriptionArtistPill(
                                                    artist: artist,
                                                    isSelected: selectedArtistIDs.contains(artist.id),
                                                    showsManagementState: true
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(isUnsubscribing)
                                            .onAppear {
                                                preloadNextSubscriptionsPageIfNeeded(
                                                    after: artist,
                                                    in: artists,
                                                    maxPage: page.maxPage
                                                )
                                            }
                                        } else {
                                            NavigationLink(value: HanaRoute.lockedSearch(.artist(name: artist.name, genre: nil))) {
                                                SubscriptionArtistPill(
                                                    artist: artist,
                                                    isSelected: false,
                                                    showsManagementState: false
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .onAppear {
                                                preloadNextSubscriptionsPageIfNeeded(
                                                    after: artist,
                                                    in: artists,
                                                    maxPage: page.maxPage
                                                )
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if !videos.isEmpty {
                        Section("更新") {
                            let portraitVideos = videos.filter { $0.style == .compact }
                            let normalVideos = videos.filter { $0.style == .normal }

                            if !portraitVideos.isEmpty {
                                HanaVideoGridLinks(videos: portraitVideos) { video in
                                    preloadNextSubscriptionsPageIfNeeded(after: video, in: videos, maxPage: page.maxPage)
                                }
                                    .padding(.vertical, 4)
                                    .listRowSeparator(.hidden)
                            }

                            ForEach(normalVideos) { video in
                                NavigationLink(value: HanaRoute.video(video.videoCode)) {
                                    HanaVideoListRow(info: video)
                                }
                                .onAppear {
                                    preloadNextSubscriptionsPageIfNeeded(after: video, in: videos, maxPage: page.maxPage)
                                }
                            }
                        }
                    }

                    if currentPage < page.maxPage {
                        Section {
                            HanaInfiniteScrollTrigger(
                                isActive: true,
                                isLoading: isLoadingMore
                            ) {
                                loadNextSubscriptionsPageIfNeeded(maxPage: page.maxPage)
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label(message, systemImage: "exclamationmark.triangle")
            } actions: {
                Button("重试") {
                    Task { await loadSubscriptions(page: 1, append: false) }
                }
            }
        }
    }

    private func openLogin() {
        services.siteSession.requestLogin()
    }

    private func visibleArtists(from page: HanimeSubscriptionsPage) -> [HanimeSubscriptionArtist] {
        let filter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return page.artists }
        return page.artists.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private func visibleVideos(from page: HanimeSubscriptionsPage) -> [HanimeInfo] {
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

    private func toggleArtistSelection(_ artist: HanimeSubscriptionArtist) {
        guard isSelectionMode else { return }
        if selectedArtistIDs.contains(artist.id) {
            selectedArtistIDs.remove(artist.id)
        } else {
            selectedArtistIDs.insert(artist.id)
        }
    }

    private func unsubscribeSelectedArtists(from page: HanimeSubscriptionsPage) async {
        let selectedArtists = page.artists.filter { selectedArtistIDs.contains($0.id) }
        guard !selectedArtists.isEmpty else { return }
        isUnsubscribing = true
        defer { isUnsubscribing = false }

        do {
            for artist in selectedArtists {
                let form = try await subscriptionForm(for: artist, pageCSRFToken: page.csrfToken)
                try await services.repository.setArtistSubscribed(
                    userID: form.userID,
                    artistID: form.artistID,
                    shouldSubscribe: false,
                    csrfToken: form.csrfToken
                )
            }
            let removedIDs = Set(selectedArtists.map(\.id))
            state = .loaded(HanimeSubscriptionsPage(
                artists: page.artists.filter { !removedIDs.contains($0.id) },
                videos: page.videos,
                csrfToken: page.csrfToken,
                maxPage: page.maxPage
            ))
            selectedArtistIDs.subtract(removedIDs)
            toastMessage = .success("已取消 \(removedIDs.count) 个订阅")
        } catch {
            if services.siteSession.handle(error) {
                alertMessage = .error("需要 Cloudflare 验证")
            } else {
                alertMessage = .error(error.localizedDescription)
            }
        }
    }

    private func subscriptionForm(
        for artist: HanimeSubscriptionArtist,
        pageCSRFToken: String?
    ) async throws -> (userID: String, artistID: String, csrfToken: String?) {
        if let userID = artist.userID, let artistID = artist.artistID {
            return (userID, artistID, pageCSRFToken)
        }

        let results = try await services.repository.search(criteria: .artist(name: artist.name, genre: nil), page: 1)
        let exactMatches = results.filter { $0.artist?.localizedCaseInsensitiveCompare(artist.name) == .orderedSame }
        let candidates = exactMatches + results.filter { !exactMatches.contains($0) }

        for candidate in candidates.prefix(6) {
            let video = try await services.repository.video(code: candidate.videoCode)
            guard let videoArtist = video.artist,
                  videoArtist.name.localizedCaseInsensitiveCompare(artist.name) == .orderedSame,
                  let subscription = videoArtist.subscription else {
                continue
            }
            return (subscription.userID, subscription.artistID, video.csrfToken ?? pageCSRFToken)
        }

        throw HanimeParseError.missingRequiredField("\(artist.name) 的订阅表单")
    }

    private func loadSubscriptions(page: Int, append: Bool) async {
        if append {
            guard !isLoadingMore else { return }
            isLoadingMore = true
        } else {
            state = .loading
            selectedArtistIDs.removeAll()
        }
        defer { isLoadingMore = false }

        do {
            let newPage = try await services.repository.subscriptions(page: page)
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

    private func loadNextSubscriptionsPageIfNeeded(maxPage: Int) {
        guard currentPage < maxPage, !isLoadingMore else { return }
        Task { await loadSubscriptions(page: currentPage + 1, append: true) }
    }

    private func preloadNextSubscriptionsPageIfNeeded(
        after artist: HanimeSubscriptionArtist,
        in artists: [HanimeSubscriptionArtist],
        maxPage: Int
    ) {
        guard HanaInfiniteScrollPreload.shouldLoadNextPage(
            currentID: artist.id,
            orderedIDs: artists.map(\.id)
        ) else {
            return
        }
        loadNextSubscriptionsPageIfNeeded(maxPage: maxPage)
    }

    private func preloadNextSubscriptionsPageIfNeeded(after video: HanimeInfo, in videos: [HanimeInfo], maxPage: Int) {
        guard HanaInfiniteScrollPreload.shouldLoadNextPage(
            currentID: video.videoCode,
            orderedIDs: videos.map(\.videoCode)
        ) else {
            return
        }
        loadNextSubscriptionsPageIfNeeded(maxPage: maxPage)
    }
}
