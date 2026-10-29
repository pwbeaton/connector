# Run it on your iPhone (about 30 minutes the first time)

You can try the app with **no setup at all**: build it, and on the "Setup needed" screen tap **Explore with sample data**. Or launch with `-demo YES` (Xcode → Product → Scheme → Edit Scheme → Run → Arguments).

To use your real Fitbit Air and your friends, do the steps below once.

## What you need
- A Mac with Xcode 26 (from the App Store) and Homebrew.
- An Apple Developer account (the free one works for your own phone; TestFlight needs the paid one).
- Your iPhone with the **Google Health** app, paired with your Fitbit Air.
- The tools: `brew install xcodegen supabase/tap/supabase`.

## 1. Pick the app's identity
Open `Config/Identity.xcconfig` and set:
1. `APP_DISPLAY_NAME`: the name under the icon (Pluto).
2. `APP_BUNDLE_ID`: a reverse-domain ID you own, e.g. `com.yourname.pluto`.
3. `DEVELOPMENT_TEAM`: your 10-character team ID from <https://developer.apple.com/account> → **Membership details**.

## 2. Google
Follow [SETUP-GOOGLE.md](SETUP-GOOGLE.md). You'll end with `GOOGLE_CLIENT_ID_PREFIX` filled in.

## 3. Supabase (the friends backend)
1. Create a project at <https://supabase.com/dashboard> → **New project**. Pick a region near you and save the database password in your password manager.
2. In Terminal, from the repo folder:
   ```sh
   supabase login
   supabase link --project-ref <your-project-ref>   # the ref is in the project URL
   supabase db push                                  # creates the tables, rules, and functions
   ```
   If you pushed the older Phase 1 schema before, run `supabase db reset --linked` once first (it only held test data). It asks before erasing.
3. Copy the secrets template and fill it in:
   ```sh
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   ```
   Values come from the dashboard → **Project Settings** → **API Keys**: the project URL and the **anon / publishable** key. Never the service-role or secret key. `Secrets.xcconfig` is git-ignored.
4. Turn on Google sign-in in Supabase: step 5 of [SETUP-GOOGLE.md](SETUP-GOOGLE.md).

## 4. Build and run
1. `xcodegen generate`, then open `App.xcodeproj`.
2. Plug in your iPhone and pick it as the run destination at the top of Xcode.
3. Select the **App** target → **Signing & Capabilities**: make sure **Automatically manage signing** is on and your team is selected. Do the same for **WidgetExtension**. Xcode registers the App Group for you.
4. Press **Run** (⌘R). The first time:
   - iPhone: **Settings → Privacy & Security → Developer Mode** → on, and restart when asked.
   - If iOS says the developer isn't trusted: **Settings → General → VPN & Device Management** → your account → **Trust**.

## 5. First launch
1. **Continue with Google** → pick your account → allow every Google Health permission.
   - "Google hasn't verified this app": tap **Advanced → Go to Pluto**. Expected for a private app.
2. **Your tracker** should say "Fitbit Air found · synced … ago". The app then reads 90 days of history.
3. Keep or change your goals, then join or create a group and share your invite code.

## 6. Check the numbers (please tell me what you see)
Open the **Google Health** app next to this one and compare:
- [ ] Today's steps
- [ ] Last night's time asleep (and deep / REM if shown)
- [ ] Last night's HRV
- [ ] Resting heart rate

Small differences can come from timing (Google Health may sync later). Big ones mean a mapping bug, which I'll fix first.

## Troubleshooting
| What you see | What to do |
|---|---|
| "Setup needed" | `Config/Secrets.xcconfig` is missing or still has example values, or the Google client prefix is still `placeholder`. Fix it, run `xcodegen generate`, and build again. |
| Google says `redirect_uri_mismatch` or "invalid client" | The bundle ID in Google's iOS client must match `APP_BUNDLE_ID` exactly. |
| Sign-in works but Supabase rejects it | In Supabase's Google provider, the iOS client ID must be in **Client IDs**, and **Skip nonce checks** must be off. |
| "Missing access to Heart …" banner | You unticked a permission. Profile → Sign out, then sign in again and allow everything. |
| "Reconnect Fitbit" every week | The Google project is still in Testing. Publish it (SETUP-GOOGLE.md step 2.7). |
| No HRV or Recovery says "Calibrating" | HRV needs about 7 nights of wearing the tracker to bed. |
| Widget shows old numbers | Open the app once; it refreshes the widget after every sync. |

## Running the local backend (optional)
For development without touching your real project: `supabase start` (needs Docker), then use the local URL and key printed by it in `Config/Secrets.xcconfig` (see the comments in `Secrets.example.xcconfig`). `supabase/seed.sql` adds five fake friends in a group with invite code `CAMP2345`.
