# Push notifications (FCM) setup

The code is done. What is left is creating the Firebase project and handing two files to the right places. Nothing here costs money
(Firebase Cloud Messaging is free), and it takes about 15 minutes.

You will end up with two secrets:

| File | Where it goes | What it does |
| --- | --- | --- |
| `google-services.json` | GitHub secret `GOOGLE_SERVICES_JSON` (and, for a local build, `packages/web/android/app/`) | Lets the **app** register with Firebase |
| service account JSON | Render env var `FIREBASE_SERVICE_ACCOUNT_JSON` on the `mongo-backend` service | Lets the **backend** send messages |

## 1. Create the Firebase project
1. Go to <https://console.firebase.google.com> and sign in with the Google account that should own this.
2. **Create a project** (or **Add project**). Name it `escanor` (any name works). You can turn Google Analytics off.
3. Wait for it to finish, then **Continue**.

## 2. Register the Android app
1. On the project home page click the **Android** icon (**Add app**).
2. **Android package name:** `io.visey.remoteharness` (exactly; it is the app's id).
3. App nickname: `Escanor` (optional). Leave the SHA-1 box empty (it is not needed for push).
4. Click **Register app**.
5. **Download `google-services.json`.** Skip the remaining steps in the wizard (the project is already set up for it) and click **Continue to console**.

## 3. Make sure Cloud Messaging is on
1. **Project settings** (gear icon) > **Cloud Messaging** tab.
2. Under **Firebase Cloud Messaging API (V1)** it should say **Enabled**. If it says Disabled, click the three dots > **Manage API in Google Cloud Console** > **Enable**.
   (You do **not** need the old "Server key". It is retired; this code uses the V1 API.)

## 4. Create the service account key (for the backend)
1. **Project settings** > **Service accounts** tab.
2. Click **Generate new private key** > **Generate key**. A `.json` file downloads.
3. Treat it like a password: anyone with it can send notifications as you. Do not commit it or paste it in chat.

## 5. Give the backend its key (Render)
1. Open the Render dashboard > the **mongo-backend** service > **Environment**.
2. Add a variable named `FIREBASE_SERVICE_ACCOUNT_JSON`. For the value, paste the **entire contents** of the service account JSON file.
   (If the dashboard mangles line breaks, use the base64 form instead: run `base64 -w0 service-account.json` and paste that single line. Both work.)
3. Save. Render redeploys. Check the logs: there should be **no** "FIREBASE_SERVICE_ACCOUNT_JSON is set but unusable" warning.
4. Check it: sign in to the app and open **Settings > Notifications**. The yellow "server is not set up" message is gone.

> The backend code ships on the `feat/fcm-push` branch of `mongo-backend`. Merging it to `main` is what deploys it; the variable alone does nothing until then.

## 6. Give the app its config (GitHub, for release builds)
1. GitHub > the harness repository > **Settings** > **Secrets and variables** > **Actions** > **New repository secret**.
2. Name: `GOOGLE_SERVICES_JSON`. Value: the **entire contents** of `google-services.json` from step 2. Save.
3. Run the **Android APK** workflow as usual. The log should say "Firebase config added".
   Without the secret the workflow still builds, but prints a warning and that APK cannot receive push.

For a build on your own machine, put the file at `packages/web/android/app/google-services.json` (it is git-ignored) and run `npm run android:apk` in `packages/web`.

## 7. Try it
1. Install the new APK. Sign in.
2. **Settings > Notifications > Turn on notifications** and allow the Android prompt.
3. Tap **Send a test notification**. It should arrive in a few seconds.
4. Real triggers already wired: a teammate pinging you, an assistant/agent action waiting for your approval, and Autopilot asking for you.

## If it does not work
| You see | Likely cause |
| --- | --- |
| "server is not set up" on the Notifications page | `FIREBASE_SERVICE_ACCOUNT_JSON` is missing or wrong, or the `feat/fcm-push` backend branch is not deployed |
| "Turn on notifications" does nothing / no prompt | The APK was built without `google-services.json` (check the workflow log for the warning) |
| "Notifications are blocked" | Android Settings > Apps > Escanor > Notifications > allow |
| Test says "Nothing was delivered" | Turn notifications off and on again in the app (re-registers the phone); also check Settings > Notifications switches are on |
| Works for a while, then stops after reinstalling | Reinstalling gives the phone a new address; open the app once so it registers again |

## What is not wired yet
- **"Machine or server down"** and **"Emergency alerts"** switches exist and are honoured, but nothing in the backend raises those events yet (it needs a monitor that notices a machine going offline). The sender is ready: call `push.notify_user(db, user_id, "server_down", title, body)` from wherever that is detected.
- iOS. The app is Android-only today.
