import SwiftData
import SwiftUI

struct HKeyframeSettingsScreen: View {
    @AppStorage(HanaSettingsKey.hKeyframesEnabled) private var hKeyframesEnabled = true
    @AppStorage(HanaSettingsKey.hKeyframeCountdownSeconds) private var countdownSeconds = 10
    @AppStorage(HanaSettingsKey.hKeyframeShowPrompt) private var showPrompt = true
    @AppStorage(HanaSettingsKey.sharedHKeyframesEnabled) private var sharedEnabled = true
    @AppStorage(HanaSettingsKey.sharedHKeyframesPreferred) private var sharedPreferred = false
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var localRecords: [HKeyframeRecord]

    private var sharedCount: Int {
        HanaHKeyframeLibrary.allSharedRecords().count
    }

    var body: some View {
        Form {
            Section("播放提醒") {
                Toggle(isOn: $hKeyframesEnabled) {
                    Label("启用 HKeyframes", systemImage: "bookmark")
                }
                Toggle(isOn: $showPrompt) {
                    Label("显示提示文本", systemImage: "text.bubble")
                }
                Stepper(value: $countdownSeconds, in: 5...30, step: 5) {
                    LabeledContent {
                        Text("\(countdownSeconds) 秒")
                    } label: {
                        Label("提前提醒", systemImage: "timer")
                    }
                }
            }

            Section("共享关键帧") {
                Toggle(isOn: $sharedEnabled) {
                    Label("使用内置共享库", systemImage: "person.2")
                }
                Toggle(isOn: $sharedPreferred) {
                    Label("共享库优先", systemImage: "star")
                }
                    .disabled(!sharedEnabled)
                LabeledContent {
                    Text("\(sharedCount)")
                } label: {
                    Label("内置条目", systemImage: "books.vertical")
                }
                NavigationLink {
                    SharedHKeyframeLibraryScreen()
                } label: {
                    Label("浏览共享库", systemImage: "person.2")
                }
            }

            Section("本地管理") {
                NavigationLink {
                    HKeyframeManagementScreen()
                } label: {
                    Label("管理本地 HKeyframes", systemImage: "list.bullet.rectangle")
                }
                LabeledContent {
                    Text("\(localRecords.count)")
                } label: {
                    Label("本地条目", systemImage: "internaldrive")
                }
            }
        }
        .navigationTitle("HKeyframes")
    }
}

private struct SharedHKeyframeLibraryScreen: View {
    @State private var query = ""
    @State private var targetGroupID: String?

    private var records: [HanaSharedHKeyframeRecord] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let allRecords = HanaHKeyframeLibrary.allSharedRecords()
        guard !text.isEmpty else { return allRecords }
        return allRecords.filter { record in
            record.title.localizedStandardContains(text)
                || record.videoCode.localizedStandardContains(text)
                || (record.group?.localizedStandardContains(text) ?? false)
                || (record.author?.localizedStandardContains(text) ?? false)
        }
    }

    private var groups: [SharedHKeyframeGroup] {
        Dictionary(grouping: records) { record in
            record.group?.nilIfEmpty ?? "未分组"
        }
        .map { title, records in
            SharedHKeyframeGroup(
                title: title,
                records: records.sorted {
                    if ($0.episode ?? 0) != ($1.episode ?? 0) {
                        return ($0.episode ?? 0) < ($1.episode ?? 0)
                    }
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if groups.isEmpty {
                    ContentUnavailableView("没有匹配的 HKeyframes", systemImage: "magnifyingglass")
                } else {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.records) { record in
                                NavigationLink(value: HanaRoute.video(record.videoCode)) {
                                    SharedHKeyframeRecordRow(record: record)
                                }
                            }
                        } header: {
                            Text(group.title)
                                .id(group.id)
                        }
                    }
                }
            }
            .navigationTitle("共享 HKeyframes")
            .searchable(text: $query, prompt: "标题、番号、系列")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(groups) { group in
                            Button(group.title) {
                                withAnimation {
                                    proxy.scrollTo(group.id, anchor: .top)
                                }
                            }
                        }
                    } label: {
                        Label("跳转", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(groups.isEmpty)
                }
            }
        }
    }
}

private struct SharedHKeyframeGroup: Identifiable {
    var id: String { title }
    let title: String
    let records: [HanaSharedHKeyframeRecord]
}

private struct SharedHKeyframeRecordRow: View {
    let record: HanaSharedHKeyframeRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 8) {
                Label(record.videoCode, systemImage: "number")
                if let episode = record.episode, episode > 0 {
                    Text("第 \(episode) 集")
                }
                Text("\(record.keyframes.count) 个关键帧")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let author = record.author {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
