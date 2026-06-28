import SwiftUI

enum DisciplineModeDraftMode: String, CaseIterable, Identifiable {
    case weekly
    case recurring
    case single

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly:
            "按星期"
        case .recurring:
            "按周期"
        case .single:
            "仅单次"
        }
    }
}

struct DisciplineModeAllowedDaysGrid: View {
    let cycleLengthDays: Int
    let dayLabels: [Int: String]
    let accessibilityLabels: [Int: String]
    @Binding var allowedDayNumbers: Set<Int>

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 10)
    ]

    init(
        cycleLengthDays: Int,
        allowedDayNumbers: Binding<Set<Int>>,
        dayLabels: [Int: String] = [:],
        accessibilityLabels: [Int: String] = [:]
    ) {
        self.cycleLengthDays = cycleLengthDays
        self._allowedDayNumbers = allowedDayNumbers
        self.dayLabels = dayLabels
        self.accessibilityLabels = accessibilityLabels
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(1...cycleLengthDays, id: \.self) { day in
                Button {
                    toggle(day)
                } label: {
                    Text(dayLabels[day] ?? "\(day)")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.bordered)
                .tint(allowedDayNumbers.contains(day) ? Color.pink : Color.gray)
                .accessibilityLabel(accessibilityLabels[day] ?? "第 \(day) 天")
            }
        }
        .onChange(of: cycleLengthDays) { _, newValue in
            allowedDayNumbers = Set(allowedDayNumbers.filter { (1...newValue).contains($0) })
            if allowedDayNumbers.isEmpty {
                allowedDayNumbers = [1]
            }
            if allowedDayNumbers.count == newValue {
                allowedDayNumbers.remove(newValue)
            }
        }
    }

    private func toggle(_ day: Int) {
        if allowedDayNumbers.contains(day) {
            allowedDayNumbers.remove(day)
        } else {
            allowedDayNumbers.insert(day)
        }
    }
}

struct DisciplineModeSingleDurationEditor: View {
    @Binding var duration: DisciplineModeSingleDuration

    var body: some View {
        Stepper(value: $duration.days, in: 0...365) {
            LabeledContent("天", value: "\(duration.days)")
        }
        Stepper(value: $duration.hours, in: 0...23) {
            LabeledContent("小时", value: "\(duration.hours)")
        }
        Stepper(value: $duration.minutes, in: 0...59) {
            LabeledContent("分钟", value: "\(duration.minutes)")
        }
    }
}
