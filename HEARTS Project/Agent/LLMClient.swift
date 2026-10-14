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
        let env = ProcessInfo.processInfo.environment
        var secrets: [String: Any] = [:]
        if let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            secrets = plist
        }
        let key = (env["ANTHROPIC_API_KEY"] ?? secrets["ANTHROPIC_API_KEY"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.hasPrefix("YOUR_") else { return nil }
        let model = env["ANTHROPIC_MODEL"] ?? secrets["ANTHROPIC_MODEL"] as? String ?? defaultModel
        return AnthropicClient(apiKey: key, model: model)
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

nonisolated enum LLMError: LocalizedError {
    case http(Int, String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .http(401, _): return "The Claude API key was rejected (401). Check ANTHROPIC_API_KEY."
        case .http(let code, let msg): return "Claude API error \(code): \(msg)"
        case .emptyReply: return "The model sent back an empty reply."
        }
    }
}
