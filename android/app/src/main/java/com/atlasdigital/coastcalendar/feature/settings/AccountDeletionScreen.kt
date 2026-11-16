package com.atlasdigital.coastcalendar.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.remote.ErrorMessages
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.feature.mylistings.PushedScaffold
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class DeletionState(
    val note: String = "",
    val submitting: Boolean = false,
    val didSubmit: Boolean = false,
    val message: String? = null,
)

/** Same contract as iOS `submitAccountDeletionRequest`: RPC `submit_support_request` with topic "Account deletion". */
object AccountDeletionRequest {
    const val TOPIC = "Account deletion"

    fun message(email: String?, note: String): String = listOf(
        "Account deletion requested from Android Account settings.",
        "Signed-in email: ${email ?: "No email available"}",
        "User note: ${note.trim().ifEmpty { "No extra note supplied." }}",
        "Please delete the account record and personal account data that Coast Calendar is not legally required to retain.",
    ).joinToString("\n\n")
}

class AccountDeletionViewModel(private val container: AppContainer) : ViewModel() {
    private val _state = MutableStateFlow(DeletionState())
    val state = _state.asStateFlow()

    fun setNote(v: String) = _state.update { it.copy(note = v.take(2000)) }

    fun submit(session: UserSession) {
        if (_state.value.submitting || _state.value.didSubmit) return
        _state.update { it.copy(submitting = true, message = null) }
        viewModelScope.launch {
            try {
                container.supportRequests.submitRaw(AccountDeletionRequest.TOPIC, AccountDeletionRequest.message(session.email, _state.value.note), null)
                _state.update {
                    it.copy(
                        submitting = false, didSubmit = true,
                        message = "Support has received your account deletion request. You can sign out now; Support will confirm once the account deletion is complete.",
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(submitting = false, message = ErrorMessages.userFacing(e)) }
            }
        }
    }
}

/** iOS `AccountDeletionRequestScreen` (Delete Account), plus a confirmation dialog before sending. */
@Composable
fun AccountDeletionScreen(viewModel: AccountDeletionViewModel, session: UserSession?, onBack: () -> Unit, onSignIn: () -> Unit) {
    val state by viewModel.state.collectAsState()
    var confirm by remember { mutableStateOf(false) }
    PushedScaffold("Delete Account", onBack) { padding ->
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            PccCard {
                Text("ACCOUNT CONTROL", style = MaterialTheme.typography.labelMedium, color = PccColors.PohutukawaRed, fontWeight = FontWeight.Black)
                Text("Request account deletion", style = MaterialTheme.typography.headlineSmall)
                Text("This starts deletion of your Coast Calendar account and personal account details. Support will confirm the request and complete deletion of data we are not legally required to keep.")
            }
            if (session == null) {
                PccCard {
                    Text("Sign in first", style = MaterialTheme.typography.titleMedium)
                    Text("Sign in to the account you want deleted, then send the request from here.")
                    PrimaryButton("Sign in", onSignIn)
                }
                return@Column
            }
            PccCard {
                Text("Request details", style = MaterialTheme.typography.titleMedium)
                Text("Signed-in account: ${session.email}")
                OutlinedTextField(
                    state.note, viewModel::setNote, label = { Text("Optional note") }, minLines = 4,
                    enabled = !state.didSubmit, modifier = Modifier.fillMaxWidth(),
                )
            }
            state.message?.let {
                PccCard {
                    Text(if (state.didSubmit) "Request sent" else "Could not send request", style = MaterialTheme.typography.titleMedium,
                        color = if (state.didSubmit) PccColors.LeafGreen else PccColors.PohutukawaRed)
                    Text(it)
                }
            }
            PrimaryButton(
                when { state.submitting -> "Sending request"; state.didSubmit -> "Request sent"; else -> "Send deletion request" },
                { confirm = true },
                enabled = !state.submitting && !state.didSubmit,
            )
        }
    }
    if (confirm && session != null) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("Send deletion request?") },
            text = { Text("Support will be asked to delete this account (${session.email}). Nothing is removed straight away; Support confirms first.") },
            confirmButton = { TextButton(onClick = { confirm = false; viewModel.submit(session) }) { Text("Send request", color = PccColors.PohutukawaRed, fontWeight = FontWeight.Black) } },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Cancel") } },
        )
    }
}
