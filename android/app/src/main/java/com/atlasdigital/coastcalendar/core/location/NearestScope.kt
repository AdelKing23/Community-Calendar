package com.atlasdigital.coastcalendar.core.location

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationManager
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.atlasdigital.coastcalendar.data.model.LocationScope
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.coroutines.resume
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

@Serializable
data class NearestScopeRow(
    val slug: String,
    val name: String,
    @SerialName("scope_type") val scopeType: String? = null,
    val subtitle: String? = null,
    @SerialName("distance_kilometers") val distanceKilometers: Double = 0.0,
    @SerialName("is_within_radius") val isWithinRadius: Boolean = false,
)

/** iOS `LocationScope.nearestKnownScope`: the 9 local places, 45 km cap, else the default area. */
object KnownCoordinates {
    data class Known(val scopeId: String, val lat: Double, val lon: Double)

    val all = listOf(
        Known("beachlands", -36.884, 175.004), Known("maraetai", -36.879, 175.035), Known("omana", -36.890, 175.026),
        Known("whitford", -36.945, 174.965), Known("clevedon", -36.990, 175.037), Known("kawakawa-bay", -36.946, 175.169),
        Known("orere-point", -36.967, 175.253), Known("hunua", -37.079, 175.067), Known("ardmore", -37.031, 174.973),
    )

    fun distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6_371_000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2).pow(2) + cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
        return 2 * r * asin(sqrt(a))
    }

    fun nearest(lat: Double, lon: Double): String {
        val best = all.minByOrNull { distanceMeters(lat, lon, it.lat, it.lon) } ?: return LocationScope.DEFAULT_ID
        return if (distanceMeters(lat, lon, best.lat, best.lon) <= 45_000) best.scopeId else LocationScope.DEFAULT_ID
    }
}

/**
 * iOS `UserLocationPreferenceStore.applyNearestScope`: RPC `nearest_location_scope(p_latitude, p_longitude, p_max_results=1)`,
 * use it when `is_within_radius`; otherwise the nearest known local place within 45 km; otherwise the default area.
 */
class NearestScopeResolver(private val client: SupabaseClient) {
    suspend fun resolve(lat: Double, lon: Double): Pair<String, String?> {
        val remote = runCatching {
            client.postgrest.rpc(
                "nearest_location_scope",
                buildJsonObject { put("p_latitude", lat); put("p_longitude", lon); put("p_max_results", 1) },
            ).decodeList<NearestScopeRow>().firstOrNull { it.isWithinRadius }
        }.getOrNull()
        if (remote != null) return remote.slug to remote.name
        return KnownCoordinates.nearest(lat, lon) to null
    }
}

/** One coarse fix from the network provider (no Google Play services), falling back to the last known fix. */
object CoarseLocation {
    fun hasPermission(context: Context) =
        ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    suspend fun current(context: Context): Location? {
        if (!hasPermission(context)) return null
        val lm = context.getSystemService(LocationManager::class.java) ?: return null
        val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER).filter { runCatching { lm.isProviderEnabled(it) }.getOrDefault(false) }
        val provider = providers.firstOrNull()
        val fresh = provider?.let { p ->
            withTimeoutOrNull(15_000) {
                suspendCancellableCoroutine<Location?> { cont ->
                    val signal = androidx.core.os.CancellationSignal()
                    cont.invokeOnCancellation { signal.cancel() }
                    LocationManagerCompat.getCurrentLocation(lm, p, signal, ContextCompat.getMainExecutor(context)) { loc ->
                        if (cont.isActive) cont.resume(loc)
                    }
                }
            }
        }
        return fresh ?: providers.mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }.maxByOrNull { it.time }
    }
}
