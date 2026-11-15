# Coast Calendar — Android (skeleton, t237)

Kotlin + Jetpack Compose (Material 3, light only) client for the **same Supabase backend** as iOS and web.
Status: project structure, architecture and first screens only. Not connected to Google Play, Firebase or any signing key.

## Build
1. Copy `local.properties.example` to `local.properties` (git-ignored). Set `sdk.dir` and the same
   `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` the iOS app uses (`Services/SupabaseConfiguration.swift`).
2. `./gradlew assembleDebug testDebugUnitTest` (JDK 17+; Android SDK platform 37).

Toolchain: AGP 9.3.3 (built-in Kotlin), Kotlin 2.4.21, Gradle 9.9.1, Compose BOM 2026.09.00,
supabase-kt 3.9.0 (auth-kt, postgrest-kt, functions-kt), Ktor 3.6 (OkHttp), kotlinx.serialization.
compileSdk 37, targetSdk 36, minSdk 26. applicationId `com.atlasdigital.coastcalendar`.

## Architecture
MVVM + repositories + manual DI (`core/di/AppContainer`), Navigation Compose with the iOS tabs
(Home · What's On · Create · Hosts · Settings).

```
core/      config (SupabaseConfig guard), di, prefs, time (NZ day bounds, poll window)
data/      model (records + domain, same column/RPC names as iOS), remote (client, errors), repository
billing/   BillingGateway — PLACEHOLDER, Play Billing not integrated
feature/   auth, home, whatson, create, welcome, settings (stub), hosts (stub)
ui/        theme (PCCTheme colours, #3A403E text), components, navigation
```

## Backend contracts mirrored from iOS
- Home / What's On: `published_event_location_targets` (location_slug = selected area, exact-area) →
  `public_events` (iOS select list; `end_at >= start of today`; order is_paid_push, is_featured, start_at) →
  `event_topics`. Unscoped `public_events` fallback if the scoped read fails.
- Areas: `location_scopes` (is_public, is_selectable) + `location_scope_edges` (widens_to); default `pohutukawa-coast`.
- Create gate: `my_business_profile` RPC + `business_subscriptions` + `current_user_is_support` RPC.
  Approved Organisation AND (active subscription OR Support). Support is the only free path (server-enforced too).
- Create: `events` insert as `pending_review` (start date required, time optional → `is_all_day`;
  recurrence weekly/fortnightly/monthly/yearly; polls open now, close 1 h–90 d, default 7 d) + `event_topics`.
  Notices: `member_notices` insert (`weekly_letter`, published).
- Welcome: `user_welcome_dismissals` (version 1), same gate as iOS t224.
