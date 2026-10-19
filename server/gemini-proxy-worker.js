// HEARTS Gemini proxy (Cloudflare Worker)
//
// The iOS app sends its Gemini request here instead of straight to Google.
// This Worker adds the Gemini API key (stored as a Cloudflare secret, never in the repo)
// and forwards the request. So anyone can clone the app and the chat just works.
//
// Deploy: Cloudflare dashboard > Workers & Pages > Create > Worker, paste this file,
// then Settings > Variables and Secrets > add a Secret named GEMINI_API_KEY.

const ALLOWED_MODELS = new Set([
  "gemini-3.5-flash-lite",
  "gemini-3.1-flash-lite",
  "gemini-3.6-flash",
  "gemini-3.8-flash",
]);
const APP_HEADER = "X-HEARTS-App"; // light filter so random bots hitting the URL get rejected
const MAX_BODY_BYTES = 60_000;
const MAX_OUTPUT_TOKENS = 4096;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/") {
      return new Response("HEARTS Gemini proxy is running.", { status: 200 });
    }

    const match = url.pathname.match(/^\/v1beta\/models\/([a-z0-9.\-]+):generateContent$/);
    if (request.method !== "POST" || !match) return error(404, "Not found.");
    if (request.headers.get(APP_HEADER) !== "hearts-ios") return error(403, "Forbidden.");

    const model = match[1];
    if (!ALLOWED_MODELS.has(model)) return error(400, `Model ${model} is not allowed.`);
    if (!env.GEMINI_API_KEY) return error(500, "GEMINI_API_KEY secret is not set on the server.");

    const raw = await request.text();
    if (raw.length > MAX_BODY_BYTES) return error(413, "Request too large.");

    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      return error(400, "Body must be JSON.");
    }
    // Only pass through the fields the app uses, and cap the output length.
    const forwarded = {
      systemInstruction: body.systemInstruction,
      contents: body.contents,
      generationConfig: {
        maxOutputTokens: Math.min(Number(body.generationConfig?.maxOutputTokens) || 2048, MAX_OUTPUT_TOKENS),
      },
    };

    const upstream = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
        body: JSON.stringify(forwarded),
      },
    );
    return new Response(upstream.body, {
      status: upstream.status,
      headers: { "Content-Type": "application/json" },
    });
  },
};

function error(status, message) {
  return new Response(JSON.stringify({ error: { code: status, message } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
