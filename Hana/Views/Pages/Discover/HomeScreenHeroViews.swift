import SwiftUI

#if canImport(UIKit)
import UIKit
private let homeHeroSystemBackground = Color(uiColor: .systemBackground)
#elseif canImport(AppKit)
import AppKit
private let homeHeroSystemBackground = Color(nsColor: .windowBackgroundColor)
#else
private let homeHeroSystemBackground = Color.white
#endif

enum HomeHeroMetrics {
    static func heroHeight(width: CGFloat, viewportHeight: CGFloat, safeAreaTop: CGFloat) -> CGFloat {
        let aspectHeight = width * 9.0 / 16.0 + safeAreaTop
        let minimum = min(max(viewportHeight * 0.38, 300), 420)
        let maximum = min(max(viewportHeight * 0.56, 360), 660)
        return min(max(aspectHeight, minimum), maximum)
    }

    static func contentLayout(
        width: CGFloat,
        viewportHeight: CGFloat,
        safeAreaTop: CGFloat
    ) -> HomeContentLayoutMetrics {
        let availableHeight = max(viewportHeight - safeAreaTop, 1)
        let widthBasedBand = min(max(width * 0.20, 150), 280)
        let heightBasedBand = min(max(availableHeight * 0.19, 132), 260)
        let widthBasedOverlap = min(max(width * 0.065, 32), 76)
        let heightBasedOverlap = min(max(availableHeight * 0.06, 30), 72)

        return HomeContentLayoutMetrics(
            transitionBand: min(widthBasedBand, heightBasedBand),
            overlap: min(widthBasedOverlap, heightBasedOverlap),
            foregroundBottomPadding: min(max(availableHeight * 0.035, 24), 42),
            surfaceTopPadding: min(max(availableHeight * 0.026, 18), 32),
            surfaceBottomPadding: min(max(availableHeight * 0.032, 24), 42),
            sectionSpacing: min(max(availableHeight * 0.024, 18), 28),
            sectionTitleSpacing: min(max(availableHeight * 0.012, 9), 14),
            railSpacing: min(max(width * 0.012, 10), 14)
        )
    }

    static func collapseDistance(width: CGFloat) -> CGFloat {
        min(max(width * 0.36, 300), 380)
    }

    static func foregroundWidth(width: CGFloat) -> CGFloat {
        min(max(width - 40, 280), 560)
    }

    static func foregroundHorizontalPadding(width: CGFloat) -> CGFloat {
        min(max(width * 0.05, 20), 44)
    }
}

struct HomeContentLayoutMetrics {
    let transitionBand: CGFloat
    let overlap: CGFloat
    let foregroundBottomPadding: CGFloat
    let surfaceTopPadding: CGFloat
    let surfaceBottomPadding: CGFloat
    let sectionSpacing: CGFloat
    let sectionTitleSpacing: CGFloat
    let railSpacing: CGFloat
}

struct HomeHeroContentTransition: View {
    let banner: HanimeBanner
    let sections: [HanimeHomeSection]
    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollY: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let safeAreaTop = proxy.safeAreaInsets.top
            let heroHeight = HomeHeroMetrics.heroHeight(
                width: width,
                viewportHeight: proxy.size.height,
                safeAreaTop: safeAreaTop
            )
            let contentLayout = HomeHeroMetrics.contentLayout(
                width: width,
                viewportHeight: proxy.size.height,
                safeAreaTop: safeAreaTop
            )
            let overlap = contentLayout.overlap
            let transitionBand = contentLayout.transitionBand
            let progress = progress(for: scrollY, width: width)
            let contentLift = transitionBand + overlap

            ScrollView {
                VStack(spacing: 0) {
                    HomeHeroBackgroundLayer(
                        banner: banner,
                        width: width,
                        heroHeight: heroHeight,
                        transitionBand: transitionBand,
                        overlap: overlap,
                        scrollY: scrollY,
                        progress: progress,
                        colorScheme: colorScheme,
                        safeAreaTop: safeAreaTop,
                        foregroundBottomPadding: contentLayout.foregroundBottomPadding
                    )
                    .zIndex(0)

                    HomeContentSurface(
                        sections: sections,
                        progress: progress,
                        width: width,
                        contentLayout: contentLayout
                    )
                    .offset(y: -contentLift)
                    .padding(.bottom, -contentLift)
                    .zIndex(1)
                }
            }
            .hanaHomeTopScrollEdgeSoft()
            .scrollIndicators(.hidden)
            .background(pageBackground)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                let roundedValue = (newValue * 2).rounded() / 2
                if abs(roundedValue - scrollY) >= 0.5 {
                    scrollY = roundedValue
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(pageBackground)
    }

    private var pageBackground: Color {
        colorScheme == .dark ? .black : homeHeroSystemBackground
    }

    private func progress(for scrollY: CGFloat, width: CGFloat) -> CGFloat {
        let distance = HomeHeroMetrics.collapseDistance(width: width)
        return min(max(scrollY / distance, 0), 1)
    }
}

