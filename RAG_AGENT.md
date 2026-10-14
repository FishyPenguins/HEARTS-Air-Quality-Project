# HEARTS agent (RAG chat)

The **Ask HEARTS** button on the map opens a chat with the HEARTS agent. It answers questions about air quality, heat and heart failure using the HEARTS knowledge base plus the live readings on the dashboard, and cites its sources.

## How it works

```
question ──► BM25Retriever ──► top chunks from hearts_knowledge.json ─┐
                                                                     ├─► system prompt ──► Claude API ──► answer + [1] [2] citations
live AQI / PM2.5 / temp / heat index / pollen (ExposomeService) ─────┘
```

1. **Retrieve.** `BM25Retriever` ranks the chunks in `Agent/Knowledge/hearts_knowledge.json` against the question, the same keyword formula search engines use. It runs on the phone with no extra API. It also adds up to 2 chunks about today's conditions (for example bad air or heat), so "can I go for a walk?" pulls in the AQI and heat guidance.
2. **Augment.** `HeartsAgent` builds a system prompt with the live conditions and the numbered chunks, plus rules: plain language, cite sources, don't invent numbers, never change meds, and say 911 for emergency symptoms.
3. **Generate.** `AnthropicClient` sends it to the Claude Messages API. The last 10 back-and-forths are kept so follow-up questions work.

With no API key set, the chat still runs in **offline mode** and shows the best-matching source passage instead of a written answer. That's handy for testing retrieval.

## Files

| File | What it does |
|---|---|
| `Agent/Knowledge/hearts_knowledge.json` | The knowledge base: 21 short summaries, each with its source and link |
| `Agent/KnowledgeBase.swift` | Loads the JSON |
| `Agent/BM25Retriever.swift` | Search (the "R" in RAG) |
| `Agent/LLMClient.swift` | `LLMClient` protocol + Claude API client |
| `Agent/HeartsAgent.swift` | The agent: retrieve, build prompt, call the LLM, keep history |
| `Agent/EnvironmentSnapshot+Exposome.swift` | Turns dashboard readings into agent input |
| `Agent/AgentChatModel.swift` | State for the chat screen |
| `Views/AgentChatView.swift` | The chat screen |

## Setting the API key

Get a key at https://console.anthropic.com. **Never commit it.** Pick one:

- **Scheme env var (easiest):** Xcode > Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables, then add `ANTHROPIC_API_KEY`. This only works when the app is launched from Xcode.
- **Secrets.plist (works when launched from the home screen too):** copy `Secrets.example.plist` to `HEARTS Project/Secrets.plist` and paste your key. It's in `.gitignore`.

Optional: set `ANTHROPIC_MODEL` the same way to use a different model (default `claude-sonnet-5-5`).

Note: a key inside the app can be pulled out of the app file by anyone who has it. That's fine for our test devices. Before real patients use it, the Claude call should move to a small backend server.

## Adding knowledge

Add an entry to `hearts_knowledge.json`:

```json
{
  "id": "unique-id",
  "title": "Short title people would search for",
  "source": "Author et al. Year, Journal",
  "url": "https://link-to-source",
  "tags": ["keywords", "people", "might", "type"],
  "text": "2 to 6 plain sentences summarizing the source. Only write what the source says."
}
```

Title words count 3x and tags 2x in search, so put the words patients would actually type there. If a common word isn't matching, add it to the `synonyms` list in `BM25Retriever.swift`.

## Next steps

- Hook in the risk model score once it runs on the phone (add it to `EnvironmentSnapshot.promptDescription`).
- Move the Claude call to a backend before real patients use the app.
- Grow the knowledge base as the lit search continues (OpenEvidence questions, Get With The Guidelines findings).
