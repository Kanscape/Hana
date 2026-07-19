import SwiftUI

struct HanaHorizontalFadingScrollView<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let showsIndicators: Bool
    private let maximumFadeWidth: CGFloat
    private let contentLeadingPadding: CGFloat
    private let contentTrailingPadding: CGFloat
    private let content: Content

    @State private var edgeState = HanaHorizontalScrollEdgeState(
        leadingOpacity: 0,
        trailingOpacity: 0,
        fadeWidth: 0,
        offsetX: 0
    )
    @State private var lastScrollSample: HanaHorizontalScrollSample?

    init(
        showsIndicators: Bool = false,
        maximumFadeWidth: CGFloat = 72,
        contentLeadingPadding: CGFloat = 0,
        contentTrailingPadding: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.showsIndicators = showsIndicators
        self.maximumFadeWidth = maximumFadeWidth
        self.contentLeadingPadding = contentLeadingPadding
        self.contentTrailingPadding = contentTrailingPadding
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: showsIndicators) {
            content
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, contentLeadingPadding)
                .padding(.trailing, contentTrailingPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onScrollGeometryChange(for: HanaHorizontalScrollEdgeState.self) { geometry in
            let metrics = HanaHorizontalFadeMetrics.resolve(
                viewportWidth: geometry.visibleRect.width,
                maximumWidth: maximumFadeWidth
            )

            return HanaHorizontalScrollEdgeState(
                leadingOpacity: edgeOpacity(
                    for: geometry.visibleRect.minX,
                    metrics: metrics
                ),
                trailingOpacity: edgeOpacity(
                    for: geometry.contentSize.width - geometry.visibleRect.maxX,
                    metrics: metrics
                ),
                fadeWidth: metrics.width,
                offsetX: geometry.visibleRect.minX
            )
        } action: { _, newValue in
            updateEdgeState(newValue)
        }
        .clipped()
        .mask {
            HanaHorizontalFadeMask(
                leadingOpacity: edgeState.leadingOpacity,
                trailingOpacity: edgeState.trailingOpacity,
                fadeWidth: edgeState.fadeWidth
            )
        }
    }

    private func edgeOpacity(
        for distance: CGFloat,
        metrics: HanaHorizontalFadeMetrics
    ) -> CGFloat {
        min(max(distance / max(metrics.width, 1), 0), 1) * metrics.strength
    }

    private func updateEdgeState(_ newValue: HanaHorizontalScrollEdgeState) {
        let now = Date.timeIntervalSinceReferenceDate
        let speed = scrollSpeed(to: newValue.offsetX, at: now)
        lastScrollSample = HanaHorizontalScrollSample(offsetX: newValue.offsetX, timestamp: now)

        if reduceMotion {
            edgeState = newValue
        } else {
            withAnimation(fadeAnimation(forSpeed: speed)) {
                edgeState = newValue
            }
        }
    }

    private func scrollSpeed(to offsetX: CGFloat, at timestamp: TimeInterval) -> CGFloat {
        guard let lastScrollSample else { return 0 }
        let elapsed = timestamp - lastScrollSample.timestamp
        guard elapsed > 0 else { return 0 }
        return abs(offsetX - lastScrollSample.offsetX) / CGFloat(elapsed)
    }

    private func fadeAnimation(forSpeed speed: CGFloat) -> Animation {
        if speed > 1_200 {
            .easeOut(duration: 0.08)
        } else if speed > 400 {
            .easeOut(duration: 0.14)
        } else {
            .easeOut(duration: 0.22)
        }
    }
}

struct HanaHorizontalFadeMetrics: Equatable {
    let width: CGFloat
    let strength: CGFloat

    static func resolve(
        viewportWidth: CGFloat,
        maximumWidth: CGFloat = 72
    ) -> HanaHorizontalFadeMetrics {
        let maximumWidth = max(maximumWidth, 1)
        let minimumWidth = min(maximumWidth, 24)
        let width = min(max(viewportWidth * 0.1, minimumWidth), maximumWidth)
        let widthProgress = maximumWidth > minimumWidth
            ? (width - minimumWidth) / (maximumWidth - minimumWidth)
            : 1

        return HanaHorizontalFadeMetrics(
            width: width,
            strength: 0.72 + widthProgress * 0.28
        )
    }
}

private struct HanaHorizontalFadeMask: View {
    let leadingOpacity: CGFloat
    let trailingOpacity: CGFloat
    let fadeWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let resolvedFadeWidth = min(fadeWidth, proxy.size.width / 2)

            HStack(spacing: 0) {
                leadingMask
                    .frame(width: resolvedFadeWidth)
                Rectangle()
                    .fill(.black)
                trailingMask
                    .frame(width: resolvedFadeWidth)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var leadingMask: some View {
        LinearGradient(
            gradient: fadeGradient(edgeOpacity: leadingOpacity),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var trailingMask: some View {
        LinearGradient(
            gradient: fadeGradient(edgeOpacity: trailingOpacity),
            startPoint: .trailing,
            endPoint: .leading
        )
    }

    private func fadeGradient(edgeOpacity: CGFloat) -> Gradient {
        let opacity = resolvedOpacity(edgeOpacity)
        let curve: [(location: CGFloat, visibility: CGFloat)] = [
            (0, 0),
            (0.2, 0.104),
            (0.4, 0.352),
            (0.6, 0.648),
            (0.8, 0.896),
            (1, 1),
        ]

        return Gradient(stops: curve.map { point in
            Gradient.Stop(
                color: .black.opacity(Double(1 - opacity * (1 - point.visibility))),
                location: point.location
            )
        })
    }

    private func resolvedOpacity(_ opacity: CGFloat) -> CGFloat {
        min(max(opacity, 0), 1)
    }
}

private struct HanaHorizontalScrollEdgeState: Equatable {
    let leadingOpacity: CGFloat
    let trailingOpacity: CGFloat
    let fadeWidth: CGFloat
    let offsetX: CGFloat
}

private struct HanaHorizontalScrollSample {
    let offsetX: CGFloat
    let timestamp: TimeInterval
}
