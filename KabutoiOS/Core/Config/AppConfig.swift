import Foundation

/// Runtime configuration injected via xcconfig → Info.plist.
/// No secrets live in source — Config/Secrets.xcconfig supplies values at
/// build time and is gitignored. See Config/Secrets.example.xcconfig.
struct AppConfig: Sendable {
    let apiBaseURL: URL
    let supabaseURL: URL
    let supabaseAnonKey: String

    enum ConfigError: Error, CustomStringConvertible {
        case missing(key: String)
        case invalidURL(key: String, value: String)

        var description: String {
            switch self {
            case .missing(let key):
                return "Missing Info.plist key: \(key). Did you create Config/Secrets.xcconfig?"
            case .invalidURL(let key, let value):
                return "Invalid URL for \(key): \(value)"
            }
        }
    }

    static func loadFromBundle(_ bundle: Bundle = .main) throws -> AppConfig {
        let apiBase = try readURL(key: "KabutoAPIBaseURL", bundle: bundle)
        let supabase = try readURL(key: "KabutoSupabaseURL", bundle: bundle)
        let anonKey = try readString(key: "KabutoSupabaseAnonKey", bundle: bundle)
        return AppConfig(
            apiBaseURL: apiBase,
            supabaseURL: supabase,
            supabaseAnonKey: anonKey
        )
    }

    private static func readString(key: String, bundle: Bundle) throws -> String {
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String,
              !raw.isEmpty
        else {
            throw ConfigError.missing(key: key)
        }
        return raw
    }

    private static func readURL(key: String, bundle: Bundle) throws -> URL {
        let raw = try readString(key: key, bundle: bundle)
        guard let url = URL(string: raw), url.scheme != nil else {
            throw ConfigError.invalidURL(key: key, value: raw)
        }
        return url
    }
}

extension AppConfig {
    /// Placeholder config used only by SwiftUI previews. Never shipped.
    static let preview = AppConfig(
        apiBaseURL: URL(string: "https://preview.invalid")!,
        supabaseURL: URL(string: "https://preview.invalid")!,
        supabaseAnonKey: "preview"
    )
}
