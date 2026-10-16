import Foundation
import UIKit
import UserNotifications

final class CoastCalendarAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationCenter.default.post(
            name: .coastCalendarDidRegisterRemoteNotifications,
            object: nil,
            userInfo: [CoastCalendarRemoteNotificationUserInfo.deviceToken: deviceToken]
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(
            name: .coastCalendarDidFailToRegisterRemoteNotifications,
            object: nil,
            userInfo: [CoastCalendarRemoteNotificationUserInfo.error: error]
        )
    }
}

enum CoastCalendarRemoteNotificationUserInfo {
    static let deviceToken = "deviceToken"
    static let error = "error"
    static let payload = "payload"
}

extension Notification.Name {
    static let coastCalendarDidRegisterRemoteNotifications = Notification.Name("coastCalendarDidRegisterRemoteNotifications")
    static let coastCalendarDidFailToRegisterRemoteNotifications = Notification.Name("coastCalendarDidFailToRegisterRemoteNotifications")
    static let coastCalendarDidOpenRemoteNotification = Notification.Name("coastCalendarDidOpenRemoteNotification")
}
