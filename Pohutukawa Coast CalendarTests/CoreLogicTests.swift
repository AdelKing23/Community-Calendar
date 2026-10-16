import XCTest
@testable import Pohutukawa_Coast_Calendar

final class CoreLogicTests: XCTestCase {
    func testMembershipContactEmailValidationUsesStandardApplicationBehaviour() {
        XCTAssertTrue(MembershipContactEmailValidator.isUsable("aylah@test.com"))
        XCTAssertTrue(MembershipContactEmailValidator.isUsable(" isaacwellis@hotmail.com "))
        XCTAssertEqual(MembershipContactEmailValidator.normalized(" isaacwellis@hotmail.com "), "isaacwellis@hotmail.com")

        XCTAssertFalse(MembershipContactEmailValidator.isUsable("aylah"))
        XCTAssertFalse(MembershipContactEmailValidator.isUsable("aylah@"))
        XCTAssertFalse(MembershipContactEmailValidator.isUsable("@test.com"))
        XCTAssertFalse(MembershipContactEmailValidator.isUsable("aylah@test"))
        XCTAssertFalse(MembershipContactEmailValidator.isUsable("ay lah@test.com"))
        XCTAssertFalse(MembershipContactEmailValidator.isUsable("aylah@test..com"))
    }

    func testMembershipOrganisationTypeIsSelectionOnlyAndRequired() {
        XCTAssertEqual(BusinessOrganisationType.allCases.map(\.title), [
            "Business",
            "School/ECE",
            "Sports club",
            "Community group",
            "Charity/non-profit",
            "Marae/cultural organisation",
            "Church/faith community",
            "Market",
            "Hospitality/venue",
            "Instructor/activity provider",
            "Council/public service",
            "Other organisation"
        ])

        var draft = BusinessProfileDraft()
        draft.name = "Maraetai Sports"
        draft.email = "club@example.test"
        XCTAssertFalse(draft.hasMinimumRequiredFields)

        draft.organisationType = .sportsClub
        XCTAssertTrue(draft.hasMinimumRequiredFields)
    }

    func testMembershipApplicationTraceAcceptsRealDeviceEmailExamples() {
        for email in ["aylah@test.com", "isaacwellis@hotmail.com"] {
            var draft = BusinessProfileDraft()
            draft.name = "Aylah Test Membership"
            draft.organisationType = .communityGroup
            draft.email = " \(email) "

            let trace = MembershipApplicationValidationTrace.evaluate(
                accountEmail: " \(email) ",
                draft: draft,
                websiteAccepted: true
            )

            XCTAssertTrue(trace.accountEmailAccepted == true, email)
            XCTAssertTrue(trace.contactEmailAccepted, email)
            XCTAssertTrue(trace.formIsValid, email)
            XCTAssertEqual(trace.payloadContactEmail, email)
            XCTAssertEqual(trace.payloadOrganisationType, BusinessOrganisationType.communityGroup.rawValue)
            XCTAssertFalse(trace.blockingFields.contains("accountEmail"), email)
            XCTAssertFalse(trace.blockingFields.contains("contactEmail"), email)
        }
    }

    func testBusinessProfileSaveRPCPayloadMatchesPostgresSignature() throws {
        var draft = BusinessProfileDraft()
        draft.name = "Aylah Test Membership"
        draft.organisationType = .communityGroup
        draft.email = " aylah@test.com "
        draft.contactName = "Aylah"
        draft.areaScopeID = "maraetai"
        draft.selectedPlan = .localBusiness

        let data = try JSONEncoder().encode(BusinessProfileSaveRequest(draft: draft))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expectedKeys: Set<String> = [
            "p_about",
            "p_address",
            "p_area_scope_id",
            "p_avatar_image_position_x",
            "p_avatar_image_position_y",
            "p_avatar_image_url",
            "p_business_name",
            "p_contact_email",
            "p_contact_name",
            "p_hero_image_position_x",
            "p_hero_image_position_y",
            "p_hero_image_url",
            "p_organisation_type",
            "p_phone",
            "p_selected_plan_id",
            "p_website"
        ]

        XCTAssertEqual(Set(payload.keys), expectedKeys)
        XCTAssertEqual(payload["p_contact_email"] as? String, "aylah@test.com")
        XCTAssertEqual(payload["p_organisation_type"] as? String, BusinessOrganisationType.communityGroup.rawValue)
        XCTAssertTrue(payload["p_website"] is NSNull)
        XCTAssertTrue(payload["p_hero_image_url"] is NSNull)
        XCTAssertTrue(payload["p_avatar_image_url"] is NSNull)
    }

