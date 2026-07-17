import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

struct SettingsScreen: View {
    @AppStorage(HanaSettingsKey.appearanceMode) private var appearanceMode = HanaAppearanceMode.system.rawValue
#if !os(macOS)
    @AppStorage(HanaSettingsKey.themeColor) private var themeColor = HanaThemeColor.defaultValue
#endif

    var body: some View {
        themedContent
    }

    @ViewBuilder
    private var themedContent: some View {
#if os(macOS)
        macThemedContent
#else
        mobileThemedContent
#endif
    }

#if os(macOS)
    @ViewBuilder
    private var macThemedContent: some View {
        let baseContent = content
            .tint(appThemeColor)
            .accentColor(appThemeColor)

        baseContent
            .onAppear {
                applyMacOSAppearance(appAppearanceMode)
            }
            .onChange(of: appAppearanceMode) { _, mode in
                applyMacOSAppearance(mode)
            }
    }

    private func applyMacOSAppearance(_ mode: HanaAppearanceMode) {
        mode.applyToApplication()
    }
#else
    @ViewBuilder
    private var mobileThemedContent: some View {
        let baseContent = content
            .tint(appThemeColor)
            .accentColor(appThemeColor)

        if let colorScheme = appAppearanceMode.colorScheme {
            baseContent.preferredColorScheme(colorScheme)
        } else {
            baseContent
        }
    }
#endif

    @ViewBuilder
    private var content: some View {
#if os(macOS)
        MacSettingsScreen()
#else
        MobileSettingsScreen()
#endif
    }

    private var appAppearanceMode: HanaAppearanceMode {
        HanaAppearanceMode(rawValue: appearanceMode) ?? .system
    }

    private var appThemeColor: Color {
#if os(macOS)
        .pink
#else
        (HanaThemeColor(rawValue: themeColor) ?? .pink).color
#endif
    }
}

private struct MobileSettingsScreen: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    PlaybackSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .playback)
                }
                NavigationLink {
                    HKeyframeSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .hKeyframes)
                }
                NavigationLink {
                    DownloadSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .downloads)
                }
                NavigationLink {
                    AppearanceSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .appearance)
                }
                NavigationLink {
                    NetworkSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .network)
                }
                NavigationLink {
                    LocalDataSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .localData)
                }
                NavigationLink {
                    AboutSettingsScreen()
                } label: {
                    SettingsNavigationRow(category: .about)
                }
            }
        }
        .navigationTitle("设置")
    }
}

#if os(macOS)
private struct MacSettingsScreen: View {
    @State private var selection = MacSettingsCategory.general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    settingsSidebarItem(.general)
                    settingsSidebarItem(.playback)
                }

                Section {
                    settingsSidebarItem(.hKeyframes)
                    settingsSidebarItem(.downloads)
                    settingsSidebarItem(.network)
                    settingsSidebarItem(.localData)
                }

                Section {
                    settingsSidebarItem(.about)
                }
            }
            .frame(minWidth: 180)
            .tint(appThemeColor)
            .accentColor(appThemeColor)
        } detail: {
            NavigationStack {
                settingsDetail(for: selection)
                    .formStyle(.grouped)
            }
            .tint(appThemeColor)
            .accentColor(appThemeColor)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 600)
        .tint(appThemeColor)
        .accentColor(appThemeColor)
    }

    private var appThemeColor: Color {
        .pink
    }

    private func settingsSidebarItem(_ category: MacSettingsCategory) -> some View {
        Label(category.title, systemImage: category.systemImage)
            .tag(category)
            .labelStyle(MacSettingsSidebarLabelStyle(tint: category.tint, iconSize: category.iconSize))
    }

    @ViewBuilder
    private func settingsDetail(for category: MacSettingsCategory) -> some View {
        switch category {
        case .general:
            MacGeneralSettingsScreen()
        case .playback:
            PlaybackSettingsScreen()
        case .hKeyframes:
            HKeyframeSettingsScreen()
        case .downloads:
            DownloadSettingsScreen()
        case .network:
            NetworkSettingsScreen()
        case .localData:
            LocalDataSettingsScreen()
        case .about:
            AboutSettingsScreen()
        }
    }
}

private enum MacSettingsCategory: String, CaseIterable, Identifiable {
    case general
    case playback
    case hKeyframes
    case downloads
    case network
    case localData
    case about

    var id: String { rawValue }

