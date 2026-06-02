import SwiftUI

struct EngagementActionRow: View {
    let event: LocalEvent
    @State private var interested = false
    @State private var going = false
    @State private var saved = false

    var body: some View {
        HStack(spacing: 6) {
            EngagementButton(title: "Interested", icon: "star", isSelected: interested) {
                interested.toggle()
            }

            EngagementButton(title: "Going", icon: "checkmark.circle", isSelected: going) {
                going.toggle()
            }

            EngagementButton(title: "Save", icon: "bookmark", isSelected: saved) {
                saved.toggle()
            }

            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.66))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(PCCTheme.cream.opacity(0.66), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
        }
    }

    private var shareText: String {
        "\(event.title)\n\(event.dateText)\n\(event.venue), \(event.town.rawValue)"
    }
}

struct EngagementButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "\(icon).fill" : icon)
                .font(.caption.weight(.black))
                .foregroundStyle(isSelected ? PCCTheme.leafGreen : PCCTheme.ink.opacity(0.66))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isSelected ? PCCTheme.leafGreen.opacity(0.12) : PCCTheme.cream.opacity(0.66),
                    in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}
