# CLAUDE.md

Memory for Claude Code sessions on this repo. Keep it under ~200 lines. Record anything learned or decided under **Decisions**. The milestone checklist lives in `docs/PLAN.md`; score formulas in `docs/SCORES.md`.

Placeholders still to be confirmed by the user (never guess them): final app name ("Connector" is a working title), bundle ID, Apple team ID, Google iOS client ID, Supabase project ref.

## Product (V1, rebuilt 2026-10-27)
An iPhone app where friends compare training-camp style stats from their **Fitbit Air**: Recovery, Sleep, and Effort scores (0–100), Effort targets, streaks, training tiers, weekly challenges, badges, records, group leaderboards, and reactions.
- **Data source:** the **Google Health API** (v4), called directly from the phone. The Fitbit Web API was shut down on 2026-10-30. Apple Health is not used, because Google Health doesn't send HRV to it.
- **Friends from day one:** groups with invite codes, per-category sharing, leaderboards, and reactions, via Supabase.
- **Style:** "Training camp", like WHOOP: scores front and center, sleek, dark-first, not cartoonish.
- The user is new to iOS. Explain key decisions in a sentence or two, prefer boring and well-documented tools, and stop at checkpoints for review.

## Non-negotiable principles
1. **Onboarding speed is the top metric.** Continue with Google → device check → goals → join or create a group → Today, in about one minute.
2. **Summarize on the device.** Raw Google Health data stays on the phone. Only daily summaries (scores and daily totals) go to Supabase.
3. **Private by default.** Row-level security (RLS) on every table. Others see your data only if you share a group, you share that category (recovery | sleep | activity) with that group, and the day isn't hidden. pgTAP tests prove it.
4. **Never rank physiology.** Recovery, HRV, and resting HR appear on cards but never on leaderboards. Leaderboards use Effort, steps, average sleep, sleep consistency, and challenge points.
5. **A missing day is never zero.** No data means "not worn / not synced", and it's shown that way.
6. **No secrets in the app binary.** The iOS Google OAuth client has no secret. The Supabase anon key is public by design. Anything secret lives in Edge Function secrets.

