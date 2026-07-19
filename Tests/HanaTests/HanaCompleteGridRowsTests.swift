import CoreGraphics
import Testing
@testable import Hana

@Suite("Related video grid rows")
struct HanaCompleteGridRowsTests {
    @Test("an incomplete first row remains visible")
    func incompleteFirstRow() {
        #expect(visibleCount(total: 1, width: 312) == 1)
        #expect(visibleCount(total: 2, width: 474) == 2)
    }

    @Test("an incomplete final row is hidden after the first row")
    func incompleteFinalRow() {
        #expect(visibleCount(total: 3, width: 312) == 2)
        #expect(visibleCount(total: 5, width: 312) == 4)
        #expect(visibleCount(total: 4, width: 474) == 3)
        #expect(visibleCount(total: 7, width: 474) == 6)
    }

    @Test("complete rows keep every video")
    func completeRows() {
        #expect(visibleCount(total: 4, width: 312) == 4)
        #expect(visibleCount(total: 6, width: 474) == 6)
    }

    private func visibleCount(total: Int, width: CGFloat) -> Int {
        HanaCompleteGridRows.visibleItemCount(
            totalCount: total,
            availableWidth: width,
            minimumItemWidth: 150,
            spacing: 12
        )
    }
}
