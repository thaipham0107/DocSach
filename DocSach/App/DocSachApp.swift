import SwiftUI
import SwiftData
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Vẫn hiện thông báo nhắc khi đang mở ứng dụng.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

@main
struct DocSachApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var importer = ImportCenter()

    let container: ModelContainer = {
        do {
            return try ModelContainer(for: Book.self, Bookmark.self, ReadingDay.self, ReadingSlot.self, ReadingSession.self)
        } catch {
            fatalError("Không tạo được cơ sở dữ liệu: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(importer)
        }
        .modelContainer(container)
    }
}
