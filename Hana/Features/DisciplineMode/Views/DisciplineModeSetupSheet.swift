import SwiftUI

struct DisciplineModeSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DisciplineModeStore.self) private var disciplineModeStore

    @State private var draftMode: DisciplineModeDraftMode = .weekly
    @State private var cycleLengthDays = 7
    @State private var weeklyAllowedWeekdayNumbers: Set<Int> = [1]
    @State private var recurringAllowedDayNumbers: Set<Int> = [1]
    @State private var singleDuration = DisciplineModeSingleDuration(days: 0, hours: 1, minutes: 0)
    @State private var showsConfirmation = false
    @State private var showsExitConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                introSection

                if canConfigure {
                    modeSection
                    configurationSection
                } else {
                    activeConfigurationSection
                }
            }
            .navigationTitle("自律模式")
            .disciplineModeNavigationTitleStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "关闭", systemImage: "xmark") {
                        dismiss()
                    }
                }

                if canConfigure {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .destructive) {
                            showsConfirmation = true
                        } label: {
                            Label("开启", systemImage: "lock")
                        }
                        .disabled(!canActivate)
                    }
                }
            }
            .alert("开启后无法撤销", isPresented: $showsConfirmation) {
                Button("开启自律模式", role: .destructive) {
                    activate()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
            .alert("退出自律模式？", isPresented: $showsExitConfirmation) {
                Button("退出自律模式", role: .destructive) {
                    exitDisciplineMode()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后自律模式将关闭，需要重新开启才会再次生效。")
            }
        }
        .disciplineModeSheetPresentation()
        .onAppear {
            disciplineModeStore.refresh()
        }
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "calendar.badge.lock")
                    .font(.headline)
                    .foregroundStyle(.pink)
                Text("👋自律，从现在开始")
                    .font(.headline)
                Text("自律模式是为了减少被欲望引导的情况。你可以配置周期或单次锁定。锁定后，在限制时间内无法进入 App 观看内容，且该操作无法撤销。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var modeSection: some View {
        Section("模式") {
            Picker("模式", selection: $draftMode) {
                ForEach(DisciplineModeDraftMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var configurationSection: some View {
        switch draftMode {
        case .weekly:
            Section("星期") {
                LabeledContent("循环周期", value: "7 天")
                DisciplineModeAllowedDaysGrid(
                    cycleLengthDays: DisciplineModeWeeklyConfiguration.cycleLengthDays,
                    allowedDayNumbers: $weeklyAllowedWeekdayNumbers,
                    dayLabels: weekdayGridLabels,
                    accessibilityLabels: weekdayAccessibilityLabels
                )
                if !weeklyConfiguration.isValid {
                    Text("允许星期需要至少选择一天，且不能选满整周。")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        case .recurring:
            Section("周期") {
                Stepper(value: $cycleLengthDays, in: 2...30) {
                    LabeledContent("循环周期", value: "\(cycleLengthDays) 天")
                }
                DisciplineModeAllowedDaysGrid(
                    cycleLengthDays: cycleLengthDays,
                    allowedDayNumbers: $recurringAllowedDayNumbers
                )
                if !recurringConfiguration.isValid {
                    Text("允许使用日需要至少选择一天，且不能选满整个周期。")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        case .single:
            Section("时长") {
                DisciplineModeSingleDurationEditor(duration: $singleDuration)
                if !singleDuration.isValid {
                    Text("单次时长需要大于 0 分钟。")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var activeConfigurationSection: some View {
        Section("当前配置") {
            Text(activeConfigurationText)
                .foregroundStyle(.secondary)
            if disciplineModeStore.state.allowsExit {
                Button(role: .destructive) {
                    showsExitConfirmation = true
                } label: {
                    Label("退出自律模式", systemImage: "lock.open")
                }
            } else {
                Text("当前配置已经生效，不能关闭或修改。")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var canConfigure: Bool {
        guard disciplineModeStore.configuration != nil else {
            return true
        }
        return disciplineModeStore.state.message != .active
    }

    private var weekdayGridLabels: [Int: String] {
        Dictionary(
            uniqueKeysWithValues: (1...DisciplineModeWeeklyConfiguration.cycleLengthDays).map { weekdayNumber in
                (weekdayNumber, DisciplineModeFormatting.weekdayShortText(for: weekdayNumber))
            }
        )
    }

    private var weekdayAccessibilityLabels: [Int: String] {
        Dictionary(
            uniqueKeysWithValues: (1...DisciplineModeWeeklyConfiguration.cycleLengthDays).map { weekdayNumber in
                (weekdayNumber, "星期\(DisciplineModeFormatting.weekdayShortText(for: weekdayNumber))")
            }
        )
    }

    private var recurringConfiguration: DisciplineModeRecurringConfiguration {
        DisciplineModeRecurringConfiguration(
            cycleLengthDays: cycleLengthDays,
            allowedDayNumbers: recurringAllowedDayNumbers
        )
    }

    private var weeklyConfiguration: DisciplineModeWeeklyConfiguration {
        DisciplineModeWeeklyConfiguration(
            allowedWeekdayNumbers: weeklyAllowedWeekdayNumbers
        )
    }

    private var canActivate: Bool {
        switch draftMode {
        case .weekly:
            weeklyConfiguration.isValid
        case .recurring:
            recurringConfiguration.isValid
        case .single:
            singleDuration.isValid
        }
    }

    private var summaryText: String {
        switch draftMode {
        case .weekly:
            let weekdays = DisciplineModeFormatting.weekdayListText(for: weeklyAllowedWeekdayNumbers)
            return "按星期\n允许使用：\(weekdays)。\n其它日期无法进入。"
        case .recurring:
            let days = recurringAllowedDayNumbers.sorted().map { "第 \($0) 天" }.joined(separator: "、")
            return "\(cycleLengthDays) 天循环\n允许使用：\(days)。\n其它日期无法进入。"
        case .single:
            let until = Date.now.addingTimeInterval(singleDuration.totalSeconds)
            return "将锁定至 \(DisciplineModeFormatting.chineseDateTimeText(for: until))。"
        }
    }

    private var confirmationMessage: String {
        summaryText
    }

    private var activeConfigurationText: String {
        guard let configuration = disciplineModeStore.configuration else {
            return "暂无配置。"
        }

        switch configuration.mode {
        case .single(let until):
            return "单次锁定至 \(DisciplineModeFormatting.chineseDateTimeText(for: until))。"
        case .weekly(let weekly):
            let weekdays = DisciplineModeFormatting.weekdayListText(for: weekly.allowedWeekdayNumbers)
            return "每周；允许使用：\(weekdays)。"
        case .recurring(let recurring):
            let days = recurring.allowedDayNumbers.sorted().map { "第 \($0) 天" }.joined(separator: "、")
            return "\(recurring.cycleLengthDays) 天循环；允许使用：\(days)。"
        }
    }

    private func activate() {
        let now = Date.now
        let mode: DisciplineModeMode

        switch draftMode {
        case .weekly:
            mode = .weekly(weeklyConfiguration)
        case .recurring:
            mode = .recurring(recurringConfiguration)
        case .single:
            mode = .single(until: now.addingTimeInterval(singleDuration.totalSeconds))
        }

        disciplineModeStore.activate(
            DisciplineModeConfiguration(createdAt: now, mode: mode)
        )
        dismiss()
    }

    private func exitDisciplineMode() {
        disciplineModeStore.clear()
        dismiss()
    }
}

private extension View {
    @ViewBuilder
    func disciplineModeSheetPresentation() -> some View {
#if os(macOS)
        self
#else
        presentationDetents([.medium, .large])
#endif
    }

    @ViewBuilder
    func disciplineModeNavigationTitleStyle() -> some View {
#if os(macOS)
        self
#else
        navigationBarTitleDisplayMode(.inline)
#endif
    }
}
