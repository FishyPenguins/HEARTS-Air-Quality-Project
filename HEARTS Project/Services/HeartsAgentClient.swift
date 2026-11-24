import Foundation

// This file talks to our RAG agent on Cloudflare (see rag-agent/worker.js).
// We send the patient's question + today's air/weather data,
// and get back an answer plus the guidelines the agent used.

// Our Cloudflare Worker URL
let heartsAgentURL = URL(string: "https://hearts-rag-agent.andrewozimek01.workers.dev/ask")!

// A guideline the agent used (comes from our HEARTS Guidelines sheet)
struct AgentSource: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let source: String
    let link: String?
    let score: Double?
}

// What the agent sends back
struct AgentReply: Codable {
    let answer: String
    let model: String?
    let sources: [AgentSource]
}

// What we send to the agent
struct AgentRequest: Codable {
    let question: String
    let patient: PatientProfile
    let environment: [String: Double]
}

// If the agent has a problem it sends back { "error": "..." }
struct AgentErrorReply: Codable {
    let error: String
}

struct HeartsAgentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct HeartsAgentClient {

    func ask(question: String,
             patient: PatientProfile,
             environment: [String: Double]) async throws -> AgentReply {

        // Build the POST request
        var request = URLRequest(url: heartsAgentURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45 // Gemini can be slow sometimes

        let body = AgentRequest(question: question, patient: patient, environment: environment)
        request.httpBody = try JSONEncoder().encode(body)

        // Send it and wait for the answer
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode != 200 {
            if let errorReply = try? JSONDecoder().decode(AgentErrorReply.self, from: data) {
                throw HeartsAgentError(message: errorReply.error)
            }
            throw HeartsAgentError(message: "The HEARTS agent returned an error (\(statusCode)).")
        }

        return try JSONDecoder().decode(AgentReply.self, from: data)
    }
}
