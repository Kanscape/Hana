import AVKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsScreen: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    PlaybackSettingsScreen()
                } label: {
                    SettingsNavigationRow(
                        title: "播放",
                        description: "清晰度、字幕、手势和播放记录",
                        systemImage: "play.rectangle",
                        tint: .blue
                    )
                }
                NavigationLink {
                    HKeyframeSettingsScreen()
                } label: {
                    SettingsNavigationRow(
                        title: "HKeyframes",
                        description: "播放提醒、共享关键帧和本地管理",
                        systemImage: "bookmark",
                        tint: .purple
                    )
                }
                NavigationLink {
                    DownloadSettingsScreen()
                } label: {
                    SettingsNavigationRow(
                        title: "下载",
                        description: "下载质量、并发、网络提醒和目录",
                        systemImage: "arrow.down.circle",
                        tint: .green
                    )
                }
                NavigationLink {
                    AppearanceSettingsScreen()
                } label: {
                    SettingsNavigationRow(
                        title: "外观",
                        description: "跟随系统，或固定浅色、深色",
                        systemImage: "circle.lefthalf.filled",
                        tint: .pink
                    )
                }
                NavigationLink {
                    NetworkSettingsScreen()
                } label: {
                    SettingsNavigationRow(
                        title: "网络与站点",
                        description: "站点地址、代理、测速和验证",
                        systemImage: "network",
                        tint: .orange
                    )
                }
                NavigationLink {
                    LocalDataSettingsScreen()
                } label: {
                    SettingsNavigationRow(
                        title: "本地数据",
                        description: "查看数量，删除本机保存的记录",
                        systemImage: "internaldrive",
                        tint: .gray
                    )
                }
            }

            Section {
                SettingsAppFooter()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .navigationTitle("设置")
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let description: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct PlaybackSettingsScreen: View {
    @AppStorage(HanaSettingsKey.defaultVideoQuality) private var defaultVideoQuality = HanaVideoQualityPreference.defaultValue.rawValue
    @AppStorage(HanaSettingsKey.allowResumePlayback) private var allowResumePlayback = true
    @AppStorage(HanaSettingsKey.showPlayedIndicator) private var showPlayedIndicator = true
    @AppStorage(HanaSettingsKey.videoLanguage) private var videoLanguage = HanaVideoLanguagePreference.zhHans.rawValue
    @AppStorage(HanaSettingsKey.pictureInPictureEnabled) private var pictureInPictureEnabled = true
    @AppStorage(HanaSettingsKey.playerLongPressRate) private var playerLongPressRate = HanaPlaybackSpeedCatalog.defaultLongPressRate

    var body: some View {
        Form {
            Section("播放器") {
                Picker(selection: defaultVideoQualityBinding) {
                    ForEach(HanaVideoQualityPreference.allCases) { quality in
                        Text(quality.title).tag(quality.rawValue)
                    }
                } label: {
                    Label("默认清晰度", systemImage: "slider.horizontal.3")
                }
                Picker(selection: $videoLanguage) {
                    ForEach(HanaVideoLanguagePreference.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                } label: {
                    Label("字幕语言", systemImage: "captions.bubble")
                }
                Toggle(isOn: $pictureInPictureEnabled) {
                    Label("画中画", systemImage: "pip")
                }
            }

            Section("手势") {
                Picker(selection: longPressRateBinding) {
                    ForEach(HanaPlaybackSpeedCatalog.longPressRates, id: \.self) { rate in
                        Text(HanaPlaybackSpeedCatalog.title(for: rate)).tag(rate)
                    }
                } label: {
                    Label("长按倍速", systemImage: "forward")
                }
            }

            Section("记录") {
                Toggle(isOn: $allowResumePlayback) {
                    Label("继续上次进度", systemImage: "clock.arrow.circlepath")
                }
                Toggle(isOn: $showPlayedIndicator) {
                    Label("显示已看标记", systemImage: "checkmark.circle")
                }
            }
        }
        .navigationTitle("播放")
        .onAppear {
            videoLanguage = HanaVideoLanguagePreference.normalizedRawValue(videoLanguage)
        }
    }

    private var longPressRateBinding: Binding<Double> {
        Binding {
            HanaPlaybackSpeedCatalog.normalizedLongPressRate(playerLongPressRate)
        } set: { newValue in
            playerLongPressRate = newValue
        }
    }

    private var defaultVideoQualityBinding: Binding<String> {
        Binding {
            HanaVideoQualityPreference.normalizedRawValue(defaultVideoQuality)
        } set: { newValue in
            defaultVideoQuality = newValue
        }
    }
}

private struct DownloadSettingsScreen: View {
    @Environment(HanaServices.self) private var services
    @AppStorage(HanaSettingsKey.defaultDownloadQuality) private var defaultDownloadQuality = HanaVideoQualityPreference.defaultValue.rawValue
    @AppStorage(HanaSettingsKey.downloadConcurrency) private var downloadConcurrency = 2
    @AppStorage(HanaSettingsKey.warnBeforeMobileDataDownload) private var warnBeforeMobileDataDownload = true
    @State private var downloadDirectoryName = HanaDownloadDirectoryPreference.displayName()
    @State private var isDirectoryImporterPresented = false
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?

    var body: some View {
        Form {
            Section("任务") {
                Picker(selection: defaultDownloadQualityBinding) {
                    ForEach(HanaVideoQualityPreference.allCases) { quality in
                        Text(quality.title).tag(quality.rawValue)
                    }
                } label: {
                    Label("下载偏好", systemImage: "arrow.down.circle")
                }
                Stepper(value: $downloadConcurrency, in: 1...5) {
                    LabeledContent {
                        Text("\(downloadConcurrency)")
                    } label: {
                        Label("同时下载", systemImage: "number")
                    }
                }
            }

            Section("网络") {
                Toggle(isOn: $warnBeforeMobileDataDownload) {
                    Label("蜂窝网络下载前提醒", systemImage: "antenna.radiowaves.left.and.right")
                }
            }

            Section("目录") {
                LabeledContent {
                    Text(downloadDirectoryName)
                } label: {
                    Label("位置", systemImage: "folder")
                }

                Button {
                    isDirectoryImporterPresented = true
                } label: {
                    Label("选择外部目录", systemImage: "folder.badge.plus")
                }

                Button {
                    exportDownloadsToExternalDirectory()
                } label: {
                    Label("导出到外部目录", systemImage: "square.and.arrow.up")
                }
                .disabled(HanaDownloadDirectoryPreference.resolvedExternalDirectory() == nil)

                Button {
                    importDownloadsFromExternalDirectory()
                } label: {
                    Label("从外部目录导入", systemImage: "square.and.arrow.down")
                }
                .disabled(HanaDownloadDirectoryPreference.resolvedExternalDirectory() == nil)

                Button(role: .destructive) {
                    HanaDownloadDirectoryPreference.clear()
                    refreshDownloadDirectoryName()
                    toastMessage = .success("已改回应用目录")
                } label: {
                    Label("使用应用目录", systemImage: "internaldrive")
                }
            }
        }
        .navigationTitle("下载")
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .fileImporter(
            isPresented: $isDirectoryImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleDownloadDirectoryImport(result)
        }
        .onAppear {
            refreshDownloadDirectoryName()
        }
    }

    private func handleDownloadDirectoryImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try HanaDownloadDirectoryPreference.saveExternalDirectory(url)
            refreshDownloadDirectoryName()
            toastMessage = .success("已选择 \(url.lastPathComponent)")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private var defaultDownloadQualityBinding: Binding<String> {
        Binding {
            HanaVideoQualityPreference.normalizedRawValue(defaultDownloadQuality)
        } set: { newValue in
            defaultDownloadQuality = newValue
        }
    }

    private func exportDownloadsToExternalDirectory() {
        do {
            let count = try services.downloadClient.exportDownloadsToExternalDirectory()
            toastMessage = .success("已导出 \(count) 个文件")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private func importDownloadsFromExternalDirectory() {
        do {
            let count = try services.downloadClient.importDownloadsFromExternalDirectory()
            toastMessage = .success("已导入 \(count) 个文件")
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }

    private func refreshDownloadDirectoryName() {
        downloadDirectoryName = HanaDownloadDirectoryPreference.displayName()
    }
}

private struct AppearanceSettingsScreen: View {
    @AppStorage(HanaSettingsKey.appearanceMode) private var appearanceMode = HanaAppearanceMode.system.rawValue
    @AppStorage(HanaSettingsKey.themeColor) private var themeColor = HanaThemeColor.defaultValue

    var body: some View {
        Form {
            Picker(selection: $appearanceMode) {
                ForEach(HanaAppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode.rawValue)
                }
            } label: {
                Text("主题")
            }
            .pickerStyle(.inline)

            Picker(selection: $themeColor) {
                ForEach(HanaThemeColor.allCases) { theme in
                    ThemeColorOptionLabel(theme: theme)
                        .tag(theme.rawValue)
                }
            } label: {
                Text("色彩")
            }
            .pickerStyle(.inline)
        }
        .navigationTitle("外观")
    }
}

private struct ThemeColorOptionLabel: View {
    let theme: HanaThemeColor

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(theme.color)
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .stroke(.secondary.opacity(0.25), lineWidth: 1)
                }
            Text(theme.title)
        }
    }
}

private struct NetworkSettingsScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.hanaReloadServices) private var reloadServices
    @AppStorage(HanaSettingsKey.siteBaseURL) private var storedSiteBaseURL = HanaSiteBaseURL.defaultValue
    @AppStorage(HanaSettingsKey.networkProxyMode) private var proxyMode = HanaNetworkProxyMode.system.rawValue
    @AppStorage(HanaSettingsKey.networkProxyHost) private var proxyHost = ""
    @AppStorage(HanaSettingsKey.networkProxyPort) private var proxyPort = 7890
    @State private var selectedBaseURL = HanaSiteBaseURL.defaultValue
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var latencyResults: [SiteLatencyResult] = []
    @State private var isTestingLatency = false
    @State private var isCredentialLoginPresented = false

    var body: some View {
        List {
            Section("站点") {
                LabeledContent {
                    Text(services.httpClient.baseURL.absoluteString)
                } label: {
                    Label("地址", systemImage: "link")
                }
                LabeledContent {
                    Text("\(services.siteSession.lastSyncedCookieCount)")
                } label: {
                    Label("Cookie", systemImage: "doc.badge.gearshape")
                }
                if let date = services.siteSession.lastCookieSyncAt {
                    LabeledContent {
                        Text(date.hanaChineseDateTimeText)
                    } label: {
                        Label("同步时间", systemImage: "clock.arrow.circlepath")
                    }
                }
            }

            Section("站点地址") {
                Picker(selection: selectedBaseURLBinding) {
                    ForEach(HanaSiteBaseURL.options, id: \.self) { url in
                        Text(url).tag(url)
                    }
                    if !HanaSiteBaseURL.options.contains(selectedBaseURL) {
                        Text(selectedBaseURL).tag(selectedBaseURL)
                    }
                } label: {
                    Label("当前选择", systemImage: "globe")
                }
            }

            Section("代理") {
                Picker(selection: $proxyMode) {
                    ForEach(HanaNetworkProxyMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                } label: {
                    Label("模式", systemImage: "network")
                }

                if selectedProxyMode.requiresEndpoint {
                    LabeledContent {
                        TextField("主机", text: $proxyHost)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("主机", systemImage: "server.rack")
                    }
                    LabeledContent {
                        TextField("端口", value: $proxyPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("端口", systemImage: "number")
                    }
                }

                Button {
                    applyNetworkSettings()
                } label: {
                    Label("应用网络设置", systemImage: "network")
                }
            }

            Section("站点测速") {
                Button {
                    Task { await runLatencyTests() }
                } label: {
                    if isTestingLatency {
                        Label("测速中", systemImage: "hourglass")
                    } else {
                        Label("测试内置地址", systemImage: "speedometer")
                    }
                }
                .disabled(isTestingLatency)

                ForEach(latencyResults) { result in
                    LabeledContent {
                        Text(result.summary)
                            .foregroundStyle(result.isReachable ? Color.secondary : Color.red)
                    } label: {
                        Label(result.url.host() ?? result.url.absoluteString, systemImage: "globe")
                    }
                }
            }

            Section("当前网络") {
                LabeledContent {
                    Text(services.networkMonitor.statusTitle)
                } label: {
                    Label("状态", systemImage: "wave.3.right")
                }
                LabeledContent {
                    Text(services.networkMonitor.usesCellular ? "是" : "否")
                } label: {
                    Label("蜂窝网络", systemImage: "antenna.radiowaves.left.and.right")
                }
                LabeledContent {
                    Text(services.networkMonitor.isExpensive ? "是" : "否")
                } label: {
                    Label("按流量计费", systemImage: "gauge.with.dots.needle.67percent")
                }
            }

            Section("验证") {
                Button {
                    services.siteSession.requestLogin()
                } label: {
                    Label("登录站点", systemImage: "person.crop.circle")
                }
                Button {
                    isCredentialLoginPresented = true
                } label: {
                    Label("账号密码登录", systemImage: "key")
                }
                Button {
                    services.siteSession.requestCloudflareVerification()
                } label: {
                    Label("站点验证", systemImage: "shield")
                }
                Button(role: .destructive) {
                    services.logout()
                } label: {
                    Label("清除站点登录状态", systemImage: "trash")
                }
            }
        }
        .navigationTitle("网络与站点")
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .sheet(isPresented: $isCredentialLoginPresented) {
            SiteCredentialLoginSheet()
        }
        .onAppear {
            selectedBaseURL = services.httpClient.baseURL.absoluteString
        }
    }

    private var selectedBaseURLBinding: Binding<String> {
        Binding(
            get: { selectedBaseURL },
            set: { newValue in
                selectedBaseURL = newValue
                applySiteBaseURL(newValue)
            }
        )
    }

    private var selectedProxyMode: HanaNetworkProxyMode {
        HanaNetworkProxyMode(rawValue: proxyMode) ?? .system
    }

    private func applyNetworkSettings() {
        guard !services.downloadClient.hasActiveDownloads else {
            alertMessage = .error("有下载进行中，完成或取消后再应用网络设置")
            return
        }
        guard selectedProxyMode.requiresEndpoint == false || proxyPort > 0 else {
            alertMessage = .error("代理端口无效")
            return
        }
        reloadServices(services.httpClient.baseURL)
        toastMessage = .success("网络设置已应用")
    }

    private func runLatencyTests() async {
        isTestingLatency = true
        latencyResults = []
        defer { isTestingLatency = false }

        for url in siteCandidates() {
            let result = await measureSiteLatency(url)
            latencyResults.append(result)
        }
    }

    private func siteCandidates() -> [URL] {
        let rawValues = HanaSiteBaseURL.options
        var seen = Set<String>()
        return rawValues.compactMap { value in
            guard let normalized = HanaSiteBaseURL.normalized(value),
                  seen.insert(normalized).inserted,
                  let url = URL(string: normalized) else {
                return nil
            }
            return url
        }
    }

    private func measureSiteLatency(_ url: URL) async -> SiteLatencyResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.connectionProxyDictionary = HanaNetworkProxySettings.current().connectionProxyDictionary
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(HanaHTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let startedAt = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            return SiteLatencyResult(
                url: url,
                milliseconds: milliseconds,
                status: statusCode.map { "HTTP \($0)" } ?? "响应有效",
                isReachable: statusCode.map { (200..<500).contains($0) } ?? true
            )
        } catch {
            let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
            return SiteLatencyResult(
                url: url,
                milliseconds: milliseconds,
                status: error.localizedDescription,
                isReachable: false
            )
        }
    }

    private func applySiteBaseURL(_ value: String) {
        guard let normalized = HanaSiteBaseURL.normalized(value),
              let url = URL(string: normalized) else {
            alertMessage = .error("地址无效")
            return
        }
        if services.httpClient.baseURL.absoluteString == normalized {
            storedSiteBaseURL = normalized
            selectedBaseURL = normalized
            toastMessage = .info("当前正在使用该地址")
            return
        }
        guard !services.downloadClient.hasActiveDownloads else {
            selectedBaseURL = services.httpClient.baseURL.absoluteString
            alertMessage = .error("有下载进行中，完成或取消后再切换站点")
            return
        }
        storedSiteBaseURL = normalized
        selectedBaseURL = normalized
        reloadServices(url)
        toastMessage = .success("已切换到 \(url.host() ?? normalized)")
    }
}

