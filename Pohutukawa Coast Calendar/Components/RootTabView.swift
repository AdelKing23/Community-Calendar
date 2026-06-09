import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case whatsOn = "What's On"
    case create = "Create"
    case calendar = "Calendar"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .whatsOn: return "calendar"
        case .create: return "plus.circle.fill"
        case .calendar: return "calendar.day.timeline.left"
        case .settings: return "gearshape"
        }
    }
}

struct RootTabView: View {
    @State private var selectedTab: MainTab = .home
    @State private var isKeyboardVisible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    HomeScreen()
                case .whatsOn:
                    WhatsOnScreen()
                case .create:
                    CreateListingScreen(
                        onNavigateHome: { selectedTab = .home },
                        onNavigateWhatsOn: { selectedTab = .whatsOn }
                    )
                case .calendar:
                    CalendarScreen()
                case .settings:
                    SettingsScreen {
                        selectedTab = .create
                    }
                }
            }

            if !isKeyboardVisible {
                PCCBottomTabBar(selectedTab: $selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isKeyboardVisible)
        .pccTracksKeyboardVisibility($isKeyboardVisible)
    }
}

struct PCCBottomTabBar: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: tab == .create ? 23 : 17, weight: .bold))

                        Text(tab.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .foregroundStyle(selectedTab == tab ? .white : PCCTheme.ink.opacity(0.58))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, tab == .create ? 9 : 8)
                    .background(
                        selectedTab == tab ? PCCTheme.leafGreen : .clear,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}
