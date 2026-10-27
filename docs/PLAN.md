# Plan: V1 (rebuilt 2026-10-27)

V1 is iOS only and Fitbit Air only, with friends from day one and a "training camp" style. The full approved plan, with its reasoning, is summarized in CLAUDE.md. This file is the checklist.

## Open questions for the user (not blocking the build)
- Final app name ("Connector" is a working title), bundle ID, Apple team ID.
- Google Cloud project and iOS OAuth client ID (steps in docs/SETUP-GOOGLE.md).
- Supabase project (steps in docs/DEVICE-SETUP.md). If the Phase 1 schema was already pushed, run `supabase db reset --linked` once.

## Overnight build milestones
Every commit is pushed, and CI must be green before the next milestone starts.

### M0 · Reset and foundations
- [x] Remove HealthKit, Sign in with Apple, and the old profile flow
- [x] project.yml: App Groups only, URL schemes (Google redirect, invites), background refresh
- [x] Theme tokens (dark-first, Recovery / Sleep / Effort colors), launch color
- [x] Demo / screenshot launch options; setup-needed screen offers demo mode
- [x] CI screenshot job publishing to the `ci-screenshots` branch
- [x] CLAUDE.md and PLAN.md rewritten

### M1 · Engine (pure Swift, unit-tested)
- [x] DayRecord model; baselines (30-day median, 7-night calibration)
- [x] Recovery, Sleep, and Effort scores; Effort target by Recovery band
- [x] Streaks with rest tokens; 28-day tier; weekly personal and group challenges
- [x] Badges and personal records
- [x] docs/SCORES.md; 60+ tests (DST, time-zone travel, missing days, calibration)

### M2 · Google Health layer
- [x] PKCE + nonce sign-in with ASWebAuthenticationSession; Keychain token store; token refresh
- [x] GoogleHealthClient (dailyRollUp, list with paging, profile, settings, pairedDevices), retries
- [x] DTOs matching the API description; Mapper → DayRecord; partial-scope handling
- [x] Fixture-based decoding tests and stubbed-network tests

### M3 · Backend
- [x] Fresh migration: profiles, profile_private, groups, members, sharing by category, daily_metrics, reactions
- [x] RPCs: create_group, join_group, preview_group, weekly_leaderboard, group_feed, group_challenge, delete_my_account
- [x] seed.sql (demo group); pgTAP: privacy, hidden days, leaderboards and feeds never leak unshared data

### M4 · Sync and storage
- [x] DayStore (App Group JSON); SyncEngine: 90-day back-fill, 3-day re-fetch, upload, retries, reconnect state
- [x] Background refresh; widget snapshot
- [x] Tests with a fake Google client and fake backend

### M5 · UI
- [x] Onboarding: Continue with Google, device check, goals, join/create group, sharing
- [x] Today: Recovery dial, Sleep and Effort, target, streaks, challenges
- [x] Team: friends' cards, reactions, leaderboards, group challenge, invite
- [x] Trends (7/30/90-day charts, records) and Profile (tier, badges, settings, sign out, delete account)
- [x] Demo mode everywhere; accessibility labels
- [ ] Screenshots reviewed on small and large iPhones, light and dark

### M6 · Widget, polish, docs
- [x] Small and medium widgets
- [x] docs/SETUP-GOOGLE.md, docs/DEVICE-SETUP.md
- [ ] First run on the user's iPhone: compare steps, sleep, HRV, resting HR with the Google Health app

## Later (not in V1)
- Push notifications (reactions, friend milestones) via an Edge Function
- Universal Links once there's a domain; web invite page and privacy policy
- More trackers: Apple Watch (HealthKit), WHOOP and Oura APIs
- Fitness-age estimate from VO2 max (with a cited formula); workouts feed
- Shareable weekly recap card (ImageRenderer + ShareLink)
- Custom profile photos (the avatars bucket and policies already exist)
- Google OAuth verification (CASA), then an App Store launch
