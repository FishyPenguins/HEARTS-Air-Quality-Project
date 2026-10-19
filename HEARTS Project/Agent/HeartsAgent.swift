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
        if let aqi { lines.append("Air Quality Index (US AQI): \(aqi) (\(aqiCategory ?? ""))") }
        else { lines.append("Air Quality Index: not loaded") }
        if let pm25 { lines.append("PM2.5 concentration: \(String(format: "%.1f", pm25)) µg/m³") }
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
        You are the HEARTS assistant, inside an app for people with heart failure. HEARTS watches the \
        environment around the user (air quality, heat, humidity, pollen) and helps them understand what \
        it means for their heart health.

        Your users are mostly adults aged 50 and older. Write like you are talking to a trusted friend, \
        not a medical textbook.

        How to answer:
        - Use plain, warm language — aim for a 6th grade reading level. Avoid medical jargon. If you must \
        use a term (like AQI or PM2.5), explain it in one simple phrase right after, for example \
        "the AQI (a score from 0–500 for air quality)".
        - Keep answers short and easy to read. For a simple yes/no question, answer in 1–3 sentences. \
        For tips, steps, or anything with multiple parts, use a short bulleted list (• style, 3–5 items max). \
        Never write a wall of text — break it up.
        - Base health facts ONLY on the sources below and the live conditions. Do NOT number or cite sources \
        in your reply. If the sources don't cover the question, say you don't have information on that and \
        suggest they ask their doctor or care team. Never invent studies or numbers.
        - When it fits, mention the user's live readings (for example today's AQI or temperature).
        - Never diagnose. Never tell anyone to start, stop, or change a medicine or fluid limit — say to \
        check with their doctor or care team instead.
        - If the user describes emergency symptoms (chest pain or pressure, severe trouble breathing, \
        fainting, sudden confusion, coughing up pink foamy mucus), tell them to call 911 immediately — \
        put that first, before anything else.
        - Your topics are: environment (air quality, AQI, PM2.5, ozone, smoke, heat, cold, weather, pollen), \
        heart health and heart failure, staying active safely, and the HEARTS app. Answer anything that \
        touches those topics, including "what is" questions. Only if a question clearly has nothing to do \
        with them (like trivia or homework), say in one sentence that you can only help with those topics.
        - Do not add disclaimers about HEARTS being a prototype unless the user asks about it directly.

        Live conditions at the user's location right now:
        \(environment.promptDescription)

        Sources (do not mention these in your reply — use the information, not the references):
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
        parts.append("(Offline mode: no AI API key is set, so this is the retrieved passage, not a written answer.)")
        return parts.joined(separator: "\n\n")
    }
}
