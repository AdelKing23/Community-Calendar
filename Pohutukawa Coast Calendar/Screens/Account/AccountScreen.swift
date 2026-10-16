import SwiftUI

struct AccountScreen: View {
    var body: some View {
        ZStack {
            PCCScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Account")
                        .font(.system(size: 40, weight: .black, design: .serif))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Public browsing works without an account.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.68))

                    AccountInfoCard(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "No Sign-In Needed",
                        message: "Anyone can browse published local events without creating a profile or joining a membership."
                    )

                    AccountInfoCard(
                        icon: "doc.text.magnifyingglass",
                        title: "Manual Review",
                        message: "Submitted listings are checked before they appear, so the public calendar stays useful, local and trusted."
                    )

                    AccountInfoCard(
                        icon: "building.2",
                        title: "Organiser Accounts",
                        message: "Regular organisers, venues and businesses may get account tools later. There is no login to use today."
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Submit a Listing")
                            .font(.title3.weight(.black))
                            .foregroundStyle(PCCTheme.ink)

                        Text("Use the Create tab to send event details for review. Include the venue, time, cost, contact details and a short public description.")
                            .foregroundStyle(PCCTheme.ink.opacity(0.68))
                    }
                    .font(.body.weight(.medium))
                    .padding(20)
                    .pccCardStyle()
                }
                .padding(.horizontal, 16)
                .padding(.top, 30)
                .padding(.bottom, 124)
            }
        }
    }
}

struct AccountInfoCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text(message)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.68))
                    .lineSpacing(3)
            }
        }
        .padding(18)
        .pccCardStyle()
    }
}
