# iOS

Bundle id `com.escanorlabs.escanor`, display name "Escanor", iOS 15 or newer (Firebase, mobile_scanner, speech_to_text).

## Build

An iPhone installs apps from a **signed .ipa**. Signing needs an Apple Developer Program membership and a Mac; GitHub's Mac
runners are the Mac (`.github/workflows/ios.yml`):

- **simulator** (every push): builds for the iOS simulator, boots an iPhone, installs, launches, and keeps a screenshot. Needs
  nothing from Apple; it is how we know the iOS project compiles and starts.
- **signed** (every push to main, or Actions > iOS > Run workflow): archives with Xcode's automatic signing and exports
  - `app-store-connect`: an .ipa uploaded to App Store Connect, so it appears in **TestFlight** (install it on any iPhone through
    the TestFlight app; testers are invited by email), and later goes to the App Store from there;
  - `release-testing`: an ad hoc .ipa that installs directly on the iPhones whose UDIDs are registered in the developer account.
  The .ipa is also attached to the run as an artifact. No unsigned .ipa is produced any more.

### One-time setup for the signed build

1. Join the Apple Developer Program (Escanor Labs; organisation enrolment needs a D-U-N-S number, an individual one does not).
2. App Store Connect > Users and Access > Integrations > App Store Connect API > generate a key with role **App Manager**
   (or Admin). Note the Key ID and Issuer ID and download `AuthKey_<id>.p8` (it can be downloaded once).
3. Note the Team ID (developer.apple.com > Membership).
4. Add four secrets to the GitHub repo (Settings > Secrets and variables > Actions):
   `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_KEY_P8_BASE64`
   (`base64 -w0 AuthKey_<id>.p8`). Or: `gh secret set APPLE_TEAM_ID -R escanorlabs-source/escanor-mobile` etc.
5. Create the app in App Store Connect (My Apps > + > New App, bundle id `com.escanorlabs.escanor`, name Escanor). Xcode registers
   the bundle id with push notifications on the first signed run if it does not exist yet.
6. Push: upload an **APNs key** (developer.apple.com > Keys > Apple Push Notifications service) to Firebase (project `escanorai` >
   Project settings > Cloud Messaging > Apple app configuration), or iPhones get no notifications.

Locally on a Mac: `flutter build ipa --export-options-plist=<filled copy of ios/ExportOptions.plist>` after choosing the team in
Xcode (Runner > Signing & Capabilities).

### Before App Store review

- **Sign in with Apple**: App Review guideline 4.8 asks apps that offer a third-party login (Google) to also offer an equivalent
  privacy-preserving login, which in practice means Sign in with Apple. It needs a Services ID and key from the developer account
  and a backend endpoint; until then TestFlight works, App Store review may reject.
- Export compliance: the app uses standard encryption (HTTPS, and AES-GCM/ECDH for the end-to-end link with Escanor Desktop);
  answer App Store Connect's export questions accordingly.

Plugins come from Swift Package Manager where they support it and from CocoaPods otherwise (`ios/Podfile`, platform 15.0).
Under CocoaPods the Podfile turns on the permission_handler permissions the app uses (microphone, speech recognition,
notifications, camera, contacts, photos); under SwiftPM permission_handler reads them from Info.plist itself.

## What is set up

- `Info.plist`: usage strings for the microphone, speech recognition, camera, contacts, photo library and local network; URL
  scheme `escanor` (sign-in returns to `escanor://auth/login?code=…`); `LSApplicationQueriesSchemes` otpauth, https, tel;
  `UIBackgroundModes` remote-notification; `NSAllowsLocalNetworking` for Wi-Fi pairing with Escanor Desktop over plain
  http/ws on the LAN (the app refuses plain addresses that are not local).
- `Runner.entitlements`: `aps-environment` (push). Xcode switches it to production when exporting for the App Store.
- `GoogleService-Info.plist` is in the Runner target's resources (Firebase).
- `EscanorDevicePlugin.swift`, registered in `AppDelegate.swift`, answers the same `escanor/device` channel as Android with
  what iOS allows: open links, call (iOS always confirms), read contacts to find who to call, the torch, open Escanor's page in
  Settings. It says plainly what iOS does not allow: opening other apps by name, alarms and timers, volume, controlling other
  apps, and "Hey Escanor" in the background (voice mode itself works with the microphone button).
- Launcher icon and launch screen are generated from `assets/images/` (see docs/ANDROID.md), background `#050505`.
