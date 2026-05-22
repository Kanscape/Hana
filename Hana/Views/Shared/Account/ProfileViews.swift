import SwiftUI

struct ProfileAccountHeader: View {
    let displayName: String
    let accountStatusIcon: String
    let accountStatusText: String
    let siteText: String
    let avatarURL: URL?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ProfileAvatarView(url: avatarURL)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                ProfileMetadataLine(
                    systemImage: accountStatusIcon,
                    text: accountStatusText,
                    font: .subheadline,
                    lineLimit: 1
                )

                ProfileMetadataLine(
                    systemImage: "link",
                    text: siteText,
                    font: .caption,
                    lineLimit: 2
                )
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
    }
}

struct ProfileMetadataLine: View {
    let systemImage: String
    let text: String
    var font: Font = .subheadline
    var lineLimit: Int = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .font(font)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            Text(text)
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ProfileAvatarView: View {
    let url: URL?

    var body: some View {
        ZStack {
            Circle()
                .fill(.secondary.opacity(0.16))

            CoverView(url: url, fallbackSystemImage: "person.crop.circle.fill")
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }
}
