import SwiftUI

struct ProfileDetailScreen: View {
    @Environment(HanaServices.self) private var services
    @State private var isCredentialLoginPresented = false

    var body: some View {
        content
            .navigationTitle("个人资料")
            .sheet(isPresented: $isCredentialLoginPresented) {
                SiteCredentialLoginSheet()
            }
    }

    @ViewBuilder
    private var content: some View {
#if os(macOS)
        macOSContent
#else
        mobileContent
#endif
    }

    private var mobileContent: some View {
        List {
            Section {
                profileHeader
            }

            siteSection

            accountSection
        }
    }

#if os(macOS)
    private var macOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                profileHeader

                Divider()

                Form {
                    siteSection

                    accountSection
                }
                .formStyle(.grouped)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollContentBackground(.visible)
    }
#endif

    private var profileHeader: some View {
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

    private var siteSection: some View {
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
    }

    private var accountSection: some View {
        Section("账号") {
            if services.siteSession.isLoggedIn {
                Button(role: .destructive) {
                    Task { await services.logout() }
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

    private var displayName: String {
        services.siteSession.isLoggedIn ? services.siteSession.displayName : "未登录"
    }

    private var accountStatusText: String {
        if services.siteSession.isLoggedIn {
            return services.siteSession.userID == nil ? "账号资料同步中" : "已登录"
        }
        return "登录后可同步订阅、收藏和账号列表"
    }

    private var avatarURL: URL? {
        services.siteSession.avatarURLString.flatMap(URL.init(string:))
    }
}
