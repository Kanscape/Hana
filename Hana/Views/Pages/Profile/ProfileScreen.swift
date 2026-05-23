import SwiftData
import SwiftUI

private enum ProfileAccountSummaryState: Equatable {
    case idle
    case loading
    case loaded(watchLaterCount: Int, playlistCount: Int)
    case unavailable
    case failed
}

struct ProfileScreen: View {
    @Environment(HanaServices.self) private var services
    @Query(sort: \WatchHistoryRecord.watchDate, order: .reverse) private var watchHistory: [WatchHistoryRecord]
    @Query(sort: \DownloadQueueRecord.createdAt, order: .reverse) private var downloadQueue: [DownloadQueueRecord]
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var hKeyframeRecords: [HKeyframeRecord]
    @State private var accountSummaryState: ProfileAccountSummaryState = .idle

    var body: some View {
        List {
            Section {
                NavigationLink(value: HanaRoute.profileDetail) {
                    ProfileAccountHeader(
                        displayName: services.siteSession.isLoggedIn ? services.siteSession.displayName : "未登录",
                        accountStatusIcon: accountStatusIcon,
                        accountStatusText: accountStatusText,
                        siteText: services.siteSession.baseURL.absoluteString,
                        avatarURL: avatarURL
                    )
                }
            }

            Section {
                NavigationLink(value: HanaRoute.watchHistory) {
                    ProfileNavigationRow(
                        title: "观看记录",
                        value: "\(visibleWatchHistoryCount)",
                        systemImage: "clock.arrow.circlepath"
                    )
                }

                NavigationLink(value: HanaRoute.watchLater) {
                    ProfileNavigationRow(
                        title: "稍后观看",
                        value: watchLaterValue,
                        systemImage: "text.badge.plus"
                    )
                }

                NavigationLink(value: HanaRoute.playlists) {
                    ProfileNavigationRow(
                        title: "播放清单",
                        value: playlistValue,
                        systemImage: "list.bullet.rectangle"
                    )
                }

                NavigationLink(value: HanaRoute.hKeyframes) {
                    ProfileNavigationRow(
                        title: "HKeyframes",
                        value: "\(hKeyframeRecords.count)",
                        systemImage: "bookmark"
                    )
                }

                NavigationLink(value: HanaRoute.downloads) {
                    ProfileNavigationRow(
                        title: "已下载的视频",
                        value: "\(downloadQueue.count)",
                        systemImage: "arrow.down.circle"
                    )
                }
            }

            Section {
                NavigationLink(value: HanaRoute.settings) {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("我的")
        .task(id: accountSummaryTaskID) {
            await loadAccountSummary()
        }
    }

    private var accountSummaryTaskID: String {
        let syncTime = services.siteSession.lastCookieSyncAt?.timeIntervalSince1970 ?? 0
        return "\(services.siteSession.isLoggedIn)-\(services.siteSession.userID ?? "")-\(syncTime)"
    }

    private var accountStatusText: String {
        if let userID = services.siteSession.userID, services.siteSession.isLoggedIn {
            return userID
        }
        return "登录后可同步订阅、收藏和账号列表"
    }

    private var accountStatusIcon: String {
        services.siteSession.isLoggedIn ? "person.text.rectangle" : "person.crop.circle.badge.exclamationmark"
    }

    private var avatarURL: URL? {
        services.siteSession.avatarURLString.flatMap(URL.init(string:))
    }

    private var visibleWatchHistoryCount: Int {
        watchHistory.filter(\.isHistoryEligible).count
    }

    private var watchLaterValue: String {
        accountSummaryValue(\.watchLaterCount)
    }

    private var playlistValue: String {
        accountSummaryValue(\.playlistCount)
    }

    private func accountSummaryValue(_ keyPath: KeyPath<ProfileLoadedAccountSummary, Int>) -> String {
        switch accountSummaryState {
        case .loaded(let watchLaterCount, let playlistCount):
            let summary = ProfileLoadedAccountSummary(
                watchLaterCount: watchLaterCount,
                playlistCount: playlistCount
            )
            return "\(summary[keyPath: keyPath])"
        case .idle, .loading:
            return services.siteSession.isLoggedIn ? "加载中" : "—"
        case .unavailable, .failed:
            return "—"
        }
    }

    private func loadAccountSummary() async {
        guard services.siteSession.isLoggedIn else {
            accountSummaryState = .unavailable
            return
        }
        guard let userID = services.siteSession.userID else {
            accountSummaryState = .unavailable
            return
        }

        if shouldShowInitialAccountSummaryLoading {
            accountSummaryState = .loading
        }
        do {
            let watchLaterCount = try await loadAccountVideoCount(kind: .watchLater, userID: userID)
            let playlistCount = try await loadPlaylistCount(userID: userID)
            accountSummaryState = .loaded(watchLaterCount: watchLaterCount, playlistCount: playlistCount)
        } catch is CancellationError {
            return
        } catch {
            _ = services.siteSession.handle(error)
            if shouldShowAccountSummaryFailure {
                accountSummaryState = .failed
            }
        }
    }

    private var shouldShowAccountSummaryFailure: Bool {
        switch accountSummaryState {
        case .loaded:
            false
        case .idle, .loading, .unavailable, .failed:
            true
        }
    }

    private var shouldShowInitialAccountSummaryLoading: Bool {
        switch accountSummaryState {
        case .loaded:
            false
        case .idle, .loading, .unavailable, .failed:
            true
        }
    }

    private func loadAccountVideoCount(kind: HanimeMyListKind, userID: String) async throws -> Int {
        let firstPage = try await services.repository.accountVideos(kind: kind, userID: userID, page: 1)
        guard firstPage.maxPage > 1 else { return firstPage.videos.count }

        var count = firstPage.videos.count
        for page in 2...firstPage.maxPage {
            let nextPage = try await services.repository.accountVideos(kind: kind, userID: userID, page: page)
            count += nextPage.videos.count
        }
        return count
    }

    private func loadPlaylistCount(userID: String) async throws -> Int {
        let firstPage = try await services.repository.playlists(userID: userID, page: 1)
        guard firstPage.maxPage > 1 else { return firstPage.playlists.count }

        var count = firstPage.playlists.count
        for page in 2...firstPage.maxPage {
            let nextPage = try await services.repository.playlists(userID: userID, page: page)
            count += nextPage.playlists.count
        }
        return count
    }
}

private struct ProfileLoadedAccountSummary {
    let watchLaterCount: Int
    let playlistCount: Int
}

private struct ProfileNavigationRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
