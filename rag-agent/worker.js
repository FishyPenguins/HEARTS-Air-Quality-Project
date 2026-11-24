// HEARTS RAG Agent (Cloudflare Worker)
//
// The iOS app sends a question plus the live air quality / weather data.
// This worker:
//   1. RETRIEVE - finds the guidelines that best match the question
//   2. AUGMENT  - adds those guidelines + the patient's data to the prompt
//   3. GENERATE - asks Gemini to write a short, simple answer
//
// Request:  POST /ask  { "question": "...", "patient": {...}, "environment": {...} }
// Response: { "answer": "...", "model": "...", "sources": [...] }
//
// The Gemini key is stored as a secret in Cloudflare (Settings > Variables): GEMINI_API_KEY


// ===================== GUIDELINES (our knowledge base) =====================
// These come straight from our "HEARTS Guidelines" spreadsheet (the one we sent to Yale).
// "text" is exactly what the sheet says the app should tell the patient.
// "link" is the government page (EPA, CDC, NIH) the guideline came from.
// If the sheet changes, update this list and redeploy.

const GUIDELINES = [
  {
    id: "aqi-daily",
    title: "Check the air quality every day",
    when: "Every day",
    text: "People with heart failure count as a 'sensitive group' for air pollution. Check the air quality (AQI) every day, using an app like AirNow. Don't wait to feel sick, because for heart patients the first sign can be serious.",
    source: "EPA Air Quality Guide for Particle Pollution (2015)",
    link: "https://www.airnow.gov/sites/default/files/2021-03/air-quality-guide_pm_2015_0.pdf",
  },
  {
    id: "aqi-101-150",
    title: "AQI 101-150 (orange)",
    when: "AQI 101-150",
    text: "The air is unhealthy for sensitive groups today. Cut back on long or hard activity outside.",
    source: "EPA Air Quality Guide for Particle Pollution (2015)",
    link: "https://www.airnow.gov/sites/default/files/2021-03/air-quality-guide_pm_2015_0.pdf",
  },
  {
    id: "aqi-151-200",
    title: "AQI 151-200 (red)",
    when: "AQI 151-200",
    text: "The air is unhealthy today. Avoid long or hard activity outside. Think about moving it indoors or doing it another day.",
    source: "EPA Air Quality Guide for Particle Pollution (2015)",
    link: "https://www.airnow.gov/sites/default/files/2021-03/air-quality-guide_pm_2015_0.pdf",
  },
  {
    id: "aqi-201-300",
    title: "AQI 201-300 (purple)",
    when: "AQI 201-300",
    text: "The air is very unhealthy today. Avoid all physical activity outside. Move it indoors or wait until the air is better.",
    source: "EPA Air Quality Guide for Particle Pollution (2015)",
    link: "https://www.airnow.gov/sites/default/files/2021-03/air-quality-guide_pm_2015_0.pdf",
  },
  {
    id: "aqi-301-plus",
    title: "AQI 301 or higher (maroon)",
    when: "AQI 301 or higher",
    text: "The air is hazardous today. Stay indoors and keep activity low. Keep the air inside your home as clean as you can.",
    source: "EPA Air Quality Guide for Particle Pollution (2013)",
    link: "https://portal.ct.gov/-/media/deep/air/aqi/airqualityguidepm2013pdf.pdf",
  },
  {
    id: "aqi-symptoms",
    title: "Symptoms on a bad air day",
    when: "AQI over 100 and the patient has symptoms",
    text: "On a bad air day, a racing or pounding heartbeat, shortness of breath, or unusual tiredness can mean a serious problem. Contact your care team.",
    source: "EPA Air Quality Guide for Particle Pollution (2015)",
    link: "https://www.airnow.gov/sites/default/files/2021-03/air-quality-guide_pm_2015_0.pdf",
  },
  {
    id: "heat-daily",
    title: "Check the heat forecast",
    when: "Warm months; HeatRisk orange or higher",
    text: "During warm months, check the heat forecast every day. Take steps to stay cool when the heat risk is orange or higher.",
    source: "CDC - Clinical Overview of Heat and Cardiovascular Disease",
    link: "https://www.cdc.gov/heat-health/hcp/clinical-overview/heat-and-people-with-cardiovascular-disease.html",
  },
  {
    id: "heat-and-air",
    title: "Hot days with bad air",
    when: "Hot day and AQI over 100",
    text: "Hot days can make the air quality worse too. On hot days, check both the heat forecast and the AQI.",
    source: "CDC - Clinical Overview of Heat and Cardiovascular Disease",
    link: "https://www.cdc.gov/heat-health/hcp/clinical-overview/heat-and-people-with-cardiovascular-disease.html",
  },
  {
    id: "heat-cooling",
    title: "How to stay cool",
    when: "Hot days",
    text: "Spend time in air conditioning. Even a few hours a day helps. If you don't have AC at home, go to a cool public place like a library or mall. Fans don't prevent heat illness once it's in the high 90s.",
    source: "CDC - Extreme Heat: A Prevention Guide",
    link: "http://emergency.cdc.gov/disasters/extremeheat/heat_guide.asp",
  },
  {
    id: "heat-meds",
    title: "Heart medicines on hot days",
    when: "Hot days; patient takes water pills or blood pressure medicine",
    text: "Some heart medicines, like water pills, can make heat harder on your body. Don't stop or change any medicine on your own. Ask your care team for a plan for hot days.",
    source: "CDC - Heat and Medications: Guidance for Clinicians",
    link: "https://www.cdc.gov/heat-health/hcp/clinical-guidance/heat-and-medications-guidance-for-clinicians.html",
  },
  {
    id: "cold-weather",
    title: "Cold weather",
    when: "Cold days",
    text: "Cold weather puts extra strain on the heart. Avoid hard work in the cold, like shoveling snow, unless your doctor says it's OK.",
    source: "Maine Emergency Management Agency - Cold weather is hard on your heart",
    link: "https://maine.gov/mema/tips/cold-weather-hard-your-heart",
  },
  {
    id: "warning-signs",
    title: "Heart failure warning signs",
    when: "Any time",
    text: "Call your care team if you feel tired or weak, are short of breath when active or at rest, get short of breath lying down, are wheezing, have a cough that won't go away, have swelling in your feet, ankles, or legs, or have gained or lost weight.",
    source: "NIH MedlinePlus - Heart failure: home monitoring",
    link: "https://medlineplus.gov/ency/patientinstructions/000113.htm",
  },
  {
    id: "weight-gain",
    title: "Daily weight check",
    when: "Daily weigh-in",
    text: "Weigh yourself every morning on the same scale, before you eat and after you use the bathroom. Call your care team if your weight goes up more than 2 to 3 pounds in a day or 5 pounds in a week.",
    source: "NIH MedlinePlus - Heart failure: home monitoring",
    link: "https://medlineplus.gov/ency/patientinstructions/000113.htm",
  },
  {
    id: "call-911",
    title: "When to call 911",
    when: "Any time",
    text: "Call 911 or go to the emergency room if you faint, have a fast and irregular heartbeat (especially with other symptoms), or have severe crushing chest pain.",
    source: "NIH MedlinePlus - Heart failure",
    link: "https://medlineplus.gov/ency/article/000158.htm",
  },
];


