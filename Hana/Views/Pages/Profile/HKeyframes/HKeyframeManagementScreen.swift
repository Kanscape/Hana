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
        content
            .navigationTitle("HKeyframes")
            .searchable(text: $query, prompt: "标题或番号")
            .hanaToast($toastMessage)
            .hanaFeedbackAlert($alertMessage)
    }

    @ViewBuilder
    private var content: some View {
        if records.isEmpty {
            ContentUnavailableView {
                Label("暂无本地 HKeyframes", systemImage: "bookmark")
            } description: {
                Text("从剪贴板导入后会显示在这里。")
            } actions: {
                importButton
                    .buttonStyle(.borderedProminent)
            }
        } else if visibleRecords.isEmpty {
            ContentUnavailableView("没有符合条件的 HKeyframes", systemImage: "line.3.horizontal.decrease.circle")
        } else {
            hKeyframeList
        }
    }

    private var hKeyframeList: some View {
        List {
            Section {
                importButton
            }

            Section("本地 HKeyframes") {
                recordRows
            }
        }
    }

    private var importButton: some View {
        Button {
            importFromPasteboard()
        } label: {
            Label("从剪贴板导入", systemImage: "doc.on.clipboard")
        }
    }

    private var recordRows: some View {
        ForEach(visibleRecords) { record in
            NavigationLink {
                HKeyframeRecordDetailScreen(record: record)
            } label: {
                HKeyframeRecordRow(record: record)
            }
        }
        .onDelete(perform: delete)
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
        detailContent
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

    @ViewBuilder
    private var detailContent: some View {
#if os(macOS)
        macOSDetailContent
#else
        detailForm
#endif
    }

    private var detailForm: some View {
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
                    deleteRecord()
                } label: {
                    Label("删除整组", systemImage: "trash")
                }
            }
        }
    }

#if os(macOS)
    private var macOSDetailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                macOSInfoSection

                Divider()

                macOSKeyframeSection

                Divider()

                macOSActionRow
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var macOSInfoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("信息")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    macOSFieldLabel("标题:")
                    TextField("标题", text: $record.title)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                }

                GridRow {
                    macOSFieldLabel("系列:")
                    TextField("系列", text: Binding(
                        get: { record.groupTitle ?? "" },
                        set: { record.groupTitle = $0.nilIfEmpty }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                }

                GridRow {
                    macOSFieldLabel("集数:")
                    TextField("集数", value: $record.episode, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }

                GridRow {
                    macOSFieldLabel("番号:")
                    Text(record.videoCode)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var macOSKeyframeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("关键帧")
                    .font(.headline)
                Spacer()
                Button {
                    isManualAddPresented = true
                } label: {
                    Label("添加关键帧", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if record.keyframes.isEmpty {
                ContentUnavailableView("暂无关键帧", systemImage: "bookmark.slash")
                    .frame(height: 140)
            } else {
                macOSKeyframeRows
            }
        }
    }

    private var macOSKeyframeRows: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("时间")
                    .frame(width: 120, alignment: .leading)
                Text("提示")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("操作")
                    .frame(width: 96, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ForEach(record.keyframes) { keyframe in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(formatTime(keyframe.seconds))
                        .font(.body.monospacedDigit())
                        .frame(width: 120, alignment: .leading)

                    Text(keyframe.prompt ?? "无")
                        .foregroundStyle(keyframe.prompt == nil ? .secondary : .primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        Button {
                            editingKeyframe = keyframe
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("编辑")

                        Button(role: .destructive) {
                            delete(keyframe)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("删除")
                    }
                    .frame(width: 96, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                if keyframe.id != record.keyframes.last?.id {
                    Divider()
                }
            }
        }
        .overlay(alignment: .top) {
            Divider()
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var macOSActionRow: some View {
        HStack {
            Button {
                copyShareText()
            } label: {
                Label("复制分享文本", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive) {
                deleteRecord()
            } label: {
                Label("删除整组", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    private func macOSFieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .trailing)
    }
#endif

    private func copyShareText() {
        do {
            HanaPasteboard.string = try HanaHKeyframeLibrary.shareText(for: record)
            toastMessage = .success("已复制到剪贴板")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private func delete(_ keyframe: HKeyframeEntry) {
        record.remove(keyframe)
        try? modelContext.save()
    }

    private func deleteRecord() {
        modelContext.delete(record)
        try? modelContext.save()
        dismiss()
    }
}
