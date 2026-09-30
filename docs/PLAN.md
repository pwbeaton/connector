# Plan

Phase checklists for [APP NAME]. Tick items as they land. Items in **Proposed additions** are Claude's suggestions and aren't part of the plan until the user approves them.

## Open questions from Phase 0 (answer before Phase 1)
1. App name, bundle ID, Apple Developer team ID, and the domain for Universal Links. Is the paid Apple Developer Program membership active?
2. Build path: GitHub Actions macOS CI plus the user's Mac? (The cloud session has no Xcode.)
3. Per-metric privacy: `daily_summaries` is a wide row, but RLS filters whole rows, not columns. Switch to one row per metric, or keep the wide table behind a masking view?
4. Private profile fields (birth_year, max_hr_override, preferred_sleep_source): move them to an owner-only `profile_private` table?
5. Birth year source for max HR: HealthKit date of birth, falling back to a one-field prompt?
6. Daily Effort: the sum of that day's workout Effort, or computed from all-day heart rate?
7. Where to store naps (e.g. a `nap_minutes` field)?
8. Sharable metric keys: sleep, resting_hr, hrv, steps, active_minutes, effort, workouts (+ vendor_score in Phase 6)?
9. Join-screen preview: allow one narrow RPC that returns a group's name and member names/avatars to anyone holding a valid invite code?
10. Hosted Supabase project for device sign-in: does one exist, or should we create one?

## Phase 0: orient and plan
- [x] CLAUDE.md with product, principles, stack, layout, data model, HealthKit rules, commands, Decisions
- [x] docs/PLAN.md with Phases 1–6 as checklists
- [ ] Questions and risks answered by the user; go-ahead for Phase 1

## Phase 1: skeleton and sign-in
- [ ] `project.yml` with an App target, a placeholder Widget target, shared sources, and a Tests target
- [ ] Entitlements: HealthKit (with background delivery), Sign in with Apple, Push Notifications, App Groups, Associated Domains for [DOMAIN]
- [ ] Health usage description in Info.plist
- [ ] Supabase URL and anon key in an uncommitted `Secrets.xcconfig`; commit `Secrets.example.xcconfig`
- [ ] `supabase/` migration with every table, the `daily_resolved` view, `can_view`, and the access policies
- [ ] `seed.sql` with 5 fake users in one group and 30 days of summaries
- [ ] Access-rule tests (pgTAP) proving:
  - [ ] non-members see nothing
  - [ ] members see only enabled metrics
  - [ ] hidden dates stay hidden
  - [ ] users can write only their own rows
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

## Phase 6: vendor boosts
- [ ] `vendor_connections` table and policies
- [ ] WHOOP API v2 and Oura API v2 through Edge Functions (OAuth started with `ASWebAuthenticationSession`, then webhooks)
- [ ] Onboarding step 5: optional WHOOP or Oura boost
- [ ] Set status to `capped` when a vendor's 10-user development limit is reached
- [ ] Vendor scores shown as badges (green/yellow/red bands), never ranked

## Proposed additions (not approved yet)
- **Phase 1:** a GitHub Actions workflow that builds and tests on a macOS runner and runs `supabase test db` on Linux, so cloud sessions can verify every push.
- **Phase 1:** a Supabase Storage bucket for avatars, with policies (owner writes; group-mates read).
- **Phase 3, before external TestFlight:** in-app account deletion (App Store Guideline 5.1.1(v)), including Sign in with Apple token revocation from an Edge Function.
- **Phase 5:** decide whose "local midnight" resets a leaderboard when group members are in different time zones.

## Parking lot (not scheduled)
- Biological or "fitness age" trend. It needs inputs such as VO2 max (Apple Watch only), and it risks reading as a medical claim in App Review. Revisit after Phase 5.
