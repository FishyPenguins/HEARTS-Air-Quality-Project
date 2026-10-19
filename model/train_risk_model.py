"""
HEARTS risk model trainer.

Trains the logistic regression the iOS app runs on the phone, then writes:
  - HEARTS Project/Risk/hearts_risk_model.json    (coefficients the app loads)
  - HEARTS Project/Patients/hearts_patients.json  (the fake patients the app can switch between)
  - model/model_report.md                         (what the model learned and how well)

IMPORTANT: everything here is FAKE. The 38 patients are made up (HEARTS_fake_patients_v2) and the
daily air, heat and hospitalizations below are simulated. The numbers are not real predictions.

How it works
------------
1. Each fake patient gets three simulated years of daily weather and PM2.5 for their town.
   Polluted/disadvantaged towns get dirtier air, and a few wildfire smoke days are mixed in.
2. A "true" daily hospitalization chance is made from the patient's chart (NYHA class, NT-proBNP,
   prior HF stays, and so on) plus the air and heat that day. Each day is then a coin flip.
3. We fit a regularized logistic regression on the chart features.
   38 patients is far too few to learn the air effect (the prototype on Oct 6 got it backwards),
   so the air and heat effects are FIXED to published sizes and passed in as an offset:
     - PM2.5, lag 0-1 day average: +1.3% risk per 10 ug/m3 (Chen et al. 2023, 51 studies)
     - Heat index above 80F: +1.5% per degree F   (placeholder until we get Ni et al. 2026 numbers)
     - Cold below 32F:       +0.8% per degree F   (placeholder, effect shows up 3-5 days later)
4. Patients are split 5 ways to check how well it ranks risk on patients it never saw (AUC).

Run:  python3 model/train_risk_model.py
"""

import csv
import json
import math
import os
from datetime import date

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_PATH = os.path.join(ROOT, "model", "data", "HEARTS_fake_patients_v2.csv")
MODEL_OUT = os.path.join(ROOT, "HEARTS Project", "Risk", "hearts_risk_model.json")
PATIENTS_OUT = os.path.join(ROOT, "HEARTS Project", "Patients", "hearts_patients.json")
REPORT_OUT = os.path.join(ROOT, "model", "model_report.md")

SEED = 491
DAYS = 3 * 365    # three simulated years per patient
HORIZON_DAYS = 7

# Published / placeholder environment effects (relative risk per unit), used as a fixed offset.
PM25_RR_PER_10 = 1.013          # Chen et al. 2023
HEAT_THRESHOLD_F = 80.0
HEAT_RR_PER_F = 1.015           # placeholder
COLD_THRESHOLD_F = 32.0
COLD_RR_PER_F = 1.008           # placeholder

ENV = {
    "pm25PerUgm3": math.log(PM25_RR_PER_10) / 10.0,
    "heatIndexThresholdF": HEAT_THRESHOLD_F,
    "heatPerDegreeF": math.log(HEAT_RR_PER_F),
    "coldThresholdF": COLD_THRESHOLD_F,
    "coldPerDegreeF": math.log(COLD_RR_PER_F),
    "referencePM25": 5.0,
}

# Chart features: key, label shown in the app, how to compute it from a patient row.
def yes(v):
    return 1.0 if str(v).strip().lower() == "yes" else 0.0

FEATURES = [
    ("age10", "Age", lambda p: p["age"] / 10.0),
    ("nyha", "NYHA class", lambda p: float(p["nyhaClass"])),
    ("logNTproBNP", "NT-proBNP level", lambda p: math.log(p["ntProBNP"])),
    ("priorHFStays", "Past heart failure hospital stays", lambda p: float(min(p["priorHFHospitalizations"], 5))),
    ("reducedEF", "Weak heart pump (EF 40% or less)", lambda p: 1.0 if p["ejectionFraction"] <= 40 else 0.0),
    ("ckd", "Kidney disease", lambda p: yes(p["ckd"])),
    ("diabetes", "Diabetes", lambda p: yes(p["diabetes"])),
    ("copd", "COPD", lambda p: yes(p["copd"])),
    ("lowSodium", "Low sodium (under 135)", lambda p: 1.0 if p["sodium"] < 135 else 0.0),
    ("homeOxygen", "Uses home oxygen", lambda p: 1.0 if p["homeOxygenL"] > 0 else 0.0),
    ("sglt2", "Takes an SGLT2 inhibitor", lambda p: yes(p["onSGLT2"])),
    ("pollutedArea", "Lives in a polluted area", lambda p: 1.0 if p["areaType"].startswith("Polluted") else 0.0),
]

