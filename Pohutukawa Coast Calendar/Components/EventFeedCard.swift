import SwiftUI

struct EventFeedCard: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                ListingRemoteImageView(
                    image: event.primaryImage,
                    context: "feed event=\(String(event.id.uuidString.prefix(8)))",
                    contentMode: .fill
                ) {
                    EventImagePlaceholderView()
                }
                .frame(height: 126)
                .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                DateTile(event: event)
                    .scaleEffect(0.82, anchor: .topLeading)
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    if event.isPoll {
                        PollBadge()
                    }

                    Text(event.category.shortLabel)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PCCTheme.pohutukawaOrange, in: Capsule())

                    if event.isPromoted {
                        Text(event.promotionBadgeTitle)
                            .font(.caption.weight(.black))
                            .foregroundStyle(PCCTheme.leafGreen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(PCCTheme.leafGreen.opacity(0.10), in: Capsule())
                    }

                    if event.isFree {
                        Text("Free")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(PCCTheme.leafGreen, in: Capsule())
                    }

                    Spacer()
                }

                Text(event.title)
                    .font(.system(size: 21, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)
                    .lineLimit(2)

                Text(event.shortDescription)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.67))
                    .lineLimit(2)
                    .lineSpacing(2)

                VStack(alignment: .leading, spacing: 6) {
                    Label(event.timeText, systemImage: "clock")
                    Label("\(event.venue), \(event.displayLocationName)", systemImage: "mappin.and.ellipse")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(PCCTheme.ink.opacity(0.58))

                if let pollDetails = event.pollDetails {
                    PollInlineResponseView(event: event, pollDetails: pollDetails)
                        .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .pccCardStyle()
    }
}

struct PollFeedCard: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PollCardHeader(event: event, compact: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.system(size: 22, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)
                    .lineLimit(2)

                if !event.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(event.shortDescription)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PCCTheme.ink.opacity(0.67))
                        .lineLimit(3)
                        .lineSpacing(2)
                }
            }

            PollHeroImage(event: event, height: 118)

            PollCardMeta(event: event)

            if let pollDetails = event.pollDetails {
                PollInlineResponseView(event: event, pollDetails: pollDetails)
            } else {
                PollUnavailablePanel()
            }

            PollActionRow(event: event)
        }
        .padding(14)
        .background(PCCTheme.cream.opacity(0.76), in: RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous)
                .stroke(PCCTheme.leafGreen.opacity(0.18), lineWidth: 1)
        )
    }
}

struct PollPostCard: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            PollCardHeader(event: event, compact: false)
            PollHeroImage(event: event, height: 150)

            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.system(size: 27, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)
                    .lineLimit(2)

                Text(event.shortDescription)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PCCTheme.ink.opacity(0.68))
                    .lineLimit(3)
                    .lineSpacing(3)
            }

            PollCardMeta(event: event)

            if let pollDetails = event.pollDetails {
                PollInlineResponseView(event: event, pollDetails: pollDetails)
            } else {
                PollUnavailablePanel()
            }

            PollActionRow(event: event)
        }
        .padding(16)
        .pccCardStyle()
    }
}

private struct PollCardHeader: View {
    let event: LocalEvent
    let compact: Bool

    var body: some View {
        HStack(spacing: 9) {
            PollBadge()

            Text(event.category.shortLabel)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PCCTheme.pohutukawaOrange, in: Capsule())

            Text(event.displayLocationName)
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.leafGreen)
                .lineLimit(1)

            Spacer(minLength: 0)

            if !compact {
                Text("Feedback")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.56))
            }
        }
    }
}

private struct PollHeroImage: View {
    let event: LocalEvent
    let height: CGFloat

