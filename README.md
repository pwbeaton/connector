# Pluto

An iPhone app for friends who wear a **Fitbit Air**: daily **Recovery**, **Sleep**, and **Effort** scores, an Effort target for the day, streaks, training tiers, weekly challenges, badges, and group leaderboards. "Training camp" style: scores front and center, dark-first.

- **Data:** read on the phone from the Google Health API. Raw data stays on the iPhone; only daily summaries are shared, and only with groups you choose, per category (Recovery, Sleep, Activity).
- **Fair leaderboards:** Effort, steps, Active Zone Minutes, and sleep. Recovery, HRV, and resting heart rate are never ranked.
- **Backend:** Supabase (Postgres with row-level security, proven by pgTAP tests).

## Try it without any setup
Build and run, then tap **Explore with sample data** (or launch with `-demo YES`). Demo mode uses the real scoring and sync code with sample data and four sample friends.

## Docs
- [docs/DEVICE-SETUP.md](docs/DEVICE-SETUP.md): run it on your iPhone with your own data.
- [docs/SETUP-GOOGLE.md](docs/SETUP-GOOGLE.md): the Google Cloud project and sign-in client.
- [docs/SCORES.md](docs/SCORES.md): how every score is computed.
- [docs/PLAN.md](docs/PLAN.md): milestones and what's next.
- [CLAUDE.md](CLAUDE.md): architecture, conventions, and decisions.

## Build and test
```sh
brew install xcodegen
xcodegen generate
UDID="$(scripts/pick-simulator.sh)"
xcodebuild build-for-testing -project App.xcodeproj -scheme App -destination "platform=iOS Simulator,id=$UDID" CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -project App.xcodeproj -scheme App -destination "platform=iOS Simulator,id=$UDID" CODE_SIGNING_ALLOWED=NO
supabase db start && supabase test db   # database access rules (needs Docker)
```

Scores are estimates to guide training, not medical advice.
