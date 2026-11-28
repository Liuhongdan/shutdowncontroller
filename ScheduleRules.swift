import Foundation

struct ShutdownSlot: Identifiable, Codable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var isEnabled: Bool
}

enum ShutdownControlMode: String, CaseIterable, Codable, Identifiable {
    case app
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app:
            return "This App"
        case .system:
            return "Continue after quitting"
        }
    }
}

enum ScheduleRules {
    static let lockWindow: TimeInterval = 2 * 60 * 60

    static func hasDuplicate(hour: Int, minute: Int, in slots: [ShutdownSlot]) -> Bool {
        slots.contains { $0.hour == hour && $0.minute == minute }
    }

    static func isLocked(
        _ slot: ShutdownSlot,
        at now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard slot.isEnabled,
              let scheduledToday = calendar.date(
                bySettingHour: slot.hour,
                minute: slot.minute,
                second: 0,
                of: now
              ) else {
            return false
        }

        let nextOccurrence: Date
        if scheduledToday >= now {
            nextOccurrence = scheduledToday
        } else {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: scheduledToday) else {
                return false
            }
            nextOccurrence = tomorrow
        }

        let timeUntilShutdown = nextOccurrence.timeIntervalSince(now)
        return timeUntilShutdown >= 0 && timeUntilShutdown < lockWindow
    }
}
