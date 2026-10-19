import Foundation

/// One passage in the HEARTS knowledge base (Agent/Knowledge/hearts_knowledge.json).
/// Each chunk is a short, plain-language summary of a real source so the agent can cite it.
nonisolated struct KnowledgeChunk: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let source: String
    let url: String
    let tags: [String]
    let text: String

    var link: URL? { url.isEmpty ? nil : URL(string: url) }
}

nonisolated struct KnowledgeBase: Sendable {
    let chunks: [KnowledgeChunk]

    init(chunks: [KnowledgeChunk]) {
        self.chunks = chunks
    }

    init(jsonData: Data) throws {
        chunks = try JSONDecoder().decode([KnowledgeChunk].self, from: jsonData)
    }

    /// Loads hearts_knowledge.json from the app bundle.
    static func bundled(in bundle: Bundle = .main) throws -> KnowledgeBase {
        guard let url = bundle.url(forResource: "hearts_knowledge", withExtension: "json") else {
            throw KnowledgeBaseError.missingFile
        }
        return try KnowledgeBase(jsonData: Data(contentsOf: url))
    }

    enum KnowledgeBaseError: LocalizedError {
        case missingFile
        var errorDescription: String? { "hearts_knowledge.json is missing from the app bundle." }
    }
}