# The made-up "truth" used only to simulate outcomes (log-odds per unit of each feature).
TRUTH = {
    "age10": 0.12, "nyha": 0.35, "logNTproBNP": 0.40, "priorHFStays": 0.22, "reducedEF": 0.20,
    "ckd": 0.30, "diabetes": 0.18, "copd": 0.22, "lowSodium": 0.28, "homeOxygen": 0.30,
    "sglt2": -0.25, "pollutedArea": 0.08,
}
TRUTH_INTERCEPT = -10.6


def to_bool(v):
    return yes(v) == 1.0


def load_patients():
    rows = list(csv.DictReader(open(CSV_PATH, newline="", encoding="utf-8")))
    patients = []
    for r in rows:
        sys_bp, dia_bp = (int(x) for x in r["Blood pressure"].split("/"))
        patients.append({
            "id": r["Patient"],
            "age": int(r["Age"]),
            "gender": r["Gender"],
            "zip": r["Home zip code"].zfill(5),
            "town": r["Town"],
            "areaType": r["Area type"],
            "insurance": r["Insurance status"],
            "employment": r["Employment status"],
            "diabetes": r["Diabetes"], "hypertension": r["Hypertension"], "copd": r["COPD"],
            "ckd": r["Chronic kidney disease"], "cad": r["Coronary artery disease"],
            "sleepApnea": r["Sleep apnea"],
            "homeOxygenL": float(r["Home oxygen (L)"] or 0),
            "bmi": float(r["BMI"]),
            "sodium": float(r["Sodium (mEq/L)"]),
            "ntProBNP": float(r["NT-proBNP (pg/mL)"]),
            "nyhaClass": int(r["NYHA class"]),
            "ejectionFraction": int(r["Ejection fraction (%)"]),
            "priorHFHospitalizations": int(r["Prior HF hospitalizations"]),
            "heartRate": int(r["Heart rate (bpm)"]),
            "systolicBP": sys_bp, "diastolicBP": dia_bp,
            "o2Saturation": int(r["O2 saturation (%)"]),
            "medications": [m.strip() for m in r["Home medications"].split(",") if m.strip()],
            "onDiuretics": r["On diuretics"], "onBetaBlockers": r["On beta blockers"],
            "onSGLT2": r["On SGLT2 inhibitor"],
            "lastHFHospitalization": r["Most recent HF hospitalization"],
        })
    return patients


def heat_index_f(t, rh):
    """NOAA Rothfusz heat index (same formula the app uses)."""
    if t < 80:
        return t
    hi = (-42.379 + 2.04901523 * t + 10.14333127 * rh - 0.22475541 * t * rh
          - 0.00683783 * t * t - 0.05481717 * rh * rh + 0.00122874 * t * t * rh
          + 0.00085282 * t * rh * rh - 0.00000199 * t * t * rh * rh)
    return hi


def simulate_year(rng, polluted):
    doy = np.arange(DAYS)
    temp = 52 + 23 * np.sin(2 * np.pi * (doy - 110) / 365.0) + rng.normal(0, 7, DAYS)
    rh = np.clip(rng.normal(65, 12, DAYS), 20, 100)
    hi = np.array([heat_index_f(t, h) for t, h in zip(temp, rh)])
    median = 10.0 if polluted else 6.5
    pm = rng.lognormal(math.log(median), 0.5, DAYS)
    smoke = rng.choice(DAYS, size=4, replace=False)        # a few wildfire smoke days
    pm[smoke] = rng.uniform(60, 150, size=4)
    pm_lag01 = (pm + np.concatenate([[pm[0]], pm[:-1]])) / 2.0
    return temp, hi, pm_lag01


def env_offset(temp, hi, pm_lag01):
    return (ENV["pm25PerUgm3"] * (pm_lag01 - ENV["referencePM25"])
            + ENV["heatPerDegreeF"] * np.maximum(0, hi - HEAT_THRESHOLD_F)
            + ENV["coldPerDegreeF"] * np.maximum(0, COLD_THRESHOLD_F - temp))