private struct SiteLatencyResult: Identifiable, Hashable {
    var id: String { url.absoluteString }

    let url: URL
    let milliseconds: Int
    let status: String
    let isReachable: Bool

    var summary: String {
        "\(milliseconds) ms · \(status)"
    }
}

private struct LocalDataSettingsScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SearchHistoryRecord.createdAt, order: .reverse) private var searchHistory: [SearchHistoryRecord]
    @Query(sort: \AdvancedSearchHistoryRecord.createdAt, order: .reverse) private var advancedSearchHistory: [AdvancedSearchHistoryRecord]
    @Query(sort: \WatchHistoryRecord.watchDate, order: .reverse) private var watchHistory: [WatchHistoryRecord]
    @Query(sort: \FavoriteVideoRecord.createdAt, order: .reverse) private var favorites: [FavoriteVideoRecord]
    @Query(sort: \WatchLaterRecord.createdAt, order: .reverse) private var watchLaterItems: [WatchLaterRecord]
    @Query(sort: \PlaylistRecord.updatedAt, order: .reverse) private var playlists: [PlaylistRecord]
    @Query(sort: \PlaylistItemRecord.createdAt, order: .reverse) private var playlistItems: [PlaylistItemRecord]
    @Query(sort: \DownloadQueueRecord.createdAt, order: .reverse) private var downloadQueue: [DownloadQueueRecord]
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var hKeyframeRecords: [HKeyframeRecord]
    @State private var pendingDeletion: LocalDataDeletionTarget?
    @State private var toastMessage: HanaToastMessage?

    var body: some View {
        List {
            Section("记录数量") {
                LabeledContent {
                    Text("\(watchHistory.count)")
                } label: {
                    Label("观看历史", systemImage: "clock.arrow.circlepath")
                }
                LabeledContent {
                    Text("\(searchHistory.count)")
                } label: {
                    Label("搜索历史", systemImage: "magnifyingglass")
                }
                LabeledContent {
                    Text("\(advancedSearchHistory.count)")
                } label: {
                    Label("高级搜索历史", systemImage: "line.3.horizontal.decrease.circle")
                }
                LabeledContent {
                    Text("\(favorites.count)")
                } label: {
                    Label("喜欢的影片", systemImage: "heart")
                }
                LabeledContent {
                    Text("\(watchLaterItems.count)")
                } label: {
                    Label("稍后观看", systemImage: "clock")
                }
                LabeledContent {
                    Text("\(playlists.count)")
                } label: {
                    Label("播放清单", systemImage: "list.bullet.rectangle")
                }
                LabeledContent {
                    Text("\(playlistItems.count)")
                } label: {
                    Label("清单项目", systemImage: "rectangle.stack")
                }
                LabeledContent {
                    Text("\(downloadQueue.count)")
                } label: {
                    Label("下载队列", systemImage: "arrow.down.circle")
                }
                LabeledContent {
                    Text("\(hKeyframeRecords.count)")
                } label: {
                    Label("HKeyframes", systemImage: "bookmark")
                }
            }

            Section("数据管理") {
                LocalDataDeletionButton(
                    title: "删除观看历史",
                    systemImage: "clock.arrow.circlepath",
                    count: watchHistory.count,
                    target: .watchHistory,
                    pendingDeletion: $pendingDeletion
                )
                LocalDataDeletionButton(
                    title: "删除搜索历史",
                    systemImage: "magnifyingglass",
                    count: searchHistory.count + advancedSearchHistory.count,
                    target: .searchHistory,
                    pendingDeletion: $pendingDeletion
                )
                LocalDataDeletionButton(
                    title: "删除账号缓存",
                    systemImage: "person.crop.circle.badge.xmark",
                    count: favorites.count + watchLaterItems.count + playlists.count + playlistItems.count,
                    target: .accountCache,
                    pendingDeletion: $pendingDeletion
                )
                LocalDataDeletionButton(
                    title: "删除下载记录与文件",
                    systemImage: "arrow.down.circle",
                    count: downloadQueue.count,
                    target: .downloads,
                    pendingDeletion: $pendingDeletion
                )
                LocalDataDeletionButton(
                    title: "删除 HKeyframes",
                    systemImage: "bookmark",
                    count: hKeyframeRecords.count,
                    target: .hKeyframes,
                    pendingDeletion: $pendingDeletion
                )
                LocalDataDeletionButton(
                    title: "删除全部本地数据",
                    systemImage: "trash",
                    count: totalRecordCount,
                    target: .all,
                    pendingDeletion: $pendingDeletion
                )
            }

        }
        .navigationTitle("本地数据")
        .hanaToast($toastMessage)
        .confirmationDialog(
            pendingDeletion?.confirmationTitle ?? "删除数据",
            isPresented: deletionDialogBinding,
            titleVisibility: .visible
        ) {
            if let pendingDeletion {
                Button(pendingDeletion.actionTitle, role: .destructive) {
                    delete(pendingDeletion)
                }
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            if let pendingDeletion {
                Text(pendingDeletion.confirmationMessage)
            }
        }
    }

    private var totalRecordCount: Int {
        watchHistory.count
            + searchHistory.count
            + advancedSearchHistory.count
            + favorites.count
            + watchLaterItems.count
            + playlists.count
            + playlistItems.count
            + downloadQueue.count
            + hKeyframeRecords.count
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding {
            pendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                pendingDeletion = nil
            }
        }
    }

    private func delete(_ target: LocalDataDeletionTarget) {
        switch target {
        case .watchHistory:
            watchHistory.forEach(modelContext.delete)
        case .searchHistory:
            searchHistory.forEach(modelContext.delete)
            advancedSearchHistory.forEach(modelContext.delete)
        case .accountCache:
            favorites.forEach(modelContext.delete)
            watchLaterItems.forEach(modelContext.delete)
            playlists.forEach(modelContext.delete)
            playlistItems.forEach(modelContext.delete)
        case .downloads:
            deleteDownloadFiles()
            downloadQueue.forEach(modelContext.delete)
        case .hKeyframes:
            hKeyframeRecords.forEach(modelContext.delete)
        case .all:
            watchHistory.forEach(modelContext.delete)
            searchHistory.forEach(modelContext.delete)
            advancedSearchHistory.forEach(modelContext.delete)
            favorites.forEach(modelContext.delete)
            watchLaterItems.forEach(modelContext.delete)
            playlists.forEach(modelContext.delete)
            playlistItems.forEach(modelContext.delete)
            deleteDownloadFiles()
            downloadQueue.forEach(modelContext.delete)
            hKeyframeRecords.forEach(modelContext.delete)
        }
        try? modelContext.save()
        toastMessage = .success("\(target.title)已删除")
        pendingDeletion = nil
    }

    private func deleteDownloadFiles() {
        for item in downloadQueue {
            services.downloadClient.cancel(id: item.id)
            guard let localFileURLString = item.localFileURLString,
                  let url = URL(string: localFileURLString),
                  FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            try? services.downloadClient.deleteLocalDownload(fileURL: url)
        }
    }
}

