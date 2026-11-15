// HEARTS RAG agent - built from scratch on Cloudflare Workers.
//
// How it works:
//   1. Search  - turn the question + today's conditions into an embedding (Gemini),
//                compare it to every guideline chunk with cosine similarity, keep the
//                top matches. The guideline for the current AQI level is always included.
//   2. Attach  - put those chunks + patient profile + environment data into the prompt
//   3. Write   - Gemini writes a plain-language answer
//
// POST /ask  body: {"question": "...", "patient": {...optional}, "environment": {...optional}}
//   environment keys the iOS app sends: aqi, pm25, temperatureF, humidityPercent, heatIndexF, pollen
// returns:   {"answer": "...", "model": "...", "sources": [{id, title, source, score}]}
//
// Secrets / variables (Worker > Settings > Variables and secrets):
//   GEMINI_API_KEY  (secret, required)
//   GEMINI_MODEL    optional, default "gemini-flash-latest"
//   HEARTS_APP_KEY  optional; if set, requests must send header x-hearts-key with this value

// ---------- KNOWLEDGE BASE ----------
// DRAFT guidelines from EPA/AirNow, CDC and AHA. Pending Yale approval.
// Only Yale-approved rows should stay here for real patients.
// Each chunk = a few sentences on one topic.
const GUIDELINES = [
  {
    id: "aqi-daily",
    title: "Check the air quality every day",
    source: "EPA Air Quality Guide for Particle Pollution (2015); EPA Particle Pollution and Your Patients' Health (DRAFT - pending Yale review)",
    text: "People with heart failure are a sensitive group for air pollution. Check the air quality (AQI) every day, using an app like AirNow. Don't wait for symptoms to decide the air is bad, because for heart patients the first sign can be serious.",
  },
  {
    id: "aqi-101-150",
    title: "AQI 101-150 (Orange, Unhealthy for Sensitive Groups)",
    source: "EPA Air Quality Guide for Particle Pollution (2015) (DRAFT - pending Yale review)",
    text: "When the AQI is 101 to 150 (orange), people with heart failure should cut back on long or hard activity outside. It's OK to be active outside, just take it easier and take more breaks.",
  },
  {
    id: "aqi-151-200",
    title: "AQI 151-200 (Red, Unhealthy)",
    source: "EPA Air Quality Guide for Particle Pollution (2015) (DRAFT - pending Yale review)",
    text: "When the AQI is 151 to 200 (red), people with heart failure should avoid long or hard activity outside. Move activity indoors or do it another day.",
  },
  {
    id: "aqi-201-300",
    title: "AQI 201-300 (Purple, Very Unhealthy)",
    source: "EPA Air Quality Guide for Particle Pollution (2015) (DRAFT - pending Yale review)",
    text: "When the AQI is 201 to 300 (purple), people with heart failure should avoid all physical activity outside. Move activity indoors or wait until the air is better.",
  },
  {
    id: "aqi-301-plus",
    title: "AQI 301+ (Maroon, Hazardous)",
    source: "EPA Air Quality Guide for Particle Pollution (2013) (DRAFT - pending Yale review)",
    text: "When the AQI is 301 or higher (maroon), people with heart failure should stay indoors and keep activity low. Keep indoor air clean: windows closed, no smoking or candles, and use an air purifier if you have one.",
  },
  {
    id: "aqi-symptoms",
    title: "Symptoms on a bad air day",
    source: "EPA Air Quality Guide for Particle Pollution (2015) (DRAFT - pending Yale review)",
    text: "On a bad air day (AQI over 100), a racing or pounding heartbeat, shortness of breath, or unusual tiredness can mean a serious problem. Contact your care team. For chest pain or severe trouble breathing, call 911.",
  },
  {
    id: "heat-daily",
    title: "Check the heat forecast",
    source: "CDC Clinical Overview of Heat and Cardiovascular Disease (DRAFT - pending Yale review)",
    text: "During warm months, people with heart failure should check the HeatRisk forecast every day and take action to stay cool when HeatRisk is orange or higher.",
  },
  {
    id: "heat-and-air",
    title: "Hot days with bad air",
    source: "CDC Clinical Overview of Heat and Cardiovascular Disease (DRAFT - pending Yale review)",
    text: "Hot days often make air quality worse too. On hot days, check both the heat and the AQI, and follow the advice for whichever one is worse.",
  },
  {
    id: "heat-cooling",
    title: "How to stay cool",
    source: "CDC Clinical Overview of Heat and Cardiovascular Disease (DRAFT - pending Yale review)",
    text: "Stay in air conditioning or go somewhere cool, like a cooling center, even for a few hours. Fans don't help much once it's 90F or hotter indoors. Avoid alcohol.",
  },
  {
    id: "heat-meds",
    title: "Heart medicines on hot days",
    source: "CDC Heat and Medications Guidance (DRAFT - pending Yale review)",
    text: "Some heart medicines, like water pills, can make heat harder on your body. Don't stop or change any medicine on your own. Ask your care team for a plan for hot days.",
  },
  {
    id: "warning-signs",
    title: "Heart failure warning signs",
    source: "AHA Warning Signs of Heart Failure (DRAFT - pending Yale review)",
    text: "Warning signs of heart failure getting worse include more shortness of breath, coughing or wheezing, swelling, feeling very tired, loss of appetite, confusion, a faster heartbeat, and sudden weight changes. If you have any of these, tell your care team.",
  },
  {
    id: "weight-gain",
    title: "Fast weight gain",
    source: "Source still needed (DRAFT - pending Yale review)",
    text: "Weigh yourself every morning. If your weight goes up fast, call your care team the same day. (Exact pounds to be set by Yale.)",
  },
  {
    id: "call-911",
    title: "When to call 911",
    source: "Source still needed (DRAFT - pending Yale review)",
    text: "Call 911 for chest pain, severe shortness of breath at rest, fainting, or new confusion. Don't drive yourself.",
  },
];