def build_dataset(patients, rng):
    X, offs, y, groups = [], [], [], []
    for gi, p in enumerate(patients):
        x = np.array([f(p) for _, _, f in FEATURES])
        temp, hi, pm = simulate_year(rng, p["areaType"].startswith("Polluted"))
        off = env_offset(temp, hi, pm)
        truth = TRUTH_INTERCEPT + sum(TRUTH[k] * x[i] for i, (k, _, _) in enumerate(FEATURES))
        prob = 1 / (1 + np.exp(-(truth + off)))
        events = rng.random(DAYS) < prob
        X.append(np.tile(x, (DAYS, 1)))
        offs.append(off)
        y.append(events.astype(float))
        groups.append(np.full(DAYS, gi))
    return np.vstack(X), np.concatenate(offs), np.concatenate(y), np.concatenate(groups)


def fit_logistic(X, y, offset, l2=5.0, iters=50):
    """Newton-Raphson logistic regression with a fixed offset and an L2 penalty (intercept not penalized)."""
    n, k = X.shape
    A = np.hstack([np.ones((n, 1)), X])
    beta = np.zeros(k + 1)
    beta[0] = math.log(max(y.mean(), 1e-6) / (1 - max(y.mean(), 1e-6)))
    pen = np.full(k + 1, l2)
    pen[0] = 0
    for _ in range(iters):
        eta = A @ beta + offset
        mu = 1 / (1 + np.exp(-eta))
        w = mu * (1 - mu)
        grad = A.T @ (y - mu) - pen * beta
        H = (A * w[:, None]).T @ A + np.diag(pen)
        step = np.linalg.solve(H, grad)
        beta += step
        if np.max(np.abs(step)) < 1e-8:
            break
    return beta


def auc(scores, labels):
    order = np.argsort(scores)
    ranks = np.empty(len(scores))
    ranks[order] = np.arange(1, len(scores) + 1)
    pos = labels == 1
    n_pos, n_neg = pos.sum(), (~pos).sum()
    if n_pos == 0 or n_neg == 0:
        return float("nan")
    return float((ranks[pos].sum() - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg))


