import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated struct ChatTurn: Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    let role: Role
    let content: String
}

/// Anything that can turn a system prompt + conversation into a reply.
/// Swap in a different provider by writing another type that conforms to this.
protocol LLMClient: Sendable {
    func complete(system: String, turns: [ChatTurn]) async throws -> String
}

/// Calls the Claude Messages API (https://docs.claude.com/en/api/messages).
///
/// API key lookup order:
///   1. ANTHROPIC_API_KEY environment variable (Xcode: Product > Scheme > Edit Scheme > Run > Arguments)
///   2. "ANTHROPIC_API_KEY" in HEARTS Project/Secrets.plist (gitignored, never commit it)
/// Model can be overridden the same way with ANTHROPIC_MODEL.
nonisolated struct AnthropicClient: LLMClient {
    static let defaultModel = "claude-sonnet-5-5"

    let apiKey: String
    let model: String
    var maxTokens = 700
    var session: URLSession = .shared

    init(apiKey: String, model: String = AnthropicClient.defaultModel) {
        self.apiKey = apiKey
        self.model = model
    }

    /// Builds a client from the environment / Secrets.plist, or nil if no key is set.
    static func fromConfiguration(bundle: Bundle = .main) -> AnthropicClient? {
        let config = LLMConfiguration.load(bundle: bundle)
        guard let key = config.value("ANTHROPIC_API_KEY") else { return nil }
        return AnthropicClient(apiKey: key, model: config.value("ANTHROPIC_MODEL") ?? defaultModel)
    }

    func complete(system: String, turns: [ChatTurn]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(model: model, max_tokens: maxTokens, system: system, messages: turns)
        )

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
            throw LLMError.http(status, message ?? String(data: data, encoding: .utf8) ?? "")
        }
        let body = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = body.content.compactMap(\.text).joined()
        guard !text.isEmpty else { throw LLMError.emptyReply }
        return text
    }

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [ChatTurn]
    }

    private struct ResponseBody: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}

/// Calls Gemini (generateContent), either through the HEARTS server or straight to Google.
///
/// Normal setup: the app talks to the HEARTS Cloudflare Worker (HeartsConfig.geminiProxyURL),
/// which holds the Gemini key. Nothing secret is in the app or the repo. See server/README.md.
///
/// Developer override: put GEMINI_API_KEY in the Xcode scheme env vars or in the gitignored
/// HEARTS Project/Secrets.plist to call Google directly with your own key.
/// Model can be overridden with GEMINI_MODEL. If the model is busy (503/429), it retries once
/// and then falls back to the next model in `fallbackModels`.
nonisolated struct GeminiClient: LLMClient {
    static let defaultModel = "gemini-3.5-flash-lite"
    static let fallbackModels = ["gemini-3.5-flash-lite", "gemini-3.1-flash-lite"]
    static let googleBaseURL = URL(string: "https://generativelanguage.googleapis.com")!

    /// Where requests go: Google, or the HEARTS server.
    let baseURL: URL
    /// Only set when calling Google directly. The HEARTS server adds the key itself.
    let apiKey: String?
    let model: String
    var maxTokens = 2048   // newer Gemini models spend part of this on thinking, so keep it roomy
    var session: URLSession = .shared

    /// Direct to Google with your own key.
    init(apiKey: String, model: String = GeminiClient.defaultModel) {
        self.baseURL = Self.googleBaseURL
        self.apiKey = apiKey
        self.model = model
    }

    /// Through the HEARTS server, which holds the key.
    init(proxyURL: URL, model: String = GeminiClient.defaultModel) {
        self.baseURL = proxyURL
        self.apiKey = nil
        self.model = model
    }

    var usesProxy: Bool { apiKey == nil }

    static func fromConfiguration(bundle: Bundle = .main) -> GeminiClient? {
        let config = LLMConfiguration.load(bundle: bundle)
        let model = config.value("GEMINI_MODEL") ?? defaultModel
        if let key = config.value("GEMINI_API_KEY") {
            return GeminiClient(apiKey: key, model: model)
        }
        let proxy = config.value("GEMINI_PROXY_URL") ?? HeartsConfig.geminiProxyURL
        if let url = URL(string: proxy), url.scheme == "https" {
            return GeminiClient(proxyURL: url, model: model)
        }
        return nil
    }

    func complete(system: String, turns: [ChatTurn]) async throws -> String {
        var models = [model]
        models += Self.fallbackModels.filter { $0 != model }
        var lastError: Error = LLMError.emptyReply

        for candidate in models {
            for attempt in 0..<2 {
                do {
                    return try await send(model: candidate, system: system, turns: turns)
                } catch LLMError.http(let code, let message) where code == 503 || code == 429 {
                    lastError = LLMError.http(code, message)
                    if attempt == 0 { try await Task.sleep(nanoseconds: 1_500_000_000) }
                } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
                    lastError = error
                }
            }
        }
        throw lastError
    }

    private func send(model: String, system: String, turns: [ChatTurn]) async throws -> String {
        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        let url = URL(string: "\(base)/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        } else {
            request.setValue("hearts-ios", forHTTPHeaderField: "X-HEARTS-App")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            systemInstruction: Content(role: nil, parts: [Part(text: system)]),
            contents: turns.map { Content(role: $0.role == .user ? "user" : "model", parts: [Part(text: $0.content)]) },
            generationConfig: GenerationConfig(maxOutputTokens: maxTokens)
        ))

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
            throw LLMError.http(status, message ?? String(data: data, encoding: .utf8) ?? "")
        }
        let body = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = (body.candidates?.first?.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMError.emptyReply }
        return text
    }

    private struct Part: Codable { var text: String?; var thought: Bool? = nil }
    private struct Content: Codable { let role: String?; let parts: [Part] }
    private struct GenerationConfig: Encodable { let maxOutputTokens: Int }
    private struct RequestBody: Encodable {
        let systemInstruction: Content
        let contents: [Content]
        let generationConfig: GenerationConfig
    }
    private struct ResponseBody: Decodable {
        struct Candidate: Decodable { let content: Content? }
        let candidates: [Candidate]?
    }
    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}

