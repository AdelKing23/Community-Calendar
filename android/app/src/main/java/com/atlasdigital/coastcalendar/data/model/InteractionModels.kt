package com.atlasdigital.coastcalendar.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** iOS `EventReportCategory` (raw values go to `submit_event_report.p_category`). */
enum class EventReportCategory(val raw: String, val title: String) {
    WrongOrOutdated("wrong_or_outdated", "Wrong or outdated"),
    SpamOrScam("spam_or_scam", "Spam or scam"),
    UnsafeOrHarmful("unsafe_or_harmful", "Unsafe or harmful"),
    InappropriateContent("inappropriate_content", "Inappropriate content"),
    WrongLocation("wrong_location", "Wrong location"),
    Other("other", "Other");

    companion object {
        fun from(raw: String?): EventReportCategory = entries.firstOrNull { it.raw == raw } ?: Other
    }
}

@Serializable
data class PollResponseCountRecord(
    @SerialName("option_text") val optionText: String,
    @SerialName("response_count") val responseCount: Int,
)

/** iOS `PollResults`. */
data class PollResults(val counts: List<PollResponseCountRecord> = emptyList()) {
    val totalResponses: Int get() = counts.sumOf { it.responseCount }
    fun count(option: String): Int = counts.firstOrNull { it.optionText == option }?.responseCount ?: 0
}

/** Row from `event_poll_responses` (iOS `PollUserResponse`). */
@Serializable
data class PollUserResponse(
    @SerialName("selected_option") val selectedOption: String? = null,
    @SerialName("custom_answer") val customAnswer: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    val isCustomAnswer: Boolean get() = selectedOption == null && !customAnswer.isNullOrBlank()
    val displayAnswer: String get() = selectedOption?.takeIf { it.isNotBlank() } ?: CUSTOM_OPTION_LABEL

    companion object {
        /** iOS `PollInlineResponseView.customOptionLabel`. */
        const val CUSTOM_OPTION_LABEL = "Other"
    }
}