def main():
    rng = np.random.default_rng(SEED)
    patients = load_patients()
    X_raw, offset, y, groups = build_dataset(patients, rng)

    # Standardize chart features using the patients (not the patient-days) so the app can reuse it.
    P = np.array([[f(p) for _, _, f in FEATURES] for p in patients])
    means, scales = P.mean(axis=0), P.std(axis=0)
    scales[scales == 0] = 1.0
    X = (X_raw - means) / scales

    # Cross-validated check, holding out whole patients.
    folds = np.arange(len(patients)) % 5
    rng.shuffle(folds)
    cv_scores, cv_labels = [], []
    for f in range(5):
        test = np.isin(groups, np.where(folds == f)[0])
        b = fit_logistic(X[~test], y[~test], offset[~test])
        eta = np.hstack([np.ones((test.sum(), 1)), X[test]]) @ b + offset[test]
        cv_scores.append(eta)
        cv_labels.append(y[test])
    cv_auc = auc(np.concatenate(cv_scores), np.concatenate(cv_labels))

    beta = fit_logistic(X, y, offset)
    intercept, coefs = float(beta[0]), beta[1:]

    def week_risk(p, pm25=ENV["referencePM25"], hi=70.0, temp=60.0):
        x = (np.array([f(p) for _, _, f in FEATURES]) - means) / scales
        off = env_offset(np.array([temp]), np.array([hi]), np.array([pm25]))[0]
        pd = 1 / (1 + math.exp(-(intercept + x @ coefs + off)))
        return 1 - (1 - pd) ** HORIZON_DAYS

    baseline = np.array([week_risk(p) for p in patients])
    levels = [
        {"name": "Low", "below": 0.02},
        {"name": "Moderate", "below": 0.05},
        {"name": "Elevated", "below": 0.10},
        {"name": "High", "below": None},
    ]

    model = {
        "name": "HEARTS heart failure risk model",
        "version": f"0.1-{date.today().isoformat()}",
        "horizonDays": HORIZON_DAYS,
        "trainedOn": f"{len(patients)} FAKE patients (HEARTS_fake_patients_v2) x {DAYS} simulated days",
        "disclaimer": "Prototype trained on fake patients and simulated air. Not a real prediction.",
        "intercept": intercept,
        "features": [
            {"key": k, "label": label, "coef": float(c), "mean": float(m), "scale": float(s)}
            for (k, label, _), c, m, s in zip(FEATURES, coefs, means, scales)
        ],
        "environment": ENV,
        "environmentSources": {
            "pm25": "Chen et al. 2023, Frontiers in Public Health (+1.3% per 10 ug/m3, lag 0-1 day)",
            "heat": "Placeholder (+1.5% per F above 80F heat index) until Ni et al. 2026 numbers are in",
            "cold": "Placeholder (+0.8% per F below 32F), effect shows up 3-5 days later (Ni et al. 2026)",
        },
        "levels": levels,
        "metrics": {
            "patientDays": int(len(y)),
            "events": int(y.sum()),
            "crossValidatedAUC": round(cv_auc, 3),
        },
    }
    os.makedirs(os.path.dirname(MODEL_OUT), exist_ok=True)
    json.dump(model, open(MODEL_OUT, "w"), indent=2)
    open(MODEL_OUT, "a").write("\n")

    os.makedirs(os.path.dirname(PATIENTS_OUT), exist_ok=True)
    json.dump(patients, open(PATIENTS_OUT, "w"), indent=2, ensure_ascii=False)
    open(PATIENTS_OUT, "a").write("\n")

    # Report
    lines = [
        "# HEARTS risk model report",
        "",
        "Generated by `model/train_risk_model.py`. Everything is trained on FAKE patients and simulated air, so these are not real predictions.",
        "",
        f"- Patient-days: {len(y):,} ({len(patients)} fake patients x {DAYS} simulated days)",
        f"- Simulated hospitalizations: {int(y.sum())}",
        f"- Cross-validated AUC (held-out patients): {cv_auc:.3f}",
        f"- Prediction window: next {HORIZON_DAYS} days",
        "",
        "## Chart features (learned)",
        "",
        "| Feature | Learned (log-odds per unit) | Truth used to simulate (per unit) |",
        "|---|---|---|",
    ]
    for (k, label, _), c, sc in zip(FEATURES, coefs, scales):
        lines.append(f"| {label} | {c / sc:+.2f} | {TRUTH[k]:+.2f} |")
    lines += [
        "",
        "## Air and heat (fixed from published studies)",
        "",
        "| Exposure | Effect | Source |",
        "|---|---|---|",
        f"| PM2.5, lag 0-1 day | +{(PM25_RR_PER_10 - 1) * 100:.1f}% per 10 ug/m3 | Chen et al. 2023 |",
        f"| Heat index above {HEAT_THRESHOLD_F:.0f}F | +{(HEAT_RR_PER_F - 1) * 100:.1f}% per F | Placeholder |",
        f"| Temperature below {COLD_THRESHOLD_F:.0f}F | +{(COLD_RR_PER_F - 1) * 100:.1f}% per F | Placeholder |",
        "",
        "## Risk levels (7-day risk)",
        "",
        "Low under 2%, Moderate 2 to 5%, Elevated 5 to 10%, High 10% or more.",
        "",
        "## Patients",
        "",
        "| Patient | Age | Town | NYHA | EF | 7-day risk (clean day) | 7-day risk (AQI ~150 smoke day, 95F feels-like) |",
        "|---|---|---|---|---|---|---|",
    ]
    for p, b in sorted(zip(patients, baseline), key=lambda t: -t[1]):
        bad = week_risk(p, pm25=55.0, hi=95.0, temp=88.0)
        lines.append(f"| {p['id']} | {p['age']} | {p['town']} | {p['nyhaClass']} | {p['ejectionFraction']}% | {b:.1%} | {bad:.1%} |")
    open(REPORT_OUT, "w").write("\n".join(lines) + "\n")

    print(f"AUC {cv_auc:.3f}, events {int(y.sum())}")
    print("levels:", {name: int(((baseline >= lo) & (baseline < hi)).sum()) for name, lo, hi in
                      [("Low", 0, .02), ("Moderate", .02, .05), ("Elevated", .05, .10), ("High", .10, 9)]})
    print(f"baseline 7-day risk: min {baseline.min():.3%} median {np.median(baseline):.3%} max {baseline.max():.3%}")


if __name__ == "__main__":
    main()
