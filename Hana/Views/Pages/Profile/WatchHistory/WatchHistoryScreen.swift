import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct WatchHistoryScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WatchHistoryRecord.watchDate, order: .reverse) private var watchHistory: [WatchHistoryRecord]
    @State private var isClearConfirmationPresented = false
    @State private var isSelectionModeActive = false

    var body: some View {
        List {
            if visibleWatchHistory.isEmpty {
                ContentUnavailableView("观看记录", systemImage: "clock.arrow.circlepath")
            } else {
                ForEach(visibleWatchHistory) { item in
                    NavigationLink(value: HanaRoute.video(item.videoCode)) {
                        WatchHistoryRow(item: item)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            delete(item)
                        } label: {
                            Label("删除记录", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("观看记录")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: toggleEditMode) {
                    Label(
                        isEditing ? "完成" : "编辑",
                        systemImage: isEditing ? "checkmark.circle" : "square.and.pencil"
                    )
                }
                .accessibilityLabel(isEditing ? "完成编辑" : "编辑")
                .disabled(visibleWatchHistory.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    isClearConfirmationPresented = true
                } label: {
                    Label("清空观看记录", systemImage: "trash")
                }
                .disabled(visibleWatchHistory.isEmpty)
            }
        }
        .confirmationDialog("清空全部观看记录？", isPresented: $isClearConfirmationPresented, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                clearAll()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var isEditing: Bool {
        isSelectionModeActive
    }

    private var visibleWatchHistory: [WatchHistoryRecord] {
        watchHistory.filter(\.isHistoryEligible)
    }

    private func toggleEditMode() {
        withAnimation(.smooth(duration: 0.2)) {
            isSelectionModeActive.toggle()
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets where visibleWatchHistory.indices.contains(index) {
            modelContext.delete(visibleWatchHistory[index])
        }
        try? modelContext.save()
    }

    private func delete(_ item: WatchHistoryRecord) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func clearAll() {
        for item in watchHistory {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}

private struct WatchHistoryRow: View {
    let item: WatchHistoryRecord

    var body: some View {
        HanaVideoListRow(
            title: item.title,
            videoCode: item.videoCode,
            coverURL: coverURL,
            metadataItems: metadataItems,
            style: HanaVideoListRowStyle(verticalPadding: 2)
        )
    }

    private var coverURL: URL? {
        guard let coverURLString = item.coverURLString else { return nil }
        return URL(string: coverURLString)
    }

    private var metadataItems: [HanaVideoMetadataItem] {
        var items = [HanaVideoMetadataItem(item.videoCode, systemImage: "number")]
        if item.progress > 1 {
            items.append(HanaVideoMetadataItem(formatTime(item.progress), systemImage: "play.circle"))
        }
        items.append(HanaVideoMetadataItem(item.watchDate.hanaChineseDateTimeText))
        return items
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
