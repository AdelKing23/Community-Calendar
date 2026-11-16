package com.atlasdigital.coastcalendar

import com.atlasdigital.coastcalendar.feature.settings.AccountDeletionRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AccountDeletionTest {
    @Test fun topicMatchesIosAndSupportDashboardDetection() {
        assertEquals("Account deletion", AccountDeletionRequest.TOPIC)
        assertTrue(AccountDeletionRequest.TOPIC.contains("deletion", ignoreCase = true))
    }

    @Test fun messageCarriesEmailAndDefaultNoteWithoutBillingWording() {
        val m = AccountDeletionRequest.message("a@b.nz", "  ")
        assertTrue(m.contains("Signed-in email: a@b.nz"))
        assertTrue(m.contains("No extra note supplied."))
        assertFalse(m.contains("subscription", ignoreCase = true))
        assertFalse(m.contains("payment", ignoreCase = true))
    }
}