    var title: String {
        settingsCategory.title
    }

    var systemImage: String {
        settingsCategory.systemImage
    }

    var tint: Color {
        settingsCategory.tint
    }

    var iconSize: CGFloat {
        switch self {
        case .playback:
            12
        case .about:
            13
        case .general, .hKeyframes, .downloads, .network, .localData:
            14
        }
    }

    private var settingsCategory: SettingsCategory {
        switch self {
        case .general:
            .general
        case .playback:
            .playback
        case .hKeyframes:
            .hKeyframes
        case .downloads:
            .downloads
        case .network:
            .network
        case .localData:
            .localData
        case .about:
            .about
        }
    }
}

private struct MacSettingsSidebarLabelStyle: LabelStyle {
    let tint: Color
    let iconSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            configuration.title
        }
    }
}

private struct MacGeneralSettingsScreen: View {
    @AppStorage(HanaSettingsKey.appearanceMode) private var appearanceMode = HanaAppearanceMode.system.rawValue
    @AppStorage(HanaSettingsKey.themeColor) private var themeColor = HanaThemeColor.defaultValue
    @AppStorage(HanaSettingsKey.demoModeEnabled) private var demoModeEnabled = false

    var body: some View {
        Form {
            Section("外观") {
                MacSettingsOptionPicker(
                    title: "主题",
                    options: HanaAppearanceMode.allCases,
                    selection: appearanceModeBinding,
                    animateSelection: false
                ) { mode, isSelected in
                    MacAppearanceModePreview(mode: mode, isSelected: isSelected)
                } label: { mode, _ in
                    mode.title
                }

                MacSettingsOptionPicker(
                    title: "色彩",
                    options: HanaThemeColor.allCases.map(\.rawValue),
                    selection: $themeColor
                ) { rawValue, isSelected in
                    MacThemeColorPreview(theme: themeColorOption(for: rawValue), isSelected: isSelected)
                } label: { rawValue, isSelected in
                    isSelected ? themeColorOption(for: rawValue).title : nil
                }
                .disabled(true)
                .grayscale(1)
                .opacity(0.45)
                .accessibilityHint("macOS 版本固定使用粉色")

                Toggle(isOn: $demoModeEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("演示模式")
                        Text("开启后会模糊视频封面")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("常规")
        .onAppear {
            resetMacOSThemeColorIfNeeded()
        }
        .onChange(of: themeColor) {
            resetMacOSThemeColorIfNeeded()
        }
    }

    private var appearanceModeBinding: Binding<HanaAppearanceMode> {
        Binding {
            HanaAppearanceMode(rawValue: appearanceMode) ?? .system
        } set: { mode in
            appearanceMode = mode.rawValue
            mode.applyToApplication()
        }
    }

    private func themeColorOption(for rawValue: String) -> HanaThemeColor {
        HanaThemeColor(rawValue: rawValue) ?? .pink
    }

    private func resetMacOSThemeColorIfNeeded() {
        guard themeColor != HanaThemeColor.defaultValue else { return }
        themeColor = HanaThemeColor.defaultValue
    }
}

private struct MacSettingsOptionPicker<Option: Hashable, Content: View>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let animateSelection: Bool
    let content: (Option, Bool) -> Content
    let label: (Option, Bool) -> String?

    init(
        title: String,
        options: [Option],
        selection: Binding<Option>,
        animateSelection: Bool = true,
        @ViewBuilder content: @escaping (Option, Bool) -> Content,
        label: @escaping (Option, Bool) -> String?
    ) {
        self.title = title
        self.options = options
        _selection = selection
        self.animateSelection = animateSelection
        self.content = content
        self.label = label
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 20)

            HStack(alignment: .top, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection == option
                    let labelText = label(option, isSelected)

                    Button {
                        updateSelection(option)
                    } label: {
                        VStack(spacing: 4) {
                            content(option, isSelected)

                            Text(labelText ?? "")
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .frame(minHeight: 16)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(labelText ?? "")
                    .accessibilityValue(isSelected ? "已选择" : "未选择")
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func updateSelection(_ option: Option) {
        if animateSelection {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = option
            }
        } else {
            selection = option
        }
    }
}

private struct MacAppearanceModePreview: View {
    let mode: HanaAppearanceMode
    let isSelected: Bool

    var body: some View {
        ZStack {
            previewBackground
                .frame(width: 100, height: 64)

            HStack(spacing: 5) {
                previewPane(width: 30, color: sidebarColor)
                previewPane(width: 48, color: contentColor)
            }

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? selectionTint : Color.clear, lineWidth: 3)
        }
        .frame(width: 100, height: 64)
    }

    @ViewBuilder
    private var previewBackground: some View {
        switch mode {
        case .system:
            MacDiagonalAppearancePreviewShape()
                .fill(Color.white)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.8))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .light:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
        case .dark:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.8))
        }
    }

    @ViewBuilder
    private func previewPane(width: CGFloat, color: Color) -> some View {
        switch mode {
        case .system:
            MacDiagonalAppearancePreviewShape()
                .fill(Color.gray.opacity(0.18))
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .frame(width: width, height: 46)
        case .light, .dark:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color)
                .frame(width: width, height: 46)
        }
    }

    private var sidebarColor: Color {
        switch mode {
        case .system:
            Color.clear
        case .light:
            Color.gray.opacity(0.18)
        case .dark:
            Color.white.opacity(0.14)
        }
    }

    private var contentColor: Color {
        switch mode {
        case .system:
            Color.primary.opacity(0.12)
        case .light:
            Color.gray.opacity(0.08)
        case .dark:
            Color.white.opacity(0.08)
        }
    }

    private var selectionTint: Color {
        .pink
    }
}

private struct MacDiagonalAppearancePreviewShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MacThemeColorPreview: View {
    let theme: HanaThemeColor
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(theme.color)
            .frame(width: 24, height: 24)
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .overlay {
                Circle()
                    .strokeBorder(isSelected ? selectionTint : Color.clear, lineWidth: 3)
                    .padding(-3)
            }
            .frame(width: 34, height: 34)
    }

    private var selectionTint: Color {
        .pink
    }
}

#endif

private struct AboutSettingsScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.openURL) private var openURL
    @AppStorage(HanaSettingsKey.autoCheckForUpdates) private var autoCheckForUpdates = true
    @AppStorage(HanaSettingsKey.updateLinkDestination) private var updateLinkDestination = HanaUpdateLinkDestination.defaultValue
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?
    @State private var availableUpdate: HanaAvailableUpdate?

    var body: some View {
        Form {
            Section {
                SettingsAppFooter()
                    .contentShape(Rectangle())
                    .onLongPressGesture {
                        let displayVersion = SettingsAppFooter.displayVersionText
                        guard !displayVersion.isEmpty else { return }
                        HanaPasteboard.string = displayVersion
                        toastMessage = .info("已复制版本号")
                    }
            }

            Section {
                Toggle(isOn: $autoCheckForUpdates) {
                    Label("自动检查", systemImage: "arrow.triangle.2.circlepath")
                }

#if os(iOS)
                Picker(selection: $updateLinkDestination) {
                    ForEach(HanaUpdateLinkDestination.allCases) { destination in
                        Text(destination.title).tag(destination.rawValue)
                    }
                } label: {
                    Label("打开方式", systemImage: "arrow.up.forward.app")
                }
#endif

                Button {
                    Task { await checkForUpdates() }
                } label: {
                    if services.updateChecker.isChecking {
                        Label("检查中", systemImage: "hourglass")
                    } else {
                        Label("检查更新", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(services.updateChecker.isChecking)
            } header: {
                Text("更新")
            } footer: {
                Text(updateFooterText)
            }

            Section("项目") {
                Button {
                    openURL(HanaUpdateChecker.websiteURL)
                } label: {
                    Label("项目网站", systemImage: "safari")
                }

                Button {
                    openURL(HanaUpdateChecker.repositoryURL)
                } label: {
                    Label("GitHub 仓库", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button {
                    openURL(HanaUpdateChecker.releasesURL)
                } label: {
                    Label("Releases 页面", systemImage: "tag")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("关于")
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .hanaUpdateAlert(update: $availableUpdate)
    }

    private var updateFooterText: String {
#if os(iOS)
        "开启后，应用会每天检查更新。选择侧载工具时，发现新版可跳转对应 App。"
#else
        "开启后，应用会每天检查更新。"
#endif
    }

    private func checkForUpdates() async {
        do {
            let result = try await services.updateChecker.checkManually()
            switch result {
            case .updateAvailable(let update):
                availableUpdate = update
            case .upToDate:
                toastMessage = .success("已是最新版本")
            case .noRelease:
                alertMessage = HanaAlertMessage(title: "暂无 Release", message: "GitHub 上还没有可用于检查的正式 Release。")
            }
        } catch {
            alertMessage = .error(error.localizedDescription)
        }
    }
}

private struct SettingsNavigationRow: View {
    let category: SettingsCategory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(category.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .foregroundStyle(.primary)
                Text(category.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private enum SettingsCategory {
    case general
    case playback
    case hKeyframes
    case downloads
    case appearance
    case network
    case localData
    case about

    var title: String {
        switch self {
        case .general:
            "常规"
        case .playback:
            "播放"
        case .hKeyframes:
            "HKeyframes"
        case .downloads:
            "下载"
        case .appearance:
            "外观"
        case .network:
            "网络与站点"
        case .localData:
            "本地数据"
        case .about:
            "关于"
        }
    }

    var description: String {
        switch self {
        case .general:
            "主题、色彩和演示模式"
        case .playback:
            "清晰度、字幕、手势和播放记录"
        case .hKeyframes:
            "播放提醒、共享关键帧和本地管理"
        case .downloads:
            "下载质量、并发、网络提醒和目录"
        case .appearance:
            "跟随系统，或固定浅色、深色"
        case .network:
            "站点地址、代理、测速和验证"
        case .localData:
            "查看数量，删除本机保存的记录"
        case .about:
            "版本、更新检查和项目页面"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .playback:
            "play.rectangle"
        case .hKeyframes:
            "bookmark"
        case .downloads:
            "arrow.down.circle"
        case .appearance:
            "circle.lefthalf.filled"
        case .network:
            "network"
        case .localData:
            "internaldrive"
        case .about:
            "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general:
            .red
        case .playback:
            .blue
        case .hKeyframes:
            .purple
        case .downloads:
            .green
        case .appearance:
            .pink
        case .network:
            .orange
        case .localData:
            .brown
        case .about:
            .gray
        }
    }
}

private struct PlaybackSettingsScreen: View {
    @AppStorage(HanaSettingsKey.defaultVideoQuality) private var defaultVideoQuality = HanaVideoQualityPreference.defaultValue.rawValue
    @AppStorage(HanaSettingsKey.allowResumePlayback) private var allowResumePlayback = true
    @AppStorage(HanaSettingsKey.showPlayedIndicator) private var showPlayedIndicator = true
    @AppStorage(HanaSettingsKey.videoLanguage) private var videoLanguage = HanaVideoLanguagePreference.zhHans.rawValue
    @AppStorage(HanaSettingsKey.pictureInPictureEnabled) private var pictureInPictureEnabled = true
    @AppStorage(HanaSettingsKey.loopPlaybackEnabled) private var loopPlaybackEnabled = false
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
                Toggle(isOn: $loopPlaybackEnabled) {
                    Label("循环播放", systemImage: "repeat")
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
    @AppStorage(HanaSettingsKey.demoModeEnabled) private var demoModeEnabled = false

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

            Section {
                Toggle("演示模式", isOn: $demoModeEnabled)
            } footer: {
                Text("开启后会模糊视频封面图片")
            }
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
        Form {
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
                            .hanaTextInputAutocapitalizationNever()
                            .hanaURLKeyboard()
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("主机", systemImage: "server.rack")
                    }
                    LabeledContent {
                        TextField("端口", value: $proxyPort, format: .number)
                            .hanaNumberKeyboard()
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
                    Task { await services.logout() }
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
    @Query(sort: \DownloadQueueRecord.createdAt, order: .reverse) private var downloadQueue: [DownloadQueueRecord]
    @Query(sort: \HKeyframeRecord.updatedAt, order: .reverse) private var hKeyframeRecords: [HKeyframeRecord]
    @State private var pendingDeletion: LocalDataDeletionTarget?
    @State private var toastMessage: HanaToastMessage?

    var body: some View {
        Form {
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
        case .downloads:
            deleteDownloadFiles()
            downloadQueue.forEach(modelContext.delete)
        case .hKeyframes:
            hKeyframeRecords.forEach(modelContext.delete)
        case .all:
            watchHistory.forEach(modelContext.delete)
            searchHistory.forEach(modelContext.delete)
            advancedSearchHistory.forEach(modelContext.delete)
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
            "会删除观看历史、搜索历史、下载记录、HKeyframes，并尝试删除本地视频文件。"
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
