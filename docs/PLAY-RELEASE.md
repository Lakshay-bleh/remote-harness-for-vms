# Releasing Escanor on Google Play

Installs from Google Play have no Play Protect warning and no "Controlled by restricted setting" lock on Accessibility, so
the Play build includes phone control. Start with the **Internal testing** track: it is live for testers within minutes and
needs no full review of the store listing.

## 1. Build the bundle

```bash
cd packages/web
npm run build && npx cap sync android
cd android
RH_VERSION_NAME=1.15.1 RH_VERSION_CODE=1151 ./gradlew bundleRelease -Pplay=true
# -> app/build/outputs/bundle/release/app-release.aab
```

Every upload needs a higher `RH_VERSION_CODE`. `-Pplay=true` uses `app/src/play/AndroidManifest.xml`:

- phone control (the Accessibility service) is included, as in the `-PphoneControl=true` sideload build
- `USE_FULL_SCREEN_INTENT` is removed (Play allows it only for calling and alarm apps). "Hey Escanor" heard while the
  screen is off then shows a heads-up notification to tap, instead of opening over the lock screen.

All 64-bit native libraries are 16 KB aligned (Vosk 0.3.75, JNA 5.19.1; Play requires this). To check a bundle:
`unzip aab 'base/lib/*'` then `readelf -lW <lib>.so`: every `LOAD` line must end in `0x4000` or more.

## 2. Signing

Release builds are signed with the **upload key**, read from `~/.config/escanor-android/signing.properties`
(or the file named by `RH_SIGNING_PROPERTIES`):

```
storeFile=/home/<you>/.config/escanor-android/upload-keystore.jks
storePassword=...
keyAlias=escanor-upload
keyPassword=...
```

Neither the keystore nor the passwords are in the repository. **Back up both files somewhere safe (a password manager).**
Without them, no further update can be uploaded until Google resets the upload key (a support request that takes days).
On the first upload, accept **Play App Signing**: Google keeps the key that signs what users install; this key only proves
the upload is yours.

Upload key SHA-256: `01:37:E1:66:30:41:29:F4:D4:8A:F1:1F:CD:85:45:F0:62:18:0A:95:FD:4F:AA:F2:DB:05:0A:E3:19:FE:D8:BB`

## 3. Play Console, first time

1. Create a developer account (one-time fee) at https://play.google.com/console and verify your identity.
2. **Create app**: name *Escanor*, app, free. Package name comes from the bundle: `io.visey.remoteharness` (it cannot
   change after the first upload).
3. **Testing > Internal testing > Create new release**: upload `app-release.aab`, release notes, **Save > Review > Roll out**.
4. **Testers**: add an email list (up to 100 Google accounts). Copy the **opt-in link** and send it to testers. They open it,
   accept, then install Escanor from the Play Store.

## 4. App content (Policy > App content)

Play blocks the release until these are filled in.

**Privacy policy**: `https://escanor.in/privacy` (has a section on the Android app).

**App access**: the app needs sign-in. Give reviewers a Google test account that can sign in, or explain how to use
"I run my own Remote Harness hub" with a test hub.

**Ads**: no ads.

**Accessibility API** (Sensitive permissions > Accessibility). Escanor is *not* an accessibility tool
(`isAccessibilityTool` is not set), so fill in the declaration:

- *Core functionality*: "Escanor is a voice assistant. When the user asks it to, by voice or in the app, it uses the
  Accessibility service to go home or back, open notifications or quick settings, scroll, tap a button by its visible
  name, type into the focused text box, and read the text on screen aloud when the user asks what is on it. It acts only
  on a command from the user and never on its own."
- *Data*: "The text on screen at the moment of a command, used on the device to find the button or answer the question.
  It is not stored, sent to our servers or shared, and is not used for advertising."
- *Prominent disclosure*: in-app, under Settings > Voice and phone control, before the user is sent to Accessibility
  settings. It lists what the service does and reads, and the user must tap "I agree". Consent and withdrawal are
  recorded (`phone_control` in the consent ledger).
- *Video*: required. Screen-record on a phone: open Settings > Voice and phone control, show the disclosure and "I agree",
  switch Escanor on in Accessibility settings, then say "go home" and "scroll down" and show it working. Upload to
  YouTube (unlisted) and paste the link.

**Foreground service** (Foreground service permissions): type *microphone*. "Hey Escanor": after the user switches it on
in Settings > Voice and phone control, the app listens for the two words on the device while a notification shows. The
user starts and stops it. Same video can show it, or record a short one.

**Data safety** (answer from what the app actually does):

| Data | Collected | Shared | Why | Optional |
|---|---|---|---|---|
| Name, email, user IDs | yes | no | Account management | no |
| Voice or sound recordings | no (speech is converted to text on the phone / by Android's speech service; the text is sent) | | | |
| Other user-generated content (assistant messages, the text of voice commands) | yes | no | App functionality | yes |
| Contacts | no (read on the device only to place a call you ask for) | | | |
| App activity: other actions (consent records) | yes | no | App functionality | yes |
| Device or other IDs (push notification token) | yes | no | App functionality | yes |
| Photos and files you attach | yes | no | App functionality | yes |

Data is encrypted in transit (HTTPS) and users can request deletion (Settings > Privacy and your data, or the account
deletion option).

**Content rating**: complete the questionnaire (utility/productivity, no user-to-user content, no ads).
**Target audience**: 18 and over.

## 5. Updates

Bump `RH_VERSION_CODE`, rebuild with `-Pplay=true`, upload a new release to the same track. To reach the public later:
promote the release to Closed testing, then Production. New personal developer accounts must run a closed test (at least
12 testers for 14 days) before Production is unlocked.