// ===================== SETTINGS =====================

const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/";
const EMBEDDING_MODEL = "gemini-embedding-001";
const CHAT_MODELS = ["gemini-flash-latest", "gemini-2.5-flash", "gemini-flash-lite-latest"]; // tried in order
const NUMBER_OF_GUIDELINES_TO_USE = 3;
const TIMEOUT_MS = 12000; // give up on a Gemini call after 12 seconds

const INSTRUCTIONS = `You are the HEARTS assistant in an app for people with heart failure.
Rules:
- Use plain, simple language. Keep the answer under 120 words.
- Only give health advice that comes from the guidelines you are given.
- If the guidelines don't cover the question, say so and tell them to ask their care team.
- Use today's air quality and weather when it matters.
- Never tell someone to change or stop a medicine. Never diagnose.
- If they mention chest pain, fainting, or severe trouble breathing, tell them to call 911 right away.`;

const HEADERS = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
};


// ===================== HELPERS =====================

// Sends a request to Gemini. Tries twice in case Google is busy.
async function callGemini(env, model, action, body) {
  let lastError = "";

  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const response = await fetch(GEMINI_URL + model + ":" + action, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      if (response.ok) {
        return await response.json();
      }
      lastError = "Gemini error " + response.status;
    } catch (error) {
      lastError = "Gemini did not respond: " + error.message;
    }
  }

  throw new Error(lastError);
}

// Turns a list of texts into embeddings (lists of numbers that capture meaning).
async function getEmbeddings(env, texts) {
  const requests = texts.map((text) => ({
    model: "models/" + EMBEDDING_MODEL,
    content: { parts: [{ text: text }] },
  }));
  const result = await callGemini(env, EMBEDDING_MODEL, "batchEmbedContents", { requests: requests });
  return result.embeddings.map((e) => e.values);
}

