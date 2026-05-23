import SwiftData
import SwiftUI

struct HKeyframeManagementScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var records: [HKeyframeRecord]
    @State private var query = ""
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?

    private var visibleRecords: [HKeyframeRecord] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return records }
        return records.filter {
            $0.title.localizedStandardContains(text)
                || $0.videoCode.localizedStandardContains(text)
                || ($0.groupTitle?.localizedStandardContains(text) ?? false)
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    importFromPasteboard()
                } label: {
                    Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                }
            }

            Section("本地 HKeyframes") {
                if visibleRecords.isEmpty {
                    ContentUnavailableView("暂无本地 HKeyframes", systemImage: "bookmark")
                } else {
                    ForEach(visibleRecords) { record in
                        NavigationLink {
                            HKeyframeRecordDetailScreen(record: record)
                        } label: {
                            HKeyframeRecordRow(record: record)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("HKeyframes")
        .searchable(text: $query, prompt: "标题或番号")
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
    }

    private func importFromPasteboard() {
        do {
            guard let text = HanaPasteboard.string else {
                throw HanaHKeyframeImportError.invalidShareText
            }
            let record = try HanaHKeyframeLibrary.decodeShareText(text)
            let videoCode = record.videoCode
            try? modelContext.delete(
                model: HKeyframeRecord.self,
                where: #Predicate<HKeyframeRecord> { item in
                    item.videoCode == videoCode
                }
            )
            modelContext.insert(record)
            try modelContext.save()
            toastMessage = .success("已导入 \(record.title)")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for offset in offsets {
            modelContext.delete(visibleRecords[offset])
        }
        try? modelContext.save()
    }
}

private struct HKeyframeRecordRow: View {
    let record: HKeyframeRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(record.keyframes.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Label(record.videoCode, systemImage: "number")
                if let groupTitle = record.groupTitle {
                    Text(groupTitle)
                }
                if let author = record.author {
                    Text(author)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

struct HKeyframeRecordDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var record: HKeyframeRecord
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var editingKeyframe: HKeyframeEntry?
    @State private var isManualAddPresented = false

    var body: some View {
        Form {
            Section("信息") {
                TextField("标题", text: $record.title)
                TextField("系列", text: Binding(
                    get: { record.groupTitle ?? "" },
                    set: { record.groupTitle = $0.nilIfEmpty }
                ))
                TextField("集数", value: $record.episode, format: .number)
                LabeledContent("番号", value: record.videoCode)
            }

            Section("关键帧") {
                if record.keyframes.isEmpty {
                    ContentUnavailableView("暂无关键帧", systemImage: "bookmark.slash")
                } else {
                    ForEach(record.keyframes) { keyframe in
                        HStack {
                            Button {
                                editingKeyframe = keyframe
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formatTime(keyframe.seconds))
                                        .font(.headline)
                                    if let prompt = keyframe.prompt {
                                        Text(prompt)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                editingKeyframe = keyframe
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive) {
                                record.remove(keyframe)
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Button {
                    isManualAddPresented = true
                } label: {
                    Label("手动添加关键帧", systemImage: "plus.circle")
                }
            }

            Section {
                Button {
                    copyShareText()
                } label: {
                    Label("复制分享文本", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    modelContext.delete(record)
                    try? modelContext.save()
                    dismiss()
                } label: {
                    Label("删除整组", systemImage: "trash")
                }
            }
        }
        .navigationTitle("HKeyframes")
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .onDisappear {
            try? modelContext.save()
        }
        .sheet(item: $editingKeyframe) { keyframe in
            HKeyframeEditSheet(
                title: "编辑关键帧",
                initialPositionMilliseconds: keyframe.positionMilliseconds,
                initialPrompt: keyframe.prompt ?? ""
            ) { updated in
                record.replace(keyframe, with: updated)
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $isManualAddPresented) {
            HKeyframeEditSheet(
                title: "添加关键帧",
                initialPositionMilliseconds: 0,
                initialPrompt: ""
            ) { keyframe in
                record.append(keyframe)
                try? modelContext.save()
            }
        }
    }

    private func copyShareText() {
        do {
            HanaPasteboard.string = try HanaHKeyframeLibrary.shareText(for: record)
            toastMessage = .success("已复制到剪贴板")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }
}
