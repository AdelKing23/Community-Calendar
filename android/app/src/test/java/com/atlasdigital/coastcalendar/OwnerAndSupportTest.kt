package com.atlasdigital.coastcalendar

import com.atlasdigital.coastcalendar.data.model.BusinessAccountState
import com.atlasdigital.coastcalendar.data.model.BusinessProfileRecord
import com.atlasdigital.coastcalendar.data.model.CoastTown
import com.atlasdigital.coastcalendar.data.model.ContactEmailValidator
import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.data.model.HostDirectoryItem
import com.atlasdigital.coastcalendar.data.model.ListingKind
import com.atlasdigital.coastcalendar.data.model.ListingStatus
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.OrganisationDraft
import com.atlasdigital.coastcalendar.data.model.OrganisationStatusCopy
import com.atlasdigital.coastcalendar.data.model.OrganisationType
import com.atlasdigital.coastcalendar.data.model.PublicMemberProfileRecord
import com.atlasdigital.coastcalendar.data.model.SupportRequestRecord
import com.atlasdigital.coastcalendar.data.model.SupportTopic
import com.atlasdigital.coastcalendar.feature.support.SupportDashboardState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant

class OwnerAndSupportTest {
    private fun event(id: String, profile: String?, status: ListingStatus = ListingStatus.Published, startIn: Duration = Duration.ofDays(1)) = LocalEvent(
        id = id, title = id, category = EventCategory.Markets, town = CoastTown.Beachlands, locationDisplayName = null,
        venue = "Hall", start = Instant.now().plus(startIn), end = Instant.now().plus(startIn).plusSeconds(3600), priceLabel = "Free", isFree = true,
        shortDescription = "", longDescription = "", businessProfileId = profile, organisationName = null, contactName = null,
        isFeatured = false, isPaidPush = false, status = status, kind = ListingKind.Event, pollDetails = null,
        isAllDay = false, createdAt = Instant.EPOCH,
    )

    @Test fun emailValidatorMatchesIosRules() {
        assertTrue(ContactEmailValidator.isUsable(" a@b.nz "))
        assertFalse(ContactEmailValidator.isUsable("a@b"))
        assertFalse(ContactEmailValidator.isUsable("a b@c.nz"))
        assertFalse(ContactEmailValidator.isUsable("a@@c.nz"))
    }

    @Test fun organisationDraftNeedsNameTypeContactAndEmail() {
        val ok = OrganisationDraft(name = "Club", type = OrganisationType.SportsClub, contactName = "Sam", email = "s@club.nz")
        assertTrue(ok.canSubmit)
        assertFalse(ok.copy(type = null).canSubmit)
        assertFalse(ok.copy(email = "nope").canSubmit)
        val p = ok.rpcParams()
        assertEquals("sports_club", p["p_organisation_type"])
        assertNull(p["p_phone"])
        assertEquals("local_business", p["p_selected_plan_id"])
        assertEquals(16, p.size)
    }

    @Test fun organisationStatusCopyHasNoPaymentWording() {
        val profile = BusinessProfileRecord(id = "p", ownerUserId = "u", businessName = "Club", status = "approved")
        val text = OrganisationStatusCopy.message(BusinessAccountState(profile = profile)) + OrganisationStatusCopy.title(BusinessAccountState(profile = profile))
        listOf("pay", "subscri", "stripe", "apple", "google play", "$").forEach { assertFalse(it, text.lowercase().contains(it)) }
    }

    @Test fun contactTopicsDropPayment() {
        assertFalse(SupportTopic.entries.any { it.raw.contains("Payment", ignoreCase = true) })
        assertEquals(listOf("Listing help", "Account", "Safety or content", "Other"), SupportTopic.entries.map { it.raw })
    }

    @Test fun hostDirectoryRanksActiveHostsFirst() {
        val quiet = PublicMemberProfileRecord(id = "A", displayName = "Alpha")
        val busy = PublicMemberProfileRecord(id = "B", displayName = "Beta")
        val hosts = HostDirectoryItem.build(listOf(quiet, busy), listOf(event("1", "b"), event("2", "b")))
            .sortedWith(HostDirectoryItem.recommended)
        assertEquals(listOf("Beta", "Alpha"), hosts.map { it.name })
        assertEquals(2, hosts.first().events.size)
        assertEquals("Next up: 1", hosts.first().subtitle)
    }

    @Test fun supportDashboardBucketsListingsLikeIos() {
        val state = SupportDashboardState(
            events = listOf(
                event("pending", null, ListingStatus.PendingReview),
                event("live", null),
                event("ended", null, startIn = Duration.ofDays(-2)),
                event("rej", null, ListingStatus.Rejected),
                event("arch", null, ListingStatus.Archived),
            ),
            requests = listOf(
                SupportRequestRecord(id = "1", status = "closed"),
                SupportRequestRecord(id = "2", status = "open"),
                SupportRequestRecord(id = "3", status = "in_review"),
            ),
        )
        assertEquals(listOf("pending"), state.pending.map { it.id })
        assertEquals(listOf("live"), state.published.map { it.id })
        assertEquals(listOf("ended"), state.ended.map { it.id })
        assertEquals(listOf("rej"), state.rejected.map { it.id })
        assertEquals(listOf("arch"), state.archived.map { it.id })
        assertEquals(listOf("2", "3"), state.inbox.map { it.id })
    }
}