/// Reads keys from the environment first, then HEARTS Project/Secrets.plist.
nonisolated struct LLMConfiguration {
    let env: [String: String]
    let secrets: [String: Any]

    static func load(bundle: Bundle = .main) -> LLMConfiguration {
        var secrets: [String: Any] = [:]
        if let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            secrets = plist
        }
        return LLMConfiguration(env: ProcessInfo.processInfo.environment, secrets: secrets)
    }

    /// Non-empty value for `key`, ignoring "YOUR_..." placeholders.
    func value(_ key: String) -> String? {
        let raw = (env[key] ?? secrets[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty || raw.hasPrefix("YOUR_") ? nil : raw
    }
}

/// Picks the LLM the app uses: Gemini if a Gemini key is set, otherwise Claude, otherwise nil (offline mode).
/// Set LLM_PROVIDER to "gemini" or "anthropic" to force one when both keys are present.
nonisolated enum LLMProviders {
    static func configured(bundle: Bundle = .main) -> LLMClient? {
        let config = LLMConfiguration.load(bundle: bundle)
        let gemini = GeminiClient.fromConfiguration(bundle: bundle)
        let claude = AnthropicClient.fromConfiguration(bundle: bundle)
        switch config.value("LLM_PROVIDER")?.lowercased() {
        case "anthropic", "claude": return claude ?? gemini
        default: return gemini ?? claude
        }
    }

    static func name(of client: LLMClient?) -> String {
        switch client {
        case is GeminiClient: return "Gemini"
        case is AnthropicClient: return "Claude"
        default: return "offline"
        }
    }
}

nonisolated enum LLMError: LocalizedError {
    case http(Int, String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .http(401, _), .http(403, _): return "The AI key was rejected. If you use the HEARTS server, its GEMINI_API_KEY secret needs a new key."
        case .http(503, _), .http(429, _): return "The AI model is busy right now. Try again in a minute."
        case .http(let code, let msg): return "AI API error \(code): \(msg)"
        case .emptyReply: return "The model sent back an empty reply."
        }
    }
}
