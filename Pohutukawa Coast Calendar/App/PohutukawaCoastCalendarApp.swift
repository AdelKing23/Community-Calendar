import SwiftUI

@main
struct PohutukawaCoastCalendarApp: App {
    @StateObject private var userSessionStore = UserSessionStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(userSessionStore)
        }
    }
}
