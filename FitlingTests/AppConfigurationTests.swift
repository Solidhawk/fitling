import Foundation
import Testing
@testable import Fitling

@Suite struct AppConfigurationTests {
    @Test func buildsHTTPSURLFromHost() throws {
        let config = try AppConfiguration(info: ["SupabaseHost": "abcd.supabase.co", "SupabasePublishableKey": "sb_publishable_test"])
        #expect(config.supabaseURL == URL(string: "https://abcd.supabase.co"))
        #expect(config.publishableKey == "sb_publishable_test")
    }

    @Test func missingHostThrows() {
        #expect(throws: AppConfiguration.Error.missing("SupabaseHost")) {
            try AppConfiguration(info: ["SupabasePublishableKey": "sb_publishable_test"])
        }
        #expect(throws: AppConfiguration.Error.missing("SupabaseHost")) {
            try AppConfiguration(info: ["SupabaseHost": "", "SupabasePublishableKey": "sb_publishable_test"])
        }
    }

    @Test func missingKeyThrows() {
        #expect(throws: AppConfiguration.Error.missing("SupabasePublishableKey")) {
            try AppConfiguration(info: ["SupabaseHost": "abcd.supabase.co"])
        }
    }

    @Test func hostWithSchemeOrPathIsRejected() {
        #expect(throws: AppConfiguration.Error.invalidHost) {
            try AppConfiguration(info: ["SupabaseHost": "https://abcd.supabase.co", "SupabasePublishableKey": "k"])
        }
    }
}
