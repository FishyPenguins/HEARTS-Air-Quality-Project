# HEARTS RAG agent (Cloudflare Worker)

This is the code for our RAG agent. It runs on Cloudflare Workers at:

https://hearts-rag-agent.andrewozimek01.workers.dev

## How it works

1. **Search:** the patient's question plus today's conditions (AQI, heat) get turned into an embedding with Gemini and compared to every guideline. The top 3 matches are kept. The guideline for the current AQI level is always included when the air is unhealthy.
2. **Attach:** those guidelines, the patient profile, and the live environment data go into the prompt.
3. **Write:** Gemini writes a short, plain-language answer and returns which guidelines it used.

## How the app uses it

The iOS app (`HEARTS Project/Services/HeartsAgentClient.swift`) sends:

```
POST /ask
{
  "question": "Is it safe to go for a walk today?",
  "patient": { "condition": "heart failure", "takesWaterPills": true },
  "environment": { "aqi": 162, "pm25": 70.1, "temperatureF": 88, "heatIndexF": 95 }
}
```

and gets back:

```
{ "answer": "...", "model": "...", "sources": [ { "id": "aqi-151-200", "title": "...", "source": "...", "score": 0.81 } ] }
```

## Guidelines

The `GUIDELINES` list at the top of `worker.js` is the knowledge base. They come from "HEARTS Guidelines v2" (EPA, CDC, NIH MedlinePlus, and the State of Maine). Each one has an exact quote and link in that sheet so the Yale doctors can approve it.

## Deploying

Cloudflare dashboard > Workers & Pages > `hearts-rag-agent` > Edit code > paste `worker.js` > Deploy.
The `GEMINI_API_KEY` secret is set under Settings > Variables and secrets. Use fake patients only (free Gemini tier).
