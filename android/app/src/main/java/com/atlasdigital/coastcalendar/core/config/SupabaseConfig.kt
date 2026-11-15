package com.atlasdigital.coastcalendar.core.config

import com.atlasdigital.coastcalendar.BuildConfig

/**
 * Mirrors iOS `SupabaseConfiguration`: same project, same publishable key, same `isConfigured` guard
 * (rejects empty/placeholder values and any service_role / secret key).
 * Values are injected into BuildConfig from git-ignored local.properties.
 */
object SupabaseConfig {
    val projectUrl: String get() = BuildConfig.SUPABASE_URL
    val publishableKey: String get() = BuildConfig.SUPABASE_PUBLISHABLE_KEY

    val isConfigured: Boolean get() = isValid(projectUrl, publishableKey)

    fun isValid(url: String, key: String): Boolean =
        url.startsWith("https://") &&
            !url.contains("your-project-ref") &&
            key.isNotBlank() &&
            !key.contains("YOUR_SUPABASE") &&
            !key.contains("service_role", ignoreCase = true) &&
            !key.contains("secret", ignoreCase = true)
}
