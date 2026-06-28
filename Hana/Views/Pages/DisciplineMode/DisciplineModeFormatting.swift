import Foundation

enum DisciplineModeFormatting {
    nonisolated static func chineseDateTimeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    nonisolated static func weekdayShortText(for weekdayNumber: Int) -> String {
        switch weekdayNumber {
        case 1:
            "一"
        case 2:
            "二"
        case 3:
            "三"
        case 4:
            "四"
        case 5:
            "五"
        case 6:
            "六"
        case 7:
            "日"
        default:
            "\(weekdayNumber)"
        }
    }

    nonisolated static func weekdayText(for weekdayNumber: Int) -> String {
        "周\(weekdayShortText(for: weekdayNumber))"
    }

    nonisolated static func weekdayListText(for weekdayNumbers: Set<Int>) -> String {
        weekdayNumbers.sorted().map(weekdayText).joined(separator: "、")
    }
}
