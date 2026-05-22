import SwiftUI
import UIKit

struct SettingsAppFooter: View {
    private let appInfo = SettingsAppInfo.current

    var body: some View {
        VStack(spacing: 8) {
            if let icon = appInfo.icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.secondary.opacity(0.18), lineWidth: 1)
                    }
            }

            VStack(spacing: 2) {
                Text(appInfo.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(appInfo.versionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsAppInfo {
    let name: String
    let versionText: String
    let icon: UIImage?

    static var current: SettingsAppInfo {
        let bundle = Bundle.main
        let name = bundle.localizedStringValue(for: "CFBundleDisplayName")
            ?? bundle.localizedStringValue(for: "CFBundleName")
            ?? ProcessInfo.processInfo.processName
        let version = bundle.localizedStringValue(for: "CFBundleShortVersionString") ?? ""

        return SettingsAppInfo(
            name: name,
            versionText: version.isEmpty ? "版本未知" : "版本 \(version)",
            icon: primaryIcon(in: bundle)
        )
    }

    private static func primaryIcon(in bundle: Bundle) -> UIImage? {
        guard let icons = bundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconName = iconFiles.last else {
            return nil
        }
        return UIImage(named: iconName)
    }
}

private extension Bundle {
    func localizedStringValue(for key: String) -> String? {
        object(forInfoDictionaryKey: key) as? String
    }
}
