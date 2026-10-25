import Foundation

struct DaySchedule: Codable, Equatable {
    var enabled: Bool
    /// Minutes after midnight.
    var startMinute: Int
    /// Minutes after midnight. Less than or equal to `startMinute` means the day runs past midnight.
    var endMinute: Int
}

struct OfficeHours: Codable, Equatable {
    var enabled = false
    /// Indexed by `Calendar.component(.weekday) - 1` (0 = Sunday).
    var days: [DaySchedule] = (0..<7).map { weekday in
        DaySchedule(enabled: (1...5).contains(weekday), startMinute: 9 * 60, endMinute: 18 * 60)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return true }
        let weekday = calendar.component(.weekday, from: date) - 1
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

        let today = days[weekday]
        if today.enabled {
            if today.endMinute > today.startMinute {
                if minute >= today.startMinute && minute < today.endMinute { return true }
            } else if minute >= today.startMinute {
                return true
            }
        }
        // Yesterday's overnight shift spilling into today.
        let yesterday = days[(weekday + 6) % 7]
        if yesterday.enabled && yesterday.endMinute <= yesterday.startMinute && minute < yesterday.endMinute {
            return true
        }
        return false
    }
}
