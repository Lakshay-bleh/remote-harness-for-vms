/// Doing one thing on the phone and saying what happened. Pure: the phone is the [DevicePlugin] interface (the real one is a
/// MethodChannel to the native side, see device.dart), so every sentence here is tested with a fake phone.
library;

import 'apps.dart';
import 'commands.dart';
import 'contacts.dart';

/// What the person has to turn on for something to work.
enum Needs { accessibility, controlBuild }

Needs? needsFrom(Object? v) => switch (v) { 'accessibility' => Needs.accessibility, 'controlBuild' => Needs.controlBuild, _ => null };

class PluginResult {
  const PluginResult({required this.ok, this.message, this.direct, this.needs});
  final bool ok;
  final String? message;

  /// The call was placed (not just the dialer opened).
  final bool? direct;

  /// What the person has to turn on for this to work.
  final Needs? needs;

  factory PluginResult.fromJson(Object? raw) {
    final j = raw is Map ? raw : const {};
    return PluginResult(
      ok: j['ok'] == true,
      message: j['message'] is String ? j['message'] as String : null,
      direct: j['direct'] is bool ? j['direct'] as bool : null,
      needs: needsFrom(j['needs']),
    );
  }
}

/// What the person has chosen about how the phone behaves for them.
class PhoneOptions {
  const PhoneOptions({this.directCalls});

  /// Place calls themselves when Android's call permission is there. Off: only open the dialer.
  final bool? directCalls;
}

class ControlStatus {
  const ControlStatus({required this.enabled, this.available, this.restricted});

  /// The person has switched Escanor on in Accessibility settings.
  final bool enabled;

  /// Phone control is part of this download.
  final bool? available;

  /// Android still greys out the switch ("Controlled by restricted setting"); null when this Android does not say.
  final bool? restricted;

  factory ControlStatus.fromJson(Object? raw) {
    final j = raw is Map ? raw : const {};
    return ControlStatus(
      enabled: j['enabled'] == true,
      available: j['available'] is bool ? j['available'] as bool : null,
      restricted: j['restricted'] is bool ? j['restricted'] as bool : null,
    );
  }
}

/// One thing done on the phone as a person would.
sealed class ControlRequest {
  const ControlRequest();
  Map<String, Object?> toJson();
}

class GlobalControl extends ControlRequest {
  const GlobalControl(this.name);
  final String name;
  @override
  Map<String, Object?> toJson() => {'action': 'global', 'name': name};
}

class ClickControl extends ControlRequest {
  const ClickControl(this.text);
  final String text;
  @override
  Map<String, Object?> toJson() => {'action': 'click', 'text': text};
}

class ScrollControl extends ControlRequest {
  const ScrollControl(this.up);
  final bool up;
  @override
  Map<String, Object?> toJson() => {'action': 'scroll', 'direction': up ? 'up' : 'down'};
}

class TypeControl extends ControlRequest {
  const TypeControl(this.text);
  final String text;
  @override
  Map<String, Object?> toJson() => {'action': 'type', 'text': text};
}

class ReadControl extends ControlRequest {
  const ReadControl();
  @override
  Map<String, Object?> toJson() => {'action': 'read'};
}

/// What the native EscanorDevice side offers. (Declared here so the logic below can be tested with a fake phone.)
abstract class DevicePlugin {
  Future<List<InstalledApp>> listApps();
  Future<PluginResult> launchPackage(String package);
  Future<PluginResult> openUrl(String url);
  Future<PluginResult> dial(String number);
  Future<PluginResult> callNumber(String number, {required bool direct});
  Future<PluginResult> callContact(String name, {bool? direct});

  /// Every contact with a number (asks Android for permission the first time). Null result: this phone only has [callContact].
  Future<({PluginResult result, List<Contact> contacts})>? listContacts();
  /// `available` is false in the normal download, which has no call permission: calls always open the dialer there. Null: an
  /// older build that does not say.
  Future<({bool granted, bool? available})> callStatus();
  Future<PluginResult> requestCallPermission();
  Future<ControlStatus> controlStatus();
  Future<PluginResult> openControlSettings();

  /// Switch phone control off from the app (switching it on again happens only in Android's Accessibility settings).
  Future<PluginResult> controlTurnOff();

  /// Escanor's App info, where Android 13+ offers "Allow restricted settings".
  Future<PluginResult> openAppInfo();
  Future<PluginResult> control(ControlRequest request);
  Future<PluginResult> setAlarm(int hour, int minute);
  Future<PluginResult> setTimer(int seconds);
  Future<PluginResult> setTorch(bool on);
  Future<PluginResult> setVolume(VolumeChange change);

  /// [screen] null = the main settings screen.
  Future<PluginResult> openSettings(SettingsScreen? screen);
}

