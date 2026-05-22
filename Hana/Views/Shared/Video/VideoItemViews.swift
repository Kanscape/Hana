import Nuke
import NukeUI
import SwiftData
import SwiftUI

struct HanaVideoMetadataItem: Hashable {
    let text: String
    let systemImage: String?

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }
}

struct HanaVideoGridCardStyle: Hashable {
    enum Background: Hashable {
        case none
        case thinMaterial
        case secondaryFill
    }

    var coverAspectRatio: CGFloat = 16.0 / 9.0
    var coverCornerRadius: CGFloat = 8
    var spacing: CGFloat = 8
    var contentPadding: CGFloat = 10
    var titleFont: Font = .headline
    var titleLineLimit: Int = 2
    var metadataSpacing: CGFloat = 8
    var background: Background = .thinMaterial
    var showsPlayedIndicator: Bool = true

    static let portrait = HanaVideoGridCardStyle(coverAspectRatio: 120.0 / 176.0)
    static let plain = HanaVideoGridCardStyle(contentPadding: 0, background: .none)
}

struct HanaVideoListRowStyle: Hashable {
    var coverSize: CGSize = CGSize(width: 128, height: 72)
    var coverCornerRadius: CGFloat = 6
    var spacing: CGFloat = 12
    var textSpacing: CGFloat = 4
    var titleFont: Font = .headline
    var titleLineLimit: Int = 2
    var metadataSpacing: CGFloat = 8
    var verticalPadding: CGFloat = 0
    var showsPlayedIndicator: Bool = true

    static let compact = HanaVideoListRowStyle(coverSize: CGSize(width: 72, height: 44), titleLineLimit: 1)
}

struct HanaVideoGridCard: View {
    @AppStorage(HanaSettingsKey.showPlayedIndicator) private var showPlayedIndicator = true
    @Query private var watchHistory: [WatchHistoryRecord]

    let title: String
    let videoCode: String
    let coverURL: URL?
    let metadataItems: [HanaVideoMetadataItem]
    let style: HanaVideoGridCardStyle

    init(info: HanimeInfo, style: HanaVideoGridCardStyle? = nil) {
        self.init(
            title: info.title,
            videoCode: info.videoCode,
            coverURL: info.coverURL,
            metadataItems: Self.metadataItems(for: info),
            style: style ?? Self.style(for: info)
        )
    }

    static func preferredWidth(for info: HanimeInfo, normal: CGFloat = 180, portrait: CGFloat = 132) -> CGFloat {
        switch info.style {
        case .normal:
            normal
        case .compact:
            portrait
        }
    }

    init(
        title: String,
        videoCode: String,
        coverURL: URL?,
        metadataItems: [HanaVideoMetadataItem] = [],
        style: HanaVideoGridCardStyle = HanaVideoGridCardStyle()
    ) {
        self.title = title
        self.videoCode = videoCode
        self.coverURL = coverURL
        self.metadataItems = metadataItems
        self.style = style
        let videoCode = videoCode
        _watchHistory = Query(
            filter: #Predicate<WatchHistoryRecord> { record in
                record.videoCode == videoCode
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.spacing) {
            HanaVideoCoverBox(
                url: coverURL,
                isWatched: isWatched,
                cornerRadius: style.coverCornerRadius,
                aspectRatio: style.coverAspectRatio
            )

            Text(title)
                .font(style.titleFont)
                .lineLimit(style.titleLineLimit, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HanaVideoMetadata(items: metadataItems, spacing: style.metadataSpacing)
        }
        .padding(style.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(HanaVideoCardBackgroundModifier(background: style.background, cornerRadius: style.coverCornerRadius))
    }

    private var isWatched: Bool {
        style.showsPlayedIndicator && showPlayedIndicator && watchHistory.first?.isWatched == true
    }

    private static func metadataItems(for info: HanimeInfo) -> [HanaVideoMetadataItem] {
        var items: [HanaVideoMetadataItem] = []
        if let duration = info.duration {
            items.append(HanaVideoMetadataItem(duration, systemImage: "clock"))
        }
        if let views = info.views {
            items.append(HanaVideoMetadataItem(views, systemImage: "eye"))
        }
        return items
    }

    private static func style(for info: HanimeInfo) -> HanaVideoGridCardStyle {
        switch info.style {
        case .normal:
            HanaVideoGridCardStyle()
        case .compact:
            .portrait
        }
    }
}

struct HanaVideoGridLinks: View {
    let videos: [HanimeInfo]
    var normalMinimumWidth: CGFloat = 150
    var portraitMinimumWidth: CGFloat = 108
    var onVideoAppear: (HanimeInfo) -> Void = { _ in }

    private var minimumCardWidth: CGFloat {
        videos.first?.style == .compact ? portraitMinimumWidth : normalMinimumWidth
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: minimumCardWidth),
                spacing: 12,
                alignment: .top
            )
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(videos) { video in
                NavigationLink(value: HanaRoute.video(video.videoCode)) {
                    HanaVideoGridCard(info: video)
                }
                .buttonStyle(.plain)
                .onAppear {
                    onVideoAppear(video)
                }
            }
        }
    }
}

