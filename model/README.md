# HEARTS risk model

`train_risk_model.py` trains the heart failure risk model the app runs on the phone.

```
python3 model/train_risk_model.py
```

It reads `data/HEARTS_fake_patients_v2.csv` and writes:

| File | What it is |
|---|---|
| `HEARTS Project/Risk/hearts_risk_model.json` | Coefficients the app loads (`RiskModel.swift`) |
| `HEARTS Project/Patients/hearts_patients.json` | The 38 fake patients the app can switch between |
| `model/model_report.md` | What it learned, AUC, and every patient's risk on a clean day vs a smoke + heat day |

**Everything here is fake.** The patients are made up and the daily air, heat and hospitalizations are simulated, so the numbers are not real predictions.

## How it works

1. Each fake patient gets three simulated years of daily weather and PM2.5 for their town. Polluted towns get dirtier air, plus a few wildfire smoke days.
2. Chart features (NYHA class, NT-proBNP, past HF stays, kidney disease, and so on) go into a regularized logistic regression.
3. Air and heat effects are **fixed to published sizes**, not learned, because 38 patients are far too few to learn them (the Oct 6 prototype got the air effect backwards):
   - PM2.5, lag 0-1 day: +1.3% per 10 µg/m³ (Chen et al. 2023, 51 studies)
   - Heat index above 80°F: +1.5% per °F (placeholder until we have Ni et al. 2026 numbers)
   - Below 32°F: +0.8% per °F (placeholder; cold acts 3 to 5 days later)
4. The output is the chance of a heart failure hospital stay in the next 7 days if today's conditions continue. Levels: Low under 2%, Moderate 2 to 5%, Elevated 5 to 10%, High 10%+.

The Swift scoring in `RiskModel.swift` uses the same feature keys as the Python. If you add a feature, add it in both places.

## When real data comes

Swap the CSV for real trial or GWTG registry data (same columns), replace the simulated outcomes with real hospitalizations, and retrain. With enough patients the air and heat effects can be learned instead of fixed.
