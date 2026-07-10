import Testing
@testable import Hana

@Suite("App build info")
struct AppBuildInfoTests {
    @Test("formats build labels without exposing platform build numbers")
    func displayVersionFormatting() {
        #expect(AppBuildInfo.displayVersion(baseVersion: "1.9.0", buildLabel: "Build 279") == "1.9.0 (Build 279)")
        #expect(AppBuildInfo.displayVersion(baseVersion: "1.9.0", buildLabel: "PR #123") == "1.9.0 (PR #123)")
        #expect(AppBuildInfo.displayVersion(baseVersion: "1.9.0", buildLabel: "feature/foo") == "1.9.0 (feature/foo)")
        #expect(AppBuildInfo.displayVersion(baseVersion: "1.9.0", buildLabel: "Local Build") == "1.9.0 (Local Build)")
    }

    @Test("only official main builds expose telemetry build number")
    func telemetryBuildNumberRules() {
        #expect(AppBuildInfo.telemetryBuildNumber(buildChannel: "main", buildNumber: "279") == "279")
        #expect(AppBuildInfo.telemetryBuildNumber(buildChannel: "pr", buildNumber: "279") == nil)
        #expect(AppBuildInfo.telemetryBuildNumber(buildChannel: "branch", buildNumber: "279") == nil)
        #expect(AppBuildInfo.telemetryBuildNumber(buildChannel: "local", buildNumber: "1") == nil)
    }
}
