import Foundation
import UserNotifications

/// Lên lịch nhắc đọc sách trước mỗi khung giờ 10 phút (lặp lại hằng ngày).
enum ReminderScheduler {
    static let minutesBefore = 10
    private static let prefix = "reading-slot-"

    struct SlotInfo {
        let id: UUID
        let hour: Int
        let minute: Int
        let durationMinutes: Int
        let label: String
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func reschedule(slots: [SlotInfo], goalMinutes: Int) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        guard !slots.isEmpty else { return }
        let status = await authorizationStatus()
        if status == .notDetermined {
            guard await requestAuthorization() else { return }
        } else if status == .denied {
            return
        }

        for slot in slots {
            var total = slot.hour * 60 + slot.minute - minutesBefore
            if total < 0 { total += 24 * 60 }
            var comps = DateComponents()
            comps.hour = total / 60
            comps.minute = total % 60

            let content = UNMutableNotificationContent()
            content.title = "📚 Còn 10 phút nữa là tới giờ đọc sách"
            let name = slot.label.isEmpty ? "" : " “\(slot.label)”"
            content.body = "Khung giờ\(name) bắt đầu lúc \(String(format: "%02d:%02d", slot.hour, slot.minute)), đọc \(slot.durationMinutes) phút nhé. Mục tiêu hôm nay: \(goalMinutes) phút."
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: prefix + slot.id.uuidString, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func sendTest() async {
        if await authorizationStatus() == .notDetermined { _ = await requestAuthorization() }
        let content = UNMutableNotificationContent()
        content.title = "📚 Thử nhắc nhở"
        content.body = "Thông báo đang hoạt động. Bạn sẽ được nhắc trước mỗi khung giờ đọc 10 phút."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }
}
