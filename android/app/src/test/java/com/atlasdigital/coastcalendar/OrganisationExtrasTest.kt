package com.atlasdigital.coastcalendar

import com.atlasdigital.coastcalendar.data.model.MemberImagePath
import com.atlasdigital.coastcalendar.data.model.MemberPlan
import com.atlasdigital.coastcalendar.data.model.OrganisationDraft
import com.atlasdigital.coastcalendar.data.model.PublicPageDraft
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OrganisationExtrasTest {
    @Test fun plansMatchIosIdsAndLimits() {
        assertEquals(listOf("local_business", "growth", "sponsor"), MemberPlan.entries.map { it.id })
        assertEquals(listOf(1, 4, 8), MemberPlan.entries.map { it.listingLimit })
        assertEquals(MemberPlan.LocalBusiness, MemberPlan.from("unknown"))
        MemberPlan.entries.flatMap { it.inclusions + it.title }.forEach {
            assertFalse(it, it.contains("$") || it.contains("month", ignoreCase = true) || it.contains("pay", ignoreCase = true))
        }
    }

    @Test fun planIsSentAsSelectedPlanId() {
        assertEquals("growth", OrganisationDraft(selectedPlanId = "growth").rpcParams()["p_selected_plan_id"])
    }

    @Test fun memberImagePathMatchesIos() {
        val p = MemberImagePath.make("ABC-USER", "avatar", "IMG-1")
        assertEquals("abc-user/avatar-img-1.jpg", p)
        assertTrue(MemberImagePath.make("u", "anything").startsWith("u/hero-"))
        assertEquals("member-images", MemberImagePath.BUCKET)
    }

    @Test fun publicPageNeedsNameAndArea() {
        assertEquals(listOf("memberName", "areaScope"), PublicPageDraft().problems)
        val filled = PublicPageDraft.prefill(PublicPageDraft(), OrganisationDraft(name = "Club", areaScopeId = "beachlands", about = "Hi"))
        assertTrue(filled.problems.isEmpty())
        assertEquals("Hi", filled.bio)
        assertEquals(listOf("contactEmail"), filled.copy(contactEmail = "nope").problems)
    }
}
