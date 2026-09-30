# Running the app on your iPhone (end of Phase 1)

These are the steps only you can do. They take about 20–30 minutes the first
time. Dashboard labels change now and then; if a label differs slightly,
look for the closest match (and tell Claude, so this file gets updated).

You need: a Mac with Xcode 26 or newer (Xcode 27 is fine), your iPhone and
its cable, and an active paid Apple Developer Program membership.

## A. Choose the app's identity (5 minutes)

1. Pick an **app name** (what shows under the icon). You can change it later.
2. Pick a **bundle ID** in reverse-domain style, for example
   `com.yourname.appname`. Use only letters, numbers, dots, and hyphens.
   It's hard to change after TestFlight, so choose carefully.
3. Find your **team ID**: open https://developer.apple.com/account, then
   scroll to **Membership details**. Copy the 10-character **Team ID**.
4. Pick the **domain** for invite links (e.g. `yourapp.com`). If you don't have
   one yet, keep `example.com` for now; invite links come in Phase 3.
5. Either send these four values to Claude, or edit `Config/Identity.xcconfig`
   yourself:
   ```
   APP_DISPLAY_NAME = Your App Name
   APP_BUNDLE_ID = com.yourname.appname
   APP_DOMAIN = yourapp.com
   DEVELOPMENT_TEAM = ABCDE12345
   ```

## B. Create the Supabase project (10 minutes)

1. Go to https://supabase.com/dashboard and sign in.
2. Click **New project**. Choose your organization, enter a name, generate a
   **database password** (save it in your password manager), pick the region
   closest to you, and click **Create new project**. Wait until it finishes.
3. Go to **Project Settings → API Keys**. Keep this tab open; you need the
   **Project URL** and the **publishable** (or **anon**) key in section C.
   Never copy the **secret** / **service_role** key into the app.
4. Go to **Authentication → Sign In / Providers → Apple**.
   - Turn **Enable Sign in with Apple** on.
   - In **Client IDs**, enter your bundle ID from A2.
   - Leave the secret key empty: native iPhone sign-in doesn't need it.
   - Click **Save**.
5. Still under **Sign In / Providers**, open **Email** and turn off
   **Enable email signups** (the app only uses Apple). Click **Save**.
6. Apply the database schema from your Mac's Terminal, in the repo folder:
   ```sh
   brew install supabase/tap/supabase
   supabase login                             # opens the browser once
   supabase link --project-ref <project-ref>  # the ref is in your Project URL: https://<project-ref>.supabase.co
   supabase db push                           # applies supabase/migrations (not the fake seed data)
   ```
   `supabase link` asks for the database password from step B2.

## C. Build and run on your iPhone (10 minutes)

1. Install Xcode from the Mac App Store if needed, open it once, and let it
   install its components.
2. In Terminal:
   ```sh
   brew install xcodegen
   git clone https://github.com/pwbeaton/connector.git
   cd connector
   git checkout claude/sleep-fitness-group-app-29ubml
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   open -e Config/Secrets.xcconfig
   ```
3. In the editor that opens, paste your values from B3 and save:
   ```
   SUPABASE_URL = https:/$()/<project-ref>.supabase.co
   SUPABASE_ANON_KEY = <publishable or anon key>
   ```
   Keep the odd-looking `https:/$()/`: it stops Xcode from reading `//` as a comment.
4. Generate and open the project:
   ```sh
   xcodegen generate
   open App.xcodeproj
   ```
5. In Xcode's left sidebar, click the blue **App** project, then the **App**
   target, then **Signing & Capabilities**. Check that **Automatically manage
   signing** is on and **Team** shows your team. Xcode registers the bundle ID,
   App Group, and capabilities for you. Do the same for the **WidgetExtension**
   target. If Xcode shows a red error, copy it to Claude.
6. On your iPhone, turn on **Settings → Privacy & Security → Developer Mode**
   (the phone restarts). Connect it with the cable and tap **Trust** if asked.
7. At the top of Xcode, choose your iPhone as the run destination, then press
   **⌘R** (Product → Run).
8. On the phone:
   1. Tap **Continue with Apple**, then confirm with Face ID. The first time, you
      can choose whether to share your name and to hide your email.
   2. Check that your first name is filled in, add a photo if you like, and tap
      **Continue**.
   3. You should see **Hi, <your name>**.
9. Confirm on the server: in the Supabase dashboard, **Authentication → Users**
   lists you, and **Table Editor → profiles** shows your name, photo URL, and
   time zone.

That completes Phase 1's "sign in on my iPhone" check. Tell Claude what you saw,
including any error text, word for word.
