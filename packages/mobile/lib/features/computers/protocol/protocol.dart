/// Port of escanor-desktop packages/remote/src/protocol.ts: the messages between the phone and the computer.
/// Messages travel as JSON objects (`{"t": "chat", ...}`); here they stay plain maps ([Msg]) so what is sealed is exactly what the
/// computer expects, with typed views for the few shapes the screens read.
library;

typedef Msg = Map<String, dynamic>;

/// Messages from the phone. Everything is sealed (AES-GCM) before it leaves the phone.
abstract final class ClientMsg {
  static Msg list() => {'t': 'list'};
  static Msg pending() => {'t': 'pending'};
  static Msg call(String id, String capability, [Object? input]) => {'t': 'call', 'id': id, 'capability': capability, 'input': ?input};

  /// [fresh]: start a new conversation (forget what this phone said before).
  static Msg chat(String id, String text, {bool fresh = false}) => {'t': 'chat', 'id': id, 'text': text, if (fresh) 'fresh': true};
  static Msg approve(String approvalId, bool ok) => {'t': 'approve', 'approvalId': approvalId, 'ok': ok};
  static Msg subscribe(List<String> channels) => {'t': 'subscribe', 'channels': channels};

  /// Which kinds of action are switched on for phones (Settings > Permissions on the computer).
  static Msg groups() => {'t': 'groups'};

  /// Ask the computer's owner to switch one on. Only the owner, at the computer, can say yes.
  static Msg requestGroup(String group) => {'t': 'request_group', 'group': group};

  /// A page of what phones and the voice assistant did, newest first: [limit] entries older than [before].
  static Msg activity({int? limit, String? before}) => {'t': 'activity', 'limit': ?limit, 'before': ?before};
  static Msg ping() => {'t': 'ping'};
}

class CapabilityInfo {
  CapabilityInfo({required this.id, required this.group, required this.describe, required this.risk, required this.inputSchema});
  final String id;
  final String group;
  final String describe;

  /// read | write | destructive
  final String risk;
  final Map<String, dynamic> inputSchema;

  factory CapabilityInfo.fromJson(Map<String, dynamic> j) => CapabilityInfo(
    id: '${j['id'] ?? ''}',
    group: '${j['group'] ?? ''}',
    describe: '${j['describe'] ?? ''}',
    risk: '${j['risk'] ?? 'read'}',
    inputSchema: j['inputSchema'] is Map ? Map<String, dynamic>.from(j['inputSchema'] as Map) : const {},
  );
}

class PermissionGroup {
  const PermissionGroup({required this.id, required this.label, required this.about, required this.enabled});
  final String id;
  final String label;
  final String about;

  /// Switched on for phones right now.
  final bool enabled;

  factory PermissionGroup.fromJson(Map<String, dynamic> j) =>
      PermissionGroup(id: '${j['id'] ?? ''}', label: '${j['label'] ?? ''}', about: '${j['about'] ?? ''}', enabled: j['enabled'] == true);
  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'about': about, 'enabled': enabled};

  @override
  bool operator ==(Object other) => other is PermissionGroup && other.id == id && other.label == label && other.about == about && other.enabled == enabled;
  @override
  int get hashCode => Object.hash(id, label, about, enabled);
}

/// `asked`: the owner has been asked on the computer. `already_on`: nothing to do. `busy`: a question about it is already waiting.
/// `unavailable`: no Escanor Desktop window is open to show the question in.
enum GroupRequestStatus { asked, alreadyOn, unknown, busy, unavailable }

GroupRequestStatus groupRequestStatusOf(Object? wire) => switch (wire) {
  'asked' => GroupRequestStatus.asked,
  'already_on' => GroupRequestStatus.alreadyOn,
  'busy' => GroupRequestStatus.busy,
  'unavailable' => GroupRequestStatus.unavailable,
  _ => GroupRequestStatus.unknown,
};

class ActivityItem {
  const ActivityItem({
    required this.at,
    required this.capabilityId,
    required this.caller,
    required this.risk,
    required this.outcome,
    required this.ms,
    this.message,
  });
  final String at;
  final String capabilityId;
  final String caller;
  final String risk;
  final String outcome;
  final num ms;
  final String? message;

  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
    at: '${j['at'] ?? ''}',
    capabilityId: '${j['capabilityId'] ?? ''}',
    caller: '${j['caller'] ?? ''}',
    risk: '${j['risk'] ?? 'read'}',
    outcome: '${j['outcome'] ?? ''}',
    ms: j['ms'] is num ? j['ms'] as num : 0,
    message: j['message'] is String ? j['message'] as String : null,
  );
  Map<String, dynamic> toJson() => {'at': at, 'capabilityId': capabilityId, 'caller': caller, 'risk': risk, 'outcome': outcome, 'ms': ms, 'message': ?message};
}

