import Foundation
import Testing

@testable import Hana

@MainActor
@Suite("Series playlist parser")
struct HanimeSeriesParserTests {
  @Test("new and legacy markup produce equivalent series items")
  func supportedMarkupVariants() throws {
    let newSeries = try #require(
      parseFixture("series-playlist-new", currentVideoCode: "1002").series)
    let legacySeries = try #require(
      parseFixture("series-playlist-legacy", currentVideoCode: "1002").series)

    #expect(newSeries == legacySeries)
    #expect(newSeries.title == "Example Series")
    #expect(newSeries.videos.map(\.videoCode) == ["1001", "1002"])
    #expect(newSeries.currentVideoCode == "1002")
  }

  @Test("legacy cards can use their own anchor href")
  func directLegacyAnchor() throws {
    let series = try #require(
      parseFixture("series-playlist-legacy-direct-anchor", currentVideoCode: "9999").series)
    let video = try #require(series.videos.first)

    #expect(series.videos.count == 1)
    #expect(video.videoCode == "4101")
    #expect(video.title == "Direct Anchor Episode")
    #expect(video.duration == "08:15")
    #expect(video.views == "410 views")
    #expect(video.rating == "91%")
    #expect(video.isCurrent)
  }

  @Test("new markup maps all available metadata")
  func newMarkupMetadata() throws {
    let series = try #require(parseFixture("series-playlist-new", currentVideoCode: "1002").series)
    let first = try #require(series.videos.first)

    #expect(first.title == "Episode One")
    #expect(first.coverURL == URL(string: "https://example.invalid/covers/1001.jpg"))
    #expect(first.duration == "12:34")
    #expect(first.views == "1,234 views")
    #expect(first.rating == "98%")
    #expect(first.author == "Studio A")
    #expect(first.category == "Animation")
    #expect(first.uploadTime == "2026-07-01")
    #expect(!first.isCurrent)
  }

  @Test(
    "DOM markers identify the current item when the detail code is absent",
    arguments: ["series-playlist-new", "series-playlist-legacy"]
  )
  func domCurrentMarkerFallback(fixtureName: String) throws {
    let series = try #require(parseFixture(fixtureName, currentVideoCode: "9999").series)

    #expect(series.currentVideoCode == "1002")
  }

  @Test("the detail code overrides a conflicting DOM marker")
  func detailCodeIsAuthoritative() throws {
    let series = try #require(
      parseFixture("series-playlist-new", currentVideoCode: "1001").series)

    #expect(series.currentVideoCode == "1001")
    #expect(series.videos.filter(\.isCurrent).count == 1)
  }

  @Test("duplicates merge without losing the current item")
  func duplicateAndMalformedItems() throws {
    let series = try #require(
      parseFixture("series-playlist-edge-cases", currentVideoCode: "3001").series)
    let first = try #require(series.videos.first)

    #expect(series.videos.count == 2)
    #expect(series.videos.map(\.videoCode) == ["3001", "3002"])
    #expect(first.title == "First Duplicate")
    #expect(first.coverURL == URL(string: "https://example.invalid/covers/3001.jpg"))
    #expect(first.duration == "09:30")
    #expect(first.rating == "90%")
    #expect(first.author == "Edge Studio")
    #expect(first.isCurrent)
    #expect(series.currentVideoCode == "3001")
  }

  @Test("a page without series still parses")
  func noSeries() throws {
    let video = try parseFixture("video-without-series", currentVideoCode: "9001")

    #expect(video.title == "Standalone Example Video")
    #expect(video.series == nil)
  }

  private func parseFixture(_ name: String, currentVideoCode: String) throws -> HanimeVideo {
    let baseURL = try #require(URL(string: "https://example.invalid/"))
    let fixtureURL = try #require(
      Bundle(for: SeriesFixtureBundleToken.self).url(forResource: name, withExtension: "html")
    )
    let html = try String(contentsOf: fixtureURL, encoding: .utf8)
    return try HanimeHTMLParser(baseURL: baseURL).parseVideo(html, videoCode: currentVideoCode)
  }
}

private final class SeriesFixtureBundleToken {}
