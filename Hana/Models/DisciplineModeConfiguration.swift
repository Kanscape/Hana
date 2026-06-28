import Foundation

public struct DisciplineModeConfiguration: Codable, Equatable, Sendable {
    public var createdAt: Date
    public var mode: DisciplineModeMode

    public init(createdAt: Date = .now, mode: DisciplineModeMode) {
        self.createdAt = createdAt
        self.mode = mode
    }
}

public enum DisciplineModeMode: Codable, Equatable, Sendable {
    case single(until: Date)
    case recurring(DisciplineModeRecurringConfiguration)
    case weekly(DisciplineModeWeeklyConfiguration)
}

public struct DisciplineModeRecurringConfiguration: Codable, Equatable, Sendable {
    public var cycleLengthDays: Int
    public var allowedDayNumbers: Set<Int>

    public init(cycleLengthDays: Int, allowedDayNumbers: Set<Int>) {
        self.cycleLengthDays = cycleLengthDays
        self.allowedDayNumbers = allowedDayNumbers
    }

    public var isValid: Bool {
        cycleLengthDays >= 2
            && allowedDayNumbers.isEmpty == false
            && allowedDayNumbers.count < cycleLengthDays
            && allowedDayNumbers.allSatisfy { (1...cycleLengthDays).contains($0) }
    }
}

public struct DisciplineModeWeeklyConfiguration: Codable, Equatable, Sendable {
    public static let cycleLengthDays = 7

    public var allowedWeekdayNumbers: Set<Int>

    public init(allowedWeekdayNumbers: Set<Int>) {
        self.allowedWeekdayNumbers = allowedWeekdayNumbers
    }

    public var isValid: Bool {
        allowedWeekdayNumbers.isEmpty == false
            && allowedWeekdayNumbers.count < Self.cycleLengthDays
            && allowedWeekdayNumbers.allSatisfy { (1...Self.cycleLengthDays).contains($0) }
    }
}

public struct DisciplineModeSingleDuration: Equatable, Sendable {
    public var days: Int
    public var hours: Int
    public var minutes: Int

    public init(days: Int, hours: Int, minutes: Int) {
        self.days = days
        self.hours = hours
        self.minutes = minutes
    }

    public var totalSeconds: TimeInterval {
        let clampedDays: Int = max(0, days)
        let clampedHours: Int = max(0, hours)
        let clampedMinutes: Int = max(0, minutes)
        let daySeconds: Int = clampedDays * 24 * 60 * 60
        let hourSeconds: Int = clampedHours * 60 * 60
        let minuteSeconds: Int = clampedMinutes * 60
        return TimeInterval(daySeconds + hourSeconds + minuteSeconds)
    }

    public var isValid: Bool {
        days >= 0 && hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59 && totalSeconds > 0
    }
}

public enum DisciplineModeAccess: Equatable, Sendable {
    case unlocked
    case locked
}

public enum DisciplineModeStateMessage: Equatable, Sendable {
    case inactive
    case invalidConfiguration
    case active
}

public enum DisciplineModeScheduleKind: Equatable, Sendable {
    case customCycle
    case weekly
}

public struct DisciplineModeState: Equatable, Sendable {
    public var access: DisciplineModeAccess
    public var message: DisciplineModeStateMessage
    public var scheduleKind: DisciplineModeScheduleKind?
    public var currentCycleDay: Int?
    public var cycleLengthDays: Int?
    public var allowedDayNumbers: Set<Int>
    public var nextAvailableAt: Date?
    public var remainingInterval: TimeInterval?
    public var allowsExit: Bool

    public init(
        access: DisciplineModeAccess,
        message: DisciplineModeStateMessage,
        scheduleKind: DisciplineModeScheduleKind? = nil,
        currentCycleDay: Int? = nil,
        cycleLengthDays: Int? = nil,
        allowedDayNumbers: Set<Int> = [],
        nextAvailableAt: Date? = nil,
        remainingInterval: TimeInterval? = nil,
        allowsExit: Bool = false
    ) {
        self.access = access
        self.message = message
        self.scheduleKind = scheduleKind
        self.currentCycleDay = currentCycleDay
        self.cycleLengthDays = cycleLengthDays
        self.allowedDayNumbers = allowedDayNumbers
        self.nextAvailableAt = nextAvailableAt
        self.remainingInterval = remainingInterval
        self.allowsExit = allowsExit
    }

    public static let inactive = DisciplineModeState(access: .unlocked, message: .inactive)
}
