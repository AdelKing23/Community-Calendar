package com.atlasdigital.coastcalendar.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.model.SupportRequestRecord
import com.atlasdigital.coastcalendar.data.model.SupportTopic
import com.atlasdigital.coastcalendar.data.remote.ErrorMessages
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.feature.mylistings.PushedScaffold
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccShapes
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ContactState(
    val topic: SupportTopic = SupportTopic.Listing,
    val reference: String = "",
    val message: String = "",
    val sending: Boolean = false,
    val sentId: String? = null,
    val error: String? = null,
    val mine: List<SupportRequestRecord> = emptyList(),
)

class ContactSupportViewModel(private val container: AppContainer) : ViewModel() {
    private val _state = MutableStateFlow(ContactState())
    val state = _state.asStateFlow()
    private var session: UserSession? = null

    fun bind(s: UserSession?) { session = s; loadMine() }
    fun update(t: (ContactState) -> ContactState) = _state.update(t)

    private fun loadMine() {
        val user = session ?: return
        viewModelScope.launch {
            runCatching { container.supportRequests.mine(user.userId) }.onSuccess { r -> _state.update { it.copy(mine = r) } }
        }
    }

    fun send() {
        val s = _state.value
        if (session == null || s.message.isBlank() || s.sending) return
        _state.update { it.copy(sending = true, error = null, sentId = null) }
        viewModelScope.launch {
            try {
                val id = container.supportRequests.submit(s.topic, s.message, s.reference)
                _state.update { it.copy(sending = false, sentId = id, message = "", reference = "") }
                loadMine()
            } catch (e: Exception) {
                _state.update { it.copy(sending = false, error = ErrorMessages.userFacing(e)) }
            }
        }
    }
}

/** iOS `ContactSupportScreen` (topics without the payment option on Android). */
@Composable
fun ContactSupportScreen(viewModel: ContactSupportViewModel, session: UserSession?, onBack: () -> Unit, onSignIn: () -> Unit) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(session?.userId) { viewModel.bind(session) }
    PushedScaffold("Contact Support", onBack) { padding ->
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            PccCard {
                Text("Contact Support", style = MaterialTheme.typography.headlineSmall)
                Text("Send a private request to Support. Your message is attached to your app account so we can follow up without showing a personal email in the app.")
            }
            if (session == null) {
                PccCard {
                    Text("Sign in so Support can reply through your app account.", fontWeight = FontWeight.Bold)
                    PrimaryButton("Sign in", onSignIn)
                }
                return@Column
            }
            PccCard {
                Text("Topic", style = MaterialTheme.typography.labelMedium)
                androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SupportTopic.entries.forEach { t ->
                        androidx.compose.material3.FilterChip(
                            selected = state.topic == t,
                            onClick = { viewModel.update { it.copy(topic = t) } },
                            label = { Text(t.raw) },
                        )
                    }
                }
                OutlinedTextField(state.reference, { v -> viewModel.update { it.copy(reference = v) } }, label = { Text("Listing reference") }, placeholder = { Text("Optional") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(state.message, { v -> viewModel.update { it.copy(message = v) } }, label = { Text("Message") }, minLines = 5, modifier = Modifier.fillMaxWidth())
            }
            state.sentId?.let { Text("Support request sent. Reference ${it.take(8).uppercase()}.", color = PccColors.LeafGreen, fontWeight = FontWeight.Bold) }
            state.error?.let { Text(it, color = PccColors.PohutukawaRed) }
            PrimaryButton(if (state.sending) "Sending" else "Send Support Request", viewModel::send, enabled = !state.sending && state.message.isNotBlank())
            if (state.mine.isNotEmpty()) {
                PccCard {
                    Text("Your Requests", style = MaterialTheme.typography.titleLarge)
                    state.mine.forEach { r ->
                        Column(Modifier.fillMaxWidth().clip(PccShapes.Small).background(Color.White.copy(alpha = 0.7f)).padding(10.dp)) {
                            Text("${r.topic} · ${r.requestStatus.label}", fontWeight = FontWeight.Bold, color = PccColors.Ink)
                            Text(r.message, maxLines = 3)
                            r.supportNote?.takeIf { it.isNotBlank() }?.let { Text("Support: $it", color = PccColors.LeafGreen) }
                        }
                    }
                }
            }
        }
    }
}
