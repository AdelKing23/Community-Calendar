package com.atlasdigital.coastcalendar.feature.organisation

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.model.BusinessAccountState
import com.atlasdigital.coastcalendar.data.model.BusinessProfileStatus
import com.atlasdigital.coastcalendar.data.model.OrganisationDraft
import com.atlasdigital.coastcalendar.data.model.OrganisationStatusCopy
import com.atlasdigital.coastcalendar.data.model.OrganisationType
import com.atlasdigital.coastcalendar.data.remote.ErrorMessages
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.feature.mylistings.PushedScaffold
import com.atlasdigital.coastcalendar.ui.components.LoadingCard
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class OrganisationState(
    val loading: Boolean = true,
    val account: BusinessAccountState = BusinessAccountState.Empty,
    val draft: OrganisationDraft = OrganisationDraft(),
    val saving: Boolean = false,
    val message: String? = null,
    val error: String? = null,
    val page: com.atlasdigital.coastcalendar.data.model.PublicPageDraft = com.atlasdigital.coastcalendar.data.model.PublicPageDraft(),
    val pendingHero: ByteArray? = null,
    val pendingAvatar: ByteArray? = null,
    val pageSaving: Boolean = false,
    val pageMessage: String? = null,
    val pageError: String? = null,
)

/** Owner Organisation status + application form (`my_business_profile` / `save_my_business_profile`). */
class OrganisationViewModel(private val container: AppContainer) : ViewModel() {
    private val _state = MutableStateFlow(OrganisationState())
    val state = _state.asStateFlow()
    private var session: UserSession? = null

    fun imageUrl(path: String?) = container.members.memberImageUrl(path)

    fun bind(session: UserSession?) {
        this.session = session
        if (session == null) { _state.value = OrganisationState(loading = false); return }
        _state.update { it.copy(loading = true) }
        viewModelScope.launch {
            val account = runCatching { container.account.businessAccount(session.userId) }.getOrDefault(BusinessAccountState.Empty)
            val draft = account.profile?.let(OrganisationDraft::from)
                ?: OrganisationDraft(contactName = session.fullName.orEmpty(), email = session.email)
            val page = account.profile?.id?.let { id -> runCatching { container.members.ownPublicPage(id) }.getOrNull() }
            val pageDraft = com.atlasdigital.coastcalendar.data.model.PublicPageDraft.prefill(
                page?.let(com.atlasdigital.coastcalendar.data.model.PublicPageDraft::from) ?: com.atlasdigital.coastcalendar.data.model.PublicPageDraft(),
                draft,
            )
            _state.update { it.copy(loading = false, account = account, draft = draft, page = pageDraft) }
        }
    }

    fun editPage(t: (com.atlasdigital.coastcalendar.data.model.PublicPageDraft) -> com.atlasdigital.coastcalendar.data.model.PublicPageDraft) =
        _state.update { it.copy(page = t(it.page), pageError = null, pageMessage = null) }

