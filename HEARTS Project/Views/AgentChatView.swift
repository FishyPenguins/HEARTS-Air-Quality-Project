import SwiftUI

struct ChatMessage: Identifiable {
    enum Role { case user, agent, error }

    let id = UUID()
    let role: Role
    let text: String
    var sources: [AgentSource] = []
}

/// Chat with the HEARTS RAG agent. Every question is sent with the live
/// air quality / weather readings so the answer fits today's conditions.
struct AgentChatView: View {
    let environment: [String: Double]
    var patient: PatientProfile = .demo

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false

    private let client = HeartsAgentClient()

    private let suggestions = [
        "Is it safe to go for a walk today?",
        "What should I do about the air quality?",
        "How do I handle the heat today?"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conditionsBar
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty { welcome }
                            ForEach(messages) { message in
                                MessageBubble(message: message).id(message.id)
                            }
                            if isSending {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("HEARTS is checking the guidelines...")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .id("typing")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastID = messages.last?.id {
                            withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                        }
                    }
                }
                inputBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ask HEARTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Pieces

    private var conditionsBar: some View {
        HStack(spacing: 14) {
            if let aqi = environment["aqi"] {
                Label("AQI \(Int(aqi))", systemImage: "aqi.medium")
            }
            if let temp = environment["temperatureF"] {
                Label("\(Int(temp))°F", systemImage: "thermometer.medium")
            }
            if let heat = environment["heatIndexF"] {
                Label("Feels \(Int(heat))°F", systemImage: "sun.max.fill")
            }
            if environment.isEmpty {
                Label("Live data not loaded yet", systemImage: "exclamationmark.triangle")
            }
            Spacer()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask a question about today's air or weather. Answers come from approved heart failure guidelines and your area's live conditions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Not medical advice. For chest pain or severe trouble breathing, call 911.")
                .font(.caption)
                .foregroundStyle(.red)
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    send(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Type your question", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
                .onSubmit { send(draft) }

            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(.thinMaterial)
    }

    // MARK: - Sending

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        draft = ""
        messages.append(ChatMessage(role: .user, text: question))
        isSending = true

        Task {
            do {
                let reply = try await client.ask(question: question,
                                                 patient: patient,
                                                 environment: environment)
                messages.append(ChatMessage(role: .agent, text: reply.answer, sources: reply.sources))
            } catch {
                messages.append(ChatMessage(
                    role: .error,
                    text: "Couldn't reach the HEARTS agent. \(error.localizedDescription)"
                ))
            }
            isSending = false
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                if !message.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Based on:")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        ForEach(message.sources) { source in
                            Text("• \(source.title) (\(source.source))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16))
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user:  return .blue
        case .agent: return Color(.secondarySystemGroupedBackground)
        case .error: return .red.opacity(0.15)
        }
    }
}

#Preview {
    AgentChatView(environment: ["aqi": 162, "temperatureF": 88])
}
