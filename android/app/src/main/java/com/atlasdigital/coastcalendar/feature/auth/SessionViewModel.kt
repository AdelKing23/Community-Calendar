package com.atlasdigital.coastcalendar.feature.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.remote.ErrorMessages
import com.atlasdigital.coastcalendar.data.repository.AuthState
import com.atlasdigital.coastcalendar.feature.welcome.WelcomeCopy
import com.atlasdigital.coastcalendar.feature.welcome.WelcomeGate
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class AuthFormState(
    val busy: Boolean = false,
    val error: String? = null,
    val info: String? = null,
)

/** App-wide session: auth state, the auth form actions, and the per-account welcome. */
class SessionViewModel(private val container: AppContainer) : ViewModel() {
    val authState: StateFlow<AuthState> =
        if (container.isConfigured) {
            container.auth.state.stateIn(viewModelScope, SharingStarted.Eagerly, AuthState.Loading)
        } else {
            MutableStateFlow<AuthState>(AuthState.SignedOut).asStateFlow()
        }

    private val _form = MutableStateFlow(AuthFormState())
    val form: StateFlow<AuthFormState> = _form.asStateFlow()

    private val _showWelcome = MutableStateFlow(false)
    val showWelcome: StateFlow<Boolean> = _showWelcome.asStateFlow()

    init {
        viewModelScope.launch {
            authState.distinctUntilChanged { a, b -> a::class == b::class && (a as? AuthState.SignedIn)?.session?.userId == (b as? AuthState.SignedIn)?.session?.userId }
                .collect { evaluateWelcome(it) }
        }
    }

    private suspend fun evaluateWelcome(state: AuthState) {
        val prefs = container.prefs
        _showWelcome.value = when (state) {
            AuthState.Loading -> false
            AuthState.SignedOut -> WelcomeGate.shouldShow(false, WelcomeGate.ServerCheck.Failed, false, prefs.signedOutWelcomeDismissed)
            is AuthState.SignedIn -> {
                val userId = state.session.userId.lowercase()
                val server = runCatching { container.welcome.hasDismissed(userId, WelcomeCopy.VERSION) }
                    .fold({ if (it) WelcomeGate.ServerCheck.Dismissed else WelcomeGate.ServerCheck.NotDismissed }, { WelcomeGate.ServerCheck.Failed })
                val onDevice = userId in WelcomeGate.accounts(prefs.welcomeDismissedAccounts)
                WelcomeGate.shouldShow(true, server, onDevice, prefs.signedOutWelcomeDismissed)
            }
        }
    }

    /** Settings → Show welcome (re-open; dismissing again is idempotent). */
    fun showWelcomeAgain() { _showWelcome.value = true }

    fun dismissWelcome() {
        _showWelcome.value = false
        val state = authState.value
        if (state is AuthState.SignedIn) {
            val userId = state.session.userId.lowercase()
            container.prefs.welcomeDismissedAccounts = WelcomeGate.adding(userId, container.prefs.welcomeDismissedAccounts)
            viewModelScope.launch { runCatching { container.welcome.recordDismissed(userId, WelcomeCopy.VERSION) } }
        } else {
            container.prefs.signedOutWelcomeDismissed = true
        }
    }

    fun clearMessages() = _form.update { it.copy(error = null, info = null) }

    fun signIn(email: String, password: String, onDone: () -> Unit) = run {
        if (!email.contains("@") || password.isEmpty()) {
            _form.value = AuthFormState(error = "Enter your email and password.")
            return@run
        }
        launchForm(onDone) { container.auth.signIn(email, password); null }
    }

    fun signUp(name: String, email: String, password: String, onDone: () -> Unit) = run {
        // iOS Settings rules: name at least 2 characters, password at least 6.
        if (name.trim().length < 2) {
            _form.value = AuthFormState(error = "Enter your name (at least 2 characters).")
            return@run
        }
        if (!email.contains("@") || password.length < 6) {
            _form.value = AuthFormState(error = "Password must be at least 6 characters.")
            return@run
        }
        launchForm(onDone) {
            container.auth.signUp(name, email, password)
            "Check your email to confirm your account, then sign in."
        }
    }

    fun forgotPassword(email: String) = run {
        if (!email.contains("@")) {
            _form.value = AuthFormState(error = "Enter your email first, then tap Forgot password.")
            return@run
        }
        launchForm(null) {
            container.auth.sendPasswordReset(email)
            "If an account uses that email, a reset link is on its way."
        }
    }

    fun resendVerification(email: String) = launchForm(null) {
        container.auth.resendVerification(email)
        "Verification email sent again."
    }

    fun refreshUser() = viewModelScope.launch { container.auth.refreshUser() }

    fun signOut() = viewModelScope.launch { runCatching { container.auth.signOut() } }

    private fun launchForm(onDone: (() -> Unit)?, block: suspend () -> String?) {
        if (!container.isConfigured) {
            _form.value = AuthFormState(error = "This build has no Supabase configuration. Add it to local.properties.")
            return
        }
        _form.value = AuthFormState(busy = true)
        viewModelScope.launch {
            try {
                val info = block()
                _form.value = AuthFormState(info = info)
                onDone?.invoke()
            } catch (e: Exception) {
                _form.value = AuthFormState(error = ErrorMessages.userFacing(e))
            }
        }
    }
}
