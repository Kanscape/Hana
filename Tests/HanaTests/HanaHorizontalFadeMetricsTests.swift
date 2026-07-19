import Testing
@testable import Hana

@Suite("Horizontal fade metrics")
struct HanaHorizontalFadeMetricsTests {
    @Test("compact viewports use a shorter and lighter fade")
    func compactViewport() {
        let compact = HanaHorizontalFadeMetrics.resolve(viewportWidth: 375)
        let regular = HanaHorizontalFadeMetrics.resolve(viewportWidth: 720)

        #expect(compact.width == 37.5)
        #expect(compact.width < regular.width)
        #expect(compact.strength < regular.strength)
    }

    @Test("fade dimensions remain within their responsive bounds")
    func responsiveBounds() {
        let narrow = HanaHorizontalFadeMetrics.resolve(viewportWidth: 120)
        let wide = HanaHorizontalFadeMetrics.resolve(viewportWidth: 1_200)

        #expect(narrow.width == 24)
        #expect(narrow.strength == 0.72)
        #expect(wide.width == 72)
        #expect(wide.strength == 1)
    }
}