    func testEventReportSubmitPayloadMatchesPostgresSignature() throws {
        let eventID = try XCTUnwrap(UUID(uuidString: "48000000-0000-0000-0000-000000000201"))
        let data = try JSONEncoder().encode(
            EventReportSubmitRequest(
                eventID: eventID,
                category: .spamOrScam,
                details: " Looks suspicious "
            )
        )
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expectedKeys: Set<String> = [
            "p_event_id",
            "p_category",
            "p_details"
        ]

        XCTAssertEqual(Set(payload.keys), expectedKeys)
        XCTAssertEqual(payload["p_event_id"] as? String, eventID.uuidString)
        XCTAssertEqual(payload["p_category"] as? String, EventReportCategory.spamOrScam.rawValue)
        XCTAssertEqual(payload["p_details"] as? String, " Looks suspicious ")
    }

    func testSupportListingModerationPayloadMatchesPostgresSignature() throws {
        let eventID = try XCTUnwrap(UUID(uuidString: "49000000-0000-0000-0000-000000000201"))
        let data = try JSONEncoder().encode(
            SupportListingModerationRequest(
                eventID: eventID,
                targetStatus: .published,
                reason: nil
            )
        )
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expectedKeys: Set<String> = [
            "p_event_id",
            "p_target_status",
            "p_reason"
        ]

        XCTAssertEqual(Set(payload.keys), expectedKeys)
        XCTAssertEqual(payload["p_event_id"] as? String, eventID.uuidString)
        XCTAssertEqual(payload["p_target_status"] as? String, ListingStatus.published.rawValue)
        XCTAssertTrue(payload["p_reason"] is NSNull)
    }

    func testSupportApplyEventChangeRequestPayloadMatchesPostgresSignature() throws {
        let changeRequestID = try XCTUnwrap(UUID(uuidString: "4f000000-0000-0000-0000-000000000601"))
        let data = try JSONEncoder().encode(
            SupportApplyEventChangeRequest(
                changeRequestID: changeRequestID,
                reviewReason: .approvedApplied,
                supportNote: nil
            )
        )
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expectedKeys: Set<String> = [
            "p_change_request_id",
            "p_review_reason",
            "p_support_note"
        ]

        XCTAssertEqual(Set(payload.keys), expectedKeys)
        XCTAssertEqual(payload["p_change_request_id"] as? String, changeRequestID.uuidString)
        XCTAssertEqual(payload["p_review_reason"] as? String, EventReviewReason.approvedApplied.rawValue)
        XCTAssertTrue(payload["p_support_note"] is NSNull)
    }

    func testMemberPublicProfileImageSavePayloadMatchesPostgresSignature() throws {
        var draft = PublicMemberProfileDraft()
        draft.displayName = "Aylah Public Page"
        draft.areaScopeID = "maraetai"
        draft.bio = "A public bio"
        draft.publicContactEmail = " aylah@test.com "
        draft.avatarImagePath = "41000000-0000-0000-0000-000000000001/avatar.jpg"
        draft.heroImagePath = nil
        draft.avatarImagePositionX = 42
        draft.avatarImagePositionY = 58
        draft.heroImagePositionX = 35
        draft.heroImagePositionY = 65

        let profileID = UUID(uuidString: "41000000-0000-0000-0000-000000000001")!
        let data = try JSONEncoder().encode(SaveMemberPublicProfileRequest(profileID: profileID, draft: draft))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expectedKeys: Set<String> = [
            "p_business_profile_id",
            "p_display_name",
            "p_area_scope_id",
            "p_bio",
            "p_public_contact_name",
            "p_public_contact_email",
            "p_public_phone",
            "p_public_location_text",
            "p_public_address",
            "p_public_website",
            "p_avatar_image_path",
            "p_hero_image_path",
            "p_avatar_image_position_x",
            "p_avatar_image_position_y",
            "p_hero_image_position_x",
            "p_hero_image_position_y"
        ]

        XCTAssertEqual(Set(payload.keys), expectedKeys)
        XCTAssertEqual(payload["p_business_profile_id"] as? String, profileID.uuidString)
        XCTAssertEqual(payload["p_public_contact_email"] as? String, "aylah@test.com")
        XCTAssertEqual(payload["p_avatar_image_path"] as? String, "41000000-0000-0000-0000-000000000001/avatar.jpg")
        XCTAssertTrue(payload["p_hero_image_path"] is NSNull)
        XCTAssertEqual(payload["p_avatar_image_position_x"] as? Double, 42)
        XCTAssertEqual(payload["p_hero_image_position_y"] as? Double, 65)
    }

