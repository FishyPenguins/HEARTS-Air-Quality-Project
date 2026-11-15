import Foundation

/// Where the HEARTS RAG agent lives (Cloudflare Worker).
enum HeartsAgentConfig {
    static let baseURL = URL(string: "https://hearts-rag-agent.andrewozimek01.workers.dev")!
    /// Optional shared key. Leave nil unless HEARTS_APP_KEY is set on the worker.
    static let appKey: String? = nil
}

/// One guideline the agent used to write its answer.
struct AgentSource: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let source: String
    let score: Double?
}

/// What the agent sends back from POST /ask.
struct AgentReply: Codable {
    let answer: String
    let model: String?
    let sources: [AgentSource]
}

private struct AgentErrorBody: Codable {
    let error: String
}

private struct AskRequest: Codable {
    let question: String
    let patient: PatientProfile
    let environment: [String: Double]
}

enum HeartsAgentError: LocalizedError {
    case server(String)
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .badResponse(let code): return "The HEARTS agent returned an error (\(code))."
        }
    }
}

/// Talks to the HEARTS RAG agent: sends the question + patient profile + live
/// environment readings, gets back an answer and the guidelines it used.
struct HeartsAgentClient {
    var baseURL: URL = HeartsAgentConfig.baseURL

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        return URLSession(configuration: config)
    }()

    func ask(question: String,
             patient: PatientProfile,
             environment: [String: Double]) async throws -> AgentReply {
        var request = URLRequest(url: baseURL.appendingPathComponent("ask"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = HeartsAgentConfig.appKey {
            request.setValue(key, forHTTPHeaderField: "x-hearts-key")
        }
        request.httpBody = try JSONEncoder().encode(
            AskRequest(question: question, patient: patient, environment: environment)
        )

        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard status == 200 else {
            if let body = try? JSONDecoder().decode(AgentErrorBody.self, from: data) {
                throw HeartsAgentError.server(body.error)
            }
            throw HeartsAgentError.badResponse(status)
        }
        return try JSONDecoder().decode(AgentReply.self, from: data)
    }
}
