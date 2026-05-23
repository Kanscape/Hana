import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PreviewMonthScreen: View {
    @Environment(HanaServices.self) private var services
    @State private var selectedMonth = Date()
    @State private var state: LoadableState<HanimePreviewPage> = .idle
    @State private var isMonthPickerPresented = false
    @State private var cachedPages: [String: HanimePreviewPage] = [:]
    @State private var prefetchedComments: [String: HanimeCommentsPage] = [:]
    @State private var preloadingMonthCodes = Set<String>()

    private var monthCode: String {
        monthCode(for: selectedMonth)
    }

    private var monthTitle: String {
        monthTitleFormatter.string(from: selectedMonth)
    }

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView("加载预告")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let page):
                PreviewMonthContent(
                    page: page,
                    monthTitle: monthTitle,
                    prefetchedComments: prefetchedComments[page.monthCode],
                    onMoveMonth: moveMonth,
                    onRefresh: loadPreview
                )
            case .failed(let message):
                ContentUnavailableView {
                    Label(message, systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("重试") {
                        Task { await loadPreview() }
                    }
                }
            }
        }
        .navigationTitle("预告月表")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isMonthPickerPresented = true
                } label: {
                    Label("选择月份", systemImage: "calendar.badge.clock")
                }

            }
        }
        .sheet(isPresented: $isMonthPickerPresented) {
            PreviewMonthPickerSheet(selectedMonth: $selectedMonth)
        }
        .task(id: monthCode) {
            await loadPreview()
        }
        .onChange(of: services.siteSession.lastCookieSyncAt) {
            Task { await loadPreview() }
        }
    }

    private func loadPreview() async {
        if let cached = cachedPages[monthCode] {
            state = .loaded(cached)
        } else {
            state = .loading
        }
        do {
            let page = try await services.repository.preview(monthCode: monthCode)
            cachedPages[monthCode] = page
            state = .loaded(page)
            await preloadRelatedContent(around: selectedMonth, currentPage: page)
        } catch {
            if services.siteSession.handle(error) {
                state = .failed("需要 Cloudflare 验证")
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func moveMonth(_ value: Int) {
        guard let date = Calendar(identifier: .gregorian).date(byAdding: .month, value: value, to: selectedMonth) else {
            return
        }
        selectedMonth = date
    }

    private func preloadRelatedContent(around date: Date, currentPage: HanimePreviewPage) async {
        await preloadComments(monthCode: currentPage.monthCode)

        for offset in [-1, 1] {
            guard let relatedDate = Calendar(identifier: .gregorian).date(byAdding: .month, value: offset, to: date) else {
                continue
            }
            let relatedCode = monthCode(for: relatedDate)
            guard cachedPages[relatedCode] == nil,
                  !preloadingMonthCodes.contains(relatedCode) else {
                continue
            }
            preloadingMonthCodes.insert(relatedCode)
            await preloadPreview(monthCode: relatedCode)
        }
    }

    private func preloadPreview(monthCode: String) async {
        defer { preloadingMonthCodes.remove(monthCode) }
        guard cachedPages[monthCode] == nil else { return }
        guard let page = try? await services.repository.preview(monthCode: monthCode) else {
            return
        }
        cachedPages[monthCode] = page
    }

    private func preloadComments(monthCode: String) async {
        guard prefetchedComments[monthCode] == nil,
              let page = try? await services.repository.comments(type: "preview", code: monthCode) else {
            return
        }
        prefetchedComments[monthCode] = page
    }

    private func monthCode(for date: Date) -> String {
        monthCodeFormatter.string(from: date)
    }

    private var monthCodeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMM"
        return formatter
    }

    private var monthTitleFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy 年 MM 月"
        return formatter
    }
}

private struct PreviewMonthPickerSheet: View {
    @Binding var selectedMonth: Date
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var month: Int

    init(selectedMonth: Binding<Date>) {
        _selectedMonth = selectedMonth
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: selectedMonth.wrappedValue)
        _year = State(initialValue: components.year ?? Calendar.current.component(.year, from: .now))
        _month = State(initialValue: components.month ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("年月") {
                    Picker("年份", selection: $year) {
                        ForEach(yearRange, id: \.self) { value in
                            Text("\(value) 年").tag(value)
                        }
                    }
                    Picker("月份", selection: $month) {
                        ForEach(1...12, id: \.self) { value in
                            Text("\(value) 月").tag(value)
                        }
                    }
                }
            }
            .navigationTitle("选择月份")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "取消", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "完成", systemImage: "checkmark") {
                        apply()
                    }
                }
            }
        }
    }

    private var yearRange: ClosedRange<Int> {
        let currentYear = Calendar.current.component(.year, from: .now)
        return (currentYear - 20)...(currentYear + 1)
    }

    private func apply() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = 1
        selectedMonth = components.date ?? selectedMonth
        dismiss()
    }
}

private struct PreviewMonthContent: View {
    let page: HanimePreviewPage
    let monthTitle: String
    let prefetchedComments: HanimeCommentsPage?
    let onMoveMonth: (Int) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                PreviewMonthHeader(page: page, monthTitle: monthTitle, onMoveMonth: onMoveMonth)

