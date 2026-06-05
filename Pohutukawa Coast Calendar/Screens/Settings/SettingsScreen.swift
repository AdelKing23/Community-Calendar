import SwiftUI

struct SettingsScreen: View {
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
                            rows: [
                                SettingsRowContent(
                                    id: "join-community",
                                    icon: "person.crop.circle.badge.plus",
                                    title: "Join the community",
                                    subtitle: "Create an account to manage your listings and see feedback insights from your posts.",
                                    detail: "Create account / Sign in",
                                    style: .disclosure,
                                    isEnabled: false
                                )
                            ]
                        )

                        SettingsListSection(
                            title: "My Listings",
                            rows: [
                                SettingsRowContent(
                                    id: "previous-listings",
                                    icon: "rectangle.stack",
                                    title: "Previous listings",
                                    subtitle: "View your submitted posts, status, and insights.",
                                    detail: "Coming soon",
                                    style: .status,
                                    isEnabled: false
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
                                    subtitle: "Save payment securely with the payment provider for quicker paid listings.",
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
                                    subtitle: nil,
                                    detail: nil,
                                    style: .disclosure,
                                    isEnabled: false
                                ),
                                SettingsRowContent(
                                    id: "privacy",
                                    icon: "hand.raised",
                                    title: "Privacy policy",
                                    subtitle: nil,
                                    detail: nil,
                                    style: .disclosure,
                                    isEnabled: false
                                ),
                                SettingsRowContent(
                                    id: "posting-rules",
                                    icon: "checkmark.seal",
                                    title: "Community posting rules",
                                    subtitle: nil,
                                    detail: nil,
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
                                    subtitle: "Public contact details can be added before launch.",
                                    detail: nil,
                                    style: .disclosure,
                                    isEnabled: false
                                )
                            ]
                        )

                        NavigationLink {
                            SupportAdminScreen()
                        } label: {
                            OwnerSupportRow()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 30)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationBarHidden(true)
        }
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

struct OwnerSupportRow: View {
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

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.30))
        }
        .padding(14)
        .background(.white.opacity(0.50), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        )
    }
}