class ActionOutcome {
  const ActionOutcome({required this.ok, required this.say, this.needs, this.ask = false});
  final bool ok;

  /// What to say (and show) to the person.
  final String say;

  /// What to turn on to make this work: the screen offers a button for it.
  final Needs? needs;

  /// The answer is a question ("Did you mean …?"): speak it, then listen for the answer.
  final bool ask;

  @override
  bool operator ==(Object other) => other is ActionOutcome && other.ok == ok && other.say == say && other.needs == needs && other.ask == ask;
  @override
  int get hashCode => Object.hash(ok, say, needs, ask);
  @override
  String toString() => 'ActionOutcome(ok: $ok, say: $say${needs != null ? ', needs: $needs' : ''}${ask ? ', ask' : ''})';
}

/// Sites that have no app on the phone but are worth opening when asked by name.
const sites = <String, String>{
  'youtube': 'https://www.youtube.com',
  'google': 'https://www.google.com',
  'github': 'https://github.com',
  'gmail': 'https://mail.google.com',
  'maps': 'https://maps.google.com',
  'google maps': 'https://maps.google.com',
  'netflix': 'https://www.netflix.com',
  'amazon': 'https://www.amazon.com',
  'spotify': 'https://open.spotify.com',
  'whatsapp': 'https://web.whatsapp.com',
  'twitter': 'https://x.com',
  'linkedin': 'https://www.linkedin.com',
  'reddit': 'https://www.reddit.com',
  'wikipedia': 'https://www.wikipedia.org',
  'chatgpt': 'https://chatgpt.com',
};

