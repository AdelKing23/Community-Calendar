package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.data.model.EventImage
import com.atlasdigital.coastcalendar.data.model.EventImageInsert
import com.atlasdigital.coastcalendar.data.model.EventImageRecord
import com.atlasdigital.coastcalendar.data.model.ListingImageStoragePath
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import io.ktor.http.ContentType
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import java.util.UUID
import kotlin.time.Duration.Companion.seconds

/** A compressed photo ready to upload (iOS `ListingPhotoUpload`). */
class ListingPhotoUpload(
    val id: String = UUID.randomUUID().toString(),
    val data: ByteArray,
    val width: Int,
    val height: Int,
    val mimeType: String = "image/jpeg",
) {
    val byteSize: Int get() = data.size
}

/**
 * Listing photos, same contract as iOS `SupabaseEventService`:
 * - read rows from the `public_event_images` view (event_id in …, order position asc);
 * - sign each path in the private `listing-images` bucket for 3600 s (`POST storage/v1/object/sign/listing-images/<path>`);
 * - upload to `listing-images/<userId>/<eventId>/<imageId>.jpg` (no upsert) then insert `event_images` metadata.
 */
class ImageRepository(private val client: SupabaseClient) {

    suspend fun imageRecords(eventIds: List<String>): Map<String, List<EventImageRecord>> {
        if (eventIds.isEmpty()) return emptyMap()
        return eventIds.distinct().chunked(150).flatMap { batch ->
            client.from("public_event_images").select(Columns.raw(EventImageRecord.SELECT)) {
                filter { isIn("event_id", batch) }
                order("position", Order.ASCENDING)
            }.decodeList<EventImageRecord>()
        }.groupBy { it.eventId }
    }

    /** iOS `signedEventImages`: a failed signature keeps the image with a null URL (placeholder shown). */
    suspend fun signed(records: List<EventImageRecord>): List<EventImage> = coroutineScope {
        records.sortedBy { it.position }.map { record ->
            async {
                val url = runCatching { signedUrl(record.storagePath) }.getOrNull()
                EventImage(record.id, record.storagePath, record.position, url, record.width, record.height)
            }
        }.awaitAll()
    }

    suspend fun signedUrl(storagePath: String): String =
        client.storage.from(ListingImageStoragePath.BUCKET).createSignedUrl(storagePath, SIGNED_URL_SECONDS.seconds)

    /** iOS `uploadListingImage(_:eventID:userID:position:)`. Position is 1-based. */
    suspend fun uploadListingImage(photo: ListingPhotoUpload, eventId: String, userId: String, position: Int) {
        val path = ListingImageStoragePath.make(userId, eventId, UUID.randomUUID().toString())
        client.storage.from(ListingImageStoragePath.BUCKET).upload(path, photo.data) {
            upsert = false
            contentType = ContentType.parse(photo.mimeType)
        }
        client.from("event_images").insert(
            EventImageInsert(
                eventId = eventId.lowercase(),
                storagePath = path,
                position = position,
                mimeType = photo.mimeType,
                byteSize = photo.byteSize,
                width = photo.width,
                height = photo.height,
            ),
        )
    }

    companion object {
        const val SIGNED_URL_SECONDS = 3600
    }
}
