import SwiftData
import SwiftUI

struct ProfileScreen: View {
    @Environment(HanaServices.self) private var services
    @Query(sort: \WatchHistoryRecord.watchDate, order: .reverse) private var watchHistory: [WatchHistoryRecord]
    @Query(sort: \DownloadQueueRecord.createdAt, order: .reverse) private var downloadQueue: [DownloadQueueRecord]
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var hKeyframeRecords: [HKeyframeRecord]

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
                        value: accountValue,
                        systemImage: "text.badge.plus"
                    )
                }

                NavigationLink(value: HanaRoute.playlists) {
                    ProfileNavigationRow(
                        title: "播放清单",
                        value: accountValue,
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

    private var accountValue: String {
        services.siteSession.isLoggedIn ? "已登录" : "需登录"
    }
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
