package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.data.model.BusinessProfileRecord
import com.atlasdigital.coastcalendar.data.model.MemberFollowUpsert
import com.atlasdigital.coastcalendar.data.model.MemberNoticeInsert
import com.atlasdigital.coastcalendar.data.model.MemberNoticeRecord
import com.atlasdigital.coastcalendar.data.model.NoticeReadInsert
import com.atlasdigital.coastcalendar.data.model.OrganisationDraft
import com.atlasdigital.coastcalendar.data.model.PublicMemberProfileRecord
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import io.github.jan.supabase.storage.storage
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * Organisation contracts from iOS `SupabaseEventService`: host directory, Belong (`member_follows`),
 * Notices (`member_notices` + `notice_reads`) and the owner's `save_my_business_profile` RPC.
 */
class MemberRepository(private val client: SupabaseClient) {
    suspend fun approvedProfiles(): List<PublicMemberProfileRecord> =
        client.from("public_host_directory").select(Columns.raw(PublicMemberProfileRecord.SELECT)) {
            filter { filterNot("published_at", FilterOperator.IS, "null") }
            order("display_name", Order.ASCENDING)
        }.decodeList<PublicMemberProfileRecord>()

    suspend fun isFollowing(profileId: String, userId: String): Boolean =
        client.from("member_follows").select(Columns.list("id")) {
            filter {
                eq("business_profile_id", profileId.lowercase())
                eq("user_id", userId.lowercase())
            }
            limit(1)
        }.data.trim().let { it != "[]" && it.isNotEmpty() }

    suspend fun setFollowing(profileId: String, userId: String, following: Boolean) {
        if (following) {
            client.from("member_follows").upsert(MemberFollowUpsert(userId.lowercase(), profileId.lowercase())) {
                onConflict = "user_id,business_profile_id"
            }
        } else {
            client.from("member_follows").delete {
                filter {
                    eq("business_profile_id", profileId.lowercase())
                    eq("user_id", userId.lowercase())
                }
            }
        }
    }

    /** Signed-out / non-owner readers only see published Notices (iOS adds status=eq.published without a token). */
    suspend fun notices(profileId: String, publishedOnly: Boolean): List<MemberNoticeRecord> =
        client.from("member_notices").select(Columns.raw(MemberNoticeRecord.SELECT)) {
            filter {
                eq("business_profile_id", profileId.lowercase())
                if (publishedOnly) eq("status", "published")
            }
            order("published_at", Order.DESCENDING, nullsFirst = false)
            order("created_at", Order.DESCENDING)
        }.decodeList<MemberNoticeRecord>()

    suspend fun noticeReads(): Set<String> =
        client.from("notice_reads").select(Columns.list("notice_id"))
            .decodeList<NoticeReadRow>().map { it.notice_id.lowercase() }.toSet()

    suspend fun markRead(noticeId: String, userId: String) {
        client.from("notice_reads").upsert(NoticeReadInsert(noticeId.lowercase(), userId.lowercase()))
    }

    /** Per-user dismiss (`member_notice_dismissals`, RLS: own rows only). */
    suspend fun dismissedNoticeIds(): Set<String> =
        client.from("member_notice_dismissals").select(Columns.list("notice_id"))
            .decodeList<NoticeReadRow>().map { it.notice_id.lowercase() }.toSet()

    suspend fun dismissNotice(noticeId: String, userId: String) {
        client.from("member_notice_dismissals").upsert(
            com.atlasdigital.coastcalendar.data.model.NoticeDismissalInsert(userId.lowercase(), noticeId.lowercase()),
        ) { onConflict = "user_id,notice_id"; ignoreDuplicates = true }
    }

    suspend fun undoDismissNotice(noticeId: String, userId: String) {
        client.from("member_notice_dismissals").delete {
            filter {
                eq("notice_id", noticeId.lowercase())
                eq("user_id", userId.lowercase())
            }
        }
    }

    suspend fun createNotice(profileId: String, ownerUserId: String, title: String, summary: String, body: String, days: Int = com.atlasdigital.coastcalendar.data.model.NoticeExpiry.DEFAULT_DAYS): MemberNoticeRecord =
        client.from("member_notices").insert(
            MemberNoticeInsert(
                businessProfileId = profileId.lowercase(),
                ownerUserId = ownerUserId.lowercase(),
                title = title.trim(),
                summary = summary.trim().ifEmpty { null },
                body = body.trim().ifEmpty { null },
                endsAt = com.atlasdigital.coastcalendar.core.time.NzTime.iso(com.atlasdigital.coastcalendar.data.model.NoticeExpiry.endsAt(days)),
            ),
        ) { select(Columns.raw(MemberNoticeRecord.SELECT)) }.decodeSingle<MemberNoticeRecord>()

