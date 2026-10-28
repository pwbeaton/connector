# How the scores work

Every number here is an **estimate for motivation, not a medical measure**. All constants live in `App/Engine/ScoreTuning.swift`; change them there after a week or two of real data. Every rule below has unit tests in `Tests/Engine/`.

## Inputs (from Google Health, per day)
| Input | Google Health data type | Notes |
|---|---|---|
| HRV | `daily-heart-rate-variability` → `averageHeartRateVariabilityMilliseconds` | Nightly RMSSD in ms |
| Resting HR | `daily-resting-heart-rate` → `beatsPerMinute` | |
| Sleep | `sleep` (main sleep only) → `summary.minutesAsleep`, `minutesInSleepPeriod`, stage minutes | The night belongs to the day you woke up. Naps are tracked separately. |
| Steps, distance | `steps`, `distance` daily roll-ups | |
| Active Zone Minutes (AZM) | `active-zone-minutes` daily roll-up | Fitbit already counts cardio and peak minutes double |
| VO₂ max | `daily-vo2-max` | Used only by biological age |
| Age | `users/me/profile` → `age` | Used only by biological age; the user can override it on the phone |

**A missing value is never zero.** If the tracker wasn't worn or hasn't synced, the day shows "no data", and goals for it are neither met nor missed until the data arrives (or 2 days pass).

## Baselines
Your personal baseline for HRV and for resting HR is the **median of the previous 30 days**, not counting the day being scored. Until there are **7 nights** of HRV, Recovery shows **Calibrating (n/7)**.

## Recovery (0–100)
How ready your body is this morning.

| Part | Weight | 100 points when… | 0 points when… |
|---|---|---|---|
| HRV vs baseline | 50% | 20% above baseline | 20% below baseline |
| Resting HR vs baseline | 20% | 5 bpm below baseline | 5 bpm above baseline |
| Sleep score | 30% | (the Sleep score itself) | |

Being exactly at your baseline gives 50 for the HRV and resting HR parts. If resting HR or sleep is missing, the remaining parts are re-weighted. If last night's HRV is missing, Recovery is "unavailable" rather than guessed.

**Bands:** **Go** 67–100 · **Steady** 34–66 · **Recover** 0–33.

## Sleep (0–100)
Tightened on 2026-10-27: the first version averaged about 90 on ordinary nights, which hid real shortfalls.

| Part | Points | Scoring | Why |
|---|---|---|---|
| Duration | 50 | 50 × (asleep ÷ goal)², capped at the goal (default 7 h 30 min). 90% of goal → 40.5, 80% → 32 | Deficits compound: two weeks of 6-hour nights impaired people as much as one to two nights without sleep (Van Dongen et al., *Sleep* 2003). Adults need 7+ hours (AASM/SRS consensus, Watson et al. 2015). |
| Restoration | 25 | Deep + REM share of time asleep: 0 at 20%, full at 42%. Nights without stage data get 50% | Young-adult norms are roughly 15–20% deep and 20–25% REM (Ohayon et al., *Sleep* 2004). |
| Efficiency | 15 | Asleep ÷ time in bed: 0 at 80%, full at 95% | The National Sleep Foundation counts 85%+ as good sleep quality (Ohayon et al., *Sleep Health* 2017). |
| Consistency | 10 | Wake time vs your usual (past week): full when on time, 0 at 60 minutes off. With fewer than 3 earlier nights, 7 points | Later and more variable sleep timing is linked to worse health (Chaput et al. 2020 review; NSF regularity consensus 2023). |

A typical good night (7 h 20 m on a 7 h 30 m goal, 36% deep + REM, 90% efficiency, on time) now scores about 83; a run of 6 h 20 m nights at 88% efficiency averages about 66.

## Effort (0–100)
`Effort = 100 × (1 − e^(−AZM / 45))`. It climbs quickly at first, then flattens, so 100 is rare.

| AZM | 10 | 22 | 30 | 45 | 60 | 90 |
|---|---|---|---|---|---|---|
| Effort | 20 | 39 | 49 | 63 | 74 | 86 |

**Effort target** for the day, from this morning's Recovery band:

| Band | Target |
|---|---|
| Go | 60–80 |
| Steady | 40–60 |
| Recover | 15–35 |

While Recovery is calibrating, the target is 40–60.

**"On target"** means reaching the bottom of the range. On Recover days, going over the top doesn't count, because rest is the goal.

## Streaks
There are three streaks: **sleep goal**, **step goal**, and **Effort on target**.
- Each day the goal is met adds 1.
- Every 7 days in a row earns a **rest token** (bank up to 2). A token covers one missed day without breaking the streak.
- Today counts as soon as the goal is met, but can't break a streak, because the day isn't over.
- A day with no data stays pending for 2 days; after that, it counts as missed.

## Training tier
**Consistency** = goals hit ÷ goals possible over the last 28 complete days (3 goals per day). Days without data count as missed: showing up is the point. The window never reaches back before your first day of data, and the first 7 days are "calibrating".

| Tier | Rookie | Bronze | Silver | Gold | Platinum | Elite |
|---|---|---|---|---|---|---|
| Consistency | < 40% | 40% | 55% | 70% | 82% | 92% |

