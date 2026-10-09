# Android

App id `com.escanorlabs.escanor`, label "Escanor". Native code: `android/app/src/main/kotlin/com/escanorlabs/escanor/`.

## Builds

There are three downloads, chosen with a Gradle property (`-P`, which `flutter build` passes through to Gradle):

| Build | Command | Phone control (Accessibility) | Calling directly (`CALL_PHONE`) | Full-screen "Hey Escanor" notification |
| --- | --- | --- | --- | --- |
| Normal | `flutter build apk --debug` (or `--release`) | not declared | not declared: always opens the dialer | not declared |
| With phone control | `flutter build apk --debug -P phoneControl=true` | declared (`src/phonecontrol`) | declared | declared |
| Google Play | `flutter build appbundle --release -P play=true` | declared (`src/play`) | declared | not declared (Play allows it only for calling and alarm apps) |

Why: Play Protect blocks a sideloaded app that declares an accessibility service, so the normal download leaves
`EscanorControlService` out of its manifest (the class is still compiled; Settings > Voice and phone control says it is not in
this download). The default build also has no SMS permission, no notification listener, no `CALL_PHONE`, no
`USE_FULL_SCREEN_INTENT` and no `SYSTEM_ALERT_WINDOW` (no build draws over other apps any more), so a downloaded APK installs
without Play Protect or payment apps objecting. The native side checks the manifest at run time (`WakeAction.declares`), so
`callStatus.available`, `requestCallPermission` and `wakeStatus.fullScreenDeclared` follow whichever build is installed.
Installed from Play, the service is not blocked, so the Play build includes it.

Payment apps: payment, UPI, wallet and banking apps refuse to run while any accessibility service is on. While phone control is
on, `EscanorControlService` watches only which app comes to the front (`typeWindowStateChanged`, nothing on screen is read);
when it is one of those (`PaymentApps.isPaymentApp`: a known list plus package names that say bank, wallet, pay or upi) it
switches itself off (`disableSelf()`) and posts a "Phone control is off so ... works" notification (channel `escanor_control`)
that opens Accessibility settings to switch it back on. Android lets a service switch itself off, never back on.

Instead of `-P` you can put `phoneControl=true` or `play=true` in `android/gradle.properties` (do not commit that). With plain
Gradle: `cd android && ./gradlew assembleDebug -PphoneControl=true`.

To compile only the native side (for example while Dart elsewhere does not build):
`cd android && ./gradlew :app:compileDebugKotlin -x compileFlutterBuildDebug`.

JVM unit tests of the native side (`android/app/src/test/kotlin`, for example `PaymentAppsTest`):
`cd android && ./gradlew :app:testDebugUnitTest -x compileFlutterBuildDebug`.

## Signing

Release builds are signed with the Play upload key when `~/.config/escanor-android/signing.properties` exists (or the file named
by `ESCANOR_SIGNING_PROPERTIES`):

```properties
storeFile=/absolute/path/to/upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Without it, release builds use the debug key so they still install. The key never goes in the repository.

## Push (Firebase)

The Google services Gradle plugin is applied only when `android/app/google-services.json` exists. Without the file the app
builds and runs with push off. Notifications that arrive while the app is closed go to the `escanor_alerts` channel with the
`ic_stat_escanor` icon tinted `#F2A73B`.

## "Hey Escanor" (wake word)

`WakeWordService` is a microphone foreground service running Vosk (`vosk-android` 0.3.75 with `jna` 5.19.1, both shipping 16 KB
page-aligned native libraries; check with `zipalign -c -P 16 -v 4 app.apk`). The ~40 MB model
(`vosk-model-small-en-us-0.15`) is downloaded over https only when the person switches the wake word on. When the phrase is
heard, `WakeAction` opens voice mode: directly if the app is in front; otherwise, while phone control is on, by starting the
activity from `EscanorControlService` (Android lets an enabled accessibility service do that); otherwise through a "Hey! I'm
listening" notification that opens `escanor://voice`, which also takes over the lock screen in builds that declare
`USE_FULL_SCREEN_INTENT` (only "with phone control") where Android allows it. There is no overlay: payment and banking apps
refuse to run next to an app that can draw over other apps.

## The device channel

Dart reaches the phone over the MethodChannel `escanor/device` (`lib/features/voice/device.dart` ↔ `EscanorDevicePlugin.kt`):
`listApps, launchPackage, openUrl, dial, callNumber, callContact, listContacts, callStatus, requestCallPermission,
controlStatus, openControlSettings, controlTurnOff, openAppInfo, control, setAlarm, setTimer, setTorch, setVolume, openSettings,
wakeStatus, wakeDownloadModel, wakeStart, wakeStop, wakePause, wakeDeleteModel, wakeOpenFullScreenSettings, wakeTest,
wakeListen, takeVoiceLink`. Native calls back with `wake`, `wakeModelProgress {percent}` and `voiceLink`.

- `callStatus` → `{granted, available}` (`available`: this build declares `CALL_PHONE`).
- `requestCallPermission` → `{ok, message?}`; in a build without `CALL_PHONE` it answers `ok: false` without prompting.
  `callNumber` / `callContact` with `direct: true` open the dialer there (`direct: false` in the answer).
- `controlTurnOff` → `{ok: true}`: switches phone control off (switching it on again happens only in Android's settings).
- `wakeStatus` → `{running, modelReady, downloading, micAllowed, opensDirectly, fullScreenDeclared, fullScreenAllowed}`.

## Notes

- Plain http is allowed by `res/xml/network_security_config.xml` only because Android cannot express "private LAN addresses":
  the app itself refuses plain addresses that are not on the local network, and `escanor.in` is https-only.
- `compileSdk` is 37 (`compileSdkMinor = 0`): permission_handler_android compiles against API 37, which the SDK ships as
  `android-37.0`. `android/build.gradle.kts` sets the minor version for plugins too, so the platform is found locally and on CI.
- minSdk 24; core library desugaring is on (flutter_local_notifications).
- Launcher icon and splash: `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` (config in
  `flutter_launcher_icons.yaml` and `flutter_native_splash.yaml`, sources in `assets/images/`).
