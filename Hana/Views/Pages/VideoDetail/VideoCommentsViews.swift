import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum HanimeCommentSort: String, CaseIterable, Identifiable {
    case latest
    case earliest
    case mostReplies
    case mostLikes
    case mostDislikes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest:
            "最新"
        case .earliest:
            "最早"
        case .mostReplies:
            "回复最多"
        case .mostLikes:
            "赞最多"
        case .mostDislikes:
            "踩最多"
        }
    }

    func sorted(_ comments: [HanimeComment]) -> [HanimeComment] {
        switch self {
        case .latest:
            comments
        case .earliest:
            comments.reversed()
        case .mostReplies:
            comments.sorted { ($0.replyCount ?? 0) > ($1.replyCount ?? 0) }
        case .mostLikes:
            comments.sorted { ($0.thumbUp ?? 0) > ($1.thumbUp ?? 0) }
        case .mostDislikes:
            comments.sorted { ($0.thumbUp ?? 0) < ($1.thumbUp ?? 0) }
        }
    }
}

struct HanimeCommentsSection: View {
    @Environment(HanaServices.self) private var services
    let commentType: String
    let targetCode: String
    let title: String
    @State private var state: LoadableState<HanimeCommentsPage> = .idle
    @State private var sort = HanimeCommentSort.latest
    @State private var draftTarget: HanimeCommentDraftTarget?
    @State private var selectedThread: HanimeComment?
    @State private var reportTarget: HanimeComment?
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?

    init(videoCode: String, title: String) {
        self.commentType = "video"
        self.targetCode = videoCode
        self.title = title
        _state = State(initialValue: .idle)
    }

    init(
        commentType: String,
        targetCode: String,
        title: String,
        initialCommentsPage: HanimeCommentsPage? = nil
    ) {
        self.commentType = commentType
        self.targetCode = targetCode
        self.title = title
        _state = State(initialValue: initialCommentsPage.map { .loaded($0) } ?? .idle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            commentsHeader

            switch state {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView("评论加载中")
                    Spacer()
                }
                .padding(.vertical, 24)
            case .loaded(let page):
                if page.comments.isEmpty {
                    ContentUnavailableView("暂无评论", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else {
                    let comments = sort.sorted(page.comments)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(comments) { comment in
                            HanimeCommentRow(
                                comment: comment,
                                onLike: { toggleReaction(comment, page: page, isPositive: true) },
                                onDislike: { toggleReaction(comment, page: page, isPositive: false) },
                                onReply: { presentComposer(parent: comment, page: page) },
                                onReport: { presentReport(comment) },
                                onOpenThread: { selectedThread = comment }
                            )
                            .padding(.vertical, 10)

                            if comment.id != comments.last?.id {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label(message, systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("重试") {
                        Task { await loadComments() }
                    }
                }
            }
        }
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .task(id: taskKey) {
            if currentCommentsPage == nil {
                await loadComments()
            }
        }
        .sheet(item: $draftTarget) { target in
            HanimeCommentComposerSheet(title: target.title) { text in
                try await submit(text, target: target)
            }
        }
        .sheet(item: $selectedThread) { comment in
            NavigationStack {
                HanimeCommentThreadView(
                    root: comment,
                    redirectURL: redirectURL,
                    currentUserID: currentCommentsPage?.currentUserID,
                    csrfToken: currentCSRFToken
                )
            }
        }
        .sheet(item: $reportTarget) { comment in
            HanimeCommentReportSheet(username: comment.username) { reason in
                try await submitReport(reason, comment: comment)
            }
        }
    }

    private var commentsHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                commentsCountBlock
                    .frame(minWidth: 48, alignment: .leading)
                composerButton
                sortButton
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    commentsCountBlock
                    Spacer(minLength: 12)
                    sortButton
                }
                composerButton
            }
        }
    }

    private var commentsCountBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("评论")
                .font(.headline.weight(.semibold))
            Text(commentCountText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }

    private var sortButton: some View {
        Menu {
            ForEach(HanimeCommentSort.allCases) { value in
                Button {
                    sort = value
                } label: {
                    if sort == value {
                        Label(value.title, systemImage: "checkmark")
                    } else {
                        Text(value.title)
                    }
                }
            }
        } label: {
            Label(sort.title, systemImage: "arrow.up.arrow.down")
        }
        .buttonStyle(.bordered)
    }

