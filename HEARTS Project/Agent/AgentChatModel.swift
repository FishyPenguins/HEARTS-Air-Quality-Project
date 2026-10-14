import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, error }
    let id = UUID()
    let role: Role
    let text: String
    var sources: [KnowledgeChunk] = []
}

/// Drives AgentChatView. Owns the HeartsAgent and the visible message list.
@Observable
@MainActor
final class AgentChatModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false
    let isOffline: Bool
    let setupError: String?

    private let agent: HeartsAgent?

    static let suggestions = [
        "Is it safe to go for a walk today?",
        "What does today's AQI mean for my heart?",
        "What should I do on a smoky day?",
        "Does heat affect heart failure?"
    ]

    init(llm: LLMClient? = AnthropicClient.fromConfiguration()) {
        do {
            let kb = try KnowledgeBase.bundled()
            agent = HeartsAgent(knowledgeBase: kb, llm: llm)
            setupError = nil
        } catch {
            agent = nil
            setupError = error.localizedDescription
        }
        isOffline = llm == nil
    }

    func send(_ text: String, environment: EnvironmentSnapshot) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking, let agent else { return }
        messages.append(ChatMessage(role: .user, text: question))
        isThinking = true

        Task {
            do {
                let reply = try await agent.ask(question, environment: environment)
                messages.append(ChatMessage(role: .assistant, text: reply.text, sources: reply.sources))
            } catch {
                messages.append(ChatMessage(role: .error, text: error.localizedDescription))
            }
            isThinking = false
        }
    }

    func clear() {
        messages.removeAll()
        Task { await agent?.reset() }
    }
}
