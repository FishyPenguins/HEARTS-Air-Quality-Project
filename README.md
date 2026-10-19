# HEARTS-Air-Quality-Project
HEARTS: Health Exposome Advisory Response Technology System is an AI-powered health monitoring application designed to deliver proactive, personalized guidance based on real-time environmental exposures (such as air quality, temperature, and wildfire smoke).

## What the app does

- **Live map** with temperature, humidity, heat index, PM2.5, AQI and pollen for where you are.
- **Patient switcher:** pick one of 38 fake practice patients, or enter your own info, and the whole app tailors to that person. Use the arrows on the risk card to flip through people.
- **On-device risk model:** a logistic regression (see `model/`) scores each person's chance of a heart failure hospital stay in the next 7 days, with today's air and heat on top.
- **Risk details + what-if simulator:** see what's raising risk, and try a smoke day, heat wave or cold snap to watch the risk change.
- **Air and heat alerts:** a banner on the map, plus a phone notification once a day when conditions are risky for that person.
- **Ask HEARTS:** a RAG chat (Gemini through a Cloudflare Worker) that answers from 27 sourced summaries plus the person's chart, risk and live conditions. See `RAG_AGENT.md`.

All patient data is fake. HEARTS is a student research prototype, not medical advice.

