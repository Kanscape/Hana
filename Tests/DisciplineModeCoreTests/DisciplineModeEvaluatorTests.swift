import Foundation
import Testing
@testable import DisciplineModeCore

@Suite("Discipline mode evaluator")
struct DisciplineModeEvaluatorTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return calendar
    }()

    @Test("single lock is active before end date")
    func singleLockActiveBeforeEndDate() throws {
        let start = try #require(date("2026-06-28 10:00"))
        let end = try #require(date("2026-06-29 10:00"))
        let now = try #require(date("2026-06-28 12:00"))
        let config = DisciplineModeConfiguration(
            createdAt: start,
            mode: .single(until: end)
        )

        let state = DisciplineModeEvaluator.evaluate(
            configuration: config,
            now: now,
            calendar: calendar
        )

        #expect(state.access == .locked)
        #expect(state.remainingInterval == TimeInterval(22 * 60 * 60))
        #expect(state.nextAvailableAt == end)
    }

    @Test("single lock expires at end date")
    func singleLockExpiresAtEndDate() throws {
        let start = try #require(date("2026-06-28 10:00"))
        let end = try #require(date("2026-06-29 10:00"))
        let config = DisciplineModeConfiguration(
            createdAt: start,
            mode: .single(until: end)
        )

        let state = DisciplineModeEvaluator.evaluate(
            configuration: config,
            now: end,
            calendar: calendar
        )

        #expect(state.access == .unlocked)
        #expect(state.remainingInterval == nil)
        #expect(state.nextAvailableAt == nil)
    }

    @Test("recurring mode allows configured cycle day")
    func recurringModeAllowsConfiguredCycleDay() throws {
        let start = try #require(date("2026-06-28 09:00"))
        let now = try #require(date("2026-06-30 12:00"))
        let config = DisciplineModeConfiguration(
            createdAt: start,
            mode: .recurring(
                DisciplineModeRecurringConfiguration(
                    cycleLengthDays: 7,
                    allowedDayNumbers: [1, 3, 5, 7]
                )
            )
        )

        let state = DisciplineModeEvaluator.evaluate(
            configuration: config,
            now: now,
            calendar: calendar
        )

        #expect(state.access == .unlocked)
        #expect(state.currentCycleDay == 3)
        #expect(state.cycleLengthDays == 7)
        #expect(state.allowsExit)
    }

    @Test("recurring mode locks non-allowed cycle day")
    func recurringModeLocksNonAllowedCycleDay() throws {
        let start = try #require(date("2026-06-28 09:00"))
        let now = try #require(date("2026-06-29 12:00"))
        let expectedNextAvailable = try #require(date("2026-06-30 00:00"))
        let config = DisciplineModeConfiguration(
            createdAt: start,
            mode: .recurring(
                DisciplineModeRecurringConfiguration(
                    cycleLengthDays: 7,
                    allowedDayNumbers: [1, 3, 5, 7]
                )
            )
        )

        let state = DisciplineModeEvaluator.evaluate(
            configuration: config,
            now: now,
            calendar: calendar
        )

        #expect(state.access == .locked)
        #expect(state.currentCycleDay == 2)
        #expect(state.nextAvailableAt == expectedNextAvailable)
        #expect(state.remainingInterval == TimeInterval(12 * 60 * 60))
        #expect(!state.allowsExit)
    }

    @Test("weekly mode allows configured real weekday")
    func weeklyModeAllowsConfiguredRealWeekday() throws {
        let start = try #require(date("2026-06-28 09:00"))
        let now = try #require(date("2026-06-30 12:00"))
        let config = DisciplineModeConfiguration(
            createdAt: start,
            mode: .weekly(
                DisciplineModeWeeklyConfiguration(
                    allowedWeekdayNumbers: [2]
                )
            )
        )

        let state = DisciplineModeEvaluator.evaluate(
            configuration: config,
            now: now,
            calendar: calendar
        )

        #expect(state.access == .unlocked)
        #expect(state.currentCycleDay == 2)
        #expect(state.cycleLengthDays == 7)
        #expect(state.allowsExit)
    }

    @Test("weekly mode locks non-allowed real weekday")
    func weeklyModeLocksNonAllowedRealWeekday() throws {
        let start = try #require(date("2026-06-28 09:00"))
        let now = try #require(date("2026-06-30 12:00"))
        let expectedNextAvailable = try #require(date("2026-07-01 00:00"))
        let config = DisciplineModeConfiguration(
            createdAt: start,
            mode: .weekly(
                DisciplineModeWeeklyConfiguration(
                    allowedWeekdayNumbers: [3]
                )
            )
        )

        let state = DisciplineModeEvaluator.evaluate(
            configuration: config,
            now: now,
            calendar: calendar
        )

        #expect(state.access == .locked)
        #expect(state.currentCycleDay == 2)
        #expect(state.nextAvailableAt == expectedNextAvailable)
        #expect(state.remainingInterval == TimeInterval(12 * 60 * 60))
        #expect(!state.allowsExit)
    }

    @Test("invalid recurring configuration is treated as inactive")
    func invalidRecurringConfigurationIsInactive() throws {
        let start = try #require(date("2026-06-28 09:00"))
        let now = try #require(date("2026-06-29 12:00"))
        let config = DisciplineModeConfiguration(
            createdAt: start,
            mode: .recurring(
                DisciplineModeRecurringConfiguration(
                    cycleLengthDays: 7,
                    allowedDayNumbers: [1, 2, 3, 4, 5, 6, 7]
                )
            )
        )

        let state = DisciplineModeEvaluator.evaluate(
            configuration: config,
            now: now,
            calendar: calendar
        )

        #expect(state.access == .unlocked)
        #expect(state.message == .invalidConfiguration)
    }

    private func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)
    }
}
