import SwiftUI

struct DisciplineModeLockScreen: View {
    @Environment(DisciplineModeStore.self) private var disciplineModeStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let state = DisciplineModeEvaluator.evaluate(
                configuration: disciplineModeStore.configuration,
                now: context.date,
                calendar: .current
            )

            VStack(spacing: 18) {
                Image(systemName: "calendar.badge.lock")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.pink)

                VStack(spacing: 8) {
                    Text("自律模式中")
                        .font(.title.bold())
                    Text(summaryText(for: state))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let remaining = state.remainingInterval {
                    Text(remainingText(remaining))
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }

                if let nextAvailableAt = state.nextAvailableAt {
                    Text("可用时间：\(DisciplineModeFormatting.chineseDateTimeText(for: nextAvailableAt))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
    }

    private func summaryText(for state: DisciplineModeState) -> String {
        if let currentCycleDay = state.currentCycleDay, let cycleLengthDays = state.cycleLengthDays {
            if state.scheduleKind == .weekly {
                let allowed = DisciplineModeFormatting.weekdayListText(for: state.allowedDayNumbers)
                let currentWeekday = DisciplineModeFormatting.weekdayText(for: currentCycleDay)
                return "每周循环，今天\(currentWeekday)。允许使用：\(allowed)。"
            }
            let allowed = state.allowedDayNumbers.sorted().map { "第 \($0) 天" }.joined(separator: "、")
            return "\(cycleLengthDays) 天循环，当前第 \(currentCycleDay) 天。允许使用：\(allowed)。"
        }
        return "限制结束前无法进入 App 观看内容。"
    }

    private func remainingText(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)天 \(hours)小时 \(minutes)分钟"
        }
        if hours > 0 {
            return "\(hours)小时 \(minutes)分钟"
        }
        return "\(minutes)分钟"
    }
}
