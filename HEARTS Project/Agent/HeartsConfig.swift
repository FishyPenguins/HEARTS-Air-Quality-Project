import Foundation

/// Settings that are safe to commit (no secrets here).
nonisolated enum HeartsConfig {
    /// The HEARTS Cloudflare Worker that holds the Gemini key and forwards chat requests.
    /// Code: server/gemini-proxy-worker.js. Setup: server/README.md.
    /// Leave empty to run the chat in offline mode (unless Secrets.plist has a GEMINI_API_KEY).
    static let geminiProxyURL = "https://hearts-gemini.andrewozimek01.workers.dev"
}