    var body: some View {
        ListingRemoteImageView(
            image: event.primaryImage,
            context: "poll event=\(String(event.id.uuidString.prefix(8)))",
            contentMode: .fill
        ) {
            PollImagePlaceholderView()
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

private struct PollCardMeta: View {
    let event: LocalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Poll closes \(event.dateText)", systemImage: "calendar.badge.clock")
            Label("Asked by \(event.organiserDisplayName)", systemImage: "person.crop.circle")
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(PCCTheme.ink.opacity(0.58))
    }
}

private struct PollActionRow: View {
    let event: LocalEvent
    @EnvironmentObject private var engagementStore: EventEngagementStore

    var body: some View {
        HStack(spacing: 7) {
            NavigationLink {
                EventDetailScreen(event: event)
            } label: {
                Label("Open Poll", systemImage: "arrow.up.right.circle")
                    .pollActionStyle(isSelected: false)
            }
            .buttonStyle(.plain)

            Button {
                engagementStore.toggleSaved(event)
            } label: {
                Label("Save", systemImage: engagementStore.isSaved(event) ? "bookmark.fill" : "bookmark")
                    .pollActionStyle(isSelected: engagementStore.isSaved(event))
            }
            .buttonStyle(.plain)

            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .pollActionStyle(isSelected: false)
            }
        }
    }

    private var shareText: String {
        """
        Poll: \(event.title)
        \(event.displayLocationName)

        Shared from Pohutukawa Coast Calendar.
        """
    }
}

private extension Label where Title == Text, Icon == Image {
    func pollActionStyle(isSelected: Bool) -> some View {
        font(.system(size: 11, weight: .black))
            .foregroundStyle(isSelected ? PCCTheme.leafGreen : PCCTheme.ink.opacity(0.66))
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(
                isSelected ? PCCTheme.leafGreen.opacity(0.12) : PCCTheme.cream.opacity(0.66),
                in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
            )
    }
}

struct PollUnavailablePanel: View {
    var body: some View {
        Label("Poll answers will appear when this poll has finished processing.", systemImage: "hourglass")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(PCCTheme.ink.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(PCCTheme.leafGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct PollInlineResponseView: View {
    static let customOptionLabel = "Other"

    let event: LocalEvent
    let pollDetails: PollDetails
    private let service: PollResponding
    private let analyticsService: EventAnalyticsRecording

    @EnvironmentObject private var userSessionStore: UserSessionStore
    @State private var results: PollResults = .empty
    @State private var selectedOption: String?
    @State private var customAnswer = ""
    @State private var isShowingCustomAnswer = false
    @State private var isSubmitting = false
    @State private var statusMessage: String?

    init(
        event: LocalEvent,
        pollDetails: PollDetails,
        service: PollResponding = SupabaseEventService(),
        analyticsService: EventAnalyticsRecording = SupabaseEventService()
    ) {
        self.event = event
        self.pollDetails = pollDetails
        self.service = service
        self.analyticsService = analyticsService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pollDetails.question)
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(pollDetails.options, id: \.self) { option in
                    PollOptionButton(
                        title: option,
                        count: results.count(for: option),
                        total: results.totalResponses,
                        isSelected: selectedOption == option,
                        isSubmitting: isSubmitting
                    ) {
                        submit(selectedOption: option, customAnswer: nil)
                    }
                }

                if pollDetails.allowsCustomAnswer {
                    PollOptionButton(
                        title: Self.customOptionLabel,
                        subtitle: "Type your own answer",
                        count: results.count(for: Self.customOptionLabel),
                        total: results.totalResponses,
                        isSelected: selectedOption == Self.customOptionLabel,
                        isSubmitting: isSubmitting
                    ) {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                            isShowingCustomAnswer.toggle()
                        }
                    }

                    if isShowingCustomAnswer {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Your answer", text: $customAnswer, axis: .vertical)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2...4)
                                .padding(12)
                                .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                                .onChange(of: customAnswer) { _, newValue in
                                    if newValue.count > PollDetails.customAnswerLimit {
                                        let limitedAnswer = newValue.prefix(PollDetails.customAnswerLimit)
                                        customAnswer = String(limitedAnswer)
                                    }
                                }

                            HStack {
                                Text("\(customAnswer.count)/\(PollDetails.customAnswerLimit)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PCCTheme.ink.opacity(0.52))

                                Spacer()

                                Button {
                                    submit(selectedOption: nil, customAnswer: customAnswer)
                                } label: {
                                    Label("Send", systemImage: "paperplane.fill")
                                        .font(.caption.weight(.black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(PCCTheme.leafGreen, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(trimmed(customAnswer).isEmpty || isSubmitting)
                                .opacity(trimmed(customAnswer).isEmpty || isSubmitting ? 0.45 : 1)
                            }
                        }
                        .padding(10)
                        .background(PCCTheme.cream.opacity(0.54), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                    }
                }
            }

            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(PCCTheme.leafGreen)
                }

                Text(statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(PCCTheme.leafGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                .stroke(PCCTheme.leafGreen.opacity(0.12), lineWidth: 1)
        )
        .task(id: event.id) {
            await loadPollState()
        }
    }

    private var statusText: String {
        if let statusMessage { return statusMessage }
        if let selectedOption {
            return "Your answer: \(selectedOption)."
        }
        if results.totalResponses == 0 { return "Be the first to answer." }
        return "\(results.totalResponses) response\(results.totalResponses == 1 ? "" : "s") so far."
    }

    private var statusColor: Color {
        if statusMessage?.localizedCaseInsensitiveContains("could not") == true {
            return .red
        }
        return PCCTheme.ink.opacity(0.58)
    }

    private func submit(selectedOption: String?, customAnswer: String?) {
        Task {
            await userSessionStore.refreshIfNeeded()
            guard let session = userSessionStore.session else {
                statusMessage = "Sign in to answer this poll."
                return
            }

            let trimmedOption = selectedOption.flatMap { nonEmpty(trimmed($0)) }
            let trimmedCustom = customAnswer.flatMap { nonEmpty(trimmed($0)) }
            guard trimmedOption != nil || trimmedCustom != nil else {
                return
            }

            isSubmitting = true
            statusMessage = nil

            do {
                try await service.submitPollResponse(
                    eventID: event.id,
                    selectedOption: trimmedOption,
                    customAnswer: trimmedCustom,
                    accessToken: session.accessToken
                )
                self.selectedOption = selectedOption ?? Self.customOptionLabel
                self.customAnswer = trimmedCustom ?? ""
                self.isShowingCustomAnswer = trimmedCustom != nil
                self.statusMessage = "Answer saved."
                try? await analyticsService.recordEventAnalytics(
                    eventID: event.id,
                    eventType: "poll_answer",
                    source: "poll_card",
                    locationScopeID: nil,
                    accessToken: session.accessToken
                )
                await loadPollState()
            } catch {
                self.statusMessage = "Your answer could not be saved. Please try again."
            }

            isSubmitting = false
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    @MainActor
    private func loadPollState() async {
        await loadCounts()
        await userSessionStore.refreshIfNeeded()

        guard let session = userSessionStore.session else {
            return
        }

        do {
            guard let response = try await service.fetchMyPollResponse(
                eventID: event.id,
                userID: session.userID,
                accessToken: session.accessToken
            ) else {
                return
            }

            selectedOption = response.displayAnswer
            if response.isCustomAnswer {
                customAnswer = response.customAnswer ?? ""
                isShowingCustomAnswer = true
            }
        } catch {
            return
        }
    }

    @MainActor
    private func loadCounts() async {
        do {
            results = try await service.fetchPollResponseCounts(eventID: event.id)
        } catch {
            results = .empty
        }
    }
}

private struct PollOptionButton: View {
    let title: String
    var subtitle: String?
    let count: Int
    let total: Int
    let isSelected: Bool
    let isSubmitting: Bool
    let action: () -> Void

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.headline.weight(.black))
                        .foregroundStyle(isSelected ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(PCCTheme.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let subtitle {
                            Text(subtitle)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PCCTheme.ink.opacity(0.54))
                        }
                    }

                    Spacer(minLength: 8)

                    Text("\(count)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.82), in: Capsule())
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(PCCTheme.ink.opacity(0.08))

                        Capsule()
                            .fill(PCCTheme.pohutukawaOrange.opacity(0.72))
                            .frame(width: max(0, proxy.size.width * percentage))
                    }
                }
                .frame(height: 5)
                .opacity(total > 0 ? 1 : 0)
            }
            .padding(11)
            .background(.white.opacity(isSelected ? 0.86 : 0.68), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                    .stroke(isSelected ? PCCTheme.pohutukawaOrange.opacity(0.48) : .white.opacity(0.32), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }
}

struct PollBadge: View {
    var body: some View {
        Label("Poll", systemImage: "chart.bar.doc.horizontal")
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(PCCTheme.leafGreen, in: Capsule())
    }
}

struct DateTile: View {
    let event: LocalEvent

    var body: some View {
        VStack(spacing: 3) {
            Text(event.monthShort)
                .font(.caption2.weight(.black))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text(event.dayNumber)
                .font(.system(size: 29, weight: .heavy, design: .rounded))
                .foregroundStyle(PCCTheme.ink)

            Text(event.weekdayShort)
                .font(.caption2.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.58))
        }
        .frame(width: 62)
        .padding(.vertical, 11)
        .background(PCCTheme.cream.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PCCTheme.leafGreen.opacity(0.08), lineWidth: 1)
        )
    }
}
