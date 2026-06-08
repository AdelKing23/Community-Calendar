import SwiftUI

@main
struct PohutukawaCoastCalendarApp: App {
    @StateObject private var userSessionStore = UserSessionStore()
    @StateObject private var ownerSessionStore = OwnerSessionStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(userSessionStore)
                .environmentObject(ownerSessionStore)
        }
    }
}