## Weekly challenges
**Personal:** three each week (Monday–Sunday), rotating through six kinds. The targets stretch your own last 4 weeks by about 10%:
- **Steps total:** average daily steps × 7 × 1.1, rounded up to 500.
- **Active Zone Minutes total:** the same, at least 150 (the WHO's weekly guideline).
- **Sleep goal nights, step goal days, Effort-on-target days:** one more than your usual weekly count, between 3 and 7.
- **Wake within 30 minutes of your usual time:** 5 days.

**Group:** one challenge shared by the whole group, rotating weekly. The order is most steps → most Active Zone Minutes → most nights of 7+ hours → best average sleep. The rotation is `((week_start − 2024-01-01) / 7) mod 4`, computed identically on the phone and the server.

## Leaderboards
Leaderboards rank **Effort, steps, average sleep, and the group challenge**. **Recovery, HRV, and resting HR are never ranked.** They reflect personal physiology, so they appear on cards only. Friends who don't share a category simply don't appear on its leaderboard.

## Badges and records
There are 20 badges (`Badges.all` in `App/Engine/Achievements.swift`), each dated the first day it was earned. Each has a short "how to earn" line (shown under it in Profile) and a "why it matters" sentence (shown when tapped). Records track your best day for steps, AZM, sleep, HRV, Recovery, and streak length, plus your lowest resting HR.

## Day-to-day change and trends
- **Today cards** show each score's change from the day before ("▲ 6 vs yesterday"): green up and red down for Recovery and Sleep, blue either way for Effort (more isn't always better). Today's Effort is unfinished, so the card shows yesterday's final Effort instead of a change.
- **Detail screens** (tap Recovery, Sleep, or Effort) chart 7, 30, or 90 days with a 7-day rolling average, and compare the last 7 days' average with the 7 days before: a change of 2 points or more is "trending up/down" (`ScoreTrend` in `App/Engine/ScoreTrend.swift`).
- Swipe right on Today (or use the arrows) to see any earlier day back to the first synced day, at most 90 days ago.

## Sleep tip
One tip per night (`SleepTip` in `App/Engine/SleepTip.swift`), shown on the Sleep detail screen, aimed at the part of the Sleep score that lost the most points: duration (tonight's planned bedtime), consistency (wake closer to your usual time, named), efficiency, or deep + REM. Consistency is skipped until there are 3 nights of history and deep + REM when the night has no stages. If nothing lost 2+ points, it says so.

## Sleep debt and tonight's bedtime
`SleepDebt` and `BedtimePlan` in `App/Engine/SleepDebt.swift`.
- **Debt** = the weighted sum of (goal − minutes asleep) over the last **14 nights** (the window RISE uses), with last night counting fully and the oldest night half. Nights over the goal pay it down; the total never goes below zero. Needs 5 nights. Under 2 h is low, 2–5 h moderate, over 5 h high (RISE suggests staying under 5 h).
- **Tonight's bedtime** = usual wake time (last 7 nights) − sleep goal − a slice of debt − the time you usually lie awake. The slice is debt ÷ 4, capped at 60 minutes, because one hour of debt takes about four nights of extra sleep to repay (Kitamura et al., *Scientific Reports* 2016). Wake time stays fixed.
- The body clock advances about an hour a day at most, so the bedtime never moves more than **60 minutes earlier than your usual bedtime** in one night; the detail screen shows the full catch-up bedtime when it's held back.
- Today shows the bedtime, how much earlier or later it is than usual, and the debt. The Sleep detail screen shows a 14-night chart of each night against the goal.

## Biological age
An effective-age estimate (`BiologicalAge` in `App/Engine/BiologicalAge.swift`), the method behind WHOOP Age, heart age, and lung age:

1. Each metric's published all-cause mortality hazard ratio (HR) against a healthy reference is turned into years with the Gompertz law: mortality rises about 10% per adult year, so **years = ln(HR) / ln(1.10) ≈ 10.5 × ln(HR)**.
2. **Biological age = your age + the sum of those years**, from the last **60 days** (at least **14 days** of data; adults only).
3. VO₂ max + resting HR, and steps + AZM, overlap (both pairs measure the same fitness or activity), so each of those four counts at **75%**.
4. **Trend**: today's estimate against the one 28 days earlier (or the earliest one at least 7 days back). ±0.2 years or less is steady (yellow); younger is improving (green); older is getting worse (red).

| Metric | Reference (neutral) | Risk used | Limits (years, before overlap) |
|---|---|---|---|
| VO₂ max (median) | WHOOP's age- and sex-specific minimums (e.g. 44 for a 30-year-old man, 38 for a woman); average of both if sex isn't set | HR 0.87 per +3.5 ml/kg/min (1 MET): Kodama et al., *JAMA* 2009 | −5 to +8 |
| Resting HR (median) | 60 bpm men, 64 women, 62 unset | HR 1.09 per +10 bpm: Zhang et al., *CMAJ* 2016 | −2 to +4 |
| Daily steps (completed days) | 8,000 (6,000 at 60+) | Paluch et al., *Lancet Public Health* 2022 quartiles: 3,553 → HR 1, 5,801 → 0.60, 7,842 → 0.55, 10,901 → 0.47 | −1.5 to +4 |
| Weekly AZM | 150 (the WHO guideline) | Arem et al., *JAMA Intern Med* 2015: none → 1, under guideline → 0.80, 1–2× → 0.69, 2–3× → 0.63, 3–5× → 0.61 | −1.5 to +4 |
| Sleep duration (average) | 7–9 h earns −0.3 years; over 9 h is neutral | HR 1.12 for short sleep, per hour under 7 h up to 2 h: Cappuccio et al., *Sleep* 2010 | 0 to +2.4 |
| Sleep consistency (spread of wake times) | ±60 min | Windred et al., *Sleep* 2024: most vs least regular HR 0.70; mapped ±20 min → −1.3, ±2 h → +2.2 | −1.3 to +2.2 |

HRV is left out on purpose: it varies too much between people to compare with population norms (WHOOP leaves it out for the same reason). Strength training and lean mass aren't measured by the Fitbit Air, so they have no effect. Method reference: the WHOOP Healthspan white paper (2025).