private struct HomeHeroBackgroundLayer: View {
    let banner: HanimeBanner
    let width: CGFloat
    let heroHeight: CGFloat
    let transitionBand: CGFloat
    let overlap: CGFloat
    let scrollY: CGFloat
    let progress: CGFloat
    let colorScheme: ColorScheme
    let safeAreaTop: CGFloat
    let foregroundBottomPadding: CGFloat

    private var totalHeight: CGFloat {
        heroHeight + transitionBand
    }

    private var pullDistance: CGFloat {
        max(-scrollY, 0)
    }

    private var parallaxOffset: CGFloat {
        scrollY > 0 ? -scrollY * 0.28 : 0
    }

    private var dimOpacity: CGFloat {
        if colorScheme == .dark {
            return 0.18 + progress * 0.42
        }
        return 0.06 + progress * 0.20
    }

    var body: some View {
        let pullDistance = pullDistance
        let parallaxOffset = parallaxOffset
        let stretchedHeight = totalHeight + pullDistance
        let blurRadius = progress * 10
        let horizontalPadding = HomeHeroMetrics.foregroundHorizontalPadding(width: width)
        let foregroundAreaTop = safeAreaTop + 56
        let foregroundAreaHeight = max(
            heroHeight - overlap - foregroundBottomPadding - foregroundAreaTop,
            72
        )
        let foregroundStyle = HomeHeroForegroundStyle.preferred(for: foregroundAreaHeight)

        ZStack(alignment: .topLeading) {
            HomeHeroBannerBackground(
                banner: banner,
                width: width,
                stretchedHeight: stretchedHeight,
                parallaxOffset: parallaxOffset,
                blurRadius: blurRadius,
                dimOpacity: dimOpacity,
                edgeGradient: edgeGradient
            )

            HomeHeroForeground(
                banner: banner,
                width: HomeHeroMetrics.foregroundWidth(width: width),
                style: foregroundStyle
            )
            .frame(
                width: width - horizontalPadding * 2,
                height: foregroundAreaHeight,
                alignment: .leading
            )
            .padding(.top, foregroundAreaTop)
            .padding(.horizontal, horizontalPadding)
            .opacity(1 - progress * 0.82)
            .offset(y: -progress * 20)
        }
        .frame(width: width, height: stretchedHeight, alignment: .top)
        .homeHeroBannerMacOSLayerClipping()
        .offset(y: -pullDistance)
    }

