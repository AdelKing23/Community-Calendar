import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case whatsOn = "What's On"
    case create = "Create"
    case calendar = "Hosts"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .whatsOn: return "calendar"
        case .create: return "plus.circle.fill"
        case .calendar: return "person.3.fill"
        case .settings: return "gearshape"
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @EnvironmentObject private var purchaseService: StoreKitPurchaseService
    @EnvironmentObject private var pushNotificationStore: PushNotificationStore
    @EnvironmentObject private var locationPreferenceStore: UserLocationPreferenceStore
    @AppStorage("communityCalendar.belonging.onboardingSeen") private var hasSeenBelongingOnboarding = false
    @AppStorage("communityCalendar.belonging.lastPromptTime") private var lastBelongingPromptTime = 0.0
    @AppStorage("communityCalendar.belonging.promptCount") private var belongingPromptCount = 0
    @State private var selectedTab: MainTab = .home
    @State private var isKeyboardVisible = false
    @State private var showBelongingOnboarding = false
    @State private var showAccountAccess = false
    @State private var showMembershipApplication = false

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
                        onNavigateWhatsOn: { selectedTab = .whatsOn },
                        onNavigateSettings: { selectedTab = .settings },
                        onApplyForMembership: { showMembershipApplication = true }
                    )
                case .calendar:
                    HostsScreen()
                case .settings:
                    SettingsScreen {
                        selectedTab = .create
                    }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.995)))
            .animation(.easeOut(duration: 0.18), value: selectedTab)

            if !isKeyboardVisible {
                PCCBottomTabBar(selectedTab: $selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !isKeyboardVisible {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .overlay(alignment: .topTrailing) {
                        AppNotificationOverlay(selectedTab: $selectedTab)
                            .padding(.top, 78)
                            .padding(.trailing, 44)
                    }
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isKeyboardVisible)
        .pccTracksKeyboardVisibility($isKeyboardVisible)
        .task {
            purchaseService.startTransactionListener()
            await purchaseService.loadProducts()
        }
        .onAppear {
            showBelongingOnboardingIfNeeded()
        }
        .onChange(of: purchaseService.state) { _, newState in
            guard case .activated = newState else { return }
            showMembershipApplication = false
        }
        .sheet(isPresented: $showBelongingOnboarding) {
            BelongingOnboardingSheet(
                isSignedIn: userSessionStore.isSignedIn,
                locationMessage: locationPreferenceStore.locationMessage,
                isLocating: locationPreferenceStore.isLocating,
                useLocation: {
                    markBelongingPromptSeen()
                    locationPreferenceStore.requestCurrentLocation()
                },
                chooseArea: {
                    markBelongingPromptSeen()
                    selectedTab = .whatsOn
                    showBelongingOnboarding = false
                },
                createAccount: {
                    markBelongingPromptSeen()
                    showBelongingOnboarding = false
                    showAccountAccess = true
                },
                applyForMembership: {
                    markBelongingPromptSeen()
                    showMembershipApplication = true
                    showBelongingOnboarding = false
                },
                skip: {
                    markBelongingPromptSeen()
                    showBelongingOnboarding = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onChange(of: locationPreferenceStore.locationMessage) { _, message in
                guard let message, message.hasPrefix("We’ll start with") else { return }
                showBelongingOnboarding = false
            }
        }
        .sheet(isPresented: $showAccountAccess) {
            AccountAccessSheet()
                .environmentObject(userSessionStore)
        }
        .sheet(isPresented: $showMembershipApplication) {
            BusinessPlansScreen()
                .environmentObject(userSessionStore)
                .environmentObject(pushNotificationStore)
                .environmentObject(purchaseService)
        }
    }

    private func showBelongingOnboardingIfNeeded() {
        guard !showBelongingOnboarding else { return }

        let now = Date().timeIntervalSince1970
        let secondsSinceLastPrompt = now - lastBelongingPromptTime
        let shouldRepeatForUnsignedUser = !userSessionStore.isSignedIn
            && belongingPromptCount < 3
            && secondsSinceLastPrompt > 60 * 60 * 24 * 21

        if !hasSeenBelongingOnboarding || shouldRepeatForUnsignedUser {
            showBelongingOnboarding = true
            belongingPromptCount += 1
            lastBelongingPromptTime = now
        }
    }

    private func markBelongingPromptSeen() {
        hasSeenBelongingOnboarding = true
        lastBelongingPromptTime = Date().timeIntervalSince1970
    }
}

struct BelongingOnboardingSheet: View {
    let isSignedIn: Bool
    let locationMessage: String?
    let isLocating: Bool
    let useLocation: () -> Void
    let chooseArea: () -> Void
    let createAccount: () -> Void
    let applyForMembership: () -> Void
    let skip: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                PCCTheme.cream.opacity(0.5).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "location.circle.fill")
                                .font(.system(size: 42, weight: .black))
                                .foregroundStyle(PCCTheme.pohutukawaOrange)

                            Text("Find Where You Belong")
                                .font(.system(size: 34, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("Belonging helps Coast Calendar show nearby listings, notices and hosts first. You can keep browsing without signing in.")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.66))
                                .lineSpacing(3)
                        }
                        .padding(18)
                        .pccCardStyle()

                        VStack(spacing: 10) {
                            BelongingPromptButton(
                                title: isLocating ? "Finding your community" : "Use my location",
                                message: "Only while the app is open.",
                                icon: isLocating ? "location.circle" : "location.fill",
                                tint: PCCTheme.leafGreen,
                                action: useLocation
                            )
                            .disabled(isLocating)

                            BelongingPromptButton(
                                title: "Choose where I belong",
                                message: "Pick a community, district or wider area.",
                                icon: "map.fill",
                                tint: PCCTheme.pohutukawaOrange,
                                action: chooseArea
                            )

                            if !isSignedIn {
                                BelongingPromptButton(
                                    title: "Create a Belonging account",
                                    message: "Save events, follow hosts and tune your feed.",
                                    icon: "person.crop.circle.badge.plus",
                                    tint: PCCTheme.leafGreen,
                                    action: createAccount
                                )
                            }

                            BelongingPromptButton(
                                title: "Register your Organisation",
                                message: "For schools, clubs, groups and businesses who want a public Organisation page.",
                                icon: "checkmark.seal.fill",
                                tint: PCCTheme.ink,
                                action: applyForMembership
                            )
                        }

                        if let locationMessage {
                            Text(locationMessage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                                .lineSpacing(2)
                        }

                        Button("Not now") {
                            skip()
                        }
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Belonging")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct BelongingPromptButton: View {
    let title: String
    let message: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.black))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.black))
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .opacity(0.78)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(tint, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PCCBottomTabBar: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        HStack(spacing: 5) {
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
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(selectedTab == tab ? .white : PCCTheme.ink.opacity(0.58))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .padding(.vertical, tab == .create ? 9 : 8)
                    .background(
                        selectedTab == tab ? PCCTheme.leafGreen : .clear,
                        in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(7)
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous)
                .stroke(.white.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: PCCTheme.deepGreen.opacity(0.14), radius: 18, x: 0, y: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}
