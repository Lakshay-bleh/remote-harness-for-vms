/// What the server's voice brain (POST /ai/voice/resolve) answers: what to say, and the actions to run on this phone. Pure.
library;

import 'apps.dart';
import 'commands.dart';

class ServerPlan {
  const ServerPlan({
    required this.source,
    this.say = '',
    this.actions = const [],
    this.needs,
    this.notDevice = false,
    this.chat = false,
    this.delegate = false,
    this.degraded,
    this.model,
  });

  /// rules | llm | none | error
  final String source;
  final String say;

  /// As the server sent them (maps): checked one by one by [planToActions] before anything reaches the phone.
  final Object? actions;

  /// 'clarify': the `say` is a question: speak it and listen again.
  final String? needs;

  /// Not something to do on the device: the app's own assistant should have it.
  final bool notDevice;

  /// `say` is the answer to small talk or a general question: just speak it.
  final bool chat;

  /// `say` is a short acknowledgement ("Checking your services."): speak it now and hand the sentence to the full assistant.
  final bool delegate;

  /// No AI model answered in time; `say` is a stand-in so the person is never left with an error for a simple question.
  final String? degraded;
  final String? model;

  factory ServerPlan.fromJson(Object? raw) {
    final j = raw is Map ? raw : const {};
    return ServerPlan(
      source: j['source'] is String ? j['source'] as String : 'none',
      say: j['say'] is String ? j['say'] as String : '',
      actions: j['actions'],
      needs: j['needs'] is String ? j['needs'] as String : null,
      notDevice: j['not_device'] == true,
      chat: j['chat'] == true,
      delegate: j['delegate'] == true,
      degraded: j['degraded'] is String ? j['degraded'] as String : null,
      model: j['model'] is String ? j['model'] as String : null,
    );
  }
}

bool _isHttps(Object? u) => u is String && RegExp(r'^https://[^\s]+$', caseSensitive: false).hasMatch(u);
bool _isInt(Object? n) => n is int || (n is double && n == n.roundToDouble() && n.isFinite);
int _int(Object? n) => (n as num).toInt();

SettingsScreen? _screen(Object? s) {
  for (final v in SettingsScreen.values) {
    if (v.name == s) return v;
  }
  return null;
}

/// Turn the server's actions into things this phone can do. Anything the phone cannot do, or that does not look right, is dropped
/// and counted (the server is trusted to decide, not to be obeyed blindly: an unknown shape never reaches the phone's plugin).
({List<PhoneAction> actions, int skipped}) planToActions(Object? actions) {
  final out = <PhoneAction>[];
  var skipped = 0;
  for (final raw in actions is List ? actions : const []) {
    final a = raw is Map ? raw : const {};
    switch (a['type']) {
      case 'open_app':
        // Chosen from this phone's own list on the server: open it by package. If the phone could not list its apps the server hands
        // the spoken name back, and the phone looks it up itself.
        if (a['unresolved'] == true && a['label'] is String) {
          out.add(OpenApp(a['label'] as String));
        } else if (a['id'] is String && (a['id'] as String).isNotEmpty && a['label'] is String) {
          out.add(OpenPackage(a['id'] as String, a['label'] as String));
        } else {
          skipped += 1;
        }
      case 'open_url':
        _isHttps(a['url']) ? out.add(OpenUrl(a['url'] as String)) : skipped += 1;
      case 'web_search':
        if (_isHttps(a['url'])) {
          out.add(OpenUrl(a['url'] as String));
        } else if (a['query'] is String && (a['query'] as String).isNotEmpty) {
          out.add(WebSearch(a['query'] as String));
        } else {
          skipped += 1;
        }
      case 'call':
        a['who'] is String && (a['who'] as String).isNotEmpty ? out.add(Call(a['who'] as String)) : skipped += 1;
      case 'alarm':
        final h = a['hour'], m = a['minute'];
        if (_isInt(h) && _isInt(m) && _int(h) >= 0 && _int(h) <= 23 && _int(m) >= 0 && _int(m) <= 59) {
          out.add(SetAlarm(_int(h), _int(m)));
        } else {
          skipped += 1;
        }
      case 'timer':
        final s = a['seconds'];
        _isInt(s) && _int(s) > 0 && _int(s) <= 86400 ? out.add(SetTimer(_int(s))) : skipped += 1;
      case 'torch':
        a['on'] is bool ? out.add(Torch(a['on'] as bool)) : skipped += 1;
      case 'volume':
        final change = switch (a['change']) {
          'up' => VolumeChange.up,
          'down' => VolumeChange.down,
          'mute' => VolumeChange.mute,
          'unmute' => VolumeChange.unmute,
          _ => null,
        };
        change != null ? out.add(Volume(change)) : skipped += 1;
      case 'settings':
        final screen = _screen(a['screen']);
        screen != null ? out.add(OpenSettings(screen)) : skipped += 1;
      default:
        skipped += 1; // media and anything new: this phone has no way to do it yet
    }
  }
  return (actions: out.take(3).toList(), skipped: skipped);
}

/// The phone's apps, as the server wants them.
List<Map<String, String>> appsForServer(List<InstalledApp> apps) => [for (final a in apps) {'id': a.package, 'label': a.label}];
