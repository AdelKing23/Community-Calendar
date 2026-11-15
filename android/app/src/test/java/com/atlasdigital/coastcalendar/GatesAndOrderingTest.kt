package com.atlasdigital.coastcalendar

import com.atlasdigital.coastcalendar.core.config.SupabaseConfig
import com.atlasdigital.coastcalendar.data.model.BusinessAccountState
import com.atlasdigital.coastcalendar.data.model.BusinessProfileRecord
import com.atlasdigital.coastcalendar.data.model.BusinessSubscriptionRecord
import com.atlasdigital.coastcalendar.data.model.CoastTown
import com.atlasdigital.coastcalendar.data.model.DateScope
import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.data.model.EventFeedOrdering
import com.atlasdigital.coastcalendar.data.model.ListingKind
import com.atlasdigital.coastcalendar.data.model.ListingStatus
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.PublicEventRecord
import com.atlasdigital.coastcalendar.data.remote.SupabaseProvider
import com.atlasdigital.coastcalendar.feature.welcome.WelcomeGate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

class GatesAndOrderingTest {
    private val now = Instant.parse("2026-11-16T00:00:00Z")
    private fun profile(status: String) = BusinessProfileRecord(id = "p", ownerUserId = "u", businessName = "Org", status = status)
    private fun sub(status: String, end: String?) = BusinessSubscriptionRecord(id = "s", businessProfileId = "p", planId = "local_business", status = status, currentPeriodEnd = end)

    @Test fun approvedOrgNeedsActiveSubscription() {
        assertFalse(BusinessAccountState(profile("approved")).canSubmitAsOrganisation)
        assertTrue(BusinessAccountState(profile("approved"), listOf(sub("active", "2099-01-01T00:00:00+00:00"))).canSubmitAsOrganisation)
        assertFalse(BusinessAccountState(profile("approved"), listOf(sub("active", "2020-01-01T00:00:00+00:00"))).canSubmitAsOrganisation)
        assertTrue(BusinessAccountState(profile("approved"), listOf(sub("cancelled", "2099-01-01T00:00:00+00:00"))).canSubmitAsOrganisation)
        assertFalse(BusinessAccountState(profile("approved"), listOf(sub("active", null))).canSubmitAsOrganisation)
    }

    @Test fun supportIsTheOnlyFreePathAndStillNeedsApprovedOrg() {
        assertTrue(BusinessAccountState(profile("approved"), isSupport = true).canSubmitAsOrganisation)
        assertFalse(BusinessAccountState(profile("pending_review"), isSupport = true).canSubmitAsOrganisation)
        assertFalse(BusinessAccountState(null, isSupport = true).canSubmitAsOrganisation)
        assertFalse(BusinessAccountState(profile("pending_review"), listOf(sub("active", "2099-01-01T00:00:00+00:00"))).canSubmitAsOrganisation)
    }

    @Test fun welcomeGateFailsOpenUnlessDismissedOnDevice() {
        assertTrue(WelcomeGate.shouldShow(true, WelcomeGate.ServerCheck.Failed, false, true))
        assertFalse(WelcomeGate.shouldShow(true, WelcomeGate.ServerCheck.Failed, true, false))
        assertFalse(WelcomeGate.shouldShow(true, WelcomeGate.ServerCheck.Dismissed, false, false))
        assertTrue(WelcomeGate.shouldShow(false, WelcomeGate.ServerCheck.Dismissed, true, false))
        assertEquals("a,b", WelcomeGate.adding("B", "a"))
    }

    @Test fun configGuardRejectsSecretKeys() {
        assertTrue(SupabaseConfig.isValid("https://x.supabase.co", "sb_publishable_abc"))
        assertFalse(SupabaseConfig.isValid("https://x.supabase.co", "sb_secret_abc"))
        assertFalse(SupabaseConfig.isValid("https://x.supabase.co", "eyJ...service_role"))
        assertFalse(SupabaseConfig.isValid("", "sb_publishable_abc"))
    }

    private fun event(id: String, start: String, created: String, featured: Boolean = false, paid: Boolean = false, end: String? = null) = LocalEvent(
        id = id, title = id, category = EventCategory.Community, town = CoastTown.Beachlands, locationDisplayName = null, venue = "v",
        start = Instant.parse(start), end = Instant.parse(end ?: start), priceLabel = "Free", isFree = true, shortDescription = "",
        longDescription = "", businessProfileId = null, organisationName = null, contactName = null, isFeatured = featured,
        isPaidPush = paid, status = ListingStatus.Published, kind = ListingKind.Event, pollDetails = null, isAllDay = false,
        createdAt = Instant.parse(created),
    )

    @Test fun boardAndDiscoveryOrderMatchIos() {
        val a = event("a", "2026-11-20T00:00:00Z", "2026-11-01T00:00:00Z")
        val b = event("b", "2026-11-18T00:00:00Z", "2026-11-10T00:00:00Z")
        val f = event("f", "2026-12-01T00:00:00Z", "2026-10-01T00:00:00Z", featured = true)
        val p = event("p", "2026-12-05T00:00:00Z", "2026-09-01T00:00:00Z", paid = true)
        assertEquals(listOf("p", "f", "b", "a"), listOf(a, b, f, p).sortedWith(EventFeedOrdering.board).map { it.id })
        assertEquals(listOf("p", "f", "b", "a"), listOf(a, b, f, p).sortedWith(EventFeedOrdering.discovery).map { it.id })
        val c = event("c", "2026-11-25T00:00:00Z", "2026-11-10T00:00:00Z")
        assertEquals(listOf("b", "c"), listOf(c, b).sortedWith(EventFeedOrdering.discovery).map { it.id })
    }

    @Test fun todayScopeUsesOverlap() {
        val nz = ZoneId.of("Pacific/Auckland")
        val e = event("t", "2026-11-15T22:00:00Z", "2026-11-01T00:00:00Z", end = "2026-11-16T02:00:00Z")
        assertTrue(DateScope.Today.matches(e, now, nz, Locale.forLanguageTag("en-NZ")))
        val later = event("l", "2026-11-17T22:00:00Z", "2026-11-01T00:00:00Z", end = "2026-11-17T23:00:00Z")
        assertFalse(DateScope.Today.matches(later, now, nz, Locale.forLanguageTag("en-NZ")))
        assertTrue(DateScope.ThisWeek.matches(later, now, nz, Locale.forLanguageTag("en-NZ")))
    }

    @Test fun publicEventRowDecodes() {
        val raw = """[{"id":"9b0f","title":"Welcome to Coast Calendar","category":"Community","town":"All Areas",
            "location_display_name":"Pōhutukawa Coast","venue":"Online","start_at":"2027-05-15T12:00:00+00:00",
            "end_at":"2027-05-16T11:59:59+00:00","is_featured":false,"is_paid_push":false,"status":"published",
            "listing_kind":"event","is_all_day":true,"created_at":"2026-11-16T00:30:00.123456+00:00","extra":1}]"""
        val row = SupabaseProvider.json.decodeFromString<List<PublicEventRecord>>(raw).single().toLocalEvent()!!
        assertTrue(row.isAllDay)
        assertEquals("All day", row.timeText())
        assertEquals("Pōhutukawa Coast", row.displayLocationName)
        assertEquals(CoastTown.All, row.town)
        assertTrue(row.isPubliclyVisible)
    }
}