## Stack (ask the user before changing)
- iOS 17+, SwiftUI, Swift 6 (App and Tests default to `MainActor`), `@Observable`, Swift Charts, WidgetKit.
- XcodeGen: `project.yml` is the source of truth. Never hand-edit `.xcodeproj` (it's git-ignored); run `xcodegen generate`.
- SPM only. The one dependency is `supabase-swift` (pinned 2.55.3). Google sign-in uses `ASWebAuthenticationSession` + PKCE with no Google SDK.
- Supabase: Postgres + RLS, Auth (Google ID token), RPCs. No Edge Functions or Cron in V1.
- Tests: Swift Testing (`Tests/`); pgTAP via `supabase test db` (`supabase/tests/`).

## Repository layout
```
project.yml, Config/          XcodeGen spec; Identity.xcconfig (name, IDs, Google client); Secrets.xcconfig (git-ignored)
App/App/                      AppMain, AppModel (demo | live | setupNeeded), RootView, LaunchOptions, AppConfig
App/Features/{Onboarding,Today,Team,Trends,Profile}/   screens + their @Observable models
App/Engine/                   pure, nonisolated scoring: DayRecord, baselines, scores, streaks, tier, challenges, badges, records
App/Google/                   PKCE auth, Keychain token store, GoogleHealthClient, DTOs (from the API description), Mapper
App/Sync/                     DayStore (App Group JSON), SyncEngine, background refresh
App/Backend/                  Supabase client + repositories (auth, profile, groups, metrics, leaderboard, reactions)
App/Demo/                     deterministic demo data (90 days + demo friends) for demo mode, previews, screenshots
App/DesignSystem/             reusable views (dials, rings, cards, avatar)
Shared/                       Theme tokens, App Group helpers, widget snapshot (used by app + widget)
Widget/                       WidgetKit extension (target name: WidgetExtension)
Tests/                        Swift Testing tests and fixtures
supabase/                     config.toml, migrations, seed.sql, pgTAP tests
scripts/                      pick-simulator.sh, screenshots.sh
docs/                         PLAN.md, SCORES.md, SETUP-GOOGLE.md, DEVICE-SETUP.md
```

## Google Health API rules
- Base `https://health.googleapis.com/v4/users/me/...`. The API description (discovery doc) is `https://health.googleapis.com/$discovery/rest?version=v4`; trust it over memory.
- Scopes (read-only): `openid email profile` + `googlehealth.{activity_and_fitness,sleep,health_metrics_and_measurements,profile,settings}.readonly`. Users can untick scopes, so check which ones were granted.
- Daily totals: `dataTypes/{steps|distance|active-zone-minutes}/dataPoints:dailyRollUp` (POST, civil-date range ≤ 90 days).
- Daily values: `list` on `daily-heart-rate-variability`, `daily-resting-heart-rate`, `daily-vo2-max`, `daily-respiratory-rate`, with filter `daily_heart_rate_variability.date >= "YYYY-MM-DD"` etc.
- Sleep: `list` on `sleep` with filter `sleep.interval.civil_end_time >= "YYYY-MM-DD"`, max page size 25. Use `metadata.mainSleep`; naps are `metadata.nap`. A night belongs to the civil date of its end.
- 64-bit integers arrive as JSON strings (`"countSum": "8423"`). Decode defensively; unknown fields are ignored.
- `users/me/pairedDevices` (settings scope) gives "Fitbit Air", battery level, and last sync time; `users/me/profile` gives age.
- The OAuth consent screen is **published (unverified)**. In "Testing", refresh tokens expire after 7 days. Unverified apps allow 100 users.

## Gamification (details and constants: docs/SCORES.md, App/Engine/ScoreTuning.swift)
- **Recovery** = HRV vs 30-day baseline (50%) + resting HR vs baseline (20%) + Sleep score (30%). Bands: Go ≥67, Steady 34–66, Recover ≤33. It shows "Calibrating" until there are 7 nights.
- **Sleep** = duration vs goal (50%), deep + REM share (25%), efficiency (15%), wake-time consistency (10%).
- **Effort** = `100·(1−e^(−AZM/45))`. The Effort target comes from the Recovery band (Go 60–80, Steady 40–60, Recover 15–35).
- **Streaks:** sleep goal, step goal, Effort on target. Rest tokens: 1 per 7-day streak, at most 2 banked.
- **Tier** (28-day consistency): Rookie, Bronze, Silver, Gold, Platinum, Elite.
- **Weekly challenges:** 3 personal + 1 group (rotating by ISO week). Badges and records.

## Commands (verified in CI)
```sh
xcodegen generate
UDID="$(scripts/pick-simulator.sh)"         # an available iPhone simulator; never assume a name
xcodebuild build-for-testing -project App.xcodeproj -scheme App \
  -destination "platform=iOS Simulator,id=$UDID" -quiet CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -project App.xcodeproj -scheme App \
  -destination "platform=iOS Simulator,id=$UDID" CODE_SIGNING_ALLOWED=NO   # no -quiet: it hides test results
scripts/screenshots.sh <App.app> <out-dir>  # demo-mode screenshots (CI publishes them to the ci-screenshots branch)

supabase start | supabase db start          # local stack / Postgres only (needs Docker)
supabase db reset                           # re-apply migrations + seed.sql
supabase test db                            # pgTAP tests
```
CI (`.github/workflows/ci.yml`) runs three jobs: `ios` (macos-26, newest non-beta Xcode), `database` (Supabase CLI 2.118.0), and `screenshots` (push only). Read results with `gh api repos/pwbeaton/connector/actions/...` or the GitHub MCP tools. Review screenshots with `git fetch origin ci-screenshots`.

Demo mode: launch with `-demo YES` (add `-screen <name> -screenshots YES` to open a screen with animations off).

## How we work
- Use plan mode before each phase: list files and key decisions, then wait for approval.
- Small commits with clear messages. **Never commit secrets.** The GitHub repo is **public**.
- After every change, build and run the tests, fix failures before moving on, and report the exact commands run.
- When the user must act (Google Cloud, Supabase dashboard, Xcode signing, iPhone), give numbered click-by-click steps.
- If an API behaves unexpectedly, check the current docs or the discovery doc rather than guessing, and record the finding below.
- Prefer simple, readable code over clever code; the user will maintain it.

## Decisions
- **2026-10-27 · V1 rebuild.** iOS only, Fitbit Air only, friends from day one, "training camp" style. Sign in with Apple and HealthKit were removed (they remain in git history before this date).
- **2026-10-27 · Sign-in.** "Continue with Google" is the only sign-in. One consent creates the Supabase account (Google ID token, nonce check on) and grants Google Health access. Sign in with Apple can return if App Review asks (guideline 4.8).
- **2026-10-27 · Leaderboards and sharing.** Sharing is by category (recovery | sleep | activity) per group. Leaderboards never include Recovery, HRV, or resting HR.
- **2026-10-27 · No server jobs in V1.** Weekly challenges are deterministic from the ISO week. Push notifications come in V1.1.
- **2026-09-30 · Build environment.** Cloud sessions run on Linux with no Xcode, so iOS builds and tests run in GitHub Actions (free: the repo is public). Docker isn't running at start (`dockerd &`). Supabase CLI: `npm install -g supabase@2.118.0`.
- **2026-09-30 · Local Supabase in cloud sessions.** `public.ecr.aws` and GHCR's blob host are blocked, Docker Hub is often rate-limited, and port 54322 is taken (`SUPABASE_DB_PORT=55322`). Fallback: run the cached `supabase/postgres` image directly, add stand-ins for the Auth/Storage tables and the current `auth.uid()`, and run test files with psql. CI is the authority.
- **2026-09-30 · Swift setup.** The module is named `App`, so write `SwiftUI.App`. The widget target is `WidgetExtension`. Mark plain data types and pure helpers `nonisolated` so they work off the main actor.
- **2026-09-30 · supabase-swift 2.55.3 API.** `auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider:, idToken:, nonce:))`. The client uses `emitLocalSessionAsInitialSession: true`. Sign out with `scope: .local`. `update(...)` is `throws` (not async).
- **2026-09-30 · Avatars.** Storage paths are `<lowercase user id>/<uuid>.jpg`, because policies compare against `auth.uid()::text`.
- **2026-09-30 · pgTAP.** `results_eq` fails on `name` columns (collation), so compare arrays with `is()`. Tests act as users via `set_config('role', …)` + `request.jwt.claims` (helpers in `supabase/tests/000-setup-tests-hooks.sql`).
- **2026-09-30 · Column-level grants.** Update payloads may contain only granted columns, never `id`.
