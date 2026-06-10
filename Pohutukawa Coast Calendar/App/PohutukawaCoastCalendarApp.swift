import SwiftUI

@main
struct PohutukawaCoastCalendarApp: App {
    @StateObject private var userSessionStore = UserSessionStore()
    @StateObject private var engagementStore = EventEngagementStore()

    var body: some Scene {
        WindowGroup {
            AppLaunchSplash {
                RootTabView()
            }
                .environmentObject(userSessionStore)
                .environmentObject(engagementStore)
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
                    Image("AtlasDigitalLogo2026")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: proxy.size.width * 0.7,
                            maxHeight: proxy.size.height * 0.7
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
