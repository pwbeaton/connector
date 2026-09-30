# CLAUDE.md

Memory for Claude Code sessions on this repo. Keep it under ~200 lines. Record anything learned or decided under **Decisions**. The full phase checklists live in `docs/PLAN.md`.

Placeholders still to be confirmed by the user (never guess them): **[APP NAME]**, **[DOMAIN]**, bundle ID, Apple team ID, App Group ID, Supabase project ref.

## Product
A native iPhone app where a group of friends share sleep, recovery, and workout stats: WHOOP-style team sharing, but for any tracker. Friends join a group from an invite link, sign in with Apple, pick the tracker they wear, grant Apple Health access, and land on a feed of daily cards for everyone in the group (steps, sleep, resting HR, HRV trend, workouts, Effort). There are weekly leaderboards and a home-screen widget.
- On iPhone, nearly every tracker writes to Apple Health (Apple Watch, Fitbit via Google Health, Garmin Connect, WHOOP, Oura), so **HealthKit is the single data source**.
- Phase 6: WHOOP and Oura users may optionally connect vendor APIs to show proprietary scores (WHOOP Recovery, Oura Readiness).
- The user is new to iOS. Explain key decisions in a sentence or two, prefer boring and well-documented tools, and stop at checkpoints for review.

## Non-negotiable principles
1. **Onboarding speed is the top metric.** Invite to your own filled-in card in about one minute. Every screen must justify itself.
2. **Summarize on the device.** Read HealthKit locally and upload only daily and workout summaries. Never upload raw heart-rate samples, location, or body weight.
3. **Private by default.** RLS on every table. A user may read another user's data only if they share a group, the owner's sharing_settings allow that metric for that group, and the date is not hidden. Tests prove it.
4. **Never rank vendor-proprietary scores against each other.** Leaderboards use only sleep average, Effort, active minutes, steps, and streaks.
5. **One source per metric per day** (rules below).
6. **No secrets in the app binary.** Vendor client secrets live in Supabase Edge Function secrets.

## Stack (ask the user before changing)
- iOS 17+, SwiftUI, Swift concurrency (async/await, actors), `@Observable`, Swift Charts, WidgetKit. Latest stable Xcode and Swift.
- XcodeGen: `project.yml` is the source of truth. Never hand-edit the `.xcodeproj`; run `xcodegen generate`.
- Swift Package Manager only. The one planned dependency is `supabase-swift`; justify any other before adding it.
- Supabase: Postgres, Auth (Sign in with Apple via ID token), RLS, Edge Functions (TypeScript), Cron, Queues. Schema is SQL in `supabase/migrations`; run locally with `supabase start`.
- Tests: Swift Testing for the app; pgTAP via `supabase test db` for access rules.

## Repository layout
```
project.yml          XcodeGen spec
App/App              entry point, routing, deep links
App/Features         Onboarding, Feed, Groups, Leaderboard, Settings
App/Health           HealthSource protocol, HealthKitSource, Summarizer, SyncEngine
App/Data             Supabase client, repositories, DTOs
App/DesignSystem     colors, typography, reusable views
Widget/              WidgetKit extension
Shared/              models + App Group cache used by app and widget
Tests/               unit tests and fixtures
supabase/            migrations, functions, tests, seed.sql
web/                 static invite page, privacy policy, apple-app-site-association
docs/                PLAN.md and decision notes
```

## Data model (Postgres), as specified; see Decisions for changes
- `profiles`: id (auth user id), display_name, avatar_url, timezone, birth_year, max_hr_override, devices text[], preferred_sleep_source
- `groups`: id, name, invite_code (unique, short, human-typeable), created_by, created_at
- `group_members`: group_id, user_id, role (owner|member), joined_at
- `sharing_settings`: user_id, group_id, metric, enabled, hidden_dates date[]
- `vendor_connections` (Phase 6): user_id, provider (whoop|oura), status (active|needs_reconnect|capped), encrypted_tokens, provider_user_id, last_synced_at
- `daily_summaries`: user_id, date, source (apple_health|whoop_api|oura_api), sleep_minutes, sleep_stages jsonb, resting_hr, hrv_ms, steps, active_minutes, effort, vendor_score jsonb {name, value, band}, synced_at. PK (user_id, date, source)
- `daily_resolved` view: one source per metric per day. Vendor API rows win for that vendor's metrics; otherwise apple_health.
- `workouts`: user_id, source, source_id, start_at, end_at, type, avg_hr, zone_minutes int[5], effort. Unique (source, source_id)
- `reactions`: id, author_id, target_type (day|workout), target_id, emoji, comment, created_at
- `push_tokens`: user_id, apns_token, updated_at
- `can_view(viewer uuid, owner uuid, metric text, day date) returns boolean`, used by every read policy.