    func testMemberProfileImageDeliveryUsesAuthenticatedObjectEndpoint() throws {
        let service = SupabaseEventService()
        let request = try XCTUnwrap(service.memberProfileImageRequest(
            path: "41000000-0000-0000-0000-000000000001/avatar.jpg",
            accessToken: "owner-token"
        ))

        XCTAssertTrue(request.url?.absoluteString.contains("/storage/v1/object/authenticated/member-images/41000000-0000-0000-0000-000000000001/avatar.jpg") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owner-token")
        XCTAssertFalse(request.url?.absoluteString.contains("/object/public/") == true)
    }

    func testMemberProfileImageCropMappingIsSharedAndDeterministic() {
        let heroOffset = MemberProfileImageCrop.offset(
            in: CGSize(width: 300, height: 200),
            isCircular: false,
            positionX: 35,
            positionY: 65
        )
        XCTAssertEqual(heroOffset.width, 10.8, accuracy: 0.001)
        XCTAssertEqual(heroOffset.height, -7.2, accuracy: 0.001)

        let avatarOffset = MemberProfileImageCrop.offset(
            in: CGSize(width: 100, height: 100),
            isCircular: true,
            positionX: 42,
            positionY: 58
        )
        XCTAssertEqual(avatarOffset.width, 1.44, accuracy: 0.001)
        XCTAssertEqual(avatarOffset.height, -1.44, accuracy: 0.001)
    }

    func testMembershipLifecycleSeparatesApplicationApprovalPaymentAndPublishing() {
        var draft = BusinessProfileDraft()
        draft.name = "Aylah Test Membership"
        draft.organisationType = .communityGroup
        draft.email = "aylah@test.com"
        draft.selectedPlan = .localBusiness

        let trace = MembershipApplicationValidationTrace.evaluate(
            accountEmail: nil,
            draft: draft,
            websiteAccepted: true
        )
        XCTAssertTrue(trace.formIsValid)

        let pending = businessProfile(status: .pendingReview, selectedPlan: .localBusiness)
        var account = BusinessAccountState(profile: pending, subscriptions: [], sponsorRequests: [])
        XCTAssertEqual(account.profile?.memberStatus, .pendingReview)
        XCTAssertFalse(account.canCompleteSubscription)
        XCTAssertFalse(account.hasPublishingAccess)

        let approved = businessProfile(status: .approved, selectedPlan: .localBusiness)
        account.profile = approved
        XCTAssertTrue(account.canCompleteSubscription)
        XCTAssertFalse(account.hasPublishingAccess)
        XCTAssertEqual(account.profile?.memberStatus, .approved)

        account.subscriptions = [
            businessSubscription(status: "cancelled", periodEnd: Date().addingTimeInterval(-3600))
        ]
        XCTAssertEqual(account.profile?.memberStatus, .approved)
        XCTAssertNil(account.activeSubscription)
        XCTAssertFalse(account.hasPublishingAccess)

        account.subscriptions = [
            businessSubscription(status: "active", periodEnd: Date().addingTimeInterval(3600))
        ]
        XCTAssertEqual(account.profile?.memberStatus, .approved)
        XCTAssertNotNil(account.activeSubscription)
        XCTAssertTrue(account.hasPublishingAccess)
    }

    func testMembershipApplicationPermissionErrorDoesNotInvalidateValidContactEmail() {
        var draft = BusinessProfileDraft()
        draft.name = "Aylah Test Membership"
        draft.organisationType = .communityGroup
        draft.email = "aylah@test.com"

        let trace = MembershipApplicationValidationTrace.evaluate(
            accountEmail: nil,
            draft: draft,
            websiteAccepted: true
        )

        XCTAssertTrue(trace.formIsValid)
        XCTAssertFalse(trace.blockingFields.contains("contactEmail"))
        XCTAssertTrue(MembershipContactEmailValidator.isUsable(trace.payloadContactEmail))
    }

    func testPollDetailsParsesReviewBlock() {
        let text = """
        Listing kind: Poll

        Tell us what the village should do next.

        [POLL]
        Question: Best day for a market?

        Options:
        1. Friday
        2. Saturday
        3. Sunday

        Custom answer: Allowed, max 250 characters
        [/POLL]
        """

        let details = PollDetails(reviewText: text)

        XCTAssertEqual(details?.question, "Best day for a market?")
        XCTAssertEqual(details?.options, ["Friday", "Saturday", "Sunday"])
        XCTAssertEqual(details?.allowsCustomAnswer, true)
    }

    func testPollReviewBlockIsStrippedFromPublicDescription() {
        let text = """
        Listing kind: Poll

        Tell us what the village should do next.

        [POLL]
        Question: Best day for a market?

        Options:
        1. Friday
        2. Saturday

        Custom answer: Not allowed
        [/POLL]
        """

        let stripped = PollDetails.strippedReviewBlock(from: text)

        XCTAssertEqual(stripped, "Tell us what the village should do next.")
        XCTAssertFalse(stripped.contains("[POLL]"))
        XCTAssertFalse(stripped.contains("Listing kind: Poll"))
    }

    func testPendingPollDraftRequiresQuestionAndTwoOptions() {
        var draft = PendingListingDraft()
        draft.listingKind = .poll
        draft.title = "Community feedback"
        draft.pollQuestion = "Which day works best?"
        draft.pollOptions = ["Friday", "Saturday", ""]

        XCTAssertTrue(draft.canSubmit)

        draft.pollOptions = ["Friday", "", ""]

        XCTAssertFalse(draft.canSubmit)
    }

    func testPendingPollDraftCapsOptionsAtTen() {
        var draft = PendingListingDraft()
        draft.listingKind = .poll
        draft.title = "Community feedback"
        draft.pollQuestion = "Pick one"
        draft.pollOptions = (1...12).map { "Option \($0)" }

        XCTAssertEqual(draft.pollDetails?.options.count, PollDetails.maxOptions)
        XCTAssertEqual(draft.pollDetails?.options.last, "Option 10")
    }

    func testMemberListingInsertUsesVerifiedMemberClassification() throws {
        var draft = PendingListingDraft()
        draft.title = "Community meeting"
        draft.venue = "Beachlands Hall"
        draft.shortDescription = "A local community meeting."
        let profileID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!

        let data = try JSONEncoder().encode(PendingEventInsert(draft: draft, businessProfileID: profileID))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(payload["business_profile_id"] as? String, profileID.uuidString)
        XCTAssertEqual(payload["unverified_user_listing"] as? Bool, false)
        XCTAssertEqual(payload["is_featured"] as? Bool, false)
        XCTAssertEqual(payload["is_paid_push"] as? Bool, false)
        XCTAssertEqual(payload["status"] as? String, ListingStatus.pendingReview.rawValue)
        XCTAssertNil(payload["submitted_by"], "The database must derive submitter provenance from auth.uid().")
    }

    func testEventDecodingPreservesOrganisationOwnershipAndSubmitterProvenance() throws {
        let profileID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
        let submitterID = UUID(uuidString: "50000000-0000-0000-0000-000000000002")!
        let data = Data("""
        {
          "id": "70000000-0000-0000-0000-000000000001",
          "title": "School fair",
          "category": "Community",
          "town": "Maraetai",
          "location_display_name": "Maraetai",
          "venue": "School Hall",
          "start_at": "2026-08-20T20:00:00Z",
          "end_at": "2026-08-20T22:00:00Z",
          "price_label": "Free",
          "is_free": true,
          "audience": "Everyone",
          "short_description": "A local school event.",
          "long_description": "A local school event.",
          "contact_name": "Office",
          "contact_phone": null,
          "contact_email": "office@example.test",
          "business_profile_id": "\(profileID.uuidString)",
          "submitted_by": "\(submitterID.uuidString)",
          "is_featured": false,
          "is_paid_push": false,
          "status": "published",
          "listing_kind": "event",
          "poll_question": null,
          "poll_options": null,
          "poll_allows_custom_answer": false,
          "unverified_user_listing": false,
          "event_images": [],
          "created_at": "2026-08-15T00:00:00Z",
          "updated_at": "2026-08-15T00:00:00Z"
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(SupabaseEventRecord.self, from: data)
        let event = try XCTUnwrap(record.localEvent())

        XCTAssertEqual(event.businessProfileID, profileID)
        XCTAssertEqual(event.submittedBy, submitterID)
    }

    func testListingImageStoragePathUsesEventOwnedNamespace() {
        let eventID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
        let imageID = UUID(uuidString: "70000000-0000-0000-0000-000000000002")!

        XCTAssertEqual(
            ListingImageStoragePath.make(eventID: eventID, imageID: imageID),
            "events/70000000-0000-0000-0000-000000000001/70000000-0000-0000-0000-000000000002.jpg"
        )
    }

    func testListingPolicyFailureUsesCompactRecoveryMessage() {
        let error = SupabaseServiceError.requestFailed(
            403,
            #"{"code":"42501","message":"new row violates row-level security policy for table \"events\""}"#
        )

        XCTAssertEqual(
            error.errorDescription,
            "We couldn’t confirm your publishing access. Refresh your member status and try again. Your listing is still here."
        )
    }

    func testListingTierPlacementRulesAreDistinct() {
        XCTAssertEqual(ListingTier.communityFree.promotionPlacement, .standard)
        XCTAssertEqual(ListingTier.commercialStandard.promotionPlacement, .standard)
        XCTAssertEqual(ListingTier.boost.promotionPlacement, .topTen)
        XCTAssertEqual(ListingTier.boostInsights.promotionPlacement, .priorityFirst)
    }

    func testDiscoveryOrderingPlacesBoostInsightsAboveStandardBoosts() {
        let standardBoost = event(
            title: "Standard boost",
            start: date(2026, 6, 18, 10),
            promotionRank: ListingPromotionPlacement.topTen.rawValue,
            paidAt: date(2026, 6, 17, 8)
        )
        let boostInsights = event(
            title: "Boost insights",
            start: date(2026, 6, 18, 12),
            promotionRank: ListingPromotionPlacement.priorityFirst.rawValue,
            paidAt: date(2026, 6, 17, 9)
        )

        let ordered = [standardBoost, boostInsights].sorted(by: EventFeedOrdering.discovery)

        XCTAssertEqual(ordered.map(\.title), ["Boost insights", "Standard boost"])
    }

    func testPriorityPromotionTieUsesEarliestPaidAt() {
        let firstPaid = event(
            title: "First paid",
            start: date(2026, 6, 18, 12),
            promotionRank: ListingPromotionPlacement.priorityFirst.rawValue,
            paidAt: date(2026, 6, 17, 8)
        )
        let secondPaid = event(
            title: "Second paid",
            start: date(2026, 6, 18, 10),
            promotionRank: ListingPromotionPlacement.priorityFirst.rawValue,
            paidAt: date(2026, 6, 17, 9)
        )

        let ordered = [secondPaid, firstPaid].sorted(by: EventFeedOrdering.discovery)

        XCTAssertEqual(ordered.map(\.title), ["First paid", "Second paid"])
    }

    func testPromotionWindowDoesNotRunUntilAFarFutureEvent() {
        let now = date(2026, 6, 17, 9)
        let eventStart = date(2027, 6, 17, 10)
        let eventEnd = date(2027, 6, 17, 12)
        let requestedEnd = date(2027, 6, 17, 12)

        let window = PromotionWindowPolicy.clampedWindow(
            tier: .boost,
            eventStart: eventStart,
            eventEnd: eventEnd,
            requestedStart: now,
            requestedEnd: requestedEnd,
            now: now
        )

        XCTAssertEqual(window?.start, now)
        XCTAssertEqual(window?.duration, ListingTier.boost.maximumPromotionDuration)
    }

    func testPromotionWindowStopsAtEventEnd() {
        let now = date(2026, 6, 17, 9)
        let eventStart = date(2026, 6, 18, 10)
        let eventEnd = date(2026, 6, 18, 12)

        let window = PromotionWindowPolicy.clampedWindow(
            tier: .boostInsights,
            eventStart: eventStart,
            eventEnd: eventEnd,
            requestedStart: now,
            requestedEnd: nil,
            now: now
        )

        XCTAssertEqual(window?.start, now)
        XCTAssertEqual(window?.end, eventEnd)
    }

    func testPromotionWindowRejectsEndedOrStandardListings() {
        let now = date(2026, 6, 17, 9)
        let eventStart = date(2026, 6, 16, 10)
        let eventEnd = date(2026, 6, 16, 12)

        XCTAssertNil(
            PromotionWindowPolicy.clampedWindow(
                tier: .commercialStandard,
                eventStart: date(2026, 6, 18, 10),
                eventEnd: date(2026, 6, 18, 12),
                requestedStart: now,
                requestedEnd: nil,
                now: now
            )
        )

        XCTAssertNil(
            PromotionWindowPolicy.clampedWindow(
                tier: .boost,
                eventStart: eventStart,
                eventEnd: eventEnd,
                requestedStart: now,
                requestedEnd: nil,
                now: now
            )
        )
    }

    func testBusinessSubscriptionProductMappingFindsMemberPlans() {
        XCTAssertEqual(
            BusinessSubscriptionPlan.plan(forProductID: "communitycalendar.business.local.monthly"),
            .localBusiness
        )
        XCTAssertEqual(
            BusinessSubscriptionPlan.plan(forProductID: "communitycalendar.business.growth.monthly"),
            .growth
        )
        XCTAssertEqual(
            BusinessSubscriptionPlan.plan(forProductID: "communitycalendar.business.sponsor.monthly"),
            .sponsor
        )
        XCTAssertNil(BusinessSubscriptionPlan.plan(forProductID: "communitycalendar.boost.standard"))
    }

    func testBusinessSubscriptionBackendActivationStatuses() {
        XCTAssertEqual(AppleBusinessSubscriptionBackendStatus.activated.rawValue, "activated")
        XCTAssertEqual(AppleBusinessSubscriptionBackendStatus.alreadyProcessed.rawValue, "already_processed")
        XCTAssertEqual(AppleBusinessSubscriptionBackendStatus.rejected.rawValue, "rejected")
    }

    func testPublicMemberProfileDecoderMatchesApprovedContract() throws {
        let data = Data(#"{"id":"11111111-1111-1111-1111-111111111111","public_slug":"maraetai-school","display_name":"Maraetai Beach School","area_scope_id":"maraetai","bio":"Learning by the coast","public_contact_name":"Office","public_contact_email":"office@example.test","public_phone":"09 000 0000","public_location_text":"Maraetai","public_address":"1 Coast Road","public_website":"https://example.test","avatar_image_path":null,"hero_image_path":null,"avatar_image_position_x":45,"avatar_image_position_y":55,"hero_image_position_x":50,"hero_image_position_y":40,"published_at":"2026-08-06T00:00:00Z","public_contact_revision":"22222222-2222-2222-2222-222222222222","public_contact_confirmed_revision":"22222222-2222-2222-2222-222222222222","public_contact_confirmed_at":"2026-08-06T00:00:01Z","owner_user_id":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","selected_plan_id":"sponsor","status":"approved"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let profile = try decoder.decode(PublicBusinessProfileRecord.self, from: data)

        XCTAssertEqual(profile.displayName, "Maraetai Beach School")
        XCTAssertEqual(profile.publicSlug, "maraetai-school")
        XCTAssertTrue(profile.isCurrentPublicContactConfirmed)
        let storedProperties = Set(Mirror(reflecting: profile).children.compactMap(\.label))
        XCTAssertFalse(storedProperties.contains("ownerUserID"))
        XCTAssertFalse(storedProperties.contains("selectedPlanID"))
        XCTAssertFalse(storedProperties.contains("status"))
        XCTAssertFalse(storedProperties.contains("contactEmail"))
    }

    func testPublicMemberProfileSelectIsAnExactAllowListWithoutPrivateFields() {
        let fields = Set(SupabaseEventService.publicMemberProfileSelect.split(separator: ",").map(String.init))
        let expected: Set<String> = [
            "id", "public_slug", "display_name", "area_scope_id", "bio",
            "public_contact_name", "public_contact_email", "public_phone",
            "public_location_text", "public_address", "public_website",
            "avatar_image_path", "hero_image_path", "avatar_image_position_x",
            "avatar_image_position_y", "hero_image_position_x", "hero_image_position_y",
            "published_at", "public_contact_revision",
            "public_contact_confirmed_revision", "public_contact_confirmed_at"
        ]

        XCTAssertEqual(fields, expected)
        XCTAssertEqual(SupabaseEventService.publicMemberProfileResource, "public_member_profiles")
        XCTAssertFalse(SupabaseEventService.publicMemberProfileSelect.contains("*"))
        XCTAssertFalse(SupabaseEventService.publicMemberProfileSelect.contains("owner_user_id"))
        XCTAssertFalse(SupabaseEventService.publicMemberProfileSelect.contains("selected_plan_id"))
        XCTAssertFalse(SupabaseEventService.publicMemberProfileSelect.contains("status"))
    }

    func testMissingPublicProfileDecodesAsUnavailable() throws {
        let profiles = try JSONDecoder().decode([PublicBusinessProfileRecord].self, from: Data("[]".utf8))
        XCTAssertNil(profiles.first)
    }

    @MainActor
    func testUserAResponseCannotOverwriteFasterUserBSignIn() async throws {
        let userA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let userB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let store = UserSessionStore(
            authService: DelayedUserAuthService(userA: userA, userB: userB),
            persistsSession: false
        )

        let slowA = Task { try await store.signIn(email: "a@example.test", password: "secret") }
        try await Task.sleep(for: .milliseconds(10))
        try await store.signIn(email: "b@example.test", password: "secret")

        do {
            try await slowA.value
            XCTFail("The stale User A request should be cancelled.")
        } catch is CancellationError {
            // Expected: User B changed the account generation first.
        }

        XCTAssertEqual(store.session?.userID, userB)
        XCTAssertEqual(store.accountContext.userID, userB)
    }

    @MainActor
    func testAccountContextInvalidatesMutationAfterSignOut() async throws {
        let userA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let store = UserSessionStore(
            authService: DelayedUserAuthService(userA: userA, userB: UUID()),
            persistsSession: false
        )
        try await store.signIn(email: "a@example.test", password: "secret")
        let mutationContext = store.captureAccountContext()

        store.signOut()

        XCTAssertFalse(store.isCurrent(mutationContext))
        XCTAssertNil(store.session)
    }

    @MainActor
    func testAccountProfileStoreScopesPersistenceByAuthenticatedUser() {
        let suiteName = "AccountProfileStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(Data("legacy".utf8), forKey: "communityCalendar.accountProfile")

        let userA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let userB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let store = AccountProfileStore(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "communityCalendar.accountProfile"))

        store.bind(to: userA)
        store.save(AccountProfile(
            displayName: "User A",
            publicRole: "Coordinator",
            organisationName: "A Trust",
            phone: " 021 111 111 ",
            website: " https://a.example ",
            preferredContactEmail: " a@example.com ",
            contactVisibility: .publicProfile
        ))

        store.bind(to: userB)
        XCTAssertEqual(store.profile, .empty)

        store.save(AccountProfile(
            displayName: "User B",
            publicRole: "Manager",
            organisationName: "B Club",
            phone: "022 222 222",
            website: "https://b.example",
            preferredContactEmail: "b@example.com",
            contactVisibility: .nameAndEmail
        ))

        store.bind(to: userA)
        XCTAssertEqual(store.profile.displayName, "User A")
        XCTAssertEqual(store.profile.phone, "021 111 111")
        XCTAssertEqual(store.profile.website, "https://a.example")
        XCTAssertEqual(store.profile.preferredContactEmail, "a@example.com")

        store.bind(to: nil)
        XCTAssertEqual(store.profile, .empty)

        store.bind(to: userB)
        XCTAssertEqual(store.profile.displayName, "User B")
    }

    private func businessProfile(
        status: BusinessProfileStatus,
        selectedPlan: BusinessSubscriptionPlan
    ) -> BusinessProfileRecord {
        let now = Date()
        return BusinessProfileRecord(
            id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
            ownerUserID: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
            businessName: "Aylah Test Membership",
            organisationTypeID: BusinessOrganisationType.communityGroup.rawValue,
            contactName: "Aylah",
            contactEmail: "aylah@test.com",
            phone: nil,
            address: nil,
            website: nil,
            about: nil,
            areaScopeID: LocationScope.defaultID,
            status: status.rawValue,
            selectedPlanID: selectedPlan.rawValue,
            heroImageURL: nil,
            avatarImageURL: nil,
            heroImagePositionX: 50,
            heroImagePositionY: 50,
            avatarImagePositionX: 50,
            avatarImagePositionY: 50,
            approvedAt: status == .approved ? now : nil,
            rejectedAt: nil,
            rejectionReason: nil,
            suspendedAt: nil,
            suspensionReason: nil,
            supportNote: nil,
            reviewedBy: nil,
            reviewedAt: status == .approved ? now : nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func businessSubscription(status: String, periodEnd: Date?) -> BusinessSubscriptionRecord {
        let now = Date()
        return BusinessSubscriptionRecord(
            id: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!,
            businessProfileID: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
            ownerUserID: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
            planID: BusinessSubscriptionPlan.localBusiness.rawValue,
            productID: BusinessSubscriptionPlan.localBusiness.productID,
            appleOriginalTransactionID: status == "active" ? "active-transaction" : nil,
            status: status,
            activeListingLimit: BusinessSubscriptionPlan.localBusiness.activeListingLimit,
            placementRank: BusinessSubscriptionPlan.localBusiness.placementRank,
            currentPeriodStart: periodEnd == nil ? nil : now.addingTimeInterval(-3600),
            currentPeriodEnd: periodEnd,
            createdAt: now,
            updatedAt: now
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func event(
        title: String,
        start: Date,
        promotionRank: Int = 0,
        paidAt: Date? = nil
    ) -> LocalEvent {
        LocalEvent(
            title: title,
            category: .community,
            town: .beachlands,
            venue: "Beachlands Hall",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            priceLabel: "Free",
            isFree: true,
            audience: "Everyone",
            shortDescription: "Community listing",
            longDescription: "Community listing",
            contactPhone: nil,
            contactEmail: nil,
            isFeatured: false,
            isPaidPush: false,
            createdAt: start,
            activePromotionRank: promotionRank,
            activePromotionPaidAt: paidAt
        )
    }
}

private struct DelayedUserAuthService: UserAuthenticating {
    let userA: UUID
    let userB: UUID

    func signIn(email: String, password: String) async throws -> UserSession {
        let isUserA = email.hasPrefix("a@")
        try await Task.sleep(for: isUserA ? .milliseconds(120) : .milliseconds(5))
        return UserSession(
            accessToken: isUserA ? "token-a" : "token-b",
            refreshToken: isUserA ? "refresh-a" : "refresh-b",
            userID: isUserA ? userA : userB,
            email: email,
            isEmailVerified: true,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    func signUp(email: String, password: String) async throws -> UserSession {
        try await signIn(email: email, password: password)
    }

    func refreshSession(refreshToken: String) async throws -> UserSession {
        try await signIn(email: refreshToken.contains("a") ? "a@example.test" : "b@example.test", password: "")
    }

    func resendVerificationEmail(email: String) async throws {}
    func sendPasswordResetEmail(email: String) async throws {}
}
