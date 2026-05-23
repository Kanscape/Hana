import SwiftUI

struct ProfileDetailScreen: View {
    @Environment(HanaServices.self) private var services
    @State private var isCredentialLoginPresented = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ProfileAvatarView(url: avatarURL)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayName)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)

                        Text(accountStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("站点") {
                ProfileMetadataLine(
                    systemImage: "link",
                    text: services.siteSession.baseURL.absoluteString
                )
                if let userID = services.siteSession.userID, services.siteSession.isLoggedIn {
                    ProfileMetadataLine(
                        systemImage: "person.text.rectangle",
                        text: userID
                    )
                }
                if let date = services.siteSession.lastCookieSyncAt {
                    LabeledContent("Cookie 同步", value: date.hanaChineseDateTimeText)
                }
            }

            Section("账号") {
                if services.siteSession.isLoggedIn {
                    Button(role: .destructive) {
                        services.logout()
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
                        services.siteSession.requestLogin()
                    } label: {
                        Label("登录站点", systemImage: "person.crop.circle")
                    }

                    Button {
                        isCredentialLoginPresented = true
                    } label: {
                        Label("账号密码登录", systemImage: "key")
                    }
                }
            }
        }
        .navigationTitle("个人资料")
        .sheet(isPresented: $isCredentialLoginPresented) {
            SiteCredentialLoginSheet()
        }
    }

    private var displayName: String {
        services.siteSession.isLoggedIn ? services.siteSession.displayName : "未登录"
    }

    private var accountStatusText: String {
        if let userID = services.siteSession.userID {
            return userID
        }
        if services.siteSession.isLoggedIn {
            return "账号资料同步中"
        }
        return "登录后可同步订阅、收藏和账号列表"
    }

    private var avatarURL: URL? {
        services.siteSession.avatarURLString.flatMap(URL.init(string:))
    }
}
