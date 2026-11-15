package com.atlasdigital.coastcalendar.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.auth.user.UserInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** Signed-in user as the app sees it (iOS `UserSession`). */
data class UserSession(
    val userId: String,
    val email: String,
    val isEmailVerified: Boolean,
    val fullName: String?,
) {
    /** iOS `greetingName`: first word of the full name. */
    val greetingName: String? get() = fullName?.trim()?.split(" ")?.firstOrNull()?.takeIf { it.isNotEmpty() }
}

sealed interface AuthState {
    data object Loading : AuthState
    data object SignedOut : AuthState
    data class SignedIn(val session: UserSession) : AuthState
}

/** Email + password auth, same endpoints as iOS `UserAuthService`: token?grant_type=password, signup (full_name), recover, resend. */
class AuthRepository(private val client: SupabaseClient) {
    val state: Flow<AuthState> = client.auth.sessionStatus.map { status ->
        when (status) {
            is SessionStatus.Authenticated -> status.session.user?.let { AuthState.SignedIn(it.toSession()) } ?: AuthState.SignedOut
            is SessionStatus.Initializing -> AuthState.Loading
            else -> AuthState.SignedOut
        }
    }

    fun currentSession(): UserSession? = client.auth.currentUserOrNull()?.toSession()

    suspend fun signIn(email: String, password: String) {
        client.auth.signInWith(Email) {
            this.email = email.trim()
            this.password = password
        }
    }

    suspend fun signUp(fullName: String, email: String, password: String) {
        client.auth.signUpWith(Email) {
            this.email = email.trim()
            this.password = password
            val name = fullName.trim()
            if (name.isNotEmpty()) data = buildJsonObject { put("full_name", name) }
        }
    }

    suspend fun sendPasswordReset(email: String) = client.auth.resetPasswordForEmail(email.trim())

    suspend fun resendVerification(email: String) = client.auth.resendEmail(OtpType.Email.SIGNUP, email.trim())

    /** Reloads the user from /auth/v1/user (iOS "Refresh status" after confirming email). */
    suspend fun refreshUser(): UserSession? = runCatching {
        client.auth.refreshCurrentSession()
        client.auth.currentUserOrNull()?.toSession()
    }.getOrNull()

    suspend fun signOut() = client.auth.signOut()

    private fun UserInfo.toSession() = UserSession(
        userId = id,
        email = email.orEmpty(),
        isEmailVerified = emailConfirmedAt != null,
        fullName = userMetadata?.get("full_name")?.jsonPrimitive?.content,
    )
}
