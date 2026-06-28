import Foundation

public enum DisciplineModeEvaluator {
    public static func evaluate(
        configuration: DisciplineModeConfiguration?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DisciplineModeState {
        guard let configuration else {
            return .inactive
        }

        switch configuration.mode {
        case .single(let until):
            return evaluateSingle(until: until, now: now)
        case .recurring(let recurring):
            return evaluateRecurring(
                recurring,
                createdAt: configuration.createdAt,
                now: now,
                calendar: calendar
            )
        case .weekly(let weekly):
            return evaluateWeekly(
                weekly,
                now: now,
                calendar: calendar
            )
        }
    }

    private static func evaluateSingle(until: Date, now: Date) -> DisciplineModeState {
        guard until > now else {
            return .inactive
        }

        return DisciplineModeState(
            access: .locked,
            message: .active,
            nextAvailableAt: until,
            remainingInterval: max(0, until.timeIntervalSince(now))
        )
    }

    private static func evaluateRecurring(
        _ recurring: DisciplineModeRecurringConfiguration,
        createdAt: Date,
        now: Date,
        calendar: Calendar
    ) -> DisciplineModeState {
        guard recurring.isValid else {
            return DisciplineModeState(access: .unlocked, message: .invalidConfiguration)
        }

        let anchorDay = calendar.startOfDay(for: createdAt)
        let currentDay = calendar.startOfDay(for: now)
        let elapsedDays = max(0, calendar.dateComponents([.day], from: anchorDay, to: currentDay).day ?? 0)
        let cycleDay = elapsedDays % recurring.cycleLengthDays + 1

        guard recurring.allowedDayNumbers.contains(cycleDay) == false else {
            return DisciplineModeState(
                access: .unlocked,
                message: .active,
                scheduleKind: .customCycle,
                currentCycleDay: cycleDay,
                cycleLengthDays: recurring.cycleLengthDays,
                allowedDayNumbers: recurring.allowedDayNumbers,
                allowsExit: true
            )
        }

        let nextAvailableAt = nextAllowedDate(
            from: currentDay,
            currentCycleDay: cycleDay,
            recurring: recurring,
            calendar: calendar
        )
        let remaining = nextAvailableAt.map { max(0, $0.timeIntervalSince(now)) }

        return DisciplineModeState(
            access: .locked,
            message: .active,
            scheduleKind: .customCycle,
            currentCycleDay: cycleDay,
            cycleLengthDays: recurring.cycleLengthDays,
            allowedDayNumbers: recurring.allowedDayNumbers,
            nextAvailableAt: nextAvailableAt,
            remainingInterval: remaining
        )
    }

    private static func evaluateWeekly(
        _ weekly: DisciplineModeWeeklyConfiguration,
        now: Date,
        calendar: Calendar
    ) -> DisciplineModeState {
        guard weekly.isValid else {
            return DisciplineModeState(access: .unlocked, message: .invalidConfiguration)
        }

        let currentDay = calendar.startOfDay(for: now)
        let weekdayNumber = weekdayNumber(for: now, calendar: calendar)

        guard weekly.allowedWeekdayNumbers.contains(weekdayNumber) == false else {
            return DisciplineModeState(
                access: .unlocked,
                message: .active,
                scheduleKind: .weekly,
                currentCycleDay: weekdayNumber,
                cycleLengthDays: DisciplineModeWeeklyConfiguration.cycleLengthDays,
                allowedDayNumbers: weekly.allowedWeekdayNumbers,
                allowsExit: true
            )
        }

        let nextAvailableAt = nextAllowedWeekdayDate(
            from: currentDay,
            currentWeekdayNumber: weekdayNumber,
            weekly: weekly,
            calendar: calendar
        )
        let remaining = nextAvailableAt.map { max(0, $0.timeIntervalSince(now)) }

        return DisciplineModeState(
            access: .locked,
            message: .active,
            scheduleKind: .weekly,
            currentCycleDay: weekdayNumber,
            cycleLengthDays: DisciplineModeWeeklyConfiguration.cycleLengthDays,
            allowedDayNumbers: weekly.allowedWeekdayNumbers,
            nextAvailableAt: nextAvailableAt,
            remainingInterval: remaining
        )
    }

    private static func nextAllowedDate(
        from currentDay: Date,
        currentCycleDay: Int,
        recurring: DisciplineModeRecurringConfiguration,
        calendar: Calendar
    ) -> Date? {
        for offset in 1...recurring.cycleLengthDays {
            let nextCycleDay = ((currentCycleDay - 1 + offset) % recurring.cycleLengthDays) + 1
            guard recurring.allowedDayNumbers.contains(nextCycleDay) else {
                continue
            }
            return calendar.date(byAdding: .day, value: offset, to: currentDay)
        }
        return nil
    }

    private static func nextAllowedWeekdayDate(
        from currentDay: Date,
        currentWeekdayNumber: Int,
        weekly: DisciplineModeWeeklyConfiguration,
        calendar: Calendar
    ) -> Date? {
        for offset in 1...DisciplineModeWeeklyConfiguration.cycleLengthDays {
            let nextWeekdayNumber = ((currentWeekdayNumber - 1 + offset) % DisciplineModeWeeklyConfiguration.cycleLengthDays) + 1
            guard weekly.allowedWeekdayNumbers.contains(nextWeekdayNumber) else {
                continue
            }
            return calendar.date(byAdding: .day, value: offset, to: currentDay)
        }
        return nil
    }

    private static func weekdayNumber(for date: Date, calendar: Calendar) -> Int {
        let calendarWeekday = calendar.component(.weekday, from: date)
        return ((calendarWeekday + 5) % DisciplineModeWeeklyConfiguration.cycleLengthDays) + 1
    }
}
