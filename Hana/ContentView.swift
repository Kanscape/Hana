//
//  ContentView.swift
//  Hana
//
//  Created by Kanscape on 2026/5/16.
//

import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HanaSettingsKey.appearanceMode) private var appearanceMode = HanaAppearanceMode.system.rawValue
    @AppStorage(HanaSettingsKey.themeColor) private var themeColor = HanaThemeColor.defaultValue
    @Query(sort: \DownloadQueueRecord.createdAt, order: .reverse) private var downloadQueue: [DownloadQueueRecord]
    @State private var selectedTab: AppTab = .discover

    private var appThemeColor: Color {
        (HanaThemeColor(rawValue: themeColor) ?? .pink).color
    }

    var body: some View {
        @Bindable var siteSession = services.siteSession

        rootContent
        .sheet(item: $siteSession.activeFlow) { flow in
            SiteWebSessionSheet(
                flow: flow,
                onComplete: { cookies in
                    completeSiteWebFlow(with: cookies)
                },
                onCancel: {
                    services.siteSession.cancel()
                }
            )
        }
        .task {
            await refreshLoginStateFromStoredCookies()
            await synchronizeDownloadsAtLaunch()
        }
        .tint(appThemeColor)
        .accentColor(appThemeColor)
        .preferredColorScheme(HanaAppearanceMode(rawValue: appearanceMode)?.colorScheme)
    }

    @ViewBuilder
    private var rootContent: some View {
#if os(macOS)
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: AppTab.discover) {
                    Label("发现", systemImage: "sparkles")
                }
                NavigationLink(value: AppTab.subscriptions) {
                    Label("订阅", systemImage: "play.rectangle.on.rectangle")
                }
                NavigationLink(value: AppTab.favorites) {
                    Label("收藏", systemImage: "heart")
                }
                NavigationLink(value: AppTab.profile) {
                    Label("我的", systemImage: "person.crop.circle")
                }
                NavigationLink(value: AppTab.search) {
                    Label("搜索", systemImage: "magnifyingglass")
                }
            }
            .navigationTitle("Hana")
        } detail: {
            NavigationStack {
                tabContent(for: selectedTab)
                    .navigationDestination(for: HanaRoute.self, destination: destination)
            }
        }
#else
        TabView(selection: $selectedTab) {
            Tab("发现", systemImage: "sparkles", value: AppTab.discover) {
                NavigationStack {
                    HomeScreen()
                        .navigationDestination(for: HanaRoute.self, destination: destination)
                }
            }

            Tab("订阅", systemImage: "play.rectangle.on.rectangle", value: AppTab.subscriptions) {
                NavigationStack {
                    SubscriptionsScreen()
                        .navigationDestination(for: HanaRoute.self, destination: destination)
                }
            }

            Tab("收藏", systemImage: "heart", value: AppTab.favorites) {
                NavigationStack {
                    FavoritesScreen()
                        .navigationDestination(for: HanaRoute.self, destination: destination)
                }
            }

            Tab(value: AppTab.profile) {
                NavigationStack {
                    ProfileScreen()
                        .navigationDestination(for: HanaRoute.self, destination: destination)
                }
            } label: {
                ProfileTabLabel()
            }

            Tab("搜索", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack {
                    SearchScreen()
                        .navigationDestination(for: HanaRoute.self, destination: destination)
                }
            }
        }
        .hanaTabSearchActivation()
#endif
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .discover:
            HomeScreen()
        case .subscriptions:
            SubscriptionsScreen()
        case .favorites:
            FavoritesScreen()
        case .profile:
            ProfileScreen()
        case .search:
            SearchScreen()
        }
    }

    @ViewBuilder
    private func destination(_ route: HanaRoute) -> some View {
        switch route {
        case .video(let code):
            VideoDetailScreen(videoCode: code)
        case .search(let criteria):
            SearchScreen(initialCriteria: criteria)
        case .lockedSearch(let criteria):
            SearchScreen(initialCriteria: criteria, locksQueryEditing: true)
        case .profileDetail:
            ProfileDetailScreen()
        case .watchHistory:
            WatchHistoryScreen()
        case .watchLater:
            WatchLaterScreen()
        case .playlists:
            PlaylistsScreen()
        case .remotePlaylist(let playlist):
            RemotePlaylistDetailScreen(playlist: playlist)
        case .hKeyframes:
            HKeyframeManagementScreen()
        case .downloads:
            DownloadsScreen()
        case .settings:
            SettingsScreen()
        }
    }

    private func completeSiteWebFlow(with cookies: [HTTPCookie]) {
        let kind = services.siteSession.activeFlow?.kind
        services.siteSession.complete(with: cookies)
        if kind == .login {
            Task { await refreshLoginState() }
        }
    }

    private func refreshLoginStateFromStoredCookies() async {
        await services.siteSession.syncDefaultWebCookies()
        guard services.siteSession.hasStoredCookies || services.siteSession.isLoggedIn else {
            services.profileAvatarStore.clear()
            return
        }
        await verifyCurrentUser()
    }

    private func refreshLoginState() async {
        await services.siteSession.syncDefaultWebCookies()
        await verifyCurrentUser()
    }

    private func verifyCurrentUser() async {
        do {
            let user = try await services.repository.currentUser()
            await services.applyLoginState(user: user)
        } catch {
            if services.siteSession.handle(error) {
                return
            }
            await services.applyLoginState(user: nil)
        }
    }

    private func synchronizeDownloadsAtLaunch() async {
        await HanaDownloadRecordSynchronizer.synchronize(
            downloadClient: services.downloadClient,
            modelContext: modelContext,
            records: downloadQueue
        )
    }
}

private struct ProfileTabLabel: View {
    @Environment(HanaServices.self) private var services

    var body: some View {
        Label {
            Text("我的")
        } icon: {
            ProfileTabIcon(imageData: services.profileAvatarStore.imageData)
        }
    }
}

private struct ProfileTabIcon: View {
    let imageData: Data?
    private let side = HanaProfileAvatarStore.tabIconPointSize

    var body: some View {
#if canImport(UIKit)
        if let imageData,
           let image = UIImage(data: imageData, scale: HanaProfileAvatarStore.tabIconImageScale)?.withRenderingMode(.alwaysOriginal) {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: side, height: side)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .frame(width: side, height: side)
        }
#else
        Image(systemName: "person.crop.circle.fill")
            .frame(width: side, height: side)
#endif
    }
}

private enum AppTab: Hashable {
    case discover
    case subscriptions
    case favorites
    case profile
    case search
}

private extension View {
    @ViewBuilder
    func hanaTabSearchActivation() -> some View {
#if os(iOS) || os(macOS)
        tabViewSearchActivation(.searchTabSelection)
#else
        self
#endif
    }
}

#Preview {
    ContentView()
        .environment(HanaServices())
        .modelContainer(
            for: [
                WatchHistoryRecord.self,
                SearchHistoryRecord.self,
                AdvancedSearchHistoryRecord.self,
                FavoriteVideoRecord.self,
                WatchLaterRecord.self,
                PlaylistRecord.self,
                PlaylistItemRecord.self,
                DownloadQueueRecord.self,
                HKeyframeRecord.self,
            ],
            inMemory: true
        )
}
