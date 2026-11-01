import Combine
import CoreLocation
import SwiftUI
import UIKit

@main
struct PohutukawaCoastCalendarApp: App {
    @UIApplicationDelegateAdaptor(CoastCalendarAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var userSessionStore = UserSessionStore()
    @StateObject private var accountProfileStore = AccountProfileStore()
    @StateObject private var engagementStore = EventEngagementStore()
    @StateObject private var reminderStore = EventReminderStore()
    @StateObject private var pushNotificationStore = PushNotificationStore()
    @StateObject private var deviceCalendarStore = DeviceCalendarStore()
    @StateObject private var purchaseService = StoreKitPurchaseService()
    @StateObject private var locationPreferenceStore = UserLocationPreferenceStore()
    @StateObject private var appOpenAnalyticsStore = AppOpenAnalyticsStore()

    var body: some Scene {
        WindowGroup {
            AppLaunchSplash {
                RootTabView()
            }
                .environmentObject(userSessionStore)
                .environmentObject(accountProfileStore)
                .environmentObject(engagementStore)
                .environmentObject(reminderStore)
                .environmentObject(pushNotificationStore)
                .environmentObject(deviceCalendarStore)
                .environmentObject(purchaseService)
                .environmentObject(locationPreferenceStore)
                .environmentObject(appOpenAnalyticsStore)
                .task {
                    locationPreferenceStore.prepareDefaultLocationIfNeeded()
                    await appOpenAnalyticsStore.recordOpenIfNeeded()
                }
                .task(id: userSessionStore.session?.userID) {
                    accountProfileStore.bind(to: userSessionStore.session?.userID)
                    purchaseService.resetAccountPresentationState()
                    await pushNotificationStore.syncSignedInSession(
                        userSessionStore.session,
                        context: userSessionStore.captureAccountContext()
                    )
                }
                .onChange(of: scenePhase) {
                    switch scenePhase {
                    case .active:
                        Task { await appOpenAnalyticsStore.recordOpenIfNeeded() }
                    case .background:
                        appOpenAnalyticsStore.appDidEnterBackground()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}

final class UserLocationPreferenceStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var locationMessage: String?
    @Published private(set) var isLocating = false

    private let manager = CLLocationManager()
    private let defaults: UserDefaults
    private let nearestLocationResolver: NearestLocationScopeResolving

    init(defaults: UserDefaults = .standard, nearestLocationResolver: NearestLocationScopeResolving = SupabaseEventService()) {
        self.defaults = defaults
        self.nearestLocationResolver = nearestLocationResolver
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var favoriteScopeID: String {
        defaults.string(forKey: Keys.favoriteScope) ?? LocationScope.defaultID
    }

    var hasAskedForLocationAccess: Bool {
        defaults.bool(forKey: Keys.hasAskedLocation)
    }

    func prepareDefaultLocationIfNeeded() {
        applyDefaultScope(reason: nil)
    }

    func requestCurrentLocation() {
        defaults.set(true, forKey: Keys.hasAskedLocation)
        locationMessage = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            isLocating = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLocating = true
            manager.requestLocation()
        case .denied, .restricted:
            applyDefaultScope(reason: "Location is off. Choose an area from the list to set where you belong.")
        @unknown default:
            applyDefaultScope(reason: nil)
        }
    }

    func saveFavorite(scope: LocationScope) {
        defaults.set(scope.id, forKey: Keys.favoriteScope)
        defaults.set(scope.id, forKey: Keys.selectedScope)
        defaults.set(scope.id, forKey: Keys.focusedScope)
        locationMessage = "\(scope.name) is saved as your favourite area."
    }

    func useFavoriteScope() {
        let scopeID = favoriteScopeID
        defaults.set(scopeID, forKey: Keys.selectedScope)
        defaults.set(scopeID, forKey: Keys.focusedScope)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isLocating = true
            manager.requestLocation()
        case .denied, .restricted:
            isLocating = false
            applyDefaultScope(reason: "No worries. Choose an area from the list to set where you belong.")
        case .notDetermined:
            break
        @unknown default:
            isLocating = false
            applyDefaultScope(reason: nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            applyDefaultScope(reason: nil)
            return
        }

        Task { @MainActor in
            await applyNearestScope(to: location.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        applyDefaultScope(reason: "We couldn’t read your location. Choose an area to set where you belong.")
    }

    @MainActor
    private func applyNearestScope(to coordinate: CLLocationCoordinate2D) async {
        defer { isLocating = false }

        if let remoteScope = await nearestRemoteScope(to: coordinate) {
            saveSelected(scopeID: remoteScope.id)
            locationMessage = "We’ll start with \(remoteScope.name)."
            return
        }

        let scope = LocationScope.nearestKnownScope(to: coordinate) ?? LocationScope.defaultScope(for: LocationScope.defaultID)
        saveSelected(scopeID: scope.id)
        locationMessage = "We’ll start with \(scope.name)."
    }

    private func nearestRemoteScope(to coordinate: CLLocationCoordinate2D) async -> NearestLocationScopeMatch? {
        do {
            return try await nearestLocationResolver
                .nearestLocationScopes(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    maxResults: 1
                )
                .first(where: \.isWithinRadius)
        } catch {
            return nil
        }
    }

    private func saveSelected(scopeID: String) {
        defaults.set(scopeID, forKey: Keys.selectedScope)
        defaults.set(scopeID, forKey: Keys.focusedScope)
        defaults.set(scopeID, forKey: Keys.homeScope)
        defaults.set(scopeID, forKey: Keys.hostsScope)
        if defaults.string(forKey: Keys.favoriteScope) == nil {
            defaults.set(scopeID, forKey: Keys.favoriteScope)
        }
    }

    private func applyDefaultScope(reason: String?) {
        if defaults.string(forKey: Keys.selectedScope) == nil {
            defaults.set(LocationScope.defaultID, forKey: Keys.selectedScope)
            defaults.set(LocationScope.defaultID, forKey: Keys.focusedScope)
        }

        if defaults.string(forKey: Keys.favoriteScope) == nil {
            defaults.set(LocationScope.defaultID, forKey: Keys.favoriteScope)
        }

        locationMessage = reason
    }

    private enum Keys {
        static let selectedScope = "communityCalendar.whatsOn.locationScope"
        static let focusedScope = "communityCalendar.whatsOn.locationFocusScope"
        static let favoriteScope = "communityCalendar.whatsOn.favoriteLocationScope"
        static let homeScope = "communityCalendar.home.locationScope"
        static let hostsScope = "communityCalendar.hosts.locationScope"
        static let hasAskedLocation = "communityCalendar.location.hasAskedForAccess"
    }
}

protocol AppOpenAnalyticsReporting {
    func recordAppOpenAndFetchWeeklyViews(installationID: String) async throws -> Int
    func fetchWeeklyAppOpenViews() async throws -> Int
}

final class AppOpenAnalyticsStore: ObservableObject {
    @Published private(set) var weeklyOpenCount: Int?

    private let service: AppOpenAnalyticsReporting
    private let defaults: UserDefaults
    private var hasRecordedCurrentForegroundSession = false

    init(service: AppOpenAnalyticsReporting = SupabaseEventService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    func appDidEnterBackground() {
        hasRecordedCurrentForegroundSession = false
    }

    @MainActor
    func recordOpenIfNeeded() async {
        guard !hasRecordedCurrentForegroundSession else { return }
        hasRecordedCurrentForegroundSession = true

        let installationID = currentInstallationID()
        recordLocalOpen()

        do {
            weeklyOpenCount = try await service.recordAppOpenAndFetchWeeklyViews(installationID: installationID)
        } catch {
            weeklyOpenCount = localWeeklyOpenCount
        }
    }

    @MainActor
    func refreshWeeklyCount() async {
        do {
            weeklyOpenCount = try await service.fetchWeeklyAppOpenViews()
        } catch {
            weeklyOpenCount = localWeeklyOpenCount
        }
    }

    private func currentInstallationID() -> String {
        if let existing = defaults.string(forKey: Keys.installationID), !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString
        defaults.set(created, forKey: Keys.installationID)
        return created
    }

    private func recordLocalOpen() {
        var values = defaults.array(forKey: Keys.localOpenDates) as? [TimeInterval] ?? []
        values.append(Date().timeIntervalSince1970)
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date().addingTimeInterval(-604_800)
        values = values.filter { Date(timeIntervalSince1970: $0) >= cutoff }
        defaults.set(values, forKey: Keys.localOpenDates)
    }

    private var localWeeklyOpenCount: Int {
        let values = defaults.array(forKey: Keys.localOpenDates) as? [TimeInterval] ?? []
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date().addingTimeInterval(-604_800)
        return values.filter { Date(timeIntervalSince1970: $0) >= cutoff }.count
    }

    private enum Keys {
        static let installationID = "communityCalendar.analytics.installationID"
        static let localOpenDates = "communityCalendar.analytics.localOpenDates"
    }
}

private extension LocationScope {
    struct KnownCoordinate {
        let scopeID: String
        let latitude: CLLocationDegrees
        let longitude: CLLocationDegrees
    }

    static func nearestKnownScope(to coordinate: CLLocationCoordinate2D) -> LocationScope? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearest = knownCoordinates
            .map { item -> (item: KnownCoordinate, distance: CLLocationDistance) in
                let itemLocation = CLLocation(latitude: item.latitude, longitude: item.longitude)
                return (item, location.distance(from: itemLocation))
            }
            .min { $0.distance < $1.distance }

        guard let nearest, nearest.distance <= 45_000 else {
            return defaultScope(for: defaultID)
        }

        return scope(id: nearest.item.scopeID) ?? defaultScope(for: defaultID)
    }

    static let knownCoordinates: [KnownCoordinate] = [
        KnownCoordinate(scopeID: "beachlands", latitude: -36.884, longitude: 175.004),
        KnownCoordinate(scopeID: "maraetai", latitude: -36.879, longitude: 175.035),
        KnownCoordinate(scopeID: "omana", latitude: -36.890, longitude: 175.026),
        KnownCoordinate(scopeID: "whitford", latitude: -36.945, longitude: 174.965),
        KnownCoordinate(scopeID: "clevedon", latitude: -36.990, longitude: 175.037),
        KnownCoordinate(scopeID: "kawakawa-bay", latitude: -36.946, longitude: 175.169),
        KnownCoordinate(scopeID: "orere-point", latitude: -36.967, longitude: 175.253),
        KnownCoordinate(scopeID: "hunua", latitude: -37.079, longitude: 175.067),
        KnownCoordinate(scopeID: "ardmore", latitude: -37.031, longitude: 174.973)
    ]
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
