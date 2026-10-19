import SwiftUI

/// "Ask HEARTS" chat screen. Each question is answered by HeartsAgent using the
/// HEARTS knowledge base (RAG) plus the live readings from the dashboard.
struct AgentChatView: View {
    let locationLabel: String
    let exposomeService: ExposomeService
    /// The person HEARTS is tailored to right now, and their risk, so answers are personal.
    var patient: Patient? = nil
    var risk: RiskAssessment? = nil
    /// Conditions the risk was scored with when the what-if simulator is on (otherwise live readings).
    var whatIf: RiskConditions? = nil

    @State private var model = AgentChatModel()
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var snapshot: EnvironmentSnapshot {
        var s = EnvironmentSnapshot(statuses: exposomeService.statuses, locationName: locationLabel)
        if let whatIf {
            // Demo mode: answer as if these were today's conditions.
            s.aqi = whatIf.aqi
            s.pm25 = whatIf.pm25
            s.heatIndexF = whatIf.heatIndexF
            s.temperatureF = whatIf.temperatureF
        }
        return s.personalized(for: patient, risk: risk)
    }

    private var suggestionList: [String] {
        guard let risk else { return AgentChatModel.suggestions }
        let me = patient?.isCustomProfile == true
        return [
            "Why is \(me ? "my" : "this patient's") risk \(risk.levelName.lowercased()) today?",
            me ? "What should I watch for this week?" : "What should this patient watch for this week?"
        ] + AgentChatModel.suggestions.prefix(3)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            conditionsBanner
                            if let error = model.setupError {
                                notice(error, icon: "exclamationmark.triangle.fill", tint: .red)
                            } else if model.isOffline {
                                notice("Offline mode: no Gemini or Claude API key is set, so HEARTS shows the source it found instead of writing an answer. See RAG_AGENT.md.",
                                       icon: "key.slash", tint: .orange)
                            }
                            if model.messages.isEmpty { suggestions }
                            ForEach(model.messages) { message in
                                MessageBubble(message: message).id(message.id)
                            }
                            if model.isThinking {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Looking through HEARTS sources…")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .id("thinking")
                            }
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: model.messages.count) {
                        withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
                    }
                    .onChange(of: model.isThinking) { _, thinking in
                        if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                    }
                }
                Text("Answers by \(model.providerName) using HEARTS sources. HEARTS is a student research prototype, not medical advice. Call 911 in an emergency.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                inputBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ask HEARTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(model.messages.isEmpty)
                }
            }
        }
    }

    // MARK: - Pieces

    private var conditionsBanner: some View {
        let s = snapshot
        return HStack(spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.title)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(whatIf == nil ? "Using live conditions in \(locationLabel)" : "Using what-if conditions")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(conditionsLine(s))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                if let patient {
                    Text(tailoredLine(patient))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(
            LinearGradient(colors: [Color(red: 0.15, green: 0.47, blue: 1.0),
                                    Color(red: 0.45, green: 0.18, blue: 0.92)],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func tailoredLine(_ patient: Patient) -> String {
        var line = "Tailored to \(patient.displayName) (\(patient.summaryLine))"
        if let risk { line += " · \(risk.levelName) risk \(risk.percentText)" }
        return line
    }

    private func conditionsLine(_ s: EnvironmentSnapshot) -> String {
        var parts: [String] = []
        if let aqi = s.aqi { parts.append("AQI \(aqi) \(s.aqiCategory ?? "")") }
        if let t = s.temperatureF { parts.append("\(Int(t.rounded()))°F") }
        if let hi = s.heatIndexF { parts.append("feels \(Int(hi.rounded()))°F") }
        return parts.isEmpty ? "Readings still loading" : parts.joined(separator: " · ")
    }

    private func notice(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.caption)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(suggestionList, id: \.self) { prompt in
                Button {
                    model.send(prompt, environment: snapshot)
                } label: {
                    HStack {
                        Text(prompt).font(.subheadline)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption)
                    }
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about air, heat, or your heart…", text: $draft, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(canSend ? Color(red: 0.45, green: 0.18, blue: 0.92) : .gray.opacity(0.5))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isThinking
    }

    private func send() {
        guard canSend else { return }
        model.send(draft, environment: snapshot)
        draft = ""
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(rendered)
                .font(.body)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .textSelection(.enabled)
                .padding(14)
                .background(background, in: RoundedRectangle(cornerRadius: 16))
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: message.text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(message.text)
    }

    private var background: AnyShapeStyle {
        switch message.role {
        case .user:
            AnyShapeStyle(LinearGradient(colors: [Color(red: 0.15, green: 0.47, blue: 1.0),
                                                  Color(red: 0.45, green: 0.18, blue: 0.92)],
                                         startPoint: .leading, endPoint: .trailing))
        case .assistant: AnyShapeStyle(.background)
        case .error: AnyShapeStyle(Color.red.opacity(0.15))
        }
    }
}

#Preview {
    AgentChatView(locationLabel: "Hamden", exposomeService: ExposomeService())
}
