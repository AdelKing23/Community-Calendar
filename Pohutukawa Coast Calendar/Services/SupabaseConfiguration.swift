import Foundation

enum SupabaseConfiguration {
    static let projectURL = URL(string: "https://fujngeynyosnplviyvbg.supabase.co")
    static let publishableKey = "sb_publishable_YsW8_4ahQtnqyDzVgMRsSg_jfgtVfMx"

    static var restURL: URL? {
        projectURL?.appendingPathComponent("rest/v1")
    }

    static var isConfigured: Bool {
        projectURL?.host != "your-project-ref.supabase.co"
        && !publishableKey.isEmpty
        && !publishableKey.contains("YOUR_SUPABASE")
        && !publishableKey.localizedCaseInsensitiveContains("service_role")
        && !publishableKey.localizedCaseInsensitiveContains("secret")
    }
}