                if !page.latestVideos.isEmpty {
                    DetailSection(title: "本月上市") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(page.latestVideos) { video in
                                    if video.videoCode.hasPrefix("preview-") {
                                        HanaVideoGridCard(info: video)
                                            .frame(width: HanaVideoGridCard.preferredWidth(for: video, normal: 170))
                                    } else {
                                        NavigationLink(value: HanaRoute.video(video.videoCode)) {
                                            HanaVideoGridCard(info: video)
                                                .frame(width: HanaVideoGridCard.preferredWidth(for: video, normal: 170))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                DetailSection(title: "新番预告") {
                    if page.items.isEmpty {
                        ContentUnavailableView("本月暂无预告", systemImage: "calendar")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(page.items) { item in
                                PreviewItemCard(item: item)
                            }
                        }
                    }
                }

                DetailSection(title: "评论") {
                    HanimeCommentsSection(
                        commentType: "preview",
                        targetCode: page.monthCode,
                        title: page.displayMonth,
                        initialCommentsPage: prefetchedComments
                    )
                }
            }
            .padding()
        }
        .refreshable {
            await onRefresh()
        }
    }
}

private struct PreviewMonthHeader: View {
    let page: HanimePreviewPage
    let monthTitle: String
    let onMoveMonth: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                CoverView(url: page.headerImageURL)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("预告月表")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                    Text(page.displayMonth.isEmpty ? monthTitle : page.displayMonth)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .padding()
            }

            HStack {
                Button {
                    onMoveMonth(-1)
                } label: {
                    Label("上个月", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!page.hasPrevious)

                Spacer()

                Button {
                    onMoveMonth(1)
                } label: {
                    Label("下个月", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(!page.hasNext)
            }
        }
    }
}

private struct PreviewItemCard: View {
    let item: HanimePreviewItem
    @State private var selectedImage: PreviewImageSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CoverView(url: item.coverURL)
                    .frame(width: 132, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.videoTitle ?? item.title ?? "未命名预告")
                        .font(.headline)
                        .lineLimit(2)

                    if let title = item.title, title != item.videoTitle {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        if let brand = item.brand {
                            Label(brand, systemImage: "building.2")
                        }
                        if let releaseDate = item.releaseDate {
                            Label(releaseDate, systemImage: "calendar")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            if let introduction = item.introduction {
                Text(introduction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !item.tags.isEmpty {
                FlowTags(tags: item.tags) { tag in
                    .search(HanimeSearchOptionCatalog.searchCriteria(forDetailTag: tag))
                }
            }

            if !item.relatedImageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(item.relatedImageURLs, id: \.absoluteString) { url in
                            Button {
                                selectedImage = PreviewImageSelection(urls: item.relatedImageURLs, selectedURL: url)
                            } label: {
                                CoverView(url: url)
                                    .frame(width: 128, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let videoCode = item.videoCode {
                NavigationLink(value: HanaRoute.video(videoCode)) {
                    Label("查看详情", systemImage: "play.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .sheet(item: $selectedImage) { selection in
            PreviewImageViewer(selection: selection)
        }
    }
}

private struct PreviewImageSelection: Identifiable {
    let urls: [URL]
    let selectedURL: URL

    var id: String { selectedURL.absoluteString }
}

private struct PreviewImageViewer: View {
    let urls: [URL]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedURL: URL
    @State private var isGridPresented = false

    init(selection: PreviewImageSelection) {
        self.urls = selection.urls
        _selectedURL = State(initialValue: selection.selectedURL)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedURL) {
                ForEach(urls, id: \.absoluteString) { url in
                    ZoomablePreviewImage(url: url)
                        .tag(url)
                }
            }
            .hanaPreviewImagePagerStyle(showIndex: urls.count > 1)
            .background(Color.black)
            .safeAreaInset(edge: .bottom) {
                if urls.count > 1 {
                    PreviewImageThumbnailStrip(
                        urls: urls,
                        selectedURL: $selectedURL,
                        selectedIndex: selectedIndex
                    )
                }
            }
            .navigationTitle("预告图片")
            .hanaInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "关闭", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("\(selectedIndex + 1) / \(urls.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.primary)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isGridPresented = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityLabel("缩略图")
                }

                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: selectedURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享")
                }
            }
            .sheet(isPresented: $isGridPresented) {
                PreviewImageGridSheet(urls: urls, selectedURL: $selectedURL)
            }
        }
    }

    private var selectedIndex: Int {
        urls.firstIndex(of: selectedURL) ?? 0
    }
}

private struct PreviewImageThumbnailStrip: View {
    let urls: [URL]
    @Binding var selectedURL: URL
    let selectedIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(urls.enumerated()), id: \.element.absoluteString) { index, url in
                        Button {
                            selectedURL = url
                        } label: {
                            CoverView(url: url)
                                .frame(width: 68, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedURL == url ? Color.accentColor : Color.white.opacity(0.18), lineWidth: selectedURL == url ? 2 : 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
            .onChange(of: selectedIndex) {
                withAnimation(.snappy) {
                    proxy.scrollTo(selectedIndex, anchor: .center)
                }
            }
        }
    }
}

private struct PreviewImageGridSheet: View {
    let urls: [URL]
    @Binding var selectedURL: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                    ForEach(urls, id: \.absoluteString) { url in
                        Button {
                            selectedURL = url
                            dismiss()
                        } label: {
                            CoverView(url: url)
                                .aspectRatio(16.0 / 10.0, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedURL == url ? Color.accentColor : Color.clear, lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("全部图片")
            .hanaInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "关闭", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ZoomablePreviewImage: View {
    let url: URL
    @State private var scale = 1.0
    @State private var lastScale = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            CoverView(url: url, contentMode: .fit, fallbackSystemImage: "photo")
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(magnificationGesture.simultaneously(with: dragGesture))
                .onTapGesture(count: 2, perform: reset)
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    reset()
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
