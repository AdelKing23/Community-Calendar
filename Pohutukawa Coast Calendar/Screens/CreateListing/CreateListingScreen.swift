import SwiftUI

struct CreateListingScreen: View {
    enum Field: Hashable {
        case title
        case venue
        case cost
        case contactName
        case contactEmail
        case description
    }

    @State private var draft = PendingListingDraft()
    @State private var didSubmit = false
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @FocusState private var focusedField: Field?
    private let listingService: EventListingSubmitting = SupabaseEventService()
    let onNavigateHome: () -> Void
    let onNavigateWhatsOn: () -> Void

    init(
        onNavigateHome: @escaping () -> Void = {},
        onNavigateWhatsOn: @escaping () -> Void = {}
    ) {
        self.onNavigateHome = onNavigateHome
        self.onNavigateWhatsOn = onNavigateWhatsOn
    }

    var body: some View {
        ZStack {
            PCCScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    CreateListingHero()

                    if didSubmit {
                        SubmissionReceivedCard(
                            onCreateAnother: resetForAnotherListing,
                            onNavigateHome: onNavigateHome,
                            onNavigateWhatsOn: onNavigateWhatsOn
                        )
                    } else {
                        PendingListingForm(
                            draft: $draft,
                            focusedField: $focusedField,
                            isSubmitting: isSubmitting,
                            submissionError: submissionError
                        ) {
                            focusedField = nil
                            submitListing()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 26)
                .padding(.bottom, PCCKeyboardSpacing.formBottomPadding)
            }
            .pccScrollableKeyboardDismiss()
            .pccBottomKeyboardInset(PCCKeyboardSpacing.formBottomInset)
        }
        .pccDismissesKeyboardOnTap {
            focusedField = nil
        }
        .pccKeyboardDoneToolbar {
            focusedField = nil
        }
    }

    private func resetForAnotherListing() {
        focusedField = nil
        submissionError = nil
        isSubmitting = false
        draft = PendingListingDraft()
        didSubmit = false
    }

    private func submitListing() {
        guard draft.canSubmit, !isSubmitting else { return }

        Task {
            await MainActor.run {
                isSubmitting = true
                submissionError = nil
            }

            do {
                try await listingService.submitPendingListing(draft)
                await MainActor.run {
                    didSubmit = true
                    isSubmitting = false
                    draft = PendingListingDraft()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionError = "The listing could not be sent. Please check your connection and try again."
                }
            }
        }
    }
}

struct CreateListingHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Submit an Event")
                .font(.system(size: 38, weight: .black, design: .serif))
                .foregroundStyle(PCCTheme.ink)

            Text("Send a coastal listing for review. Approved events appear in the public calendar.")
                .font(.title3.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .pccCardStyle()
    }
}

struct PendingListingForm: View {
    @Binding var draft: PendingListingDraft
    @FocusState.Binding var focusedField: CreateListingScreen.Field?
    let isSubmitting: Bool
    let submissionError: String?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Listing Details")
                .font(.title3.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            PCCFormField(title: "Event Name", text: $draft.title, prompt: "Coastal concert, market, class")
                .focused($focusedField, equals: .title)
            PCCFormField(title: "Venue", text: $draft.venue, prompt: "Hall, beach, club, cafe")
                .focused($focusedField, equals: .venue)

            Picker("Town", selection: $draft.town) {
                ForEach(CoastTown.allCases.filter { $0 != .all }) { town in
                    Text(town.rawValue).tag(town)
                }
            }
            .pickerStyle(.segmented)

            Picker("Category", selection: $draft.category) {
                ForEach(EventCategory.allCases) { category in
                    Text(category.shortLabel).tag(category)
                }
            }

            DatePicker("Date", selection: $draft.date, displayedComponents: .date)
            DatePicker("Time", selection: $draft.time, displayedComponents: .hourAndMinute)

            PCCFormField(title: "Cost", text: $draft.priceLabel, prompt: "Free, koha, $20")
                .focused($focusedField, equals: .cost)
            PCCFormField(title: "Contact Name", text: $draft.contactName, prompt: "Organiser or venue")
                .focused($focusedField, equals: .contactName)
            PCCFormField(title: "Contact Email", text: $draft.contactEmail, prompt: "name@example.co.nz")
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .contactEmail)

            VStack(alignment: .leading, spacing: 8) {
                Text("Short Description")
                    .font(.caption.weight(.black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.54))

                TextEditor(text: $draft.shortDescription)
                    .frame(minHeight: 112)
                    .focused($focusedField, equals: .description)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }

            ListingReviewNote()

            if let submissionError {
                Label(submissionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PCCTheme.pohutukawaRed)
            }

            Button(action: onSubmit) {
                Label(isSubmitting ? "Sending Listing" : "Submit for Review", systemImage: isSubmitting ? "hourglass" : "paperplane.fill")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(draft.canSubmit && !isSubmitting ? PCCTheme.leafGreen : PCCTheme.ink.opacity(0.28), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .disabled(!draft.canSubmit || isSubmitting)
        }
        .font(.body.weight(.medium))
        .foregroundStyle(PCCTheme.ink)
        .padding(20)
        .pccCardStyle()
    }
}

struct ListingReviewNote: View {
    var body: some View {
        Label("Listings are reviewed before they appear publicly.", systemImage: "checkmark.seal")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(PCCTheme.ink.opacity(0.64))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PCCTheme.leafGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct PCCFormField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.54))

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .padding(13)
                .background(PCCTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
        }
    }
}

struct SubmissionReceivedCard: View {
    let onCreateAnother: () -> Void
    let onNavigateHome: () -> Void
    let onNavigateWhatsOn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(PCCTheme.leafGreen)

            Text("Listing Sent for Review")
                .font(.title2.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text("Thanks. The event will stay pending until it has been checked and approved for the public feed.")
                .font(.body.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.68))
                .lineSpacing(3)

            VStack(spacing: 10) {
                Button(action: onCreateAnother) {
                    Label("Create Another Listing", systemImage: "plus.circle.fill")
                        .font(.headline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(PCCTheme.leafGreen, in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))

                HStack(spacing: 10) {
                    Button(action: onNavigateHome) {
                        Label("Back to Home", systemImage: "house.fill")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }

                    Button(action: onNavigateWhatsOn) {
                        Label("What's On", systemImage: "calendar")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(PCCTheme.leafGreen)
                .background(PCCTheme.leafGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .pccCardStyle()
    }
}