## HealthKit rules
- **Read-only** access: step count, sleep analysis (with stages), resting HR, HRV (SDNN), heart rate, Apple exercise time, workouts. Request write access **only in DEBUG** builds, for the seeding tool.
- iOS never reveals whether read access was granted. After the sheet, look for samples from the last 7 days grouped by source (HKSource name + bundle ID). Map sources to device tiles in **one small data-driven table**. Don't hardcode guessed third-party bundle IDs as facts; log what is observed.
- **Steps:** `HKStatisticsCollectionQuery`, cumulative sum per local day (HealthKit merges overlapping sources by the user's priority order).
- **Sleep:** group asleep samples (core, deep, REM, unspecified) into sessions, merging gaps < 60 min. A night belongs to the local date of its final wake-up. `sleep_minutes` counts asleep stages only (not in-bed, not awake). Several sources for one night: use preferred_sleep_source, else the source with most asleep minutes. Naps (< 3 h, ending before 6 pm) are stored separately and don't count toward the night.
- **Resting HR:** the day's resting HR sample, averaged if several. **HRV:** mean of that night's samples; only ever *shown* as % change vs the user's own 30-day median.
- **Active minutes:** Apple exercise time where present, otherwise total workout minutes.
- **Workouts:** from `HKWorkout`. Minutes in 5 HR zones (50–60, 60–70, 70–80, 80–90, 90–100 % of max HR) from HR samples during the workout. Max HR = max_hr_override, else 220 − age. **Effort** = Σ(zone number × minutes in zone). De-duplicate by HealthKit UUID.
- **Sync:** backfill 30 days after first authorization. Then `HKObserverQuery` with hourly background delivery + `HKAnchoredObjectQuery` with anchors persisted per type, plus a sync on every foreground. If the device is locked (HealthKit inaccessible), defer and retry. Uploads are idempotent upserts keyed on (user_id, date, source).
- **Summarizer is a pure function** from samples to summaries, fully unit-tested with fixtures: night crossing midnight, nap, two sources for one night, DST change, time-zone travel.

## Onboarding (details in docs/PLAN.md)
Invite link → Sign in with Apple → name + photo → device tiles → Health primer, system sheet, data-arriving check → (Phase 6 vendor boost) → sharing preset → backfill with progress → feed. **Never ask for notification permission during onboarding**; ask the first time someone reacts to the user's card.

## Design
Native and calm: system fonts, SF Symbols, light + dark, Dynamic Type, large tap targets, rounded cards, haptics on reactions. One accent color; green/yellow/red bands are reserved for vendor scores. Must work on an iPhone SE-sized screen. Accessibility labels on charts.

## Commands (to be verified in Phase 1; keep exact)
```sh
# iOS (macOS only)
xcodegen generate
xcrun simctl list devices available        # pick an iPhone simulator UDID; never assume a name
xcodebuild -project "[APP NAME].xcodeproj" -scheme "[APP NAME]" \
  -destination "platform=iOS Simulator,id=<UDID>" build
xcodebuild -project "[APP NAME].xcodeproj" -scheme "[APP NAME]" \
  -destination "platform=iOS Simulator,id=<UDID>" test

# Supabase (needs Docker)
supabase start
supabase db reset          # re-apply migrations + seed.sql
supabase test db           # pgTAP tests in supabase/tests
```

## How we work
- Use plan mode before each phase: list files and key decisions, then wait for approval.
- Small commits with clear messages. **Never commit secrets.** The GitHub repo is **public**.
- After every change, build and run the tests, fix failures before moving on, and report the exact commands run.
- When the user must act (Apple Developer portal, Xcode signing, Supabase dashboard, iPhone), stop and give numbered click-by-click steps.
- If an Apple or Supabase API behaves unexpectedly, check current docs rather than guessing, and record the finding below.
- Prefer simple, readable code over clever code; the user will maintain it.

## Decisions
- **2026-09-30 · Build environment.** Claude Code cloud sessions run on Linux: no Xcode, no Simulator, and `download.swift.org` is blocked, so iOS builds and tests must run on the user's Mac or a macOS CI runner. Docker is installed but not running (start it with `dockerd &`). Docker Hub is reachable; `public.ecr.aws` (Supabase's default image registry) is blocked. The Supabase CLI installs via npm.
- **2026-09-30 · Fitbit data path.** Google Health for iOS 5.05 (rolling out from 2026-08-02) writes steps, heart rate, sleep, exercise, and vitals to Apple Health (Google Health → Connections → Apps and services → Apple Health). Press reports say **HRV does not transfer**. This is unverified until observed on the user's iPhone.
- **2026-09-30 · Sign in with Apple** gives the user's name only on the *first* authorization and never gives a photo. The photo comes from the user (or an initials avatar).
- **2026-09-30 · Sharing default.** No sharing_settings row means *not shared* (private by default). The onboarding preset creates the rows.
- Open questions awaiting the user are listed at the top of `docs/PLAN.md`.