String formatClock(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${'$minute'.padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String part(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';
  return [if (h > 0) part(h, 'hour'), if (m > 0) part(m, 'minute'), if (s > 0) part(s, 'second')].join(' ');
}

const _screenNames = <SettingsScreen, String>{
  SettingsScreen.wifi: 'Wi-Fi',
  SettingsScreen.bluetooth: 'Bluetooth',
  SettingsScreen.display: 'display',
  SettingsScreen.sound: 'sound',
  SettingsScreen.battery: 'battery',
  SettingsScreen.apps: 'apps',
  SettingsScreen.location: 'location',
};
const _volumeWords = <VolumeChange, String>{
  VolumeChange.up: 'Volume up.',
  VolumeChange.down: 'Volume down.',
  VolumeChange.mute: 'Muted.',
  VolumeChange.unmute: 'Unmuted.',
};
const _trouble = 'I could not do that on this phone.';

ActionOutcome _outcome(PluginResult r, String good) =>
    r.ok ? ActionOutcome(ok: true, say: good) : ActionOutcome(ok: false, say: (r.message ?? '').isNotEmpty ? r.message! : _trouble, needs: r.needs);

/// The phone's own buttons and gestures: what each is called when done, for the spoken answer.
const _controlDone = <ControlOp, String>{
  ControlOp.home: 'Going home.',
  ControlOp.back: 'Going back.',
  ControlOp.recents: 'Here are your recent apps.',
  ControlOp.notifications: 'Here are your notifications.',
  ControlOp.quickSettings: 'Here are your quick settings.',
  ControlOp.lock: 'Locking the phone.',
  ControlOp.screenshot: 'Taking a screenshot.',
  ControlOp.scrollUp: 'Scrolling up.',
  ControlOp.scrollDown: 'Scrolling down.',
};

/// Said when the person has not turned the permission on: what to do, in this app and in Android.
const needsAccessibility =
    'To control your phone, Escanor needs the Accessibility permission. Open Settings, then Voice and phone control in this app, and turn it on.';

String _bare(String url) => url.replaceFirst(RegExp(r'^https://(www\.)?'), '');
final _phoneNumber = RegExp(r'^\+?\d{3,}$');

/// Do one thing on the phone and say what happened. Never throws: whatever goes wrong becomes a sentence the assistant can speak.
/// With no phone plugin only opening a link works (through [openLink]), and it says what is missing.
Future<ActionOutcome> runPhoneAction(PhoneAction action, DevicePlugin? dev,
    {PhoneOptions options = const PhoneOptions(), Future<bool> Function(String url)? openLink}) async {
  if (dev == null) {
    if (action is OpenApp && sites[action.name] != null && openLink != null) {
      await openLink(sites[action.name]!);
      return ActionOutcome(ok: true, say: 'Opening ${_bare(sites[action.name]!)}.');
    }
    if (action is OpenUrl && openLink != null) {
      await openLink(action.url);
      return ActionOutcome(ok: true, say: 'Opening ${_bare(action.url)}.');
    }
    return const ActionOutcome(ok: false, say: 'That works in the Android app. Open Escanor on your phone and ask again.');
  }
  try {
    switch (action) {
      case OpenApp(:final name):
        final site = sites[name];
        final app = matchApp(name, await dev.listApps());
        if (app != null) {
          final launched = await dev.launchPackage(app.package);
          if (launched.ok) return ActionOutcome(ok: true, say: 'Opening ${app.label}.');
          // The app is there but would not start: a site that does the same job is better than "that did not work".
          if (site != null) return _outcome(await dev.openUrl(site), 'Opening ${_bare(site)} in the browser.');
          return ActionOutcome(ok: false, say: (launched.message ?? '').isNotEmpty ? launched.message! : 'I could not open ${app.label}.');
        }
        if (site != null) return _outcome(await dev.openUrl(site), 'Opening ${_bare(site)}.');
        return ActionOutcome(ok: false, say: 'I couldn’t find an app called $name on this phone.');
      case OpenPackage(:final package, :final label):
        return _outcome(await dev.launchPackage(package), 'Opening $label.');
      case OpenUrl(:final url):
        return _outcome(await dev.openUrl(url), 'Opening ${_bare(url).replaceFirst(RegExp(r'/.*$'), '')}.');
      case Call(:final who):
        final direct = options.directCalls != false; // on unless the person turned it off; the phone still needs Android's call permission
        ActionOutcome placed(PluginResult r, String who) {
          if (!r.ok) return ActionOutcome(ok: false, say: (r.message ?? '').isNotEmpty ? r.message! : _trouble);
          if (r.direct == true) return ActionOutcome(ok: true, say: 'Calling $who.');
          final extra = (r.message ?? '').isNotEmpty && r.message != who ? ' ${r.message}' : '';
          return ActionOutcome(ok: true, say: 'Opening the dialer with $who. Press call to ring.$extra');
        }

        if (_phoneNumber.hasMatch(who)) return placed(await dev.callNumber(who, direct: direct), who);
        final listing = dev.listContacts();
        if (listing != null) {
          // Find the person among the phone's own contacts, forgiving how the recogniser spelled the name ("usic" for "USICT", "20 27" for 2027).
          final list = await listing;
          if (!list.result.ok) return ActionOutcome(ok: false, say: (list.result.message ?? '').isNotEmpty ? list.result.message! : _trouble);
          final choice = chooseContact(who, list.contacts);
          switch (choice) {
            case NoContact():
              return ActionOutcome(ok: false, say: 'I couldn’t find $who in your contacts.');
            case AskContact(:final options):
              final names = options.map((o) => o.name).toList();
              final said = names.length > 1 ? '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}' : names.first;
              return ActionOutcome(ok: true, ask: true, say: 'Did you mean $said?');
            case OneContact(:final contact):
              return placed(await dev.callNumber(contact.numbers.first, direct: direct), contact.name);
          }
        }
        final r = await dev.callContact(who, direct: direct);
        return placed(r, r.ok && (r.message ?? '').isNotEmpty ? r.message! : who);
      case Control(:final op):
        if (op == ControlOp.scrollUp || op == ControlOp.scrollDown) {
          return _outcome(await dev.control(ScrollControl(op == ControlOp.scrollUp)), _controlDone[op]!);
        }
        return _outcome(await dev.control(GlobalControl(controlOpName(op))), _controlDone[op]!);
      case TapText(:final text):
        return _outcome(await dev.control(ClickControl(text)), 'Tapped $text.');
      case TypeText(:final text):
        return _outcome(await dev.control(TypeControl(text)), 'Typed it.');
      case ReadScreen():
        final r = await dev.control(const ReadControl());
        return r.ok ? ActionOutcome(ok: true, say: 'On your screen: ${r.message ?? ''}') : _outcome(r, '');
      case SetAlarm(:final hour, :final minute):
        return _outcome(await dev.setAlarm(hour, minute), 'Alarm set for ${formatClock(hour, minute)}.');
      case SetTimer(:final seconds):
        return _outcome(await dev.setTimer(seconds), 'Timer set for ${formatDuration(seconds)}.');
      case Torch(:final on):
        return _outcome(await dev.setTorch(on), on ? 'Flashlight on.' : 'Flashlight off.');
      case Volume(:final change):
        return _outcome(await dev.setVolume(change), _volumeWords[change]!);
      case WebSearch(:final query):
        return _outcome(await dev.openUrl('https://www.google.com/search?q=${Uri.encodeComponent(query)}'), 'Searching for $query.');
      case OpenSettings(:final screen):
        return _outcome(await dev.openSettings(screen), 'Opening ${_screenNames[screen] ?? screen.name} settings.');
    }
  } catch (_) {
    return const ActionOutcome(ok: false, say: _trouble);
  }
}
