import Foundation

@main
struct ScheduleRulesTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let slots = [
            ShutdownSlot(hour: 10, minute: 30, isEnabled: true),
            ShutdownSlot(hour: 22, minute: 0, isEnabled: false)
        ]
        expect(ScheduleRules.hasDuplicate(hour: 10, minute: 30, in: slots), "same time is a duplicate")
        expect(ScheduleRules.hasDuplicate(hour: 22, minute: 0, in: slots), "disabled time is still a duplicate")
        expect(!ScheduleRules.hasDuplicate(hour: 10, minute: 31, in: slots), "different minute is not a duplicate")

        let enabledSlot = ShutdownSlot(hour: 10, minute: 30, isEnabled: true)
        let disabledSlot = ShutdownSlot(hour: 10, minute: 30, isEnabled: false)
        let now = date(2026, 11, 27, 8, 30, calendar: calendar)
        expect(!ScheduleRules.isLocked(enabledSlot, at: now, calendar: calendar), "exactly two hours is not locked")
        expect(
            ScheduleRules.isLocked(enabledSlot, at: now.addingTimeInterval(1), calendar: calendar),
            "less than two hours is locked"
        )
        expect(!ScheduleRules.isLocked(disabledSlot, at: now, calendar: calendar), "disabled slot is not locked")
        expect(
            ScheduleRules.isLocked(enabledSlot, at: date(2026, 11, 27, 10, 30, calendar: calendar), calendar: calendar),
            "slot is locked at its scheduled time"
        )
        expect(
            !ScheduleRules.isLocked(
                enabledSlot,
                at: date(2026, 11, 27, 10, 31, calendar: calendar),
                calendar: calendar
            ),
            "passed slot uses the next day's occurrence"
        )
        expect(
            ScheduleRules.isLocked(
                ShutdownSlot(hour: 0, minute: 30, isEnabled: true),
                at: date(2026, 11, 27, 23, 0, calendar: calendar),
                calendar: calendar
            ),
            "lock window crosses midnight"
        )

        print("All schedule rule tests passed.")
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("Test failed: \(message)\n", stderr)
            exit(1)
        }
    }
}