    private var edgeGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .clear, location: 0.42),
                    .init(color: .black.opacity(0.24), location: 0.62),
                    .init(color: .black.opacity(0.68), location: 0.82),
                    .init(color: .black, location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0.00),
                .init(color: .clear, location: 0.44),
                .init(color: .white.opacity(0.18), location: 0.64),
                .init(color: .white.opacity(0.72), location: 0.86),
                .init(color: homeHeroSystemBackground, location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct HomeHeroBannerBackground: View {
    let banner: HanimeBanner
    let width: CGFloat
    let stretchedHeight: CGFloat
    let parallaxOffset: CGFloat
    let blurRadius: CGFloat
    let dimOpacity: CGFloat
    let edgeGradient: LinearGradient

    var body: some View {
        ZStack(alignment: .topLeading) {
            CoverView(
                url: banner.coverURL,
                contentMode: .fill,
                alignment: .top,
                placeholderCornerRadius: 0
            )
            .frame(width: width, height: stretchedHeight)
            .visualEffect { effect, _ in
                effect
                    .offset(y: parallaxOffset)
                    .blur(radius: blurRadius)
            }

            Rectangle()
                .fill(.black.opacity(dimOpacity))

            Rectangle()
                .fill(edgeGradient)
                .frame(height: stretchedHeight)
        }
        .frame(width: width, height: stretchedHeight, alignment: .top)
        .clipped()
        .homeHeroBannerMacOSBackgroundExtension()
    }
}

private struct HomeHeroForeground: View {
    let banner: HanimeBanner
    let width: CGFloat
    let style: HomeHeroForegroundStyle

    var body: some View {
        HomeHeroForegroundLayout(
            banner: banner,
            width: width,
            style: style
        )
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

private struct HomeHeroForegroundLayout: View {
    let banner: HanimeBanner
    let width: CGFloat
    let style: HomeHeroForegroundStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.spacing) {
            Text(banner.title)
                .font(style.titleFont)
                .foregroundStyle(.white)
                .lineLimit(style.titleLineLimit)
                .minimumScaleFactor(style.titleMinimumScale)
                .allowsTightening(true)
                .shadow(color: .black.opacity(0.62), radius: 12, y: 2)

            if style.showsDescription, let description = banner.description {
                Text(description)
                    .font(style.descriptionFont)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(style.descriptionLineLimit)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .shadow(color: .black.opacity(0.50), radius: 8, y: 2)
            }

            if let code = banner.videoCode {
                NavigationLink(value: HanaRoute.video(code)) {
                    Label("播放", systemImage: "play.fill")
                        .font(style.buttonFont)
                        .padding(.horizontal, style.buttonHorizontalPadding)
                        .padding(.vertical, style.buttonVerticalPadding)
                        .background(.white.opacity(0.92), in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

private enum HomeHeroForegroundStyle {
    case regular
    case compact
    case minimal

    static func preferred(for availableHeight: CGFloat) -> HomeHeroForegroundStyle {
        if availableHeight >= 178 {
            return .regular
        }
        if availableHeight >= 112 {
            return .compact
        }
        return .minimal
    }

    var titleFont: Font {
        switch self {
        case .regular:
            return .title.weight(.bold)
        case .compact:
            return .title3.weight(.bold)
        case .minimal:
            return .headline.weight(.bold)
        }
    }

    var titleLineLimit: Int {
        switch self {
        case .regular, .compact:
            return 2
        case .minimal:
            return 1
        }
    }

    var titleMinimumScale: CGFloat {
        switch self {
        case .regular:
            return 0.82
        case .compact:
            return 0.78
        case .minimal:
            return 0.70
        }
    }

    var showsDescription: Bool {
        return self != .minimal
    }

    var descriptionFont: Font {
        switch self {
        case .regular:
            return .subheadline
        case .compact:
            return .caption
        case .minimal:
            return .caption2
        }
    }

    var descriptionLineLimit: Int {
        switch self {
        case .regular:
            return 2
        case .compact, .minimal:
            return 1
        }
    }

    var buttonFont: Font {
        switch self {
        case .regular:
            return .headline.weight(.semibold)
        case .compact:
            return .subheadline.weight(.semibold)
        case .minimal:
            return .caption.weight(.semibold)
        }
    }

    var spacing: CGFloat {
        switch self {
        case .regular:
            return 14
        case .compact:
            return 10
        case .minimal:
            return 7
        }
    }

    var buttonHorizontalPadding: CGFloat {
        switch self {
        case .regular:
            return 17
        case .compact:
            return 14
        case .minimal:
            return 11
        }
    }

    var buttonVerticalPadding: CGFloat {
        switch self {
        case .regular:
            return 11
        case .compact:
            return 8
        case .minimal:
            return 6
        }
    }
}

private struct HomeContentSurface: View {
    let sections: [HanimeHomeSection]
    let progress: CGFloat
    let width: CGFloat
    let contentLayout: HomeContentLayoutMetrics

    private var cornerRadius: CGFloat {
        let start = min(max(width * 0.04, 28), 42)
        let end: CGFloat = 0
        return start - (start - end) * progress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSectionsView(
                sections: sections,
                sectionSpacing: contentLayout.sectionSpacing,
                sectionTitleSpacing: contentLayout.sectionTitleSpacing,
                railSpacing: contentLayout.railSpacing
            )
            .padding(.top, contentLayout.surfaceTopPadding)
            .padding(.bottom, contentLayout.surfaceBottomPadding)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            HomeContentSurfaceBackground(cornerRadius: cornerRadius)
        }
    }
}

private struct HomeContentSurfaceBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: leadingCornerRadius,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: cornerRadius
            ),
            style: .continuous
        )
        .fill(homeHeroSystemBackground)
        .homeContentSurfaceMacOSBackgroundExtension()
    }

    private var leadingCornerRadius: CGFloat {
#if os(macOS)
        0
#else
        cornerRadius
#endif
    }
}

struct HomeSectionsView: View {
    let sections: [HanimeHomeSection]
    var sectionSpacing: CGFloat = 24
    var sectionTitleSpacing: CGFloat = 12
    var railSpacing: CGFloat = 14

    var body: some View {
        LazyVStack(alignment: .leading, spacing: sectionSpacing) {
            ForEach(sections) { section in
                HomeSectionView(
                    section: section,
                    sectionTitleSpacing: sectionTitleSpacing,
                    railSpacing: railSpacing
                )
            }
        }
    }
}

private struct HomeSectionView: View {
    let section: HanimeHomeSection
    let sectionTitleSpacing: CGFloat
    let railSpacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: sectionTitleSpacing) {
            Text(section.title)
                .font(.headline)
                .padding(.horizontal)

            HomeSectionVideosView(videos: section.videos, railSpacing: railSpacing)
        }
    }
}

private struct HomeSectionVideosView: View {
    let videos: [HanimeInfo]
    let railSpacing: CGFloat

    var body: some View {
#if os(macOS)
        HanaVideoGridLinks(videos: videos)
            .padding(.horizontal)
#else
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: railSpacing) {
                ForEach(videos) { video in
                    NavigationLink(value: HanaRoute.video(video.videoCode)) {
                        HanaVideoGridCard(info: video)
                            .frame(width: HanaVideoGridCard.preferredWidth(for: video))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
#endif
    }
}

private extension View {
    @ViewBuilder
    func homeHeroBannerMacOSBackgroundExtension() -> some View {
#if os(macOS)
        backgroundExtensionEffect()
#else
        self
#endif
    }

    @ViewBuilder
    func homeHeroBannerMacOSLayerClipping() -> some View {
#if os(macOS)
        self
#else
        clipped()
#endif
    }

    @ViewBuilder
    func homeContentSurfaceMacOSBackgroundExtension() -> some View {
#if os(macOS)
        backgroundExtensionEffect()
#else
        self
#endif
    }
}
