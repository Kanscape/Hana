import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SearchScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SearchHistoryRecord.createdAt, order: .reverse) private var searchHistory: [SearchHistoryRecord]
    @Query(sort: \AdvancedSearchHistoryRecord.createdAt, order: .reverse) private var advancedSearchHistory: [AdvancedSearchHistoryRecord]
    private let locksQueryEditing: Bool
    private let lockedQuery: String?
    @State private var criteria: HanimeSearchCriteria
    @State private var state: LoadableState<[HanimeInfo]> = .idle
    @State private var currentPage = 1
    @State private var canLoadMore = false
    @State private var isLoadingMore = false
    @State private var isFilterPresented = false
    @State private var hasLoadedInitialCriteria = false
    @State private var toastMessage: HanaToastMessage?

    init(initialCriteria: HanimeSearchCriteria = .empty, locksQueryEditing: Bool = false) {
        let normalizedCriteria = initialCriteria.normalized()
        self.locksQueryEditing = locksQueryEditing
        self.lockedQuery = locksQueryEditing ? normalizedCriteria.query.nilIfEmpty : nil
        _criteria = State(initialValue: normalizedCriteria)
    }

    var body: some View {
        Group {
            switch state {
            case .idle:
                SearchIdleView(histories: Array(advancedSearchHistory.prefix(12))) { history in
                    apply(history)
                } onDelete: { offsets in
                    deleteHistories(at: offsets, from: Array(advancedSearchHistory.prefix(12)))
                }
            case .loading:
                ProgressView("搜索中")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let videos):
                if videos.isEmpty {
                    ContentUnavailableView("没有结果", systemImage: "magnifyingglass")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if !visibleFilterTags.isEmpty {
                                SearchFilterSummary(tags: visibleFilterTags)
                                    .padding(.horizontal)
                            }

                            let portraitVideos = videos.filter { $0.style == .compact }
                            let normalVideos = videos.filter { $0.style == .normal }

                            if !portraitVideos.isEmpty {
                                SearchVideoGridLinks(videos: portraitVideos) { video in
                                    preloadNextSearchPageIfNeeded(after: video, in: videos)
                                }
                                    .padding(.horizontal)
                            }

                            ForEach(normalVideos) { video in
                                NavigationLink {
                                    VideoDetailScreen(videoCode: video.videoCode)
                                } label: {
                                    HanaVideoListRow(info: video)
                                        .padding(10)
                                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                                .onAppear {
                                    preloadNextSearchPageIfNeeded(after: video, in: videos)
                                }
                            }

                            HanaInfiniteScrollTrigger(
                                isActive: canLoadMore,
                                isLoading: isLoadingMore,
                                action: loadNextSearchPageIfNeeded
                            )
                            .padding(.horizontal)
                        }
                        .padding(.vertical, 12)
                    }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label(message, systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("重试") {
                        Task { await search(reset: true) }
                    }
                }
            }
        }
        .navigationTitle(navigationTitleText)
        .hanaNavigationSubtitle(navigationSubtitleText)
        .hanaSearchInput(text: $criteria.query, isEnabled: !locksQueryEditing)
        .onSubmit(of: .search) {
            Task { await search(reset: true) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isFilterPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("筛选")

                if isShowingSearchHistory {
                    HanaToolbarIconButton(title: "清理搜索历史", systemImage: "trash", role: .destructive) {
                        clearAllHistories()
                    }
                }
            }
        }
        .hanaToast($toastMessage)
        .sheet(isPresented: $isFilterPresented) {
            HanimeSearchFilterSheet(criteria: $criteria, lockedQuery: lockedQuery) {
                Task { await search(reset: true) }
            }
        }
        .task {
            guard !hasLoadedInitialCriteria else { return }
            hasLoadedInitialCriteria = true
            if !criteria.isEmpty {
                await search(reset: true)
            }
        }
        .onChange(of: services.siteSession.lastCookieSyncAt) {
            if !criteria.isEmpty {
                Task { await search(reset: true) }
            }
        }
    }

    private var navigationTitleText: String {
        lockedQuery ?? "搜索"
    }

    private var navigationSubtitleText: String? {
        criteria.hasNonQueryFilters ? "已筛选" : nil
    }

    private var hasSearchHistories: Bool {
        !searchHistory.isEmpty || !advancedSearchHistory.isEmpty
    }

    private var visibleFilterTags: [String] {
        var visibleCriteria = criteria
        if lockedQuery != nil {
            visibleCriteria.query = ""
        }
        return visibleCriteria.activeFilters
    }

    private var isShowingSearchHistory: Bool {
        if case .idle = state {
            return hasSearchHistories
        }
        return false
    }

    private func search(reset: Bool) async {
        let nextCriteria = criteria.applyingLockedQuery(lockedQuery).normalized()
        guard !nextCriteria.isEmpty else {
            criteria = nextCriteria
            state = .idle
            return
        }

        criteria = nextCriteria
        let page = reset ? 1 : currentPage + 1
        if reset {
            state = .loading
            canLoadMore = false
        } else {
            guard canLoadMore, !isLoadingMore else { return }
            isLoadingMore = true
        }
        defer { isLoadingMore = false }

        do {
            let videos = try await services.repository.search(criteria: nextCriteria, page: page)
            currentPage = page
            canLoadMore = !videos.isEmpty
            saveSearch(nextCriteria)
            if reset {
                state = .loaded(videos)
            } else if case .loaded(let currentVideos) = state {
                state = .loaded(mergedVideos(currentVideos, videos))
            } else {
                state = .loaded(videos)
            }
        } catch {
            if services.siteSession.handle(error) {
                state = .failed("需要 Cloudflare 验证")
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func mergedVideos(_ current: [HanimeInfo], _ next: [HanimeInfo]) -> [HanimeInfo] {
        var seen = Set(current.map(\.videoCode))
        return current + next.filter { seen.insert($0.videoCode).inserted }
    }

    private func loadNextSearchPageIfNeeded() {
        guard canLoadMore, !isLoadingMore else { return }
        Task { await search(reset: false) }
    }

    private func preloadNextSearchPageIfNeeded(after video: HanimeInfo, in videos: [HanimeInfo]) {
        guard HanaInfiniteScrollPreload.shouldLoadNextPage(
            currentID: video.videoCode,
            orderedIDs: videos.map(\.videoCode)
        ) else {
            return
        }
        loadNextSearchPageIfNeeded()
    }

    private func saveSearch(_ criteria: HanimeSearchCriteria) {
        let criteria = criteria.normalized()
        guard !criteria.isEmpty else { return }
        let query = criteria.summary
        let key = criteria.historyKey
        try? modelContext.delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { record in
                record.query == query
            }
        )
        try? modelContext.delete(
            model: AdvancedSearchHistoryRecord.self,
            where: #Predicate<AdvancedSearchHistoryRecord> { record in
                record.criteriaKey == key
            }
        )
        modelContext.insert(SearchHistoryRecord(query: query))
        modelContext.insert(AdvancedSearchHistoryRecord(criteria: criteria))
        try? modelContext.save()
    }

    private func apply(_ history: AdvancedSearchHistoryRecord) {
        criteria = history.criteria
        Task { await search(reset: true) }
    }

    private func deleteHistories(at offsets: IndexSet, from histories: [AdvancedSearchHistoryRecord]) {
        for index in offsets where histories.indices.contains(index) {
            let history = histories[index]
            let query = history.summary
            try? modelContext.delete(
                model: SearchHistoryRecord.self,
                where: #Predicate<SearchHistoryRecord> { record in
                    record.query == query
                }
            )
            modelContext.delete(history)
        }
        try? modelContext.save()
    }

    private func clearAllHistories() {
        searchHistory.forEach(modelContext.delete)
        advancedSearchHistory.forEach(modelContext.delete)
        do {
            try modelContext.save()
            toastMessage = .success("搜索历史已清理")
        } catch {
            toastMessage = .info("清理搜索历史失败")
        }
    }
}