    private var composerButton: some View {
        Button {
            presentComposer(parent: nil, page: currentCommentsPage)
        } label: {
            Label("写下评论", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, 14)
                .background(.fill.quaternary, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var currentCommentsPage: HanimeCommentsPage? {
        if case .loaded(let page) = state {
            return page
        }
        return nil
    }

    private var currentCSRFToken: String? {
        currentCommentsPage?.csrfToken
    }

    private var commentCountText: String {
        guard let page = currentCommentsPage else { return "加载中" }
        return "\(page.comments.count)"
    }

    private var taskKey: String {
        "\(commentType)-\(targetCode)"
    }

    private var redirectURL: String {
        if commentType == "preview" {
            return services.httpClient.baseURL.appendingPathComponent("previews/\(targetCode)").absoluteString
        }

        var components = URLComponents(
            url: services.httpClient.baseURL.appendingPathComponent("watch"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "v", value: targetCode)]
        return components?.url?.absoluteString ?? "https://hanime1.me/watch?v=\(targetCode)"
    }

    private func loadComments() async {
        state = .loading
        do {
            state = .loaded(try await services.repository.comments(type: commentType, code: targetCode))
        } catch {
            if services.siteSession.handle(error) {
                state = .failed("需要 Cloudflare 验证")
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func presentComposer(parent: HanimeComment?, page: HanimeCommentsPage?) {
        guard services.siteSession.isLoggedIn else {
            services.siteSession.requestLogin()
            return
        }
        guard let page else {
            alertMessage = .error("评论还没有加载完成。")
            return
        }
        draftTarget = HanimeCommentDraftTarget(targetCode: targetCode, parent: parent, commentsPage: page)
    }

    private func presentReport(_ comment: HanimeComment) {
        guard services.siteSession.isLoggedIn else {
            services.siteSession.requestLogin()
            return
        }
        guard comment.reportableID != nil, comment.reportableType != nil else {
            alertMessage = .error("这条评论无法举报。")
            return
        }
        reportTarget = comment
    }

    private func submit(_ text: String, target: HanimeCommentDraftTarget) async throws {
        if let parent = target.parent {
            let replyID = parent.post.foreignID ?? parent.commentID
            guard let replyID else { throw HanaNetworkError.invalidResponse }
            try await services.repository.postCommentReply(
                commentID: replyID,
                text: text,
                csrfToken: target.commentsPage.csrfToken
            )
        } else {
            try await services.repository.postComment(
                type: commentType,
                code: target.targetCode,
                text: text,
                commentsPage: target.commentsPage
            )
        }
        await loadComments()
        toastMessage = .success(target.parent == nil ? "评论已发送" : "回复已发送")
    }

    private func submitReport(_ reason: String, comment: HanimeComment) async throws {
        guard let page = currentCommentsPage, let currentUserID = page.currentUserID else {
            throw HanaNetworkError.invalidResponse
        }
        try await services.repository.reportComment(
            comment,
            reason: reason,
            currentUserID: currentUserID,
            redirectURL: redirectURL,
            csrfToken: page.csrfToken
        )
        toastMessage = .success("举报已发送")
    }

    private func toggleReaction(_ comment: HanimeComment, page: HanimeCommentsPage, isPositive: Bool) {
        guard services.siteSession.isLoggedIn else {
            services.siteSession.requestLogin()
            return
        }
        updateComment(isPositive ? comment.toggledLike() : comment.toggledDislike())
        Task {
            do {
                try await services.repository.setCommentLike(comment, isPositive: isPositive, csrfToken: page.csrfToken)
            } catch {
                updateComment(comment)
                if services.siteSession.handle(error) {
                    alertMessage = .error("需要 Cloudflare 验证")
                } else {
                    alertMessage = .error(error.localizedDescription)
                }
            }
        }
    }

    private func updateComment(_ updated: HanimeComment) {
        guard case .loaded(let page) = state else { return }
        let comments = page.comments.map { $0.id == updated.id ? updated : $0 }
        state = .loaded(HanimeCommentsPage(comments: comments, currentUserID: page.currentUserID, csrfToken: page.csrfToken))
    }
}

struct HanimeCommentDraftTarget: Identifiable {
    let targetCode: String
    let parent: HanimeComment?
    let commentsPage: HanimeCommentsPage

    var id: String {
        "comment-\(targetCode)-\(parent?.id ?? "root")"
    }

    var title: String {
        if let parent {
            "回复 \(parent.username)"
        } else {
            "写评论"
        }
    }
}

struct HanimeCommentThreadView: View {
    @Environment(HanaServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let root: HanimeComment
    let redirectURL: String
    let currentUserID: String?
    let csrfToken: String?
    @State private var displayedRoot: HanimeComment
    @State private var state: LoadableState<HanimeCommentsPage> = .idle
    @State private var draftTarget: HanimeCommentDraftTarget?
    @State private var reportTarget: HanimeComment?
    @State private var toastMessage: HanaToastMessage?
    @State private var alertMessage: HanaAlertMessage?

    init(root: HanimeComment, redirectURL: String, currentUserID: String?, csrfToken: String?) {
        self.root = root
        self.redirectURL = redirectURL
        self.currentUserID = currentUserID
        self.csrfToken = csrfToken
        _displayedRoot = State(initialValue: root)
    }

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView("回复加载中")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let page):
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HanimeCommentRow(
                            comment: displayedRoot,
                            onLike: { toggleReaction(displayedRoot, page: page, isPositive: true) },
                            onDislike: { toggleReaction(displayedRoot, page: page, isPositive: false) },
                            onReply: { presentComposer(parent: displayedRoot, page: page) },
                            onReport: { presentReport(displayedRoot) },
                            onOpenThread: {}
                        )
                        .padding(.vertical, 12)
                        Divider()

                        if page.comments.isEmpty {
                            ContentUnavailableView("暂无回复", systemImage: "bubble.left")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                        } else {
                            ForEach(page.comments) { reply in
                                HanimeCommentRow(
                                    comment: reply,
                                    showsThreadButton: false,
                                    onLike: { toggleReaction(reply, page: page, isPositive: true) },
                                    onDislike: { toggleReaction(reply, page: page, isPositive: false) },
                                    onReply: { presentComposer(parent: reply, page: page) },
                                    onReport: { presentReport(reply) },
                                    onOpenThread: {}
                                )
                                .padding(.vertical, 12)
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .refreshable {
                    await loadReplies()
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label(message, systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("重试") {
                        Task { await loadReplies() }
                    }
                }
            }
        }
        .navigationTitle("回复")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                HanaToolbarIconButton(title: "关闭", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
        .hanaToast($toastMessage)
        .hanaFeedbackAlert($alertMessage)
        .task(id: root.id) {
            displayedRoot = root
            await loadReplies()
        }
        .sheet(item: $draftTarget) { target in
            HanimeCommentComposerSheet(title: target.title) { text in
                try await submit(text, target: target)
            }
        }
        .sheet(item: $reportTarget) { comment in
            HanimeCommentReportSheet(username: comment.username) { reason in
                try await submitReport(reason, comment: comment)
            }
        }
    }

    private func loadReplies() async {
        guard let commentID = root.post.foreignID ?? root.commentID else {
            state = .loaded(HanimeCommentsPage(comments: [], currentUserID: currentUserID, csrfToken: csrfToken))
            return
        }
        state = .loading
        do {
            let page = try await services.repository.commentReplies(commentID: commentID)
            state = .loaded(HanimeCommentsPage(comments: page.comments, currentUserID: currentUserID, csrfToken: csrfToken))
        } catch {
            if services.siteSession.handle(error) {
                state = .failed("需要 Cloudflare 验证")
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func presentComposer(parent: HanimeComment, page: HanimeCommentsPage) {
        guard services.siteSession.isLoggedIn else {
            services.siteSession.requestLogin()
            return
        }
        draftTarget = HanimeCommentDraftTarget(
            targetCode: root.post.foreignID ?? root.commentID ?? root.id,
            parent: parent,
            commentsPage: page
        )
    }

    private func presentReport(_ comment: HanimeComment) {
        guard services.siteSession.isLoggedIn else {
            services.siteSession.requestLogin()
            return
        }
        guard comment.reportableID != nil, comment.reportableType != nil else {
            alertMessage = .error("这条评论无法举报。")
            return
        }
        reportTarget = comment
    }

    private func submit(_ text: String, target: HanimeCommentDraftTarget) async throws {
        let replyID = target.parent?.post.foreignID ?? target.parent?.commentID
        guard let replyID else { throw HanaNetworkError.invalidResponse }
        try await services.repository.postCommentReply(commentID: replyID, text: text, csrfToken: target.commentsPage.csrfToken)
        await loadReplies()
        toastMessage = .success("回复已发送")
    }

    private func submitReport(_ reason: String, comment: HanimeComment) async throws {
        guard let currentUserID else {
            throw HanaNetworkError.invalidResponse
        }
        try await services.repository.reportComment(
            comment,
            reason: reason,
            currentUserID: currentUserID,
            redirectURL: redirectURL,
            csrfToken: csrfToken
        )
        toastMessage = .success("举报已发送")
    }

    private func toggleReaction(_ comment: HanimeComment, page: HanimeCommentsPage, isPositive: Bool) {
        guard services.siteSession.isLoggedIn else {
            services.siteSession.requestLogin()
            return
        }
        updateComment(isPositive ? comment.toggledLike() : comment.toggledDislike())
        Task {
            do {
                try await services.repository.setCommentLike(comment, isPositive: isPositive, csrfToken: page.csrfToken)
            } catch {
                updateComment(comment)
                alertMessage = .error(services.siteSession.handle(error) ? "需要 Cloudflare 验证" : error.localizedDescription)
            }
        }
    }

    private func updateComment(_ updated: HanimeComment) {
        if root.id == updated.id {
            displayedRoot = updated
            return
        }
        guard case .loaded(let page) = state else { return }
        let comments = page.comments.map { $0.id == updated.id ? updated : $0 }
        state = .loaded(HanimeCommentsPage(comments: comments, currentUserID: page.currentUserID, csrfToken: page.csrfToken))
    }
}

struct HanimeCommentRow: View {
    let comment: HanimeComment
    var showsThreadButton = true
    let onLike: () -> Void
    let onDislike: () -> Void
    let onReply: () -> Void
    let onReport: () -> Void
    let onOpenThread: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CoverView(url: comment.avatarURL)
                .frame(width: 38, height: 38)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(comment.username)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(comment.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                Text(comment.content)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Button(action: onLike) {
                        Label("\(comment.thumbUp ?? 0)", systemImage: comment.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                    }

                    Button(action: onDislike) {
                        Label("踩", systemImage: comment.isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }

                    Button(action: onReply) {
                        Label("回复", systemImage: "arrowshape.turn.up.left")
                    }

                    Button(action: onReport) {
                        Label("举报", systemImage: "flag")
                    }

                    if showsThreadButton, (comment.hasMoreReplies || (comment.replyCount ?? 0) > 0) {
                        Button(action: onOpenThread) {
                            Label("\(comment.replyCount ?? 0)", systemImage: "bubble.left")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
            }
        }
    }
}

struct HanimeCommentReportReason: Identifiable, Hashable {
    let title: String
    let key: String

    var id: String { key }

    static let all: [HanimeCommentReportReason] = [
        HanimeCommentReportReason(title: "煽动仇恨或恶意内容", key: "煽動仇恨或惡意內容"),
        HanimeCommentReportReason(title: "暴力或令人反感的内容", key: "暴力或令人反感的內容"),
        HanimeCommentReportReason(title: "广告内容或垃圾内容", key: "廣告內容或垃圾內容"),
        HanimeCommentReportReason(title: "其他检举理由", key: "其他檢舉理由")
    ]
}

struct HanimeCommentReportSheet: View {
    let username: String
    let onSubmit: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReasonKey = HanimeCommentReportReason.all[0].key
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("评论用户") {
                    Text(username)
                }

                Section("举报原因") {
                    Picker("举报原因", selection: $selectedReasonKey) {
                        ForEach(HanimeCommentReportReason.all) { reason in
                            Text(reason.title).tag(reason.key)
                        }
                    }
                    .pickerStyle(.inline)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("举报评论")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "取消", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isSending)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .accessibilityLabel("提交")
                    .disabled(isSending)
                }
            }
        }
    }

    private func submit() {
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await onSubmit(selectedReasonKey)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSending = false
            }
        }
    }
}

struct HanimeCommentComposerSheet: View {
    let title: String
    let onSubmit: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .focused($isFocused)
                        .frame(minHeight: 160)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if text.isEmpty {
                        Text("说点什么")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "取消", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isSending)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .accessibilityLabel("发送")
                    .disabled(trimmedText.isEmpty || isSending)
                }
            }
        }
        .task {
            isFocused = true
        }
    }

    private func submit() {
        let message = trimmedText
        guard !message.isEmpty else { return }
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await onSubmit(message)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSending = false
            }
        }
    }
}