    /** Owner read of their own public page draft (RLS lets the owner read unpublished rows). */
    suspend fun ownPublicPage(profileId: String): PublicMemberProfileRecord? =
        client.from("public_member_profiles").select(Columns.raw(PublicMemberProfileRecord.SELECT)) {
            filter { eq("id", profileId.lowercase()) }
            limit(1)
        }.decodeList<PublicMemberProfileRecord>().firstOrNull()

    suspend fun uploadMemberImage(bytes: ByteArray, kind: String, userId: String): String {
        require(bytes.size <= com.atlasdigital.coastcalendar.data.model.MemberImagePath.MAX_BYTES) { "That image is larger than 5 MB." }
        val path = com.atlasdigital.coastcalendar.data.model.MemberImagePath.make(userId, kind)
        client.storage.from(com.atlasdigital.coastcalendar.data.model.MemberImagePath.BUCKET).upload(path, bytes) {
            upsert = false
            contentType = io.ktor.http.ContentType.Image.JPEG
        }
        return path
    }

    suspend fun deleteMemberImage(path: String) {
        client.storage.from(com.atlasdigital.coastcalendar.data.model.MemberImagePath.BUCKET).delete(path)
    }

    fun memberImageUrl(path: String?): String? =
        path?.takeIf { it.isNotBlank() }?.let { client.storage.from(com.atlasdigital.coastcalendar.data.model.MemberImagePath.BUCKET).publicUrl(it) }

    /** iOS `saveOwnPublicProfileDraft` then `confirmOwnPublicContact`. */
    suspend fun savePublicPage(profileId: String, d: com.atlasdigital.coastcalendar.data.model.PublicPageDraft): PublicMemberProfileRecord {
        fun opt(v: String) = v.trim().ifEmpty { null }?.let(::JsonPrimitive) ?: JsonNull
        val saved = client.postgrest.rpc(
            "save_member_public_profile_with_images",
            buildJsonObject {
                put("p_business_profile_id", JsonPrimitive(profileId.lowercase()))
                put("p_display_name", JsonPrimitive(d.displayName.trim()))
                put("p_area_scope_id", JsonPrimitive(d.areaScopeId.trim()))
                put("p_bio", opt(d.bio))
                put("p_public_contact_name", opt(d.contactName))
                put("p_public_contact_email", opt(d.contactEmail))
                put("p_public_phone", opt(d.phone))
                put("p_public_location_text", opt(d.locationText))
                put("p_public_address", opt(d.address))
                put("p_public_website", opt(d.website))
                put("p_avatar_image_path", d.avatarImagePath?.let(::JsonPrimitive) ?: JsonNull)
                put("p_hero_image_path", d.heroImagePath?.let(::JsonPrimitive) ?: JsonNull)
                put("p_avatar_image_position_x", JsonPrimitive(d.positions[0]))
                put("p_avatar_image_position_y", JsonPrimitive(d.positions[1]))
                put("p_hero_image_position_x", JsonPrimitive(d.positions[2]))
                put("p_hero_image_position_y", JsonPrimitive(d.positions[3]))
            },
        ).decodeProfile()
        val revision = saved.publicContactRevision ?: return saved
        return client.postgrest.rpc(
            "confirm_member_public_contact",
            buildJsonObject {
                put("p_business_profile_id", JsonPrimitive(profileId.lowercase()))
                put("p_public_contact_revision", JsonPrimitive(revision))
            },
        ).decodeProfile()
    }

    private inline fun io.github.jan.supabase.postgrest.result.PostgrestResult.decodeProfile(): PublicMemberProfileRecord =
        runCatching { decodeAs<PublicMemberProfileRecord>() }.getOrNull() ?: decodeList<PublicMemberProfileRecord>().first()

    suspend fun saveOrganisation(draft: OrganisationDraft): BusinessProfileRecord {
        val params = buildJsonObject {
            draft.rpcParams().forEach { (k, v) ->
                put(k, when (v) {
                    null -> JsonNull
                    is Number -> JsonPrimitive(v)
                    else -> JsonPrimitive(v.toString())
                })
            }
        }
        val result = client.postgrest.rpc("save_my_business_profile", params)
        return runCatching { result.decodeSingle<BusinessProfileRecord>() }.getOrElse { result.decodeAs<BusinessProfileRecord>() }
    }

    @kotlinx.serialization.Serializable
    private data class NoticeReadRow(val notice_id: String)
}
