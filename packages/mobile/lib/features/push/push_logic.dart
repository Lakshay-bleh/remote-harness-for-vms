/// Push notifications: the rules, kept apart from Firebase so they can be tested without a phone.
library;

/// unsupported: not a phone app. unavailable: it is, but this build was made without Firebase's config, so it cannot register.
enum PushState { unsupported, unavailable, off, on, denied }

/// Where tapping a notification lands. The same names as the app's tabs.
enum PushDest { assistant, computers, connections, machines, settings }

/// The Android notification channel the backend names in every message. Keep the two in step.
const channelId = 'escanor_alerts';
const channelName = 'Alerts';
const channelDescription = 'Approvals, outages and messages from your team';

/// Where this phone's push address is remembered (so sign-out can tell Escanor to forget it).
const tokenKey = 'escanor.push.token';

/// Set once the person has turned push on, so the next start registers again without asking.
const allowedKey = 'escanor.push.allowed';

const _routes = <String, PushDest>{
  'deployment_approvals': PushDest.assistant,
  'emergency_alerts': PushDest.assistant,
  'team_pings': PushDest.assistant,
  'server_down': PushDest.machines,
};

/// Where tapping a notification should land. Anything unexpected opens the main screen.
PushDest routeFor(Object? data) {
  final kind = data is Map ? data['kind'] : null;
  return kind is String && _routes.containsKey(kind) ? _routes[kind]! : PushDest.assistant;
}

/// The phone's answer to "may Escanor notify you?".
PushState stateFromPermission(String p) => p == 'granted' ? PushState.on : (p == 'denied' ? PushState.denied : PushState.off);

enum ChannelState { ok, quiet, blocked, missing }

/// Can the Alerts channel actually show a notification? (Android: 0 = switched off, 1-2 = silent only, 3+ = normal.)
ChannelState channelState(List<({String id, int? importance})>? channels) {
  ({String id, int? importance})? c;
  for (final x in channels ?? const <({String id, int? importance})>[]) {
    if (x.id == channelId) {
      c = x;
      break;
    }
  }
  if (c == null) return ChannelState.missing;
  final importance = c.importance ?? 3; // not reported: assume normal
  return importance <= 0 ? ChannelState.blocked : (importance < 3 ? ChannelState.quiet : ChannelState.ok);
}

/// What the backend calls this phone.
String pushPlatform({required bool ios}) => ios ? 'ios' : 'android';
