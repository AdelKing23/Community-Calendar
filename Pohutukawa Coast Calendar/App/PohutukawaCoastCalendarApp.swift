import SwiftUI

@main
struct PohutukawaCoastCalendarApp: App {
    @StateObject private var userSessionStore = UserSessionStore()
    @StateObject private var engagementStore = EventEngagementStore()
    @StateObject private var reminderStore = EventReminderStore()

    var body: some Scene {
        WindowGroup {
            AppLaunchSplash {
                RootTabView()
            }
                .environmentObject(userSessionStore)
                .environmentObject(engagementStore)
                .environmentObject(reminderStore)
        }
    }
}

private struct AppLaunchSplash<Content: View>: View {
    @State private var isShowingSplash = true

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content

            if isShowingSplash {
                Color.black
                    .ignoresSafeArea()

                GeometryReader { proxy in
                    let width = proxy.size.width.isFinite ? max(proxy.size.width, 1) : 1
                    let height = proxy.size.height.isFinite ? max(proxy.size.height, 1) : 1

                    Image("AtlasDigitalLogo2026")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: width * 0.7,
                            maxHeight: height * 0.7
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.35))
            withAnimation(.easeOut(duration: 0.45)) {
                isShowingSplash = false
            }
        }
    }
}
