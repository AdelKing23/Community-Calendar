package com.atlasdigital.coastcalendar.feature.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccScreenBackground

/** Email/password sign in, create account (with name) and forgot password — same flows as iOS Account. */
@Composable
fun AuthScreen(session: SessionViewModel, onSignedIn: () -> Unit, onBack: (() -> Unit)? = null) {
    val form by session.form.collectAsState()
    var createMode by rememberSaveable { mutableStateOf(false) }
    var name by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }

    PccScreenBackground {
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (onBack != null) TextButton(onClick = onBack) { Text("Back") }
            Text(if (createMode) "Create account" else "Sign in", style = MaterialTheme.typography.headlineMedium)
            Text("Free, quick, and keeps local listings accountable.", style = MaterialTheme.typography.bodyMedium)
            PccCard {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    SegmentedButton(selected = !createMode, onClick = { createMode = false; session.clearMessages() }, shape = SegmentedButtonDefaults.itemShape(0, 2)) { Text("Sign in") }
                    SegmentedButton(selected = createMode, onClick = { createMode = true; session.clearMessages() }, shape = SegmentedButtonDefaults.itemShape(1, 2)) { Text("Create account") }
                }
                if (createMode) {
                    OutlinedTextField(name, { name = it }, label = { Text("Full name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                }
                OutlinedTextField(
                    email, { email = it }, label = { Text("Email") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                )
                OutlinedTextField(
                    password, { password = it }, label = { Text("Password") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                )
                form.error?.let { Text(it, color = PccColors.PohutukawaRed, style = MaterialTheme.typography.bodyMedium) }
                form.info?.let { Text(it, color = PccColors.LeafGreen, style = MaterialTheme.typography.bodyMedium) }
                PrimaryButton(
                    text = if (form.busy) "Please wait…" else if (createMode) "Create account" else "Sign in",
                    enabled = !form.busy,
                    onClick = {
                        if (createMode) session.signUp(name, email, password) { createMode = false }
                        else session.signIn(email, password, onSignedIn)
                    },
                )
                if (!createMode) {
                    TextButton(onClick = { session.forgotPassword(email) }, enabled = !form.busy) { Text("Forgot password?") }
                }
            }
        }
    }
}
