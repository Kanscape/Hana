import Foundation
import Testing

@testable import Hana

@Suite("Duplicate video parser boundaries")
struct HanimeDuplicateVideoParserTests {
    @Test("all public remote video lists preserve the first code occurrence")
    func publicParserEntries() throws {
        let html = try fixtureHTML()
        let parser = try HanimeHTMLParser(baseURL: #require(URL(string: "https://example.invalid/")))

        let home = try parser.parseHome(html)
        #expect(home.sections.count == 2)
        expectFirstWins(home.sections[0].videos, title: "Home First")
        #expect(home.sections[1].videos.map(\.videoCode) == ["2001", "2002"])
        #expect(home.sections[1].videos.first?.title == "Simplified First")

        expectFirstWins(try parser.parseSearch(html), title: "Search First")
        expectFirstWins(
            try parser.parseVideo(html, videoCode: "9000").relatedVideos,
            title: "Related First"
        )
        expectFirstWins(try parser.parseAccountVideoList(html).videos, title: "Account First")
        expectFirstWins(try parser.parsePlaylistItems(html).videos, title: "Playlist First")
        expectFirstWins(try parser.parseSubscriptions(html).videos, title: "Subscription First")
    }

    private func expectFirstWins(_ videos: [HanimeInfo], title: String) {
        #expect(videos.map(\.videoCode) == ["1001", "1002"])
        #expect(videos.first?.title == title)
    }

    private func fixtureHTML() throws -> String {
        let url = try #require(
            Bundle(for: DuplicateVideoFixtureBundleToken.self).url(
                forResource: "duplicate-video-lists",
                withExtension: "html"
            )
        )
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private final class DuplicateVideoFixtureBundleToken {}