const SYSTEM_PROMPT = `You are the HEARTS assistant, inside an app for people with heart failure.
HEARTS watches air quality, heat, humidity and weather and helps patients understand what it means for them.

Rules:
- Use plain language a patient can follow. Short sentences. No medical jargon. Keep answers under 120 words.
- Base health advice ONLY on the guideline excerpts provided. If they don't cover the question, say so and suggest asking the care team.
- Use the patient profile and current environment data when they are provided. Mention today's AQI or heat when it matters.
- Never change or stop medications. Never diagnose.
- If the patient describes chest pain, fainting, severe shortness of breath, or confusion, tell them to call 911 right away.`;

const GEMINI = "https://generativelanguage.googleapis.com/v1beta";
const EMBED_MODEL = "gemini-embedding-001";
const TOP_K = 3;
const CALL_TIMEOUT_MS = 12000; // never let one Gemini call hang the request
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, x-hearts-key",
};

let guidelineVectors = null; // cached while the Worker stays warm

// Calls Gemini with a timeout; retries when Google is busy (429/500/503) or slow
async function gemini(env, path, body, attempts = 2) {
  let last = "";
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const r = await fetch(`${GEMINI}/${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
      });
      if (r.ok) return r.json();
      last = `Gemini ${r.status}: ${(await r.text()).slice(0, 300)}`;
      if (![429, 500, 503].includes(r.status)) break;
    } catch (e) {
      last = `Gemini call failed: ${e.name === "TimeoutError" ? "timed out" : e.message}`;
    }
    await new Promise((s) => setTimeout(s, 600 * (attempt + 1)));
  }
  throw new Error(last);
}

// Backup models if the main one is overloaded or unavailable
function chatModels(env) {
  return [env.GEMINI_MODEL || "gemini-flash-latest", "gemini-2.5-flash", "gemini-flash-lite-latest"];
}

async function embed(env, texts) {
  const out = [];
  for (let i = 0; i < texts.length; i += 100) {
    const res = await gemini(env, `models/${EMBED_MODEL}:batchEmbedContents`, {
      requests: texts.slice(i, i + 100).map((t) => ({
        model: `models/${EMBED_MODEL}`,
        content: { parts: [{ text: t }] },
      })),
    });
    out.push(...res.embeddings.map((e) => e.values));
  }
  return out;
}

function cosine(a, b) {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
  return na && nb ? dot / Math.sqrt(na * nb) : 0;
}

// Which AQI guideline matches today's number
function aqiChunkId(aqi) {
  if (typeof aqi !== "number") return null;
  if (aqi > 300) return "aqi-301-plus";
  if (aqi > 200) return "aqi-201-300";
  if (aqi > 150) return "aqi-151-200";
  if (aqi > 100) return "aqi-101-150";
  return null;
}

// Turns the app's numbers into words so the search can match them
function describeEnvironment(env) {
  if (!env || typeof env !== "object") return "";
  const parts = [];
  if (typeof env.aqi === "number") parts.push(`Air quality index (AQI) is ${Math.round(env.aqi)}.`);
  if (typeof env.heatIndexF === "number") parts.push(`Heat index is ${Math.round(env.heatIndexF)}F.`);
  else if (typeof env.temperatureF === "number") parts.push(`Temperature is ${Math.round(env.temperatureF)}F.`);
  if (typeof env.heatIndexF === "number" && env.heatIndexF >= 90) parts.push("It is a hot day.");
  return parts.join(" ");
}

// Step 1: Search (retrieval)
async function retrieve(env, question, environment) {
  const chunks = GUIDELINES.filter((c) => c.text && c.text.trim());
  if (!chunks.length) return [];
  if (!guidelineVectors || guidelineVectors.length !== chunks.length) {
    guidelineVectors = await embed(env, chunks.map((c) => `${c.title}\n${c.text}`));
  }
  const query = `${question}\n${describeEnvironment(environment)}`.trim();
  const [q] = await embed(env, [query]);
  let ranked = chunks
    .map((c, i) => ({ chunk: c, score: cosine(q, guidelineVectors[i]) }))
    .sort((a, b) => b.score - a.score);

  // Always include the guideline for today's AQI level when the air is unhealthy
  const forced = aqiChunkId(environment && environment.aqi);
  if (forced) {
    const hit = ranked.find((h) => h.chunk.id === forced);
    if (hit) ranked = [hit, ...ranked.filter((h) => h !== hit)];
  }
  return ranked.slice(0, TOP_K);
}

// Steps 2 + 3: Attach (augmentation) and Write (generation)
async function answer(env, question, patient, environment, hits) {
  const excerpts = hits.length
    ? hits.map(({ chunk: c }) => `[${c.id}] ${c.title} (${c.source})\n${c.text}`).join("\n\n")
    : "(No guidelines loaded yet.)";
  const prompt =
    `Guideline excerpts:\n${excerpts}\n\n` +
    `Patient profile:\n${JSON.stringify(patient || "not provided")}\n\n` +
    `Current environment:\n${JSON.stringify(environment || "not provided")}\n\n` +
    `Patient question:\n${question}`;
  let res, lastErr;
  for (const model of chatModels(env)) {
    try {
      res = await gemini(env, `models/${model}:generateContent`, {
        system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.3 },
      }, 1);
      res.model = model;
      break;
    } catch (e) { lastErr = e; }
  }
  if (!res) throw lastErr;
  const parts = res?.candidates?.[0]?.content?.parts || [];
  return {
    text: parts.map((p) => p.text || "").join("").trim() || "Sorry, I couldn't come up with an answer right now.",
    model: res.model,
  };
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });

    if (request.method === "GET") {
      return json({ name: "HEARTS RAG agent", status: "ok", guidelines: GUIDELINES.length, usage: "POST /ask {question, patient?, environment?}" });
    }
    if (request.method !== "POST" || url.pathname !== "/ask") return json({ error: "use POST /ask" }, 404);

    if (env.HEARTS_APP_KEY && request.headers.get("x-hearts-key") !== env.HEARTS_APP_KEY) {
      return json({ error: "unauthorized" }, 401);
    }
    if (!env.GEMINI_API_KEY) return json({ error: "GEMINI_API_KEY secret is not set" }, 500);

    let body;
    try { body = await request.json(); } catch { return json({ error: "body must be JSON" }, 400); }
    const question = (body.question || "").trim();
    if (!question) return json({ error: "missing 'question'" }, 400);

    try {
      const hits = await retrieve(env, question, body.environment);
      const out = await answer(env, question, body.patient, body.environment, hits);
      return json({
        answer: out.text,
        model: out.model,
        sources: hits.map(({ chunk: c, score }) => ({ id: c.id, title: c.title, source: c.source, score: Math.round(score * 1000) / 1000 })),
      });
    } catch (e) {
      return json({ error: String(e.message || e) }, 502);
    }
  },
};
