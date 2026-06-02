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

                        NavigationLink {
                            SupportAdminScreen()
                        } label: {
                            SettingsActionSection(
                                icon: "lock.shield",
                                title: "Launch Support Tools",
                                message: "Owner-only launch tools. This is not a public account login or Supabase Auth yet."
                            )
                        }
                        .buttonStyle(.plain)

                        SettingsInfoSection(
                            title: "Contact Pōhutukawa Coast Calendar",
                            message: "Use the Create tab to submit a listing. For support, use the contact option once live details are added. Public contact details can be added before launch."
                        )

                        SettingsInfoSection(
                            title: "Submit an Event",
                            message: "Use the Create tab to send event details for review. Approved listings appear in the public calendar."
                        )

                        SettingsInfoSection(
                            title: "Areas Covered",
                            message: "Whitford, Beachlands, Maraetai and Clevedon."
                        )

                        SettingsInfoSection(
                            title: "Listing Rules",
                            message: "Listings should be local, public-facing and useful. Submitted listings are reviewed before publishing."
                        )

                        SettingsInfoSection(
                            title: "Privacy Summary",
                            message: "No account is required to browse. Submitted contact details are used for review and organiser contact."
                        )

                        SettingsInfoSection(
                            title: "Business & Featured Listings",
                            message: "Community and non-profit listings are free. Commercial standard listing $15, featured listing $35, homepage or weekend feature $75, business monthly plan $49/month, founding sponsor packages $250-$1,500. Pricing may be confirmed before launch."
                        )

                        SettingsInfoSection(
                            title: "MVP Review",
                            message: "Public listings are reviewed before appearing. Submitted listings can be checked in Supabase/admin during MVP. Full owner approval tools are coming next."
                        )

                        SettingsInfoSection(
                            title: "App Information",
                            message: "Version 1.0"
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 30)
                    .padding(.bottom, 124)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct SettingsInfoSection: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .pccCardStyle()
    }
}

struct SettingsActionSection: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text(message)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.68))
                    .lineSpacing(3)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.36))
        }
        .padding(20)
        .pccCardStyle()
    }
}
