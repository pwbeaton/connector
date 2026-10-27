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
| Part | Points | Full points when… |
|---|---|---|
| Duration | 50 | Asleep for at least your sleep goal (default 7 h 30 min) |
| Restoration | 25 | Deep + REM are at least 40% of time asleep. Nights without stage data get 60% of these points. |
| Efficiency | 15 | Asleep ÷ time in bed is 95% or more (0 points at 75%) |
| Consistency | 10 | You woke at your usual time (average of the past week). 0 points at 90 minutes off. With fewer than 3 earlier nights, you get 7 points. |

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
There are 20 badges (`Badges.all` in `App/Engine/Achievements.swift`), each dated the first day it was earned. Records track your best day for steps, AZM, sleep, HRV, Recovery, and streak length, plus your lowest resting HR.
