import Foundation
import Testing

@testable import Hana

@Suite("Home recommendation parser")
struct HanimeHomeParserTests {
    @Test("matches Han1meViewer recommendation keys, titles, and order")
    func referenceRecommendationMapping() throws {
        let page = try parseFixture("home-recommendations-reference")

        #expect(page.sections.map(\.key) == [
            "latest_hanime",
            "latest_release",
            "latest_upload",
            "watching_now",
            "short_episode",
            "motion_anime",
            "3d_cg",
            "2_5d",
            "2d_anime",
            "ai_generated",
            "mmd",
            "cosplay"
        ])
        #expect(page.sections.map(\.title) == [
            "最新里番",
            "最新上市",
            "最新上传",
            "他们在看",
            "泡面番",
            "动态动画",
            "3D作品",
            "2.5D",
            "2D动画",
            "AI生成",
            "MMD",
            "Cosplay"
        ])

        let latestHanime = try #require(page.sections.first)
        #expect(latestHanime.id == "latest_hanime")
        #expect(latestHanime.videos.map(\.videoCode) == ["9000", "1002"])

        let firstVideo = try #require(latestHanime.videos.first)
        #expect(firstVideo.title == "First Ecchi Item")
        #expect(firstVideo.coverURL == URL(string: "https://example.invalid/covers/9000-ecchi.jpg"))
        #expect(firstVideo.duration == "12:34")
        #expect(firstVideo.views == "1,234 views")
        #expect(firstVideo.artist == "Studio A")
        #expect(firstVideo.uploadTime == "2026-07-17")
        #expect(firstVideo.style == .normal)

        let latestRelease = try #require(page.sections.dropFirst().first)
        #expect(latestRelease.videos.map(\.videoCode) == ["9000"])
        #expect(page.sections.flatMap(\.videos).contains { $0.videoCode == "4999" } == false)
        #expect(page.sections.flatMap(\.videos).contains { $0.videoCode == "9999" } == false)
    }

    @Test("compact compatibility keeps reference order and requires marker")
    func compactCompatibility() throws {
        let page = try parseFixture("home-recommendations-compact")

        #expect(page.sections.map(\.key) == ["latest_hanime", "latest_upload"])
        #expect(page.sections[0].videos.map(\.videoCode) == ["2201", "2202"])
        #expect(page.sections[0].videos.allSatisfy { $0.style == .compact })
        #expect(page.sections[1].videos.map(\.videoCode) == ["2101"])
        #expect(page.sections.flatMap(\.videos).contains { $0.videoCode == "2413" } == false)
    }

    @Test("unknown homepage structure is an explicit error")
    func unknownStructure() throws {
        let html = try fixtureHTML("home-recommendations-unknown")
        let parser = try parser()

        #expect(throws: HanimeParseError.self) {
            try parser.parseHome(html)
        }
    }

    private func parseFixture(_ name: String) throws -> HanimeHomePage {
        try parser().parseHome(fixtureHTML(name))
    }

    private func parser() throws -> HanimeHTMLParser {
        HanimeHTMLParser(baseURL: try #require(URL(string: "https://example.invalid/")))
    }

    private func fixtureHTML(_ name: String) throws -> String {
        let fixtureURL = try #require(
            Bundle(for: HomeRecommendationFixtureBundleToken.self).url(
                forResource: name,
                withExtension: "html"
            )
        )
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }
}

private final class HomeRecommendationFixtureBundleToken {}
