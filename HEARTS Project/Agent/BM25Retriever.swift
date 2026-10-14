import Foundation

/// The "R" in RAG: finds the knowledge chunks most related to a question.
///
/// Uses BM25 keyword ranking (the classic search-engine formula). It runs fully on the phone,
/// needs no embedding API, and is easy to explain. Titles and tags count extra, and a small
/// synonym list maps everyday words ("smoky", "hot", "water pill") onto the words the sources use.
nonisolated struct BM25Retriever: Sendable {
    struct Result: Sendable {
        let chunk: KnowledgeChunk
        let score: Double
    }

    private struct Doc: Sendable {
        let chunk: KnowledgeChunk
        let termFreq: [String: Double]
        let length: Double
    }

    private let docs: [Doc]
    private let docFreq: [String: Int]
    private let avgLength: Double
    private let k1 = 1.5
    private let b = 0.75

    init(knowledgeBase: KnowledgeBase) {
        var docs: [Doc] = []
        var df: [String: Int] = [:]
        for chunk in knowledgeBase.chunks {
            var tf: [String: Double] = [:]
            // Title and tags are weighted 3x and 2x so a chunk *about* a topic beats one that mentions it.
            for t in Self.tokenize(chunk.title) { tf[t, default: 0] += 3 }
            for t in Self.tokenize(chunk.tags.joined(separator: " ")) { tf[t, default: 0] += 2 }
            for t in Self.tokenize(chunk.text) { tf[t, default: 0] += 1 }
            for term in tf.keys { df[term, default: 0] += 1 }
            docs.append(Doc(chunk: chunk, termFreq: tf, length: tf.values.reduce(0, +)))
        }
        self.docs = docs
        self.docFreq = df
        self.avgLength = docs.isEmpty ? 1 : docs.map(\.length).reduce(0, +) / Double(docs.count)
    }

    /// Top `limit` chunks for `query`. Chunks with no matching words are never returned.
    func retrieve(_ query: String, limit: Int = 4) -> [Result] {
        let queryTerms = Set(Self.expand(Self.tokenize(query)))
        guard !queryTerms.isEmpty, !docs.isEmpty else { return [] }
        let n = Double(docs.count)

        let scored: [Result] = docs.compactMap { doc in
            var score = 0.0
            for term in queryTerms {
                guard let f = doc.termFreq[term], let dfTerm = docFreq[term] else { continue }
                let idf = log(1 + (n - Double(dfTerm) + 0.5) / (Double(dfTerm) + 0.5))
                score += idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * doc.length / avgLength))
            }
            return score > 0 ? Result(chunk: doc.chunk, score: score) : nil
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }

    // MARK: - Text processing

    static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "pm2.5", with: "pm25")
            .replacingOccurrences(of: "pm 2.5", with: "pm25")
            .replacingOccurrences(of: "µg/m³", with: " ")
        var tokens: [String] = []
        var current = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens.filter { $0.count > 1 && !stopWords.contains($0) }.map(stem)
    }

    /// Very light stemmer: folds plurals and -ing/-ed so "hospitalizations" matches "hospitalization".
    static func stem(_ word: String) -> String {
        guard word.count > 4 else { return word }
        for suffix in ["ations", "ation", "ings", "ing", "ies", "ed"] where word.hasSuffix(suffix) {
            let base = String(word.dropLast(suffix.count))
            if base.count >= 3 {
                return suffix == "ies" ? base + "y" : base
            }
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us") {
            return String(word.dropLast())
        }
        return word
    }

    /// Adds source vocabulary for everyday words people actually type.
    static func expand(_ tokens: [String]) -> [String] {
        var out = tokens
        for t in tokens {
            if let extra = synonyms[t] { out += extra.flatMap { tokenize($0) } }
        }
        return out
    }

    private static let synonyms: [String: [String]] = [
        "air": ["aqi"],
        "quality": ["aqi"],
        "aqi": ["air quality index"],
        "pollution": ["pm25", "aqi"],
        "polluted": ["pm25", "aqi", "pollution"],
        "smoky": ["smoke", "wildfire"],
        "smoke": ["wildfire", "pm25"],
        "fire": ["wildfire", "smoke"],
        "hot": ["heat", "temperature"],
        "warm": ["heat", "temperature"],
        "humid": ["humidity", "heat index"],
        "cold": ["cold", "temperature"],
        "freezing": ["cold", "temperature"],
        "walk": ["exercise", "activity", "outdoor"],
        "run": ["exercise", "activity", "outdoor"],
        "jog": ["exercise", "activity", "outdoor"],
        "workout": ["exercise", "activity"],
        "outside": ["outdoor", "activity"],
        "safe": ["advice", "what to do", "actions"],
        "should": ["advice", "what to do"],
        "breath": ["shortness of breath", "symptoms"],
        "breathe": ["shortness of breath", "symptoms"],
        "swollen": ["swelling", "warning signs"],
        "symptom": ["warning signs"],
        "pill": ["medication"],
        "pills": ["medication"],
        "meds": ["medication"],
        "medicine": ["medication"],
        "water": ["fluids", "diuretic"],
        "drink": ["fluids", "dehydration"],
        "purifier": ["air cleaner", "hepa", "indoor"],
        "filter": ["air cleaner", "hepa"],
        "mask": ["n95", "mask"],
        "chest": ["emergency", "911"],
        "pain": ["emergency"],
        "hospital": ["hospitalization"],
        "risk": ["risk", "hospitalization"],
        "score": ["risk", "model"],
        "app": ["hearts"],
        "allergy": ["pollen"],
        "allergies": ["pollen"],
        "study": ["research"],
        "studies": ["research"],
        "evidence": ["research"]
    ]

    private static let stopWords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "your", "can", "has", "have", "with", "this",
        "that", "from", "they", "was", "were", "what", "when", "how", "why", "who", "which", "will",
        "would", "could", "about", "into", "than", "then", "there", "their", "them", "its", "is", "it",
        "of", "to", "in", "on", "at", "by", "or", "as", "be", "an", "do", "does", "did", "my", "me",
        "so", "if", "too", "very", "just", "also", "more", "most", "some", "any", "all", "today", "now",
        "is", "am", "im", "i", "a", "get", "like", "much", "many", "ok", "okay", "go", "going"
    ]
}
