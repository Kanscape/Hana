import Foundation
import Testing

@testable import Hana

@Suite("Remote video deduplication")
struct HanimeVideoDeduplicationTests {
    @Test("preserves order and the complete first item")
    func firstItemWins() {
        let first = info(code: "1001", title: "First", duration: "10:00")
        let conflicting = info(code: "1001", title: "Conflicting", duration: "20:00")
        let second = info(code: "1002", title: "Second", duration: "30:00")

        let result = [first, conflicting, second, conflicting].deduplicatedByVideoCode()

        #expect(result.map(\.videoCode) == ["1001", "1002"])
        #expect(result.map(\.title) == ["First", "Second"])
        #expect(result.map(\.duration) == ["10:00", "30:00"])
    }

    @Test("account pagination removes current, next, and cross-page duplicates")
    func accountPagination() {
        let first = info(code: "1001", title: "First")
        let currentConflict = info(code: "1001", title: "Current conflict")
        let nextConflict = info(code: "1001", title: "Next conflict")
        let second = info(code: "1002", title: "Second")
        let nextSecondConflict = info(code: "1002", title: "Next second conflict")

        let current = HanimeAccountVideoList(
            videos: [first, currentConflict],
            description: "Current",
            csrfToken: "old",
            maxPage: 1
        )
        let next = HanimeAccountVideoList(
            videos: [nextConflict, second, nextSecondConflict],
            description: "Next",
            csrfToken: "new",
            maxPage: 3
        )

        let result = current.merging(next)

        #expect(result.videos.map(\.videoCode) == ["1001", "1002"])
        #expect(result.videos.map(\.title) == ["First", "Second"])
        #expect(result.description == "Current")
        #expect(result.csrfToken == "new")
        #expect(result.maxPage == 3)
    }

    @Test("subscription pagination uses the same first-item rule")
    func subscriptionPagination() {
        let first = info(code: "1001", title: "First")
        let conflict = info(code: "1001", title: "Conflict")
        let second = info(code: "1002", title: "Second")
        let current = HanimeSubscriptionsPage(
            artists: [],
            videos: [first, conflict],
            csrfToken: nil,
            maxPage: 1
        )
        let next = HanimeSubscriptionsPage(
            artists: [],
            videos: [conflict, second, second],
            csrfToken: "next",
            maxPage: 2
        )

        let result = current.merging(next)

        #expect(result.videos.map(\.videoCode) == ["1001", "1002"])
        #expect(result.videos.map(\.title) == ["First", "Second"])
        #expect(result.csrfToken == "next")
        #expect(result.maxPage == 2)
    }

    private func info(code: String, title: String, duration: String? = nil) -> HanimeInfo {
        HanimeInfo(
            title: title,
            coverURL: URL(string: "https://example.invalid/covers/\(code).jpg"),
            videoCode: code,
            duration: duration,
            views: nil,
            uploadTime: nil,
            artist: nil,
            style: .normal
        )
    }
}
