# HEARTS Gemini server (Cloudflare Worker)

The app never holds the Gemini key. It sends chat requests to this small Cloudflare Worker, which adds the key and forwards them to Google. So the repo can stay public and anyone who clones it gets a working chat.

```
app ──► https://hearts-gemini.<you>.workers.dev ──(adds key)──► Gemini
```

## Deploy (one time, about 10 minutes, free)

1. Sign up at https://dash.cloudflare.com/sign-up (free plan, no card).
2. **Workers & Pages** > **Create** > **Create Worker** (start from "Hello World"). Name it `hearts-gemini` and click **Deploy**.
3. Click **Edit code**, delete everything, paste in `gemini-proxy-worker.js` from this folder, and click **Deploy**.
4. Back on the Worker's page: **Settings** > **Variables and Secrets** > **Add**. Type: **Secret**, Name: `GEMINI_API_KEY`, Value: the Gemini key. Click **Deploy**.
5. Copy the Worker URL (like `https://hearts-gemini.yourname.workers.dev`) into `HeartsConfig.geminiProxyURL` in `HEARTS Project/Agent/HeartsConfig.swift` and commit.

Check it: opening the URL in a browser should say "HEARTS Gemini proxy is running."

## Changing the key

If Google revokes the key or you make a new one, change the `GEMINI_API_KEY` secret in step 4. Nobody has to update the app.

## What it allows

- Only `POST /v1beta/models/<model>:generateContent`, only for the Gemini models listed in the file, and only with the `X-HEARTS-App: hearts-ios` header the app sends.
- Requests are capped at 60 KB and answers at 4,096 tokens.
- The header isn't real security, since the repo is public. If someone starts abusing the URL, add a rate limit in the Cloudflare dashboard (Security > WAF > Rate limiting rules) or change the header value in both places.
