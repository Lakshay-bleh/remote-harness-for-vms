import 'package:escanor/features/voice/actions.dart';
import 'package:escanor/features/voice/apps.dart';
import 'package:escanor/features/voice/commands.dart';
import 'package:escanor/features/voice/contacts.dart';

/// A phone that records what it was asked to do. Each method can be replaced; a replaced method is not recorded (as in the web tests).
class FakePhone implements DevicePlugin {
  FakePhone({
    this.apps = const [InstalledApp(label: 'YouTube', package: 'com.yt'), InstalledApp(label: 'WhatsApp', package: 'com.wa')],
    this.onListApps,
    this.onLaunch,
    this.onOpenUrl,
    this.onCallNumber,
    this.onCallContact,
    this.onListContacts,
    this.onControl,
    this.onSetTorch,
    this.onSetTimer,
  });

  final List<InstalledApp> apps;
  final Future<List<InstalledApp>> Function()? onListApps;
  final Future<PluginResult> Function(String package)? onLaunch;
  final Future<PluginResult> Function(String url)? onOpenUrl;
  final Future<PluginResult> Function(String number, bool direct)? onCallNumber;
  final Future<PluginResult> Function(String name, bool? direct)? onCallContact;
  final Future<({PluginResult result, List<Contact> contacts})> Function()? onListContacts;
  final Future<PluginResult> Function(ControlRequest r)? onControl;
  final Future<PluginResult> Function(bool on)? onSetTorch;
  final Future<PluginResult> Function(int seconds)? onSetTimer;

  final List<(String, Object?)> calls = [];
  ({bool granted, bool? available}) callStatusAnswer = (granted: true, available: true);
  static const _ok = PluginResult(ok: true);

  Future<PluginResult> _rec(String name, Object? args) async {
    calls.add((name, args));
    return _ok;
  }

  (String, Object?)? find(String name) {
    for (final c in calls) {
      if (c.$1 == name) return c;
    }
    return null;
  }

  @override
  Future<List<InstalledApp>> listApps() async {
    calls.add(('listApps', null));
    return onListApps != null ? onListApps!() : apps;
  }

  @override
  Future<PluginResult> launchPackage(String package) => onLaunch != null ? onLaunch!(package) : _rec('launchPackage', {'package': package});
  @override
  Future<PluginResult> openUrl(String url) => onOpenUrl != null ? onOpenUrl!(url) : _rec('openUrl', {'url': url});
  @override
  Future<PluginResult> dial(String number) => _rec('dial', {'number': number});
  @override
  Future<PluginResult> callNumber(String number, {required bool direct}) =>
      onCallNumber != null ? onCallNumber!(number, direct) : _rec('callNumber', {'number': number, 'direct': direct});
  @override
  Future<PluginResult> callContact(String name, {bool? direct}) =>
      onCallContact != null ? onCallContact!(name, direct) : _rec('callContact', {'name': name, 'direct': direct});
  @override
  Future<({PluginResult result, List<Contact> contacts})>? listContacts() => onListContacts?.call();
  @override
  Future<({bool granted, bool? available})> callStatus() async => callStatusAnswer;
  @override
  Future<PluginResult> requestCallPermission() => _rec('requestCallPermission', null);
  @override
  Future<ControlStatus> controlStatus() async => const ControlStatus(enabled: true);
  @override
  Future<PluginResult> openControlSettings() => _rec('openControlSettings', null);
  @override
  Future<PluginResult> controlTurnOff() => _rec('controlTurnOff', null);
  @override
  Future<PluginResult> openAppInfo() => _rec('openAppInfo', null);
  @override
  Future<PluginResult> control(ControlRequest request) => onControl != null ? onControl!(request) : _rec('control', request.toJson());
  @override
  Future<PluginResult> setAlarm(int hour, int minute) => _rec('setAlarm', {'hour': hour, 'minute': minute});
  @override
  Future<PluginResult> setTimer(int seconds) => onSetTimer != null ? onSetTimer!(seconds) : _rec('setTimer', {'seconds': seconds});
  @override
  Future<PluginResult> setTorch(bool on) => onSetTorch != null ? onSetTorch!(on) : _rec('setTorch', {'on': on});
  @override
  Future<PluginResult> setVolume(VolumeChange change) => _rec('setVolume', {'change': change.name});
  @override
  Future<PluginResult> openSettings(SettingsScreen? screen) => _rec('openSettings', {'screen': screen?.name ?? 'main'});
}
