# Plan: V1 (rebuilt 2026-10-27)

V1 is iOS only and Fitbit Air only, with friends from day one and a "training camp" style. The full approved plan, with its reasoning, is summarized in CLAUDE.md. This file is the checklist.

## Open questions for the user (not blocking the build)
- Final app name ("Connector" is a working title), bundle ID, Apple team ID.
- Google Cloud project and iOS OAuth client ID (steps in docs/SETUP-GOOGLE.md).
- Supabase project (steps in docs/DEVICE-SETUP.md). If the Phase 1 schema was already pushed, run `supabase db reset --linked` once.

## Overnight build milestones
Every commit is pushed, and CI must be green before the next milestone starts.

### M0 · Reset and foundations
- [ ] Remove HealthKit, Sign in with Apple, and the old profile flow
- [ ] project.yml: App Groups only, URL schemes (Google redirect, invites), background refresh
- [ ] Theme tokens (dark-first, Recovery / Sleep / Effort colors), launch color
- [ ] Demo / screenshot launch options; setup-needed screen offers demo mode
- [ ] CI screenshot job publishing to the `ci-screenshots` branch
- [ ] CLAUDE.md and PLAN.md rewritten

### M1 · Engine (pure Swift, unit-tested)
- [ ] DayRecord model; baselines (30-day median, 7-night calibration)
- [ ] Recovery, Sleep, and Effort scores; Effort target by Recovery band
- [ ] Streaks with rest tokens; 28-day tier; weekly personal and group challenges
- [ ] Badges and personal records
- [ ] docs/SCORES.md; 60+ tests (DST, time-zone travel, missing days, calibration)

### M2 · Google Health layer
- [ ] PKCE + nonce sign-in with ASWebAuthenticationSession; Keychain token store; token refresh
- [ ] GoogleHealthClient (dailyRollUp, list with paging, profile, settings, pairedDevices), retries
- [ ] DTOs matching the API description; Mapper → DayRecord; partial-scope handling
- [ ] Fixture-based decoding tests and stubbed-network tests

### M3 · Backend
- [ ] Fresh migration: profiles, profile_private, groups, members, sharing by category, daily_metrics, reactions
- [ ] RPCs: create_group, join_group, preview_group, weekly_leaderboard, group_challenge, delete_my_account
- [ ] seed.sql (demo group); pgTAP: privacy, hidden days, leaderboards never rank physiology

### M4 · Sync and storage
- [ ] DayStore (App Group JSON); SyncEngine: 90-day back-fill, 3-day re-fetch, upload, retries, reconnect state
- [ ] Background refresh; widget snapshot
- [ ] Tests with a fake Google client and fake backend

### M5 · UI
- [ ] Onboarding: Continue with Google, device check, goals, join/create group, sharing
- [ ] Today: Recovery dial, Sleep and Effort, target, streaks, challenges
- [ ] Team: friends' cards, reactions, leaderboards, group challenge, invite
- [ ] Trends (7/30/90-day charts, records) and Profile (tier, badges, settings, sign out, delete account)
- [ ] Demo mode everywhere; accessibility; screenshots reviewed on small and large iPhones, light and dark

### M6 · Widget, polish, docs
- [ ] Small and medium widgets
- [ ] docs/SETUP-GOOGLE.md, docs/DEVICE-SETUP.md, morning summary

## Later (not in V1)
- Push notifications (reactions, friend milestones) via an Edge Function
- Universal Links once there's a domain; web invite page and privacy policy
- More trackers: Apple Watch (HealthKit), WHOOP and Oura APIs
- Fitness-age estimate from VO2 max (with a cited formula); workouts feed
- Google OAuth verification, then an App Store launch
