# Plan

Phase checklists for [APP NAME]. Tick items as they land. Items added after the original brief are marked with who added them and when.

## Open questions
- App name, bundle ID, Apple Developer team ID, domain for Universal Links; paid Apple Developer Program? (Needed before the on-device step of Phase 1. Until then they are placeholders in one config file.)
- Hosted Supabase project for device sign-in: exists, or create one?
- Phase 2: add date of birth, body mass, biological sex, and VO2 max to the first Health permission sheet, so the unified score needs no second prompt later?
- Phase 5: whose "local midnight" resets a leaderboard when members are in different time zones? Does the unified score join the leaderboards (this would amend principle 4)?

## Resolved in Phase 0 (2026-09-30, the user accepted Claude's recommendations)
- One row per metric per day (`daily_metrics`) so RLS enforces per-metric sharing; `daily_resolved` uses `security_invoker`.
- Owner-only `profile_private` for birth_year, max_hr_override, preferred_sleep_source.
- Age from HealthKit date of birth, with a one-field fallback.
- Daily Effort = the sum of that day's workout Effort.
- Naps live in the sleep row's `detail`, never in its value.
- Metric keys: sleep, resting_hr, hrv, steps, active_minutes, effort, workouts (+ vendor_score).
- `preview_group(invite_code)` RPC is the one exception to "non-members see nothing".
- GitHub Actions CI (macOS build and test, Linux `supabase test db`); the user's Mac handles signing and device runs.
- Account deletion before external TestFlight; `avatars` storage bucket in Phase 1.

## Phase 0: orient and plan
- [x] CLAUDE.md with product, principles, stack, layout, data model, HealthKit rules, commands, Decisions
- [x] docs/PLAN.md with Phases 1–6 as checklists
- [x] Questions and risks answered by the user; go-ahead for Phase 1

## Phase 1: skeleton and sign-in
- [x] `project.yml` with an App target, a placeholder Widget target, shared sources, and a Tests target
- [x] Entitlements: HealthKit (with background delivery), Sign in with Apple, Push Notifications, App Groups, Associated Domains for [DOMAIN]
- [x] Health usage description in Info.plist
- [x] Supabase URL and anon key in an uncommitted `Secrets.xcconfig`; commit `Secrets.example.xcconfig`
- [x] `supabase/` migration with every table (incl. `profile_private`, `daily_metrics`), the `daily_resolved` view, `can_view`, `preview_group`, and the access policies
- [x] `avatars` storage bucket and policies
- [x] `seed.sql` with 5 fake users in one group and 30 days of summaries
- [x] Access-rule tests (pgTAP) proving:
  - [x] non-members see nothing
  - [x] members see only enabled metrics
  - [x] hidden dates stay hidden
  - [x] users can write only their own rows
- [x] GitHub Actions CI: `xcodegen generate` + build + test on macOS; `supabase test db` on Linux
- [ ] App: Sign in with Apple, then a profile screen (name, photo, time zone detected automatically)
- [ ] **Done when:** `xcodegen generate` succeeds, the `xcodebuild` build succeeds, `supabase test db` passes, and the user can sign in on their iPhone

## Phase 2: HealthKit reader
- [ ] `HealthSource` protocol and `HealthKitSource` implementation
- [ ] Pure `Summarizer` (samples in, summaries out)
- [ ] `SyncEngine` actor: 30-day backfill, anchors persisted per type, upload with retry, deferral when the device is locked
- [ ] Onboarding step 3: device tiles (Apple Watch, WHOOP, Oura, Fitbit, Garmin, Other, Just my iPhone), multi-select, saved to `profiles.devices`; first sleep-capable pick becomes `preferred_sleep_source`
- [ ] Onboarding step 4: Health primer (one sentence on why, plus the data types), system sheet, data-arriving check (last 7 days grouped by source); Fitbit/Garmin guide with Check again and Skip for now
- [ ] Onboarding step 6: sharing preset (sleep, recovery metrics, workouts, steps all on; per-metric toggles), then backfill with progress, then the feed
- [ ] Temporary "Create my first group" button (invites arrive in Phase 3)
- [ ] "My data" debug screen: last 30 days of computed summaries with the source used for each metric
- [ ] DEBUG-only seeding tool for the Simulator: sleep with stages crossing midnight, workouts with heart rate, steps from two sources
- [ ] Unit tests for every Summarizer rule:
  - [ ] steps per local day
  - [ ] sleep sessions, 60-minute gap merge, asleep stages only
  - [ ] night crossing midnight belongs to the wake-up date
  - [ ] nap stored separately
  - [ ] two sources recording the same night (preferred source, else most asleep minutes)
  - [ ] daylight-saving change
  - [ ] time-zone travel
  - [ ] resting HR average, HRV nightly mean
  - [ ] active minutes: exercise time, else workout minutes
  - [ ] HR zones, max HR (override vs 220 − age), Effort, de-duplication by UUID
- [ ] **Done when:** the user's card on their own iPhone shows last night's sleep from their Fitbit Air (Google Health → Apple Health), and the numbers match the Health app within rounding

## Phase 3: groups and feed
- [ ] Universal Links (`https://[DOMAIN]/join/{code}`) and typed invite codes on the welcome screen
- [ ] Join flow: Join screen showing group name and members
- [ ] `web/`: static invite page with a TestFlight button and "tap the link again after installing", privacy policy, `apple-app-site-association`
- [ ] Sharing settings screen (per group, per metric, hidden dates)
- [ ] Feed cards for everyone in the group
- [ ] Swift Charts trends (with accessibility labels)
- [ ] In-app account deletion (App Store Guideline 5.1.1(v)), including Sign in with Apple token revocation from an Edge Function
- [ ] First TestFlight build

## Phase 4: background sync and widget
- [ ] `HKObserverQuery` with hourly background delivery
- [ ] App Group cache shared by app and widget
- [ ] Small and medium widgets
- [ ] "Last synced" labels

## Phase 5: competition and push
- [ ] 30-day baselines
- [ ] Weekly leaderboards that reset Monday at local midnight (sleep average, Effort, active minutes, steps, streaks only)
- [ ] Reactions and comments (haptics); ask for notification permission the first time someone reacts to the user's card
- [ ] Shareable weekly recap image
- [ ] Apple push notifications sent from an Edge Function using token-based auth
- [ ] 48-hour stale-data nudge run by Cron
- [ ] Unified score (added by the user 2026-09-30): one standardized number from HRV, exercise, age, weight, steps, etc., showing where each person stands and who is trending which way. Write a short design note in `docs/` first. Constraints are under Decisions in CLAUDE.md: computed on device, HRV only as change vs own baseline, no medical framing, ask before ranking it.

## Phase 6: vendor boosts
- [ ] `vendor_connections` table and policies
- [ ] WHOOP API v2 and Oura API v2 through Edge Functions (OAuth started with `ASWebAuthenticationSession`, then webhooks)
- [ ] Onboarding step 5: optional WHOOP or Oura boost
- [ ] Set status to `capped` when a vendor's 10-user development limit is reached
- [ ] Vendor scores shown as badges (green/yellow/red bands), never ranked
