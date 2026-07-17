import Foundation
import Testing

@testable import Hana

@Suite("Related videos parser")
struct HanimeRelatedVideosParserTests {
    @Test("normal related cards preserve metadata")
    func normalRelatedCards() throws {
        let videos = try parseFixture("related-videos-normal")

        #expect(videos.map(\.videoCode) == ["7101", "7102"])
        #expect(videos.map(\.style) == [.normal, .normal])

        let current = try #require(videos.first)
        #expect(current.title == "Current Normal Example")
        #expect(current.coverURL == URL(string: "https://example.invalid/covers/7101.jpg"))
        #expect(current.duration == "12:34")
        #expect(current.views == "1,234 views")
        #expect(current.artist == "Studio A")
        #expect(current.uploadTime == "2026-07-17")

        let legacy = try #require(videos.last)
        #expect(legacy.title == "Legacy Class Example")
        #expect(legacy.duration == "08:15")
        #expect(legacy.views == "567 views")
    }

    @Test("current grid cards preserve metadata and skip ads")
    func currentGridCards() throws {
        let videos = try parseFixture("related-videos-grid")

        #expect(videos.map(\.videoCode) == ["7301", "7302"])
        #expect(videos.map(\.style) == [.normal, .normal])
        let video = try #require(videos.first)
        #expect(video.videoCode == "7301")
        #expect(video.title == "Current Grid Example")
        #expect(video.coverURL == URL(string: "https://example.invalid/covers/7301.jpg"))
        #expect(video.duration == "10:24")
        #expect(video.views == "8,765 views")
        #expect(video.artist == "Studio C")
        #expect(video.uploadTime == "2026-07-15")
    }

    @Test("simplified fallback requires its DOM marker")
    func simplifiedMarkerBoundary() throws {
        let videos = try parseFixture("related-videos-simplified")

        #expect(videos.count == 1)
        let video = try #require(videos.first)
        #expect(video.videoCode == "7201")
        #expect(video.title == "Simplified Example")
        #expect(video.style == .compact)
    }

    private func parseFixture(_ name: String) throws -> [HanimeInfo] {
        let baseURL = try #require(URL(string: "https://example.invalid/"))
        let fixtureURL = try #require(
            Bundle(for: RelatedVideosFixtureBundleToken.self).url(
                forResource: name,
                withExtension: "html"
            )
        )
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        return try HanimeHTMLParser(baseURL: baseURL)
            .parseVideo(html, videoCode: "7000")
            .relatedVideos
    }
}

private final class RelatedVideosFixtureBundleToken {}
