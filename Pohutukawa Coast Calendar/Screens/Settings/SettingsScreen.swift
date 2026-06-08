import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @EnvironmentObject private var ownerSessionStore: OwnerSessionStore

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Settings")
                            .font(.system(size: 40, weight: .black, design: .serif))
                            .foregroundStyle(PCCTheme.ink)

                        SettingsListSection(
                            title: "Account",
                            rows: accountRows
                        )

                        if userSessionStore.isSignedIn {
                            Button {
                                userSessionStore.signOut()
                            } label: {
                                SettingsSignOutRow()
                            }
                            .buttonStyle(.plain)
                        }

                        SettingsListSection(
                            title: "My Listings",
                            rows: [
                                SettingsRowContent(
                                    id: "previous-listings",
                                    icon: "rectangle.stack",
                                    title: "Previous listings",
                                    subtitle: "View submitted posts and review status from the Create tab.",
                                    detail: "Create tab",
                                    style: .status,
                                    isEnabled: true
                                )
                            ]
                        )

                        SettingsListSection(
                            title: "Payment",
                            rows: [
                                SettingsRowContent(
                                    id: "faster-checkout",
                                    icon: "creditcard",
                                    title: "Faster checkout",
                                    subtitle: "Paid listing checkout will be handled securely by the payment provider.",
                                    detail: "Coming soon",
                                    style: .status,
                                    isEnabled: false
                                )
                            ],
                            footer: "Payment details are handled securely by the payment provider, not stored in this app."
                        )

                        SettingsListSection(
                            title: "Appearance",
                            rows: [
                                SettingsRowContent(
                                    id: "theme",
                                    icon: "circle.lefthalf.filled",
                                    title: "Theme",
                                    subtitle: "System default for now.",
                                    detail: nil,
                                    style: .toggle(isOn: true),
                                    isEnabled: false
                                )
                            ]
                        )

                        SettingsListSection(
                            title: "Documents",
                            rows: [
                                SettingsRowContent(
                                    id: "terms",
                                    icon: "doc.text",
                                    title: "Terms and conditions",
                                    subtitle: "Clear listing and app terms before launch.",
                                    detail: "Coming soon",
                                    style: .disclosure,
                                    isEnabled: false
                                ),
                                SettingsRowContent(
                                    id: "privacy",
                                    icon: "hand.raised",
                                    title: "Privacy policy",
                                    subtitle: "How account and listing details are used.",
                                    detail: "Coming soon",
                                    style: .disclosure,
                                    isEnabled: false
                                ),
                                SettingsRowContent(
                                    id: "posting-rules",
                                    icon: "checkmark.seal",
                                    title: "Community posting rules",
                                    subtitle: "What can be listed and what needs review.",
                                    detail: "Coming soon",
                                    style: .disclosure,
                                    isEnabled: false
                                )
                            ]
                        )

                        SettingsListSection(
                            title: "Area",
                            rows: [
                                SettingsRowContent(
                                    id: "current-area",
                                    icon: "mappin.and.ellipse",
                                    title: "Current area",
                                    subtitle: CommunityArea.defaultAreaName,
                                    detail: nil,
                                    style: .plain,
                                    isEnabled: true
                                )
                            ],
                            footer: "More communities coming soon."
                        )

                        SettingsListSection(
                            title: "Help",
                            rows: [
                                SettingsRowContent(
                                    id: "contact",
                                    icon: "envelope",
                                    title: "Contact \(CommunityArea.appBrandName)",
                                    subtitle: "Use Create to submit a listing. Support contact details will be added before launch.",
                                    detail: "Soon",
                                    style: .disclosure,
                                    isEnabled: false
                                )
                            ]
                        )

                        NavigationLink {
                            SupportAdminScreen()
                        } label: {
                            OwnerSupportRow(isSignedIn: ownerSessionStore.isSignedIn)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var accountRows: [SettingsRowContent] {
        if userSessionStore.isSignedIn {
            return [
                SettingsRowContent(
                    id: "account-details",
                    icon: "person.crop.circle.fill",
                    title: "Account details",
                    subtitle: userSessionStore.email ?? "Signed-in account",
                    detail: "Active",
                    style: .status,
                    isEnabled: true
                )
            ]
        }

        return [
            SettingsRowContent(
                id: "join-community",
                icon: "person.crop.circle.badge.plus",
                title: "Create account / Sign in",
                subtitle: "Create a free account when you are ready to submit and manage listings.",
                detail: "Create tab",
                style: .disclosure,
                isEnabled: true
            )
        ]
    }
}

struct SettingsListSection: View {
    let title: String
    let rows: [SettingsRowContent]
    var footer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.58))
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    SettingsRow(content: row)

                    if row.id != rows.last?.id {
                        Divider()
                            .overlay(PCCTheme.ink.opacity(0.08))
                            .padding(.leading, 48)
                    }
                }
            }
            .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                    .stroke(.white.opacity(0.82), lineWidth: 1)
            )

            if let footer {
                Text(footer)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.56))
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }
}

struct SettingsRowContent: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let detail: String?
    let style: SettingsRowStyle
    let isEnabled: Bool
}

enum SettingsRowStyle: Equatable {
    case plain
    case disclosure
    case status
    case toggle(isOn: Bool)
}

struct SettingsRow: View {
    let content: SettingsRowContent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: content.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(content.isEnabled ? PCCTheme.pohutukawaOrange : PCCTheme.ink.opacity(0.34))
                .frame(width: 34, height: 34)
                .background(PCCTheme.cream.opacity(0.70), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(content.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.ink)

                if let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)

            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .opacity(content.isEnabled ? 1 : 0.72)
    }

    @ViewBuilder
    private var accessory: some View {
        switch content.style {
        case .plain:
            EmptyView()
        case .disclosure:
            HStack(spacing: 7) {
                if let detail = content.detail {
                    Text(detail)
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.34))
            }
        case .status:
            if let detail = content.detail {
                Text(detail)
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(PCCTheme.cream.opacity(0.86), in: Capsule())
            }
        case .toggle(let isOn):
            Toggle("", isOn: .constant(isOn))
                .labelsHidden()
                .disabled(true)
        }
    }
}

struct SettingsSignOutRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PCCTheme.pohutukawaRed)
                .frame(width: 30, height: 30)
                .background(PCCTheme.pohutukawaRed.opacity(0.08), in: Circle())

            Text("Sign Out")
                .font(.subheadline.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaRed)

            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        )
    }
}

struct OwnerSupportRow: View {
    let isSignedIn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PCCTheme.ink.opacity(0.48))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.64), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Owner Support")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.72))

                Text("For authorised listing reviewers only.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.52))
            }

            Spacer()

            if isSignedIn {
                Text("Signed in")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.leafGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.30))
            }
        }
        .padding(14)
        .background(.white.opacity(0.50), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        )
    }
}