private struct SearchVideoGridLinks: View {
    let videos: [HanimeInfo]
    var onVideoAppear: (HanimeInfo) -> Void = { _ in }

    private var minimumCardWidth: CGFloat {
        videos.first?.style == .compact ? 132 : 180
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: minimumCardWidth),
                spacing: 12,
                alignment: .top
            )
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(videos) { video in
                NavigationLink {
                    VideoDetailScreen(videoCode: video.videoCode)
                } label: {
                    HanaVideoGridCard(info: video)
                }
                .buttonStyle(.plain)
                .onAppear {
                    onVideoAppear(video)
                }
            }
        }
    }
}

private struct SearchIdleView: View {
    let histories: [AdvancedSearchHistoryRecord]
    let onSelect: (AdvancedSearchHistoryRecord) -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        if histories.isEmpty {
            ContentUnavailableView("输入关键词或筛选条件", systemImage: "magnifyingglass")
        } else {
            List {
                ForEach(histories) { history in
                    Button {
                        onSelect(history)
                    } label: {
                        AdvancedSearchHistoryRow(history: history)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: onDelete)
            }
        }
    }
}

private struct AdvancedSearchHistoryRow: View {
    let history: AdvancedSearchHistoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(history.summary)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            Text(history.createdAt.hanaChineseDateTimeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct SearchFilterSummary: View {
    let tags: [String]

    var body: some View {
        FlowTags(tags: tags)
    }
}

private struct HanimeSearchFilterSheet: View {
    @Binding var criteria: HanimeSearchCriteria
    let lockedQuery: String?
    let onSearch: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: HanimeSearchCriteria

    init(
        criteria: Binding<HanimeSearchCriteria>,
        lockedQuery: String? = nil,
        onSearch: @escaping () -> Void
    ) {
        _criteria = criteria
        self.lockedQuery = lockedQuery
        self.onSearch = onSearch
        let value = criteria.wrappedValue.applyingLockedQuery(lockedQuery)
        _draft = State(initialValue: value)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础") {
                    Picker("类型", selection: optionalSelection(\.genre)) {
                        Text("全部").tag("")
                        ForEach(HanimeSearchOption.genres) { option in
                            Text(option.title).tag(option.value ?? "")
                        }
                    }

                    Picker("排序", selection: optionalSelection(\.sort)) {
                        Text("默认").tag("")
                        ForEach(HanimeSearchOption.sortOptions) { option in
                            Text(option.title).tag(option.value ?? "")
                        }
                    }
                }

                Section("时间") {
                    Picker("日期范围", selection: datePresetSelection) {
                        Text("全部").tag("")
                        ForEach(HanimeSearchOption.dateOptions) { option in
                            Text(option.title).tag(option.value ?? "")
                        }
                    }

                    Picker("年份", selection: releaseYearSelection) {
                        Text("全部").tag(0)
                        ForEach(releaseYearOptions, id: \.self) { year in
                            Text("\(year) 年").tag(year)
                        }
                    }

                    Picker("月份", selection: releaseMonthSelection) {
                        Text("全年").tag(0)
                        ForEach(1...12, id: \.self) { month in
                            Text("\(month) 月").tag(month)
                        }
                    }

                    Picker("时长", selection: optionalSelection(\.duration)) {
                        Text("全部").tag("")
                        ForEach(HanimeSearchOption.durationOptions) { option in
                            Text(option.title).tag(option.value ?? "")
                        }
                    }
                }

                Section("标签") {
                    NavigationLink {
                        HanimeSearchOptionSelectionView(
                            title: "标签",
                            sections: HanimeSearchOptionCatalog.tagSections,
                            selectedValues: $draft.tags
                        )
                    } label: {
                        SearchSelectionSummaryRow(title: "已选择", count: draft.tags.count)
                    }
                }

                Section("厂商") {
                    NavigationLink {
                        HanimeSearchOptionSelectionView(
                            title: "厂商",
                            sections: HanimeSearchOptionCatalog.brandSections,
                            selectedValues: $draft.brands
                        )
                    } label: {
                        SearchSelectionSummaryRow(title: "已选择", count: draft.brands.count)
                    }
                }
            }
            .navigationTitle("筛选")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "取消", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .destructiveAction) {
                    HanaToolbarIconButton(title: "重置", systemImage: "eraser", role: .destructive) {
                        draft = HanimeSearchCriteria.empty.applyingLockedQuery(lockedQuery)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "完成", systemImage: "checkmark") {
                        criteria = draft.applyingLockedQuery(lockedQuery)
                        dismiss()
                        onSearch()
                    }
                }
            }
        }
    }

    private func optionalSelection(_ keyPath: WritableKeyPath<HanimeSearchCriteria, String?>) -> Binding<String> {
        Binding {
            draft[keyPath: keyPath] ?? ""
        } set: { value in
            draft[keyPath: keyPath] = value.isEmpty ? nil : value
        }
    }

    private var datePresetSelection: Binding<String> {
        Binding {
            draft.date ?? ""
        } set: { value in
            draft.date = value.isEmpty ? nil : value
            if !value.isEmpty {
                draft.releaseYear = nil
                draft.releaseMonth = nil
            }
        }
    }

    private var releaseYearSelection: Binding<Int> {
        Binding {
            draft.releaseYear ?? 0
        } set: { value in
            draft.releaseYear = value == 0 ? nil : value
            if value == 0 {
                draft.releaseMonth = nil
            } else {
                draft.date = nil
            }
        }
    }

    private var releaseMonthSelection: Binding<Int> {
        Binding {
            draft.releaseMonth ?? 0
        } set: { value in
            draft.releaseMonth = value == 0 ? nil : value
            if value != 0 {
                draft.releaseYear = draft.releaseYear ?? Calendar.current.component(.year, from: .now)
                draft.date = nil
            }
        }
    }

    private var releaseYearOptions: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        return Array((1990...(currentYear + 1)).reversed())
    }
}

