# Set up Google (about 15 minutes)

The app reads your Fitbit Air's data from the **Google Health API** and signs you in with Google. Both use one Google Cloud project with one **iOS OAuth client**. The iOS client has no secret, so nothing secret goes into the app.

Before you start, decide the app's **bundle ID** (for example `com.yourname.pluto`). Google needs it, and it must match `APP_BUNDLE_ID` in `Config/Identity.xcconfig`.

Google moves buttons around now and then. If a label below doesn't match, look for the closest one; the names of the pages (Branding, Audience, Data Access, Clients) are the stable part.

## 1. Create the project and turn on the API
1. Open <https://console.cloud.google.com> and sign in with the Google account you'll use for development.
2. Click the project picker at the top left, then **New project**.
3. Name it (for example "Pluto"), click **Create**, and wait for it to be selected.
4. Open the menu (☰) → **APIs & Services** → **Library**.
5. Search for **Google Health API**, open it, and click **Enable**.

## 2. Consent screen (Google Auth Platform)
1. Menu (☰) → **Google Auth Platform** (on older consoles: **APIs & Services → OAuth consent screen**). Click **Get started** if asked.
2. **App information:** app name "Pluto" and your email as the support email. Click **Next**.
3. **Audience:** choose **External**. Click **Next**.
4. **Contact information:** your email. Click **Next**, tick the agreement, and click **Create**.
5. Open **Data Access** → **Add or remove scopes**. In "Manually add scopes", paste these lines, click **Add to table**, then **Update** and **Save**:
   ```
   openid
   https://www.googleapis.com/auth/userinfo.email
   https://www.googleapis.com/auth/userinfo.profile
   https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly
   https://www.googleapis.com/auth/googlehealth.sleep.readonly
   https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly
   https://www.googleapis.com/auth/googlehealth.profile.readonly
   https://www.googleapis.com/auth/googlehealth.settings.readonly
   ```
6. Open **Audience** → **Test users** → **Add users**, and add your Google email plus every friend who will use the app. Google's Health API docs ask for this while the app is unverified (up to 100 people).
7. Still on **Audience**, click **Publish app** and confirm. The status becomes "In production" (unverified).
   - Why: while an app is in "Testing", Google expires sign-ins after **7 days**. Published, they last.
   - Your friends will see a "Google hasn't verified this app" screen once. They tap **Advanced → Go to Pluto (unsafe)**. That's expected for a private app.
   - If Google won't let you publish, stay in Testing. The app still works; it shows **Reconnect Fitbit** about once a week.

## 3. Create the iOS client
1. **Google Auth Platform** → **Clients** → **Create client**.
2. **Application type:** **iOS**.
3. **Name:** "Pluto iOS".
4. **Bundle ID:** your bundle ID (exactly as in `Config/Identity.xcconfig`).
5. **Team ID:** your Apple team ID (optional, but fill it in if you have it).
6. Click **Create** and copy the **Client ID**. It looks like `1234567890-abc123def456.apps.googleusercontent.com`.

## 4. Put the client ID in the app
1. Open `Config/Identity.xcconfig`.
2. Set `GOOGLE_CLIENT_ID_PREFIX` to the part **before** `.apps.googleusercontent.com`:
   ```
   GOOGLE_CLIENT_ID_PREFIX = 1234567890-abc123def456
   ```
   The redirect scheme (`com.googleusercontent.apps.<prefix>`) is built from it automatically.
3. Run `xcodegen generate`.

The client ID isn't a secret (it ships inside every iOS app that uses Google sign-in), so it's fine in the public repo.

## 5. Tell Supabase about the client
1. Open your Supabase project → **Authentication** → **Sign In / Providers** → **Google**.
2. Turn **Enable Sign in with Google** on.
3. In **Client IDs**, paste the full iOS client ID from step 3.
   - If the dashboard also insists on a client secret: create a second client of type **Web application** in Google (step 3 again, no redirect URIs needed), paste its ID **first** and the iOS ID second, separated by a comma, and paste the Web client's secret. The iOS app never sees that secret.
4. Leave **Skip nonce checks** **off**. The app sends Google a hashed one-time nonce and gives Supabase the original, so the check passes and replayed tokens are refused.
5. Click **Save**.

## How it fits together
- "Continue with Google" opens Google's page in Apple's sign-in sheet (`ASWebAuthenticationSession`) with PKCE.
- Google returns an authorization code; the app trades it for tokens and keeps them in the Keychain.
- The ID token signs you in to Supabase; the access token reads Google Health from the phone.
- If you untick a scope on the consent screen, the app still works and tells you what's missing.

## Later: more than 100 users
Unverified apps are limited to 100 users. A public launch needs Google's app verification, which for these restricted scopes includes a third-party security assessment (CASA). See <https://developers.google.com/health/app-verification>.
