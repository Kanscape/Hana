import AVKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let defaultDownloadGroupName = "默认分组"

struct DownloadsScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HanaSettingsKey.warnBeforeMobileDataDownload) private var warnBeforeMobileDataDownload = true
    @Query(sort: \DownloadQueueRecord.createdAt, order: .reverse) private var queue: [DownloadQueueRecord]
    @Query(sort: \DownloadGroupRecord.name, order: .forward) private var downloadGroups: [DownloadGroupRecord]
    @State private var localPlayback: LocalVideoPlayback?
    @State private var mobileDataDownloadID: String?
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var isCreateGroupPresented = false
    @State private var isGroupManagerPresented = false
    @State private var movingDownloadItem: DownloadQueueRecord?
    @State private var newGroupName = ""
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            DownloadQueueList(
                items: queue,
                groupNames: downloadGroupNames,
                progressProvider: progress(for:),
                isDownloadingProvider: isDownloading(id:),
                onStart: startDownloadAction,
                onCancel: cancelDownload,
                onPlay: playLocalFile,
                onDelete: delete,
                onMoveGroup: { item in
                    movingDownloadItem = item
                }
            )
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("已下载的视频")
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .toolbar { downloadToolbar }
        .sheet(item: $localPlayback) { playback in
            LocalVideoPlayerSheet(playback: playback)
        }
        .sheet(isPresented: $isGroupManagerPresented) {
            DownloadGroupManagementSheet(
                groupNames: downloadGroupNames,
                onRename: renameDownloadGroup,
                onDelete: deleteDownloadGroup
            )
        }
        .sheet(item: $movingDownloadItem) { item in
            DownloadMoveGroupSheet(
                item: item,
                groupNames: downloadGroupNames,
                onMove: moveDownloadItem
            )
        }
        .alert("新建分组", isPresented: $isCreateGroupPresented) {
            TextField("分组名称", text: $newGroupName)
            Button("创建") {
                createDownloadGroup(named: newGroupName)
                newGroupName = ""
            }
            .disabled(normalizedDownloadGroupName(newGroupName) == defaultDownloadGroupName)
            Button("取消", role: .cancel) {
                newGroupName = ""
            }
        }
        .task {
            await synchronizeDownloadRecords(showStatus: false)
        }
        .alert("当前网络可能按流量计费", isPresented: mobileDataAlertBinding) {
            Button("继续下载") {
                continueAfterMobileDataWarning()
            }
            Button("取消", role: .cancel) {
                mobileDataDownloadID = nil
            }
        } message: {
            Text("设置里开启了蜂窝网络下载前提醒。")
        }
    }

    @ToolbarContentBuilder
    private var downloadToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                newGroupName = ""
                isCreateGroupPresented = true
            } label: {
                Label("新建分组", systemImage: "folder.badge.plus")
            }

            Button(action: toggleEditMode) {
                Label(
                    isEditing ? "完成" : "编辑",
                    systemImage: isEditing ? "checkmark.circle" : "square.and.pencil"
                )
            }
            .accessibilityLabel(isEditing ? "完成编辑" : "编辑")
            .disabled(queue.isEmpty)
        }

        ToolbarItem(placement: .secondaryAction) {
            Button {
                isGroupManagerPresented = true
            } label: {
                Label("分组管理", systemImage: "folder")
            }
            .disabled(queue.isEmpty && downloadGroupNames.count <= 1)
        }

        ToolbarItem(placement: .secondaryAction) {
            Button(action: scanLocalDownloads) {
                Label("扫描本地文件", systemImage: "folder.badge.plus")
            }
        }
    }

    private func progress(for id: String) -> Double? {
        services.downloadClient.progress(for: id)
    }

    private func isDownloading(id: String) -> Bool {
        services.downloadClient.isDownloading(id: id)
    }

    private var isEditing: Bool {
        editMode.isEditing
    }

    private func toggleEditMode() {
        withAnimation(.smooth(duration: 0.2)) {
            editMode = editMode.isEditing ? .inactive : .active
        }
    }

    private func startDownloadAction(_ item: DownloadQueueRecord) {
        guard !item.mediaURLString.hasPrefix("file://") else {
            alertMessage = .error("本地文件没有远程下载地址。")
            return
        }
        if shouldConfirmMobileDataDownload {
            mobileDataDownloadID = item.id
            return
        }
        Task { await startDownload(item) }
    }

    private func playLocalFile(item: DownloadQueueRecord, url: URL) {
        localPlayback = LocalVideoPlayback(fileURL: url, title: item.title)
    }

    private func startDownload(_ item: DownloadQueueRecord, retryOnFailure: Bool = true) async {
        guard !services.downloadClient.isDownloading(id: item.id) else { return }
        guard let mediaURL = URL(string: item.mediaURLString) else {
            item.status = "下载失败"
            item.errorMessage = "下载地址无效"
            try? modelContext.save()
            return
        }

        await HanaDownloadNotifications.requestAuthorizationIfNeeded()
        item.status = "下载中"
        item.errorMessage = nil
        item.completedAt = nil
        item.progress = 0
        item.retryCount += 1
        try? modelContext.save()

        let request = HanimeDownloadRequest(
            id: item.id,
            videoCode: item.videoCode,
            title: item.title,
            coverURLString: item.coverURLString,
            quality: item.quality,
            mediaURL: mediaURL
        )

        let progressTask = Task { await syncProgress(for: item) }
        defer { progressTask.cancel() }

        do {
            let file = try await services.downloadClient.download(request) { snapshot in
                applyPersistedDownloadTask(snapshot, to: item)
                try? modelContext.save()
            }
            item.status = "已完成"
            item.localFileURLString = file.fileURL.absoluteString
            item.completedAt = .now
            item.progress = 1
            item.downloadedByteCount = file.byteCount
            item.expectedByteCount = file.byteCount
            item.backgroundTaskUpdatedAt = .now
            item.errorMessage = file.byteCount.map { ByteCountFormatStyle().format($0) }
        } catch {
            if services.siteSession.handle(error) {
                item.status = "需要 Cloudflare 验证"
            } else if let urlError = error as? URLError, urlError.code == .cancelled {
                item.status = "已取消"
                item.errorMessage = nil
            } else if retryOnFailure {
                item.status = "重试中"
                item.errorMessage = error.localizedDescription
                try? modelContext.save()
                try? await Task.sleep(for: .seconds(1))
                await startDownload(item, retryOnFailure: false)
                return
            } else {
                item.status = "下载失败"
                item.errorMessage = error.localizedDescription
            }
        }
        try? modelContext.save()
    }

    private func syncProgress(for item: DownloadQueueRecord) async {
        while !Task.isCancelled {
            if let snapshot = services.downloadClient.persistedTask(id: item.id) {
                applyPersistedDownloadTask(snapshot, to: item)
                try? modelContext.save()
            } else if let progress = services.downloadClient.progress(for: item.id) {
                item.progress = progress
                try? modelContext.save()
            }
            if !services.downloadClient.isDownloading(id: item.id) {
                break
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func cancelDownload(_ item: DownloadQueueRecord) {
        services.downloadClient.cancel(id: item.id)
        item.status = "已取消"
        item.errorMessage = nil
        try? modelContext.save()
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let item = queue[index]
            services.downloadClient.cancel(id: item.id)
            if let localURL = localFileURL(for: item) {
                try? services.downloadClient.deleteLocalDownload(fileURL: localURL)
            }
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    private var downloadGroupNames: [String] {
        var names = Set(downloadGroups.map { normalizedDownloadGroupName($0.name) })
        names.formUnion(queue.map { normalizedDownloadGroupName($0.downloadGroupName) })
        names.insert(defaultDownloadGroupName)
        return names.sorted { lhs, rhs in
            if lhs == defaultDownloadGroupName { return true }
            if rhs == defaultDownloadGroupName { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private func createDownloadGroup(named rawName: String) {
        let name = normalizedDownloadGroupName(rawName)
        guard name != defaultDownloadGroupName else {
            alertMessage = .error("默认分组已存在")
            return
        }
        guard !downloadGroupNames.contains(name) else {
            alertMessage = .error("\(name) 已存在")
            return
        }
        modelContext.insert(DownloadGroupRecord(name: name))
        try? modelContext.save()
        toastMessage = .success("已创建分组 \(name)")
    }

    private func moveDownloadItem(_ item: DownloadQueueRecord, to groupName: String) {
        item.downloadGroupName = normalizedDownloadGroupName(groupName)
        try? modelContext.save()
        toastMessage = .success("已移动到 \(item.downloadGroupName)")
    }

    private func renameDownloadGroup(from oldName: String, to newName: String) {
        let oldName = normalizedDownloadGroupName(oldName)
        let newName = normalizedDownloadGroupName(newName)
        guard oldName != newName else { return }
        for item in queue where normalizedDownloadGroupName(item.downloadGroupName) == oldName {
            item.downloadGroupName = newName
        }
        if let oldRecord = downloadGroups.first(where: { normalizedDownloadGroupName($0.name) == oldName }) {
            modelContext.delete(oldRecord)
        }
        if newName != defaultDownloadGroupName,
           !downloadGroups.contains(where: { normalizedDownloadGroupName($0.name) == newName }) {
            modelContext.insert(DownloadGroupRecord(name: newName))
        }
        try? modelContext.save()
        toastMessage = .success("已重命名为 \(newName)")
    }

    private func deleteDownloadGroup(_ name: String) {
        let name = normalizedDownloadGroupName(name)
        for item in queue where normalizedDownloadGroupName(item.downloadGroupName) == name {
            item.downloadGroupName = defaultDownloadGroupName
        }
        if let record = downloadGroups.first(where: { normalizedDownloadGroupName($0.name) == name }) {
            modelContext.delete(record)
        }
        try? modelContext.save()
        toastMessage = .success("已把 \(name) 中的视频移到默认分组")
    }

    private func applyPersistedDownloadTask(
        _ snapshot: HanimePersistedDownloadTask,
        to item: DownloadQueueRecord
    ) {
        item.backgroundSessionIdentifier = snapshot.sessionIdentifier
        item.backgroundTaskIdentifier = snapshot.taskIdentifier
        item.backgroundTaskStartedAt = snapshot.createdAt
        item.backgroundTaskUpdatedAt = snapshot.updatedAt
        item.downloadedByteCount = snapshot.downloadedByteCount
        item.expectedByteCount = snapshot.expectedByteCount
        item.completionNotificationSentAt = snapshot.notificationSentAt
        item.progress = snapshot.progress

        switch snapshot.status {
        case .running:
            guard item.status != "已完成" else { return }
            item.status = "下载中"
            item.localFileURLString = nil
            item.errorMessage = progressMessage(for: snapshot)
            item.completedAt = nil
        case .completed:
            item.status = "已完成"
            item.localFileURLString = snapshot.localFileURLString
            item.completedAt = snapshot.completedAt ?? item.completedAt ?? .now
            item.progress = 1
            item.errorMessage = snapshot.downloadedByteCount.map { ByteCountFormatStyle().format($0) }
        case .failed:
            guard item.status != "已完成" else { return }
            item.status = "下载失败"
            item.errorMessage = snapshot.errorDescription
            item.completedAt = snapshot.completedAt
        case .cancelled:
            guard item.status != "已完成" else { return }
            item.status = "已取消"
            item.errorMessage = nil
            item.completedAt = snapshot.completedAt
        }
    }

    private func progressMessage(for snapshot: HanimePersistedDownloadTask) -> String? {
        guard let downloaded = snapshot.downloadedByteCount,
              let expected = snapshot.expectedByteCount,
              expected > 0 else {
            return nil
        }
        let downloadedText = ByteCountFormatStyle().format(downloaded)
        let expectedText = ByteCountFormatStyle().format(expected)
        return "\(downloadedText) / \(expectedText)"
    }

    private func localFileURL(for item: DownloadQueueRecord) -> URL? {
        guard let localFileURLString = item.localFileURLString,
              let url = URL(string: localFileURLString),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private var shouldConfirmMobileDataDownload: Bool {
        warnBeforeMobileDataDownload && services.networkMonitor.shouldTreatAsMetered
    }

    private var mobileDataAlertBinding: Binding<Bool> {
        Binding {
            mobileDataDownloadID != nil
        } set: { isPresented in
            if !isPresented {
                mobileDataDownloadID = nil
            }
        }
    }

    private func continueAfterMobileDataWarning() {
        guard let id = mobileDataDownloadID else { return }
        mobileDataDownloadID = nil
        guard let item = queue.first(where: { $0.id == id }) else { return }
        Task { await startDownload(item) }
    }

    private func scanLocalDownloads() {
        Task {
            await synchronizeDownloadRecords(showStatus: true)
        }
    }

    private func synchronizeDownloadRecords(showStatus: Bool) async {
        let localFileResult = Result { try services.downloadClient.localDownloads() }
        await HanaDownloadRecordSynchronizer.synchronize(
            downloadClient: services.downloadClient,
            modelContext: modelContext,
            records: queue
        )

        guard showStatus else { return }
        switch localFileResult {
        case .success(let files) where files.isEmpty:
            toastMessage = .info("没有发现本地下载文件。")
        case .success(let files):
            toastMessage = .success("已同步 \(files.count) 个本地文件。")
        case .failure(let error):
            alertMessage = .error(error.localizedDescription)
        }
    }

}

private struct DownloadQueueList: View {
    let items: [DownloadQueueRecord]
    let groupNames: [String]
    let progressProvider: (String) -> Double?
    let isDownloadingProvider: (String) -> Bool
    let onStart: (DownloadQueueRecord) -> Void
    let onCancel: (DownloadQueueRecord) -> Void
    let onPlay: (DownloadQueueRecord, URL) -> Void
    let onDelete: (IndexSet) -> Void
    let onMoveGroup: (DownloadQueueRecord) -> Void
    @State private var collapsedGroupIDs = Set<String>()

    var body: some View {
        if groups.isEmpty {
            Section {
                ContentUnavailableView("暂无已下载视频", systemImage: "arrow.down.circle")
            }
        } else {
            Section {
                ForEach(groups) { group in
                    DisclosureGroup(isExpanded: groupExpansionBinding(group.id)) {
                        ForEach(group.items) { item in
                            DownloadQueueRow(
                                item: item,
                                progress: progressProvider(item.id),
                                isDownloading: isDownloadingProvider(item.id),
                                onStart: {
                                    onStart(item)
                                },
                                onCancel: {
                                    onCancel(item)
                                },
                                onPlay: { url in
                                    onPlay(item, url)
                                },
                                onMoveGroup: {
                                    onMoveGroup(item)
                                }
                            )
                        }
                        .onDelete { offsets in
                            onDelete(globalOffsets(for: group, offsets: offsets))
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                                .lineLimit(1)
                            Text("\(group.items.count) 个文件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var displayItems: [DownloadQueueRecord] {
        items.filter(\.shouldAppearInDownloads)
    }

    private var groups: [DownloadQueueGroup] {
        let recordsByGroup = Dictionary(grouping: displayItems) { item in
            normalizedDownloadGroupName(item.downloadGroupName)
        }
        let names = Set(groupNames).union(recordsByGroup.keys)
        return names.compactMap { groupName in
            let records = recordsByGroup[groupName, default: []]
            guard !records.isEmpty || groupName != defaultDownloadGroupName else {
                return nil
            }
            let sortedRecords = records.sorted { $0.createdAt > $1.createdAt }
            return DownloadQueueGroup(
                id: groupName,
                title: groupName,
                items: sortedRecords
            )
        }
        .sorted { lhs, rhs in
                if lhs.items.isEmpty != rhs.items.isEmpty {
                    return !lhs.items.isEmpty
                }
                let leftDate = lhs.items.map(\.createdAt).max() ?? .distantPast
                let rightDate = rhs.items.map(\.createdAt).max() ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                if lhs.title == defaultDownloadGroupName { return true }
                if rhs.title == defaultDownloadGroupName { return false }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private func groupExpansionBinding(_ id: String) -> Binding<Bool> {
        Binding {
            !collapsedGroupIDs.contains(id)
        } set: { isExpanded in
            if isExpanded {
                collapsedGroupIDs.remove(id)
            } else {
                collapsedGroupIDs.insert(id)
            }
        }
    }

    private func globalOffsets(for group: DownloadQueueGroup, offsets: IndexSet) -> IndexSet {
        IndexSet(offsets.compactMap { groupIndex in
            let item = group.items[groupIndex]
            return items.firstIndex { $0.id == item.id }
        })
    }
}

private struct DownloadQueueGroup: Identifiable {
    let id: String
    let title: String
    let items: [DownloadQueueRecord]
}

private struct DownloadQueueRow: View {
    let item: DownloadQueueRecord
    let progress: Double?
    let isDownloading: Bool
    let onStart: () -> Void
    let onCancel: () -> Void
    let onPlay: (URL) -> Void
    let onMoveGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(item.quality, systemImage: "slider.horizontal.3")
                Label(item.status, systemImage: statusIcon)
                if let fileSizeText {
                    Text(fileSizeText)
                }
            }
            .labelStyle(DownloadInfoLabelStyle())
            .font(.caption)
            .foregroundStyle(.secondary)

            if item.status == "下载中" {
                if let progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView(value: item.progress)
                }
            }

            if let message = statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if item.retryCount > 0 {
                    Text("尝试 \(item.retryCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if shouldShowStartButton {
                    Button(action: onStart) {
                        Label(startTitle, systemImage: startIcon)
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(startTitle)
                    .disabled(isDownloading || !canStart)
                }

                if let localURL = item.existingLocalFileURL {
                    Button {
                        onPlay(localURL)
                    } label: {
                        Label("播放", systemImage: "play.circle")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("播放")
                }

                Menu {
                    Button(action: onMoveGroup) {
                        Label("移动分组", systemImage: "folder")
                    }

                    if let localURL = item.existingLocalFileURL {
                        ShareLink(item: localURL) {
                            Label("分享文件", systemImage: "square.and.arrow.up")
                        }
                    }

                    if isDownloading {
                        Button(role: .cancel, action: onCancel) {
                            Label("取消下载", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch item.status {
        case "已完成":
            "checkmark.circle"
        case "下载中":
            "arrow.down.circle"
        case "下载失败":
            "exclamationmark.triangle"
        case "已取消":
            "xmark.circle"
        default:
            "clock"
        }
    }

    private var statusMessage: String? {
        guard item.status != "已完成" else { return nil }
        return item.errorMessage
    }

    private var fileSizeText: String? {
        guard item.status == "已完成" else { return nil }
        return item.errorMessage
    }

    private var shouldShowStartButton: Bool {
        canStart && !isDownloading && item.status != "已完成"
    }

    private var startTitle: String {
        item.status == "下载失败" || item.status == "已取消" ? "重新下载" : "开始下载"
    }

    private var startIcon: String {
        item.status == "下载失败" || item.status == "已取消" ? "arrow.clockwise" : "arrow.down"
    }

    private var canStart: Bool {
        !item.mediaURLString.hasPrefix("file://")
    }
}

private struct DownloadInfoLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

private extension DownloadQueueRecord {
    var existingLocalFileURL: URL? {
        guard let localFileURLString,
              let url = URL(string: localFileURLString),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    var shouldAppearInDownloads: Bool {
        status == "已完成" ? existingLocalFileURL != nil : true
    }
}

private struct DownloadMoveGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: DownloadQueueRecord
    let groupNames: [String]
    let onMove: (DownloadQueueRecord, String) -> Void
    @State private var selectedGroupName: String

    init(
        item: DownloadQueueRecord,
        groupNames: [String],
        onMove: @escaping (DownloadQueueRecord, String) -> Void
    ) {
        self.item = item
        self.groupNames = groupNames
        self.onMove = onMove
        _selectedGroupName = State(initialValue: normalizedDownloadGroupName(item.downloadGroupName))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("视频") {
                    Text(item.title)
                    LabeledContent("当前分组", value: normalizedDownloadGroupName(item.downloadGroupName))
                }

                Section("已有分组") {
                    Picker("移动到", selection: $selectedGroupName) {
                        ForEach(groupNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
            }
            .navigationTitle("移动分组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "取消", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "保存", systemImage: "checkmark") {
                        onMove(item, selectedGroupName)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DownloadGroupManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let groupNames: [String]
    let onRename: (String, String) -> Void
    let onDelete: (String) -> Void
    @State private var renamingGroupName: String?
    @State private var renameText = ""
    @State private var deletingGroupName: String?

    var body: some View {
        NavigationStack {
            List {
                Section("分组") {
                    ForEach(groupNames, id: \.self) { name in
                        HStack {
                            Label(name, systemImage: "folder")
                            Spacer()
                            Menu {
                                Button {
                                    renamingGroupName = name
                                    renameText = name
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    deletingGroupName = name
                                } label: {
                                    Label("移回默认分组", systemImage: "arrow.uturn.backward")
                                }
                                .disabled(name == defaultDownloadGroupName)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("分组管理")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "完成", systemImage: "checkmark") { dismiss() }
                }
            }
            .alert("重命名分组", isPresented: renameAlertBinding) {
                TextField("分组名称", text: $renameText)
                Button("保存") {
                    guard let renamingGroupName else { return }
                    onRename(renamingGroupName, renameText)
                    self.renamingGroupName = nil
                }
                Button("取消", role: .cancel) {
                    renamingGroupName = nil
                }
            }
            .confirmationDialog("把该分组内的视频移回默认分组？", isPresented: deleteConfirmationBinding, titleVisibility: .visible) {
                Button("移回默认分组", role: .destructive) {
                    guard let deletingGroupName else { return }
                    onDelete(deletingGroupName)
                    self.deletingGroupName = nil
                }
                Button("取消", role: .cancel) {
                    deletingGroupName = nil
                }
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding {
            renamingGroupName != nil
        } set: { isPresented in
            if !isPresented {
                renamingGroupName = nil
            }
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding {
            deletingGroupName != nil
        } set: { isPresented in
            if !isPresented {
                deletingGroupName = nil
            }
        }
    }
}

private func normalizedDownloadGroupName(_ value: String?) -> String {
    value?.nilIfEmpty ?? defaultDownloadGroupName
}

private struct LocalVideoPlayback: Identifiable {
    let id = UUID()
    let fileURL: URL
    let title: String
}

private struct LocalVideoPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let playback: LocalVideoPlayback
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .background(.black)
                .ignoresSafeArea(edges: .bottom)
            .navigationTitle(playback.title)
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "完成", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                HanaPlaybackAudioSession.activateForVideoPlayback()
                let nextPlayer = AVPlayer(url: playback.fileURL)
                nextPlayer.isMuted = false
                nextPlayer.volume = 1.0
                player = nextPlayer
                nextPlayer.play()
            }
            .onDisappear {
                player?.pause()
                HanaPlaybackAudioSession.deactivateAfterPlayback()
            }
        }
    }
}
