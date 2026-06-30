import Foundation

enum AppBuildInfo {
    private static let defaultBuildChannel = "local"
    private static let defaultBuildLabel = "Local Build"

    static var buildChannel: String {
        bundleString(for: "HanaBuildChannel") ?? defaultBuildChannel
    }

    static var buildLabel: String {
        bundleString(for: "HanaBuildLabel") ?? defaultBuildLabel
    }

    static var isLocalBuild: Bool {
        buildChannel == "local"
    }

    static var isOfficialBuild: Bool {
        buildChannel == "main"
    }

    static func displayVersion(baseVersion: String) -> String {
        displayVersion(baseVersion: baseVersion, buildLabel: buildLabel)
    }

    static func displayVersion(baseVersion: String, buildLabel: String) -> String {
        let normalizedVersion = baseVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedVersion.isEmpty {
            return ""
        }

        let normalizedLabel = buildLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedLabel.isEmpty {
            return normalizedVersion
        }
        return "\(normalizedVersion) (\(normalizedLabel))"
    }

    static func telemetryBuildNumber(buildNumber: String?) -> String? {
        telemetryBuildNumber(buildChannel: buildChannel, buildNumber: buildNumber)
    }

    static func telemetryBuildNumber(buildChannel: String, buildNumber: String?) -> String? {
        guard buildChannel == "main" else {
            return nil
        }

        let normalizedBuildNumber = buildNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalizedBuildNumber.isEmpty {
            return nil
        }
        return normalizedBuildNumber
    }

    private static func bundleString(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