private struct SearchSelectionSummaryRow: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(count == 0 ? "无" : "\(count)")
                .foregroundStyle(.secondary)
        }
    }
}

private struct HanimeSearchOptionSelectionView: View {
    let title: String
    let sections: [HanimeSearchOptionSection]
    @Binding var selectedValues: [String]
    @State private var query = ""

    private var selectedSet: Set<String> {
        Set(selectedValues)
    }

    private var displayedSections: [HanimeSearchOptionSection] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return sections }
        return sections.compactMap { section in
            let options = section.options.filter { option in
                option.title.localizedCaseInsensitiveContains(text)
                    || (option.value?.localizedCaseInsensitiveContains(text) == true)
            }
            guard !options.isEmpty else { return nil }
            return HanimeSearchOptionSection(title: section.title, options: options)
        }
    }

    var body: some View {
        List {
            Section("已选择") {
                if selectedValues.isEmpty {
                    Text("未选择")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedValues, id: \.self) { value in
                        Button {
                            remove(value)
                        } label: {
                            HStack {
                                Text(displayTitle(for: value))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button(role: .destructive) {
                        selectedValues = []
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                }
            }

            if sections.isEmpty {
                ContentUnavailableView("选项不可用", systemImage: "exclamationmark.triangle")
                    .listRowBackground(Color.clear)
            } else if displayedSections.isEmpty {
                ContentUnavailableView("没有匹配选项", systemImage: "magnifyingglass")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(displayedSections) { section in
                    Section(section.title) {
                        ForEach(section.options) { option in
                            Button {
                                toggle(option)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(option.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if let value = option.value, selectedSet.contains(value) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .searchable(text: $query, prompt: "搜索\(title)")
    }

    private func toggle(_ option: HanimeSearchOption) {
        guard let value = option.value, !value.isEmpty else { return }
        if selectedSet.contains(value) {
            remove(value)
        } else {
            selectedValues.append(value)
            selectedValues = normalized(selectedValues)
        }
    }

    private func remove(_ value: String) {
        selectedValues.removeAll { $0 == value }
    }

    private func displayTitle(for value: String) -> String {
        sections.lazy
            .flatMap(\.options)
            .first { $0.value == value }?
            .title ?? value
    }

    private func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