private enum LocalDataDeletionTarget: Identifiable {
    case watchHistory
    case searchHistory
    case accountCache
    case downloads
    case hKeyframes
    case all

    var id: String { title }

    var title: String {
        switch self {
        case .watchHistory:
            "观看历史"
        case .searchHistory:
            "搜索历史"
        case .accountCache:
            "账号缓存"
        case .downloads:
            "下载记录与文件"
        case .hKeyframes:
            "HKeyframes"
        case .all:
            "全部本地数据"
        }
    }

    var confirmationTitle: String {
        "确认删除\(title)"
    }

    var confirmationMessage: String {
        switch self {
        case .downloads:
            "会删除下载记录，并尝试删除本地视频文件。"
        case .hKeyframes:
            "会删除本机保存的 HKeyframes。"
        case .all:
            "会删除观看历史、搜索历史、账号缓存、播放清单、下载记录、HKeyframes，并尝试删除本地视频文件。"
        default:
            "该操作只影响本机保存的数据。"
        }
    }

    var actionTitle: String {
        "删除\(title)"
    }
}

private struct LocalDataDeletionButton: View {
    let title: String
    let systemImage: String
    let count: Int
    let target: LocalDataDeletionTarget
    @Binding var pendingDeletion: LocalDataDeletionTarget?

    var body: some View {
        Button(role: .destructive) {
            pendingDeletion = target
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(count == 0)
    }
}
