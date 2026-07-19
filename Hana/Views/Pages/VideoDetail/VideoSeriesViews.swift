import SwiftUI
#if os(iOS)
import UIKit
#endif

struct VideoSeriesSection: View {
  let series: HanimeVideoSeries

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("系列影片")
          .font(.headline)

        if let title = series.title {
          Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      ScrollViewReader { proxy in
        HanaHorizontalFadingScrollView(
          contentLeadingPadding: horizontalScrollOverflow + 1,
          contentTrailingPadding: horizontalScrollOverflow + 1
        ) {
          LazyHStack(alignment: .top, spacing: 12) {
            ForEach(series.videos) { video in
              NavigationLink(value: HanaRoute.video(video.videoCode)) {
                VideoSeriesCard(video: video)
              }
              .buttonStyle(.plain)
              .id(video.videoCode)
            }
          }
        }
        .padding(.horizontal, -horizontalScrollOverflow)
        .task(id: series.currentVideoCode) {
          scrollToCurrent(using: proxy)
        }
      }
    }
  }

  private func scrollToCurrent(using proxy: ScrollViewProxy) {
    guard let currentVideoCode = series.currentVideoCode else { return }
    withAnimation(.easeInOut(duration: 0.25)) {
      proxy.scrollTo(currentVideoCode, anchor: .center)
    }
  }

  private var horizontalScrollOverflow: CGFloat {
#if os(iOS)
    UIDevice.current.userInterfaceIdiom == .phone ? 20 : 0
#else
    0
#endif
  }
}

private struct VideoSeriesCard: View {
  let video: HanimeSeriesVideo

  private let width: CGFloat = 196

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HanaVideoGridCard(
        title: video.title,
        videoCode: video.videoCode,
        coverURL: video.coverURL,
        metadataItems: cardMetadata,
        style: cardStyle
      )

      if let attributionText {
        Text(attributionText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if let detailText {
        Text(detailText)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
    }
    .padding(8)
    .frame(width: width, alignment: .topLeading)
    .background(
      .secondary.opacity(video.isCurrent ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 8)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(
          video.isCurrent ? Color.accentColor : .secondary.opacity(0.14),
          lineWidth: video.isCurrent ? 1.5 : 1)
    }
    .overlay(alignment: .topLeading) {
      if video.isCurrent {
        Image(systemName: "play.fill")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
          .padding(7)
          .background(Color.accentColor, in: Circle())
          .padding(12)
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(video.title)
    .accessibilityValue(accessibilityValue)
    .accessibilityAddTraits(video.isCurrent ? .isSelected : [])
  }

  private var cardStyle: HanaVideoGridCardStyle {
    var style = HanaVideoGridCardStyle.plain
    style.titleFont = .subheadline.weight(.semibold)
    return style
  }

  private var cardMetadata: [HanaVideoMetadataItem] {
    var items: [HanaVideoMetadataItem] = []
    if let duration = video.duration {
      items.append(HanaVideoMetadataItem(duration, systemImage: "clock"))
    }
    if let views = video.views {
      items.append(HanaVideoMetadataItem(views, systemImage: "eye"))
    }
    return items
  }

  private var attributionText: String? {
    joinedMetadata([video.author, video.category])
  }

  private var detailText: String? {
    joinedMetadata([video.rating, video.uploadTime])
  }

  private var accessibilityValue: String {
    var values = [String]()
    if video.isCurrent {
      values.append("当前播放")
    }
    values.append(
      contentsOf: [
        video.duration,
        video.views,
        video.rating,
        video.author,
        video.category,
        video.uploadTime,
      ].compactMap { $0 })
    return values.joined(separator: "，")
  }

  private func joinedMetadata(_ values: [String?]) -> String? {
    let text = values.compactMap { $0 }.joined(separator: " · ")
    return text.isEmpty ? nil : text
  }
}
