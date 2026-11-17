package com.atlasdigital.coastcalendar.data.remote

import io.github.jan.supabase.auth.exception.AuthRestException
import io.github.jan.supabase.exceptions.HttpRequestException
import io.github.jan.supabase.exceptions.RestException

/** Short, user-facing messages (iOS `pccUserFacingMessage` / `translatedPostgRESTMessage`, simplified). */
object ErrorMessages {
    fun userFacing(error: Throwable): String {
        val raw = (error.message ?: "").lowercase()
        return when {
            error is HttpRequestException -> "We couldn’t reach Coast Calendar. Check your connection and try again."
            error is AuthRestException && raw.contains("invalid login") -> "That email and password don’t match. Check them and try again."
            error is AuthRestException && raw.contains("email not confirmed") -> "Confirm your email first. We can send the link again."
            error is AuthRestException && raw.contains("already registered") -> "An account already uses that email. Sign in instead."
            // Server-side suspension enforcement (t253): any refusal that names suspension.
            raw.contains("suspended") -> com.atlasdigital.coastcalendar.data.model.OrganisationSuspended.MESSAGE
            raw.contains("allowance") || raw.contains("listing limit") ->
                "Your plan’s listing allowance is used up for this period."
            raw.contains("subscription") -> "Member access must be active before this Organisation can create listings."
            raw.contains("row-level security") -> "This account can’t do that yet. Refresh your Organisation status and try again."
            error is RestException -> "Something went wrong on our side. Please try again soon."
            else -> "Please try again soon."
        }
    }
}
