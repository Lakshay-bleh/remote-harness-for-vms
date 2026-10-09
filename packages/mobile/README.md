# Escanor mobile

The Escanor app for iOS and Android, built with Flutter. App id / bundle id: `com.escanorlabs.escanor`.

It is a full native rewrite of the earlier Capacitor app (`remote-harness-for-vms/packages/web`): the
Escanor assistant, your computers running Escanor Desktop (paired end to end encrypted, over the cloud
relay or your Wi-Fi), connections (integrations), machines on your own Remote Harness hub, voice
("Hey Escanor", phone control on Android), push notifications, billing, account and privacy settings, and
the pixel companions.

## Layout

```
lib/
  core/        API client (token renewal), session + sign-in, storage, cache, prefs, theme, navigation
  ui/          shared widgets (buttons, sheets, settings rows, markdown)
  shell/       the signed-in app: tab bar (phones) / rail (tablets)
  features/
    auth/        welcome, email + Google sign-in
    assistant/   the Escanor assistant chat, chat list, approvals, machine sheet
    composer/    the message box (attachments, dictation, voice mode)
    computers/   Escanor Desktop pairing (QR / code), encrypted link, chat, activity, permissions
    connections/ integrations
    machines/    Remote Harness hub (hosted and your own)
    settings/    settings and preferences;  account/  billing, security, privacy, deletion
    push/        Firebase Cloud Messaging
    voice/       voice orb, voice mode, commands, wake word and phone control (native on Android)
    companion/   the pixel companions
```

## Develop

```bash
flutter pub get
flutter analyze
flutter test
flutter run                                   # against api.escanor.in
flutter run --dart-define=ESCANOR_API=http://10.0.2.2:8100/api/v1   # a local backend from the Android emulator
```
