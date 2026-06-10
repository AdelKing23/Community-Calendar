import SwiftUI

@main
struct PohutukawaCoastCalendarApp: App {
    @StateObject private var userSessionStore = UserSessionStore()
    @StateObject private var engagementStore = EventEngagementStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(userSessionStore)
                .environmentObject(engagementStore)
        }
    }
}