// Cosine similarity: how close two embeddings are (1 = same meaning, 0 = unrelated).
function similarity(a, b) {
  let dot = 0;
  let lengthA = 0;
  let lengthB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    lengthA += a[i] * a[i];
    lengthB += b[i] * b[i];
  }
  return dot / (Math.sqrt(lengthA) * Math.sqrt(lengthB));
}

// Picks the AQI guideline that matches today's number.
function aqiGuidelineFor(aqi) {
  if (aqi > 300) return "aqi-301-plus";
  if (aqi > 200) return "aqi-201-300";
  if (aqi > 150) return "aqi-151-200";
  if (aqi > 100) return "aqi-101-150";
  return null;
}

// Describes today's conditions in words so the search can match them.
function describeConditions(environment) {
  let text = "";
  if (environment.aqi != null) text += "The air quality index (AQI) is " + Math.round(environment.aqi) + ". ";
  if (environment.temperatureF != null) text += "The temperature is " + Math.round(environment.temperatureF) + "F. ";
  if (environment.heatIndexF != null) text += "It feels like " + Math.round(environment.heatIndexF) + "F. ";
  return text;
}


// ===================== STEP 1: RETRIEVE =====================

let guidelineEmbeddings = null; // saved so we only make them once

async function findGuidelines(env, question, environment) {
  // Make embeddings for every guideline (only the first time)
  if (guidelineEmbeddings == null) {
    guidelineEmbeddings = await getEmbeddings(env, GUIDELINES.map((g) => g.title + ". " + g.when + ". " + g.text));
  }

  // Make an embedding for the question + today's conditions
  const searchText = question + " " + describeConditions(environment);
  const questionEmbedding = (await getEmbeddings(env, [searchText]))[0];

  // Score every guideline and sort best match first
  let results = GUIDELINES.map((guideline, i) => ({
    guideline: guideline,
    score: similarity(questionEmbedding, guidelineEmbeddings[i]),
  }));
  results.sort((a, b) => b.score - a.score);

  // If the air is unhealthy, always include the guideline for today's AQI level
  const aqiId = aqiGuidelineFor(environment.aqi);
  if (aqiId != null) {
    const aqiResult = results.find((r) => r.guideline.id == aqiId);
    results = [aqiResult].concat(results.filter((r) => r != aqiResult));
  }

  return results.slice(0, NUMBER_OF_GUIDELINES_TO_USE);
}


// ===================== STEP 2 + 3: AUGMENT AND GENERATE =====================

async function writeAnswer(env, question, patient, environment, matches) {
  // Build the prompt: guidelines + patient + conditions + question
  let prompt = "Guidelines:\n";
  for (const match of matches) {
    prompt += "- " + match.guideline.title + ": " + match.guideline.text + "\n";
  }
  prompt += "\nPatient: " + JSON.stringify(patient);
  prompt += "\nToday's conditions: " + JSON.stringify(environment);
  prompt += "\n\nQuestion: " + question;

  const body = {
    system_instruction: { parts: [{ text: INSTRUCTIONS }] },
    contents: [{ role: "user", parts: [{ text: prompt }] }],
  };

  // Try each model until one works
  for (const model of CHAT_MODELS) {
    try {
      const result = await callGemini(env, model, "generateContent", body);
      const answer = result.candidates[0].content.parts[0].text;
      return { answer: answer.trim(), model: model };
    } catch (error) {
      console.log(model + " failed: " + error.message);
    }
  }
  throw new Error("All Gemini models failed. Try again in a minute.");
}


// ===================== MAIN: handles requests from the app =====================

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method == "OPTIONS") {
      return new Response(null, { headers: HEADERS });
    }

    // Quick check that the agent is running
    if (request.method == "GET") {
      return Response.json({ status: "ok", guidelines: GUIDELINES.length }, { headers: HEADERS });
    }

    if (request.method != "POST" || url.pathname != "/ask") {
      return Response.json({ error: "Use POST /ask" }, { status: 404, headers: HEADERS });
    }

    const data = await request.json().catch(() => ({}));
    const question = (data.question || "").trim();
    const patient = data.patient || {};
    const environment = data.environment || {};

    if (question == "") {
      return Response.json({ error: "Missing question" }, { status: 400, headers: HEADERS });
    }

    try {
      const matches = await findGuidelines(env, question, environment);
      const result = await writeAnswer(env, question, patient, environment, matches);

      return Response.json({
        answer: result.answer,
        model: result.model,
        sources: matches.map((m) => ({
          id: m.guideline.id,
          title: m.guideline.title,
          source: m.guideline.source,
          link: m.guideline.link,
          score: Math.round(m.score * 100) / 100,
        })),
      }, { headers: HEADERS });
    } catch (error) {
      return Response.json({ error: error.message }, { status: 502, headers: HEADERS });
    }
  },
};
