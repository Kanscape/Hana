import AVKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FlowTags: View {
    let tags: [String]
    var routeForTag: ((String) -> HanaRoute?)?

    init(tags: [String], routeForTag: ((String) -> HanaRoute?)? = nil) {
        self.tags = tags
        self.routeForTag = routeForTag
    }

    var body: some View {
        HanaFlowTagLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                tagView(tag)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tagView(_ tag: String) -> some View {
        if let route = routeForTag?(tag) {
            NavigationLink(value: route) {
                tagLabel(tag)
            }
            .buttonStyle(.plain)
            .contextMenu {
                copyTagButton(tag)
            }
        } else {
            tagLabel(tag)
                .contextMenu {
                    copyTagButton(tag)
                }
        }
    }

    private func tagLabel(_ tag: String) -> some View {
        Text(tag)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.secondary.opacity(0.18), lineWidth: 0.5)
            }
            .contentShape(Capsule())
    }

    private func copyTagButton(_ tag: String) -> some View {
        Button {
            UIPasteboard.general.string = tag
        } label: {
            Label("复制标签", systemImage: "doc.on.doc")
        }
    }
}

struct VideoTagStrip: View {
    let tags: [String]
    @State private var isCollapsed = false

    var body: some View {
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TAGs")
                        .font(.headline)
                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline.weight(.semibold))
                            .rotationEffect(.degrees(isCollapsed ? 0 : 180))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCollapsed ? "展开标签" : "收起标签")
                }

                if !isCollapsed {
                    FlowTags(tags: tags) { tag in
                        .search(HanimeSearchOptionCatalog.searchCriteria(forDetailTag: tag))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.secondary.opacity(0.12), lineWidth: 1)
            }
        }
    }
}

struct HanaFlowTagLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 8) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = arrangedRows(in: availableWidth, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat.zero) { result, row in
            result + row.height
        } + verticalSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangedRows(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func arrangedRows(in availableWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentItems: [RowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let idealSize = subviews[index].sizeThatFits(.unspecified)
            let size: CGSize
            if availableWidth.isFinite {
                size = CGSize(width: min(idealSize.width, availableWidth), height: idealSize.height)
            } else {
                size = idealSize
            }
            let itemWidth = currentItems.isEmpty ? size.width : size.width + horizontalSpacing
            if !currentItems.isEmpty, currentWidth + itemWidth > availableWidth {
                rows.append(Row(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = [RowItem(index: index, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(RowItem(index: index, size: size))
                currentWidth += itemWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(Row(items: currentItems, width: currentWidth, height: currentHeight))
        }
        return rows
    }

    private struct Row {
        let items: [RowItem]
        let width: CGFloat
        let height: CGFloat
    }

    private struct RowItem {
        let index: Int
        let size: CGSize
    }
}
