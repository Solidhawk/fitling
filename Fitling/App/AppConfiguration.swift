import Foundation

/// Supabase settings from Info.plist, filled from `Config/Supabase.xcconfig` at build time.
/// The publishable key is meant to be public; Row Level Security protects the data.
struct AppConfiguration: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        case missing(String)
        case invalidHost
    }

    let supabaseURL: URL
    let publishableKey: String

    init(info: [String: Any]) throws(Error) {
        guard let host = info["SupabaseHost"] as? String, !host.isEmpty else { throw .missing("SupabaseHost") }
        guard !host.contains("/"), !host.contains(":"), let url = URL(string: "https://\(host)") else { throw .invalidHost }
        guard let key = info["SupabasePublishableKey"] as? String, !key.isEmpty else {
            throw .missing("SupabasePublishableKey")
        }
        supabaseURL = url
        publishableKey = key
    }

    static func fromBundle(_ bundle: Bundle = .main) throws(Error) -> AppConfiguration {
        try AppConfiguration(info: bundle.infoDictionary ?? [:])
    }
}