struct HanaVideoListRow: View {
    @AppStorage(HanaSettingsKey.showPlayedIndicator) private var showPlayedIndicator = true
    @Query private var watchHistory: [WatchHistoryRecord]

    let title: String
    let videoCode: String
    let coverURL: URL?
    let metadataItems: [HanaVideoMetadataItem]
    let style: HanaVideoListRowStyle

    init(info: HanimeInfo, style: HanaVideoListRowStyle = HanaVideoListRowStyle()) {
        self.init(
            title: info.title,
            videoCode: info.videoCode,
            coverURL: info.coverURL,
            metadataItems: Self.metadataItems(for: info),
            style: style
        )
    }

    init(
        title: String,
        videoCode: String,
        coverURL: URL?,
        metadataItems: [HanaVideoMetadataItem] = [],
        style: HanaVideoListRowStyle = HanaVideoListRowStyle()
    ) {
        self.title = title
        self.videoCode = videoCode
        self.coverURL = coverURL
        self.metadataItems = metadataItems
        self.style = style
        let videoCode = videoCode
        _watchHistory = Query(
            filter: #Predicate<WatchHistoryRecord> { record in
                record.videoCode == videoCode
            }
        )
    }

    var body: some View {
        HStack(spacing: style.spacing) {
            HanaVideoCoverWithStatus(
                url: coverURL,
                isWatched: isWatched,
                cornerRadius: style.coverCornerRadius
            )
            .frame(width: style.coverSize.width, height: style.coverSize.height)

            VStack(alignment: .leading, spacing: style.textSpacing) {
                Text(title)
                    .font(style.titleFont)
                    .lineLimit(style.titleLineLimit)

                HanaVideoMetadata(items: metadataItems, spacing: style.metadataSpacing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, style.verticalPadding)
    }

    private var isWatched: Bool {
        style.showsPlayedIndicator && showPlayedIndicator && watchHistory.first?.isWatched == true
    }

    private static func metadataItems(for info: HanimeInfo) -> [HanaVideoMetadataItem] {
        var items: [HanaVideoMetadataItem] = []
        if let duration = info.duration {
            items.append(HanaVideoMetadataItem(duration, systemImage: "clock"))
        }
        if let views = info.views {
            items.append(HanaVideoMetadataItem(views, systemImage: "eye"))
        }
        return items
    }
}

struct CoverView: View {
    @Environment(HanaServices.self) private var services
    let url: URL?
    var contentMode: ContentMode = .fill
    var alignment: Alignment = .center
    var fallbackSystemImage = "play.rectangle"
    var placeholderCornerRadius: CGFloat = 8

    var body: some View {
        LazyImage(request: imageRequest) { state in
            ZStack {
                RoundedRectangle(cornerRadius: placeholderCornerRadius)
                    .fill(.secondary.opacity(0.16))

                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                } else if url == nil || state.error != nil {
                    Image(systemName: fallbackSystemImage)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
        }
        .pipeline(services.imagePipeline)
        .clipped()
    }

    private var imageRequest: Nuke.ImageRequest? {
        guard let url else { return nil }
        let urlRequest = services.httpClient.imageURLRequest(
            for: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 12
        )
        return Nuke.ImageRequest(urlRequest: urlRequest)
    }
}

private struct HanaVideoCoverWithStatus: View {
    let url: URL?
    let isWatched: Bool
    let cornerRadius: CGFloat

    var body: some View {
        CoverView(url: url)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .topTrailing) {
                if isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .blue)
                        .font(.title3)
                        .padding(5)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(6)
                        .accessibilityLabel("已看")
                }
            }
    }
}

private struct HanaVideoCoverBox: View {
    let url: URL?
    let isWatched: Bool
    let cornerRadius: CGFloat
    let aspectRatio: CGFloat

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.16)
            HanaVideoCoverWithStatus(
                url: url,
                isWatched: isWatched,
                cornerRadius: cornerRadius
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

private struct HanaVideoMetadata: View {
    let items: [HanaVideoMetadataItem]
    let spacing: CGFloat

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: spacing) {
                ForEach(items, id: \.self) { item in
                    if let systemImage = item.systemImage {
                        Label(item.text, systemImage: systemImage)
                            .labelStyle(HanaCompactMetadataLabelStyle(spacing: 3))
                    } else {
                        Text(item.text)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

private struct HanaVideoCardBackgroundModifier: ViewModifier {
    let background: HanaVideoGridCardStyle.Background
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        switch background {
        case .none:
            content
        case .thinMaterial:
            content.background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        case .secondaryFill:
            content.background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

private struct HanaCompactMetadataLabelStyle: LabelStyle {
    let spacing: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

extension Date {
    var hanaChineseDateText: String {
        formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day())
    }

    var hanaChineseDateTimeText: String {
        formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day().hour().minute())
    }
}
