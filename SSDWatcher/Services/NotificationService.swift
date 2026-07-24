import Foundation
import UserNotifications

final class NotificationService {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(location: MonitoredLocation) {
        let content = UNMutableNotificationContent()
        content.title = "\(location.health.title) write activity"
        content.subtitle = "\(location.candidate.product.displayName) · \(location.displayName)"
        content.body = notificationBody(for: location)
        content.sound = location.health == .critical ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: "write-alert-\(location.id)-\(location.health.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func notificationBody(for location: MonitoredLocation) -> String {
        let rate = Formatters.recordRate(location.metrics.recordRate)
        if location.metrics.growthBytesPerSecond > 0 {
            let growth = Formatters.byteRate(location.metrics.growthBytesPerSecond)
            return "\(rate) and \(growth) of database growth at \(location.path)."
        }
        return "\(rate) at \(location.path). Open SSD Watcher for details."
    }
}