/// An action on the computer waiting for a person's OK (`{t: 'approval', ...}`).
class Approval {
  const Approval({required this.approvalId, required this.capabilityId, required this.describe, required this.risk, this.input});
  final String approvalId;
  final String capabilityId;
  final String describe;
  final String risk;
  final Object? input;

  factory Approval.fromJson(Map<String, dynamic> j) => Approval(
    approvalId: '${j['approvalId'] ?? ''}',
    capabilityId: '${j['capabilityId'] ?? ''}',
    describe: '${j['describe'] ?? ''}',
    risk: '${j['risk'] ?? ''}',
    input: j['input'],
  );
}

class MachineInfo {
  const MachineInfo({required this.name, required this.hostname, required this.os, required this.appVersion});
  final String name;
  final String hostname;
  final String os;
  final String appVersion;
  factory MachineInfo.fromJson(Map<String, dynamic> j) =>
      MachineInfo(name: '${j['name'] ?? ''}', hostname: '${j['hostname'] ?? ''}', os: '${j['os'] ?? ''}', appVersion: '${j['appVersion'] ?? ''}');
}

/// The pairing payload shown as a QR code (and as plain text next to it).
class PairingPayload {
  const PairingPayload({this.v = 1, required this.code, required this.machine, required this.lan, this.agentId});
  final int v;

  /// The one-time pairing secret: ABCD-EFGH-…
  final String code;
  final String machine;

  /// LAN addresses to try, `host:port`.
  final List<String> lan;

  /// Backend machine id, when signed in and cloud access is on: lets the phone reach this computer away from home.
  final String? agentId;

  Map<String, dynamic> toJson() => {'v': v, 'code': code, 'machine': machine, 'lan': lan, 'agentId': agentId};

  @override
  bool operator ==(Object other) =>
      other is PairingPayload && other.v == v && other.code == code && other.machine == machine && other.agentId == agentId && _listEq(other.lan, lan);
  @override
  int get hashCode => Object.hash(v, code, machine, agentId, lan.join(','));
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

const protocolVersion = 1;
const maxMessageBytes = 256 * 1024;
const maxSkewMs = 5 * 60000;

/// The relay command the phone queues in the Escanor backend: plugin `desktop`, action `sealed`.
const relayPlugin = 'desktop';
const relayAction = 'sealed';

/// Pairing a new phone over the cloud: queued by a phone that knows the code, answered by the computer showing it.
const relayPairAction = 'pair';

final _groupId = RegExp(r'^[a-z0-9_]{1,40}$');

/// What the computer accepts from a phone (the same check it runs), so the phone never sends something it would refuse.
bool isClientMsg(Object? v) {
  if (v is! Map) return false;
  final m = v;
  bool isInt(Object? x) => x is int || (x is double && x == x.roundToDouble());
  switch (m['t']) {
    case 'list':
    case 'pending':
    case 'ping':
    case 'groups':
      return true;
    case 'call':
      return m['id'] is String && m['capability'] is String && (m['capability'] as String).length < 100;
    case 'chat':
      final text = m['text'];
      return m['id'] is String && text is String && text.isNotEmpty && text.length <= 4000 && (m['fresh'] == null || m['fresh'] is bool);
    case 'activity':
      final limit = m['limit'];
      final before = m['before'];
      return (limit == null || (isInt(limit) && (limit as num) >= 1 && limit <= 50)) && (before == null || (before is String && before.length <= 40));
    case 'request_group':
      return m['group'] is String && _groupId.hasMatch(m['group'] as String);
    case 'approve':
      return m['approvalId'] is String && m['ok'] is bool;
    case 'subscribe':
      return m['channels'] is List && (m['channels'] as List).every((c) => c == 'events' || c == 'stats');
    default:
      return false;
  }
}

/// The first message of type [t] among [replies] (or null).
Msg? firstOf(List<Msg> replies, Set<String> types) {
  for (final m in replies) {
    if (types.contains(m['t'])) return m;
  }
  return null;
}
