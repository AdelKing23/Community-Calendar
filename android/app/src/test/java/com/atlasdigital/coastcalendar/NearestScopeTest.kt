package com.atlasdigital.coastcalendar

import com.atlasdigital.coastcalendar.core.location.KnownCoordinates
import com.atlasdigital.coastcalendar.data.model.LocationScope
import org.junit.Assert.assertEquals
import org.junit.Test

class NearestScopeTest {
    @Test fun picksNearestKnownLocalPlace() {
        assertEquals("beachlands", KnownCoordinates.nearest(-36.885, 175.003))
        assertEquals("clevedon", KnownCoordinates.nearest(-36.99, 175.04))
    }

    @Test fun beyondFortyFiveKmFallsBackToDefault() {
        assertEquals(LocationScope.DEFAULT_ID, KnownCoordinates.nearest(-41.29, 174.78)) // Wellington
    }
}
