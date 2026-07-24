import Foundation
import UserNotifications

final class NotificationService {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(home: MonitoredHome) {
        let content = UNMutableNotificationContent()
        content.title = "\(home.health.title) write activity"
        content.subtitle = home.displayName
        content.body = notificationBody(for: home)
        content.sound = home.health == .critical ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: "write-alert-\(home.id)-\(home.health.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func notificationBody(for home: MonitoredHome) -> String {
        let rate = Formatters.rate(home.metrics.insertRate)
        if home.metrics.growthBytesPerSecond > 0 {
            let growth = Formatters.byteRate(home.metrics.growthBytesPerSecond)
            return "\(rate) and \(growth) of database growth at \(home.path)."
        }
        return "\(rate) at \(home.path). Open SSD Watcher for details."
    }
}
