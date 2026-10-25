import UserNotifications

/// Runs for every Breather push, even with the phone asleep (paid builds). Applies or lifts
/// the Screen Time block, then shows the notification unchanged.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        #if BREATHER_PAID
        if let info = request.content.userInfo["breather"] as? [String: Any], let action = info["action"] as? String {
            if action == "block", info["block"] as? Bool == true {
                ScreenTimeShield.apply()
            } else if action == "unblock" {
                ScreenTimeShield.clear()
            }
        }
        #endif
        contentHandler(request.content)
    }
}
