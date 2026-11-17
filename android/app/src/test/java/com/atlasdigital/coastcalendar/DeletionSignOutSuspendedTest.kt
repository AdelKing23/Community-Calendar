package com.atlasdigital.coastcalendar

import com.atlasdigital.coastcalendar.data.model.BusinessAccountState
import com.atlasdigital.coastcalendar.data.model.BusinessProfileRecord
import com.atlasdigital.coastcalendar.data.model.OrganisationStatusCopy
import com.atlasdigital.coastcalendar.data.model.OrganisationSuspended
import com.atlasdigital.coastcalendar.data.remote.ErrorMessages
import com.atlasdigital.coastcalendar.data.repository.CompleteAccountDeletion
import com.atlasdigital.coastcalendar.feature.create.CreateGate
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** t253: iOS 5a067ca edge-function deletion + suspended Organisation copy. */
class DeletionSignOutSuspendedTest {
    @Test fun deletionBodyMatchesIosEncoding() {
        val body = CompleteAccountDeletion.body("ABCDEF12-3456-7890-ABCD-EF1234567890", "note")
        assertEquals("abcdef12-3456-7890-abcd-ef1234567890", body["request_id"]!!.jsonPrimitive.content)
        assertEquals("note", body["support_note"]!!.jsonPrimitive.content)
        assertFalse(CompleteAccountDeletion.body("x", null).containsKey("support_note"))
        assertEquals("complete-account-deletion", CompleteAccountDeletion.FUNCTION_NAME)
    }

    @Test fun deletionWordingMatchesIos() {
        assertEquals("Account deletion completed. Their login, personal details and photos have been removed.", CompleteAccountDeletion.SUCCESS)
        assertEquals("Could not complete account deletion. It is safe to try again.", CompleteAccountDeletion.FAILURE)
        assertEquals(CompleteAccountDeletion.FAILURE, CompleteAccountDeletion.failureMessage(500))
        assertEquals(CompleteAccountDeletion.FAILURE, CompleteAccountDeletion.failureMessage(null))
        assertTrue(CompleteAccountDeletion.failureMessage(401).contains("Sign in"))
        assertTrue(CompleteAccountDeletion.failureMessage(403).contains("Support only"))
        assertTrue(CompleteAccountDeletion.failureMessage(409).contains("already been deleted"))
    }

    @Test fun suspendedOrganisationSaysContactSupport() {
        val p = BusinessProfileRecord(id = "p", ownerUserId = "u", businessName = "Club", status = "suspended")
        val state = BusinessAccountState(profile = p)
        assertEquals(OrganisationSuspended.TITLE, OrganisationStatusCopy.title(state))
        assertEquals("Your organisation is suspended - contact Support.", OrganisationStatusCopy.message(state))
        assertEquals(OrganisationSuspended.TITLE, CreateGate.title(state))
        assertTrue(CreateGate.message(state).startsWith(OrganisationSuspended.MESSAGE))
        assertFalse(state.canSubmitAsOrganisation)
        assertTrue(OrganisationSuspended.message("Overdue review").endsWith("Reason: Overdue review"))
    }

    @Test fun serverSuspensionRefusalIsTranslated() {
        assertEquals(OrganisationSuspended.MESSAGE, ErrorMessages.userFacing(IllegalStateException("Organisation is suspended")))
    }
}
