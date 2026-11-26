import Foundation
import SwiftData

enum ReadingStats {
    static let goalKey = "dailyGoalMinutes"
    static let defaultGoal = 30

    static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static var currentGoal: Int {
        let v = UserDefaults.standard.integer(forKey: goalKey)
        return v > 0 ? v : defaultGoal
    }

    @MainActor
    static func add(seconds: Double, startedAt: Date, bookTitle: String, context: ModelContext) {
        let k = key(for: startedAt)
        let descriptor = FetchDescriptor<ReadingDay>(predicate: #Predicate<ReadingDay> { $0.day == k })
        if let day = try? context.fetch(descriptor).first {
            day.seconds += seconds
            day.goalMinutes = currentGoal
        } else {
            context.insert(ReadingDay(day: k, seconds: seconds, goalMinutes: currentGoal))
        }
        context.insert(ReadingSession(day: k, startedAt: startedAt, seconds: seconds, bookTitle: bookTitle))
        try? context.save()
    }

    static func date(from key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    static func durationText(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) phút" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) giờ" : "\(h) giờ \(m) phút"
    }

    /// Số ngày liên tiếp (tính tới hôm nay hoặc hôm qua) đạt mục tiêu.
    static func streak(days: [ReadingDay], goalMinutes: Int) -> Int {
        let map = Dictionary(days.map { ($0.day, $0.seconds) }, uniquingKeysWith: +)
        let goal = Double(max(1, goalMinutes) * 60)
        var date = Date()
        var count = 0
        if (map[key(for: date)] ?? 0) < goal {
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        while (map[key(for: date)] ?? 0) >= goal {
            count += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return count
    }
}

/// Đếm thời gian đọc khi màn hình đọc đang mở.
final class ReadingTimer {
    private var startedAt: Date?

    func start() {
        if startedAt == nil { startedAt = Date() }
    }

    @MainActor
    func stop(context: ModelContext, bookTitle: String) {
        guard let start = startedAt else { return }
        startedAt = nil
        let seconds = Date().timeIntervalSince(start)
        guard seconds > 5 else { return }
        ReadingStats.add(seconds: min(seconds, 4 * 3600), startedAt: start, bookTitle: bookTitle, context: context)
    }
}
