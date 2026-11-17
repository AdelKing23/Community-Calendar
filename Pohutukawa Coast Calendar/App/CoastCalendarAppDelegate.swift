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

/// Scene delegate named in the static Info.plist scene manifest (build 12) so the iOS 27
/// launch-time UIScene check sees an explicit scene configuration. SwiftUI still owns the
/// window and all content; this class adds no behaviour.
final class CoastCalendarSceneDelegate: NSObject, UIWindowSceneDelegate {}

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