    /** iOS member photo: ≤ 1800 px, JPEG 0.82, kept on the device until Save. */
    fun pickImage(uri: android.net.Uri, kind: String) {
        viewModelScope.launch {
            val photo = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                runCatching {
                    com.atlasdigital.coastcalendar.core.image.ListingPhotoCompressor.compress(
                        container.appContext.contentResolver, uri,
                        com.atlasdigital.coastcalendar.core.image.ListingPhotoCompressor.MEMBER_MAX_DIMENSION,
                        com.atlasdigital.coastcalendar.core.image.ListingPhotoCompressor.MEMBER_JPEG_QUALITY,
                    )
                }.getOrNull()
            }
            when {
                photo == null -> _state.update { it.copy(pageError = "That image could not be loaded. Please choose another photo.") }
                photo.data.size > com.atlasdigital.coastcalendar.data.model.MemberImagePath.MAX_BYTES ->
                    _state.update { it.copy(pageError = "That image is larger than 5 MB after resizing. Please choose another photo.") }
                kind == "avatar" -> _state.update { it.copy(pendingAvatar = photo.data, pageError = null) }
                else -> _state.update { it.copy(pendingHero = photo.data, pageError = null) }
            }
        }
    }

    /** iOS `finishHomePageSetup`: upload pending images, save the public page, confirm contact; clean up uploads on failure. */
    fun savePage() {
        val s = _state.value
        val profile = s.account.profile ?: return
        val user = session ?: return
        if (s.pageSaving) return
        if (s.page.problems.isNotEmpty()) {
            _state.update { it.copy(pageError = "Add a public name and location, then check any optional contact details before saving.") }
            return
        }
        _state.update { it.copy(pageSaving = true, pageError = null, pageMessage = null) }
        viewModelScope.launch {
            val uploaded = mutableListOf<String>()
            try {
                var draft = s.page
                s.pendingHero?.let { bytes -> container.members.uploadMemberImage(bytes, "hero", user.userId).also { uploaded += it; draft = draft.copy(heroImagePath = it) } }
                s.pendingAvatar?.let { bytes -> container.members.uploadMemberImage(bytes, "avatar", user.userId).also { uploaded += it; draft = draft.copy(avatarImagePath = it) } }
                val saved = container.members.savePublicPage(profile.id, draft)
                _state.update {
                    it.copy(
                        pageSaving = false, pendingHero = null, pendingAvatar = null,
                        page = com.atlasdigital.coastcalendar.data.model.PublicPageDraft.from(saved),
                        pageMessage = if (saved.publishedAt == null) "Your public page details are saved and confirmed. Publication remains server-controlled."
                        else "Your public page details are saved.",
                    )
                }
            } catch (e: Exception) {
                uploaded.forEach { runCatching { container.members.deleteMemberImage(it) } }
                _state.update { it.copy(pageSaving = false, pageError = "Your public page could not be saved. Your edits are still here so you can try again. (${ErrorMessages.userFacing(e)})") }
            }
        }
    }

    fun edit(t: (OrganisationDraft) -> OrganisationDraft) = _state.update { it.copy(draft = t(it.draft), error = null, message = null) }

    fun save() {
        val s = _state.value
        if (!s.draft.canSubmit) { _state.update { it.copy(error = "Add the organisation name, type, contact name and a usable contact email.") }; return }
        if (s.saving) return
        _state.update { it.copy(saving = true, error = null, message = null) }
        viewModelScope.launch {
            try {
                val saved = container.members.saveOrganisation(s.draft)
                val sent = s.account.profile == null
                _state.update {
                    it.copy(
                        saving = false,
                        account = it.account.copy(profile = saved),
                        draft = OrganisationDraft.from(saved),
                        message = if (sent) "Application sent. Support will review ${saved.businessName}." else "Organisation details saved.",
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(saving = false, error = ErrorMessages.userFacing(e)) }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OrganisationScreen(viewModel: OrganisationViewModel, session: UserSession?, onBack: () -> Unit, onSignIn: () -> Unit, onOpenPage: (String) -> Unit) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(session?.userId) { viewModel.bind(session) }
    val d = state.draft
    PushedScaffold("Organisation", onBack) { padding ->
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (session == null) {
                PccCard {
                    Text("Register your Organisation", style = MaterialTheme.typography.headlineSmall)
                    Text("Sign in first, then apply for an Organisation page. Support reviews each application.")
                    PrimaryButton("Sign in", onSignIn)
                }
                return@Column
            }
            if (state.loading) { LoadingCard("Loading Organisation"); return@Column }
            PccCard {
                Text(OrganisationStatusCopy.title(state.account), style = MaterialTheme.typography.headlineSmall)
                Text(OrganisationStatusCopy.message(state.account))
                state.account.profile?.supportNote?.takeIf { it.isNotBlank() }?.let { Text("Support: $it", color = PccColors.LeafGreen) }
                val profile = state.account.profile
                if (profile != null && profile.memberStatus == BusinessProfileStatus.Approved) {
                    OutlinedButton(onClick = { onOpenPage(profile.id) }, modifier = Modifier.fillMaxWidth()) { Text("Open Organisation page") }
                }
            }
            PccCard {
                Text("Organisation details", style = MaterialTheme.typography.titleLarge)
                OutlinedTextField(d.name, { v -> viewModel.edit { it.copy(name = v) } }, label = { Text("Organisation name *") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                var open by remember { mutableStateOf(false) }
                ExposedDropdownMenuBox(expanded = open, onExpandedChange = { open = it }) {
                    OutlinedTextField(
                        value = d.type?.title ?: "",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Organisation type *") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(open) },
                        modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
                    )
                    ExposedDropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                        OrganisationType.entries.forEach { t ->
                            DropdownMenuItem(text = { Text(t.title) }, onClick = { viewModel.edit { it.copy(type = t) }; open = false })
                        }
                    }
                }
                OutlinedTextField(d.contactName, { v -> viewModel.edit { it.copy(contactName = v) } }, label = { Text("Contact name *") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(d.email, { v -> viewModel.edit { it.copy(email = v) } }, label = { Text("Contact email *") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth())
                OutlinedTextField(d.phone, { v -> viewModel.edit { it.copy(phone = v) } }, label = { Text("Phone") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), modifier = Modifier.fillMaxWidth())
                OutlinedTextField(d.address, { v -> viewModel.edit { it.copy(address = v) } }, label = { Text("Address") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(d.website, { v -> viewModel.edit { it.copy(website = v) } }, label = { Text("Website") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(d.about, { v -> viewModel.edit { it.copy(about = v) } }, label = { Text("About") }, minLines = 4, modifier = Modifier.fillMaxWidth())
                Text("Contact details here are private to Support. Public page details are confirmed separately.", style = MaterialTheme.typography.bodyMedium)
            }
            PlanChoiceCard(d.selectedPlanId) { id -> viewModel.edit { it.copy(selectedPlanId = id) } }
            state.message?.let { Text(it, color = PccColors.LeafGreen, fontWeight = FontWeight.Bold) }
            state.error?.let { Text(it, color = PccColors.PohutukawaRed) }
            // t253: a suspended Organisation can't change anything until Support unsuspends it (the server refuses too).
            val suspended = state.account.profile?.memberStatus == BusinessProfileStatus.Suspended
            if (suspended) {
                Text(com.atlasdigital.coastcalendar.data.model.OrganisationSuspended.MESSAGE, color = PccColors.PohutukawaRed, fontWeight = FontWeight.Bold)
            } else {
                PrimaryButton(
                    if (state.saving) "Saving" else if (state.account.profile == null) "Send Application" else "Save Details",
                    viewModel::save,
                    enabled = !state.saving,
                )
                if (state.account.profile != null) PublicPageCard(viewModel, state)
            }
        }
    }
}


/** iOS plan list (same ids). No prices or payment here: member access is switched on separately. */
@Composable
private fun PlanChoiceCard(selectedId: String, onSelect: (String) -> Unit) {
    PccCard {
        Text("Plan", style = MaterialTheme.typography.titleLarge)
        Text("Choose the plan that fits how often you post. Support sees your choice with the application; member access is switched on separately.",
            style = MaterialTheme.typography.bodyMedium)
        com.atlasdigital.coastcalendar.data.model.MemberPlan.entries.forEach { plan ->
            val selected = plan.id == selectedId
            Column(
                Modifier.fillMaxWidth().clip(com.atlasdigital.coastcalendar.ui.theme.PccShapes.Small)
                    .background(if (selected) PccColors.LeafGreen.copy(alpha = 0.08f) else androidx.compose.ui.graphics.Color.White.copy(alpha = 0.74f))
                    .border(1.5.dp, if (selected) PccColors.LeafGreen.copy(alpha = 0.45f) else androidx.compose.ui.graphics.Color.Transparent, com.atlasdigital.coastcalendar.ui.theme.PccShapes.Small)
                    .clickable { onSelect(plan.id) }
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                androidx.compose.foundation.layout.Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(plan.title, style = MaterialTheme.typography.titleMedium, color = PccColors.Ink, fontWeight = FontWeight.Black)
                        Text(plan.audience, style = MaterialTheme.typography.labelMedium)
                    }
                    androidx.compose.material3.RadioButton(selected = selected, onClick = { onSelect(plan.id) })
                }
                plan.inclusions.forEach { Text("✓  $it", style = MaterialTheme.typography.bodySmall) }
            }
        }
    }
}

/** iOS member home page editor: public name, area, bio, public contact details, hero + avatar images (`member-images`). */
@Composable
private fun PublicPageCard(viewModel: OrganisationViewModel, state: OrganisationState) {
    val p = state.page
    val heroPicker = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia(),
    ) { uri -> if (uri != null) viewModel.pickImage(uri, "hero") }
    val avatarPicker = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia(),
    ) { uri -> if (uri != null) viewModel.pickImage(uri, "avatar") }
    val imageOnly = androidx.activity.result.PickVisualMediaRequest(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly)
    PccCard {
        Text("Public page", style = MaterialTheme.typography.titleLarge)
        Text("What people see on your Organisation page. Images are optional.", style = MaterialTheme.typography.bodyMedium)
        ImageSlot("Cover image", state.pendingHero, viewModel.imageUrl(p.heroImagePath), 150.dp) { heroPicker.launch(imageOnly) }
        ImageSlot("Profile image", state.pendingAvatar, viewModel.imageUrl(p.avatarImagePath), 96.dp) { avatarPicker.launch(imageOnly) }
        OutlinedTextField(p.displayName, { v -> viewModel.editPage { it.copy(displayName = v) } }, label = { Text("Public name *") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(p.bio, { v -> viewModel.editPage { it.copy(bio = v) } }, label = { Text("About") }, minLines = 3, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(p.contactName, { v -> viewModel.editPage { it.copy(contactName = v) } }, label = { Text("Public contact name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(p.contactEmail, { v -> viewModel.editPage { it.copy(contactEmail = v) } }, label = { Text("Public contact email") }, singleLine = true,
            isError = "contactEmail" in p.problems, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth())
        OutlinedTextField(p.phone, { v -> viewModel.editPage { it.copy(phone = v) } }, label = { Text("Public phone") }, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), modifier = Modifier.fillMaxWidth())
        OutlinedTextField(p.locationText, { v -> viewModel.editPage { it.copy(locationText = v) } }, label = { Text("Location") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(p.address, { v -> viewModel.editPage { it.copy(address = v) } }, label = { Text("Public address") }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(p.website, { v -> viewModel.editPage { it.copy(website = v) } }, label = { Text("Website") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        state.pageMessage?.let { Text(it, color = PccColors.LeafGreen, fontWeight = FontWeight.Bold) }
        state.pageError?.let { Text(it, color = PccColors.PohutukawaRed) }
        PrimaryButton(if (state.pageSaving) "Saving" else "Save public page", viewModel::savePage, enabled = !state.pageSaving)
    }
}

@Composable
private fun ImageSlot(title: String, pending: ByteArray?, url: String?, height: androidx.compose.ui.unit.Dp, onPick: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Black, color = PccColors.Ink)
        val model: Any? = pending ?: url
        if (model != null) {
            coil3.compose.AsyncImage(
                model = model, contentDescription = title, contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().height(height).clip(com.atlasdigital.coastcalendar.ui.theme.PccShapes.Small),
            )
        }
        OutlinedButton(onClick = onPick, modifier = Modifier.fillMaxWidth()) { Text(if (model == null) "Choose image" else "Replace image") }
    }
}
