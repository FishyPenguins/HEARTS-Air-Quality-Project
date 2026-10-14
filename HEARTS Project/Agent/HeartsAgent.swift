import Foundation

/// The live readings the agent gets with every question. Built from ExposomeService on the phone
/// (see EnvironmentSnapshot+Exposome.swift). Any value can be nil if that source hasn't loaded.
nonisolated struct EnvironmentSnapshot: Sendable, Equatable {
    var locationName: String?
    var aqi: Int?
    var pm25: Double?
    var temperatureF: Double?
    var humidityPercent: Double?
    var heatIndexF: Double?
    var pollen: Double?
    var capturedAt: Date = Date()

    static let empty = EnvironmentSnapshot()

    var aqiCategory: String? {
        guard let aqi else { return nil }
        switch aqi {
        case ..<51: return "Good"
        case 51...100: return "Moderate"
        case 101...150: return "Unhealthy for Sensitive Groups"
        case 151...200: return "Unhealthy"
        case 201...300: return "Very Unhealthy"
        default: return "Hazardous"
        }
    }

    /// Plain-text block that goes into the system prompt.
    var promptDescription: String {
        var lines: [String] = []
        if let locationName { lines.append("Location: \(locationName)") }
        if let aqi { lines.append("Air Quality Index (AirNow): \(aqi) (\(aqiCategory ?? ""))") }
        else { lines.append("Air Quality Index: not loaded") }
        if let pm25 { lines.append("PM2.5 AQI reading (AirNow): \(Int(pm25))") }
        if let temperatureF { lines.append("Temperature: \(Int(temperatureF.rounded()))°F") }
        if let humidityPercent { lines.append("Humidity: \(Int(humidityPercent.rounded()))%") }
        if let heatIndexF { lines.append("Heat index (feels like): \(Int(heatIndexF.rounded()))°F") }
        if let pollen { lines.append("Grass pollen: \(Int(pollen.rounded())) grains/m³") }
        lines.append("Noise, light pollution, green space: not available in HEARTS yet")
        return lines.joined(separator: "\n")
    }

    /// Extra search words so a vague question ("can I go for a walk?") still pulls the
    /// chunks that matter for today's conditions.
    var retrievalHints: [String] {
        var hints: [String] = []
        if let aqi {
            hints.append(aqi > 100 ? "aqi unhealthy sensitive actions" : aqi > 50 ? "aqi moderate" : "aqi good")
        }
        if let feels = heatIndexF ?? temperatureF {
            if feels >= 85 { hints.append("heat hot") }
            if feels <= 32 { hints.append("cold") }
        }
        return hints
    }
}

nonisolated struct AgentReply: Sendable {
    let text: String
    let sources: [KnowledgeChunk]
    /// True when no LLM key was configured and the reply is just the retrieved passages.
    let isOffline: Bool
}

/// HEARTS chat agent: Retrieval-Augmented Generation over the HEARTS knowledge base.
///
/// For each question it
///   1. retrieves the most relevant knowledge chunks (BM25Retriever),
///   2. adds the live exposome readings,
///   3. asks the LLM to answer using only that material, and cite it as [1], [2], ...
/// If no LLM is configured it still works in "offline mode" and shows what it retrieved.
actor HeartsAgent {
    private let retriever: BM25Retriever
    private let llm: LLMClient?
    private var history: [ChatTurn] = []
    private let maxHistoryTurns = 10
    let retrievalLimit: Int

    init(knowledgeBase: KnowledgeBase, llm: LLMClient?, retrievalLimit: Int = 4) {
        self.retriever = BM25Retriever(knowledgeBase: knowledgeBase)
        self.llm = llm
        self.retrievalLimit = retrievalLimit
    }

    var hasLLM: Bool { llm != nil }

    func reset() { history.removeAll() }

    func ask(_ question: String, environment: EnvironmentSnapshot) async throws -> AgentReply {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        // Include the previous user turn so follow-ups ("what about tomorrow?") still retrieve well.
        let lastUserTurn = history.last(where: { $0.role == .user })?.content ?? ""
        let questionHits = retriever.retrieve(trimmed + " " + lastUserTurn, limit: retrievalLimit).map(\.chunk)
        let conditionHits = environment.retrievalHints.prefix(2)
            .compactMap { retriever.retrieve($0, limit: 1).first?.chunk }
        // Mostly chunks about the question, plus up to 2 slots for today's conditions (bad air, heat, cold).
        var sources = Array(questionHits.prefix(max(1, retrievalLimit - conditionHits.count)))
        for chunk in conditionHits + questionHits where sources.count < retrievalLimit && !sources.contains(chunk) {
            sources.append(chunk)
        }

        guard let llm else {
            return AgentReply(text: Self.offlineAnswer(sources: sources, environment: environment),
                              sources: sources, isOffline: true)
        }

        let system = Self.systemPrompt(environment: environment, sources: sources)
        let turns = history + [ChatTurn(role: .user, content: trimmed)]
        let answer = try await llm.complete(system: system, turns: turns)

        history.append(ChatTurn(role: .user, content: trimmed))
        history.append(ChatTurn(role: .assistant, content: answer))
        if history.count > maxHistoryTurns * 2 { history.removeFirst(history.count - maxHistoryTurns * 2) }

        return AgentReply(text: answer, sources: sources, isOffline: false)
    }

    // MARK: - Prompting

    static func systemPrompt(environment: EnvironmentSnapshot, sources: [KnowledgeChunk]) -> String {
        let numbered = sources.enumerated().map { i, chunk in
            "[\(i + 1)] \(chunk.title) (\(chunk.source))\n\(chunk.text)"
        }.joined(separator: "\n\n")

        return """
        You are the HEARTS assistant, inside a research app for people with heart failure. HEARTS \
        (Health Exposome Advisory Response Technology System) watches the environment around the user \
        (air quality, heat, humidity, pollen) and helps them understand what it means for their heart.

        How to answer:
        - Use plain, friendly language at about an 8th grade reading level. Keep it short: 2 to 5 sentences, \
        or a few short bullets if they asked what to do.
        - Base health facts ONLY on the numbered sources below and the live conditions. Cite sources inline \
        like [1] or [2]. If the sources don't cover the question, say you don't have information on that and \
        suggest asking their care team. Never invent studies or numbers.
        - When it fits, connect the answer to the user's live conditions (for example today's AQI).
        - Do not diagnose, and never tell anyone to start, stop, or change a medicine or fluid limit. For those, \
        say to check with their doctor or care team.
        - If the user describes emergency symptoms (chest pain or pressure, severe trouble breathing, fainting, \
        sudden confusion, coughing up pink foamy mucus), tell them to call 911 now, first, before anything else.
        - HEARTS is a student research prototype, not a medical device. Mention this only if it matters for the question.

        Live conditions at the user's location right now:
        \(environment.promptDescription)

        Sources:
        \(numbered.isEmpty ? "(no matching sources found)" : numbered)
        """
    }

    static func offlineAnswer(sources: [KnowledgeChunk], environment: EnvironmentSnapshot) -> String {
        var parts: [String] = []
        if let aqi = environment.aqi {
            parts.append("Right now the AQI is \(aqi) (\(environment.aqiCategory ?? "")).")
        }
        if let top = sources.first {
            parts.append("Here's the most relevant thing I found:\n\n\(top.title)\n\(top.text)")
        } else {
            parts.append("I couldn't find anything in the HEARTS knowledge base about that.")
        }
        parts.append("(Offline mode: no Claude API key is set, so this is the retrieved passage, not a written answer.)")
        return parts.joined(separator: "\n\n")
    }
}
