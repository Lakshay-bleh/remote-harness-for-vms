import 'dart:convert';

/// The hub's wire protocol, as the phone sees it (packages/shared/src/protocol.ts and validate.ts): what the hub
/// pushes over /ws, its REST shapes, and the checks a message must pass before it is sent. Everything that comes
/// from the hub is treated as untrusted: a frame or row that does not match the protocol is dropped, not guessed at.
/// (The agent<->hub frames, MCP-server registry rules, rate limiting and redaction live on the hub, not here.)

bool _isId(Object? v) => v is String && v.isNotEmpty && v.length <= 256;
bool _isOptId(Object? v) => v == null || _isId(v);
bool _isOptString(Object? v) => v == null || v is String;

/// A non-empty string of at most 256 characters: what the hub accepts as an id.
bool isIdString(Object? v) => _isId(v);

class ImageAttachment {
  const ImageAttachment({required this.mediaType, required this.dataBase64});
  final String mediaType;
  final String dataBase64;
  Map<String, dynamic> toJson() => {'mediaType': mediaType, 'dataBase64': dataBase64};
}

class ClaudeAccount {
  const ClaudeAccount({required this.id, required this.label});
  final String id;
  final String label;

  static ClaudeAccount? tryParse(Object? j) {
    if (j is! Map || !_isId(j['id'])) return null;
    return ClaudeAccount(id: j['id'] as String, label: j['label'] is String ? j['label'] as String : j['id'] as String);
  }

  static List<ClaudeAccount> listFrom(Object? j) =>
      j is List ? [for (final a in j) ?ClaudeAccount.tryParse(a)] : const [];

  @override
  bool operator ==(Object other) => other is ClaudeAccount && other.id == id && other.label == label;
  @override
  int get hashCode => Object.hash(id, label);
}

/// The account a chat runs as when the machine reports none.
const defaultAccounts = [ClaudeAccount(id: 'default', label: 'default')];

class VmDto {
  const VmDto({required this.id, required this.name, required this.connected, this.lastSeenAt, this.accounts = const []});
  final String id;
  final String name;
  final bool connected;
  final String? lastSeenAt;
  final List<ClaudeAccount> accounts;

  VmDto copyWith({String? name, bool? connected, List<ClaudeAccount>? accounts}) =>
      VmDto(id: id, name: name ?? this.name, connected: connected ?? this.connected, lastSeenAt: lastSeenAt, accounts: accounts ?? this.accounts);

  static VmDto? tryParse(Object? j) {
    if (j is! Map || !_isId(j['id'])) return null;
    return VmDto(
      id: j['id'] as String,
      name: j['name'] is String ? j['name'] as String : j['id'] as String,
      connected: j['connected'] == true,
      lastSeenAt: j['lastSeenAt'] is String ? j['lastSeenAt'] as String : null,
      accounts: ClaudeAccount.listFrom(j['accounts']),
    );
  }

  static List<VmDto> listFrom(Object? j) => j is List ? [for (final v in j) ?VmDto.tryParse(v)] : const [];
}

class SessionDto {
  const SessionDto({
    required this.id,
    required this.vmId,
    required this.cwd,
    required this.title,
    required this.createdAt,
    required this.lastMessageAt,
    required this.status,
    required this.accountId,
  });
  final String id;
  final String vmId;
  final String cwd;
  final String title;
  final String createdAt;
  final String lastMessageAt;

  /// active | idle | ended
  final String status;
  final String accountId;

  SessionDto copyWith({String? status, String? title}) => SessionDto(
      id: id, vmId: vmId, cwd: cwd, title: title ?? this.title, createdAt: createdAt, lastMessageAt: lastMessageAt, status: status ?? this.status, accountId: accountId);

  static SessionDto? tryParse(Object? j) {
    if (j is! Map || !_isId(j['id'])) return null;
    String s(String k, [String fallback = '']) => j[k] is String ? j[k] as String : fallback;
    final created = s('createdAt');
    return SessionDto(
      id: j['id'] as String,
      vmId: s('vmId'),
      cwd: s('cwd'),
      title: s('title', 'Untitled'),
      createdAt: created,
      lastMessageAt: s('lastMessageAt', created),
      status: const ['active', 'idle', 'ended', 'waiting'].contains(j['status']) ? j['status'] as String : 'idle',
      accountId: s('accountId', 'default'),
    );
  }

  static List<SessionDto> listFrom(Object? j) => j is List ? [for (final v in j) ?SessionDto.tryParse(v)] : const [];
}

/// The row the app adds (never stored) when the machine says a session ended, so a run without a result stops spinning.
const sessionEndedType = 'session_ended';

class MessageDto {
  const MessageDto({required this.id, required this.sessionId, required this.vmId, required this.message, required this.createdAt});

  /// The hub's row id, or a local one for a row that arrived over the socket.
  final num id;
  final String sessionId;
  final String vmId;

  /// The raw SDK message (a JSON map), or the hub's own `permission_request` / `user local` shapes.
  final Object? message;
  final String createdAt;

  static MessageDto? tryParse(Object? j) {
    if (j is! Map || j['id'] is! num) return null;
    return MessageDto(
      id: j['id'] as num,
      sessionId: j['sessionId'] is String ? j['sessionId'] as String : '',
      vmId: j['vmId'] is String ? j['vmId'] as String : '',
      message: j['message'],
      createdAt: j['createdAt'] is String ? j['createdAt'] as String : '',
    );
  }

  static List<MessageDto> listFrom(Object? j) => j is List ? [for (final v in j) ?MessageDto.tryParse(v)] : const [];
}

// ---------- Hub -> phone (the /ws push channel) ----------

sealed class HubEvent {
  const HubEvent();
}

class VmStatusEvent extends HubEvent {
  const VmStatusEvent({required this.vmId, required this.name, required this.connected, required this.accounts});
  final String vmId;
  final String name;
  final bool connected;
  final List<ClaudeAccount> accounts;
}

class SdkMessageEvent extends HubEvent {
  const SdkMessageEvent({required this.vmId, required this.sessionId, this.tempId, required this.message, required this.createdAt});
  final String vmId;
  final String sessionId;
  final String? tempId;
  final Object? message;
  final String createdAt;
}

/// The reply as Claude is writing it: the whole text so far. Never stored; the finished message follows as an sdk_message.
class SdkPartialEvent extends HubEvent {
  const SdkPartialEvent({required this.vmId, required this.sessionId, required this.text});
  final String vmId;
  final String sessionId;
  final String text;
}

class SessionCreatedEvent extends HubEvent {
  const SessionCreatedEvent(
      {required this.vmId, required this.tempId, required this.sessionId, required this.cwd, required this.title, required this.accountId});
  final String vmId;
  final String tempId;
  final String sessionId;
  final String cwd;
  final String title;
  final String accountId;
}

class SessionEndedEvent extends HubEvent {
  const SessionEndedEvent({required this.vmId, required this.sessionId});
  final String vmId;
  final String sessionId;
}

class PermissionRequestEvent extends HubEvent {
  const PermissionRequestEvent(
      {required this.vmId, required this.sessionId, required this.requestId, required this.toolName, required this.input, this.blockedPath});
  final String vmId;
  final String sessionId;
  final String requestId;
  final String toolName;
  final Map<String, dynamic> input;
  final String? blockedPath;
}

class PermissionResolvedEvent extends HubEvent {
  const PermissionResolvedEvent({required this.vmId, required this.sessionId, required this.requestId});
  final String vmId;
  final String sessionId;
  final String requestId;
}

/// One frame from the hub's socket, or null when it is not a message this app understands (the hub's
/// 'pong', a malformed frame, a type from a newer hub).
HubEvent? parseHubFrame(Object? raw) {
  if (raw is! String) return null;
  Object? m;
  try {
    m = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (m is! Map) return null;
  switch (m['type']) {
    case 'vm_status':
      if (!_isId(m['vmId']) || m['accounts'] is! List) return null;
      return VmStatusEvent(
        vmId: m['vmId'] as String,
        name: m['name'] is String ? m['name'] as String : m['vmId'] as String,
        connected: m['connected'] == true,
        accounts: ClaudeAccount.listFrom(m['accounts']),
      );
    case 'sdk_message':
      if (!_isId(m['vmId']) || !_isId(m['sessionId']) || !_isOptId(m['tempId'])) return null;
      return SdkMessageEvent(
        vmId: m['vmId'] as String,
        sessionId: m['sessionId'] as String,
        tempId: m['tempId'] as String?,
        message: m['message'],
        createdAt: m['createdAt'] is String ? m['createdAt'] as String : DateTime.now().toUtc().toIso8601String(),
      );
    case 'sdk_partial':
      if (!_isId(m['vmId']) || !_isId(m['sessionId']) || m['text'] is! String) return null;
      return SdkPartialEvent(vmId: m['vmId'] as String, sessionId: m['sessionId'] as String, text: m['text'] as String);
    case 'session_created':
      if (!_isId(m['vmId']) || !_isId(m['tempId']) || !_isId(m['sessionId']) || m['cwd'] is! String || m['title'] is! String || m['accountId'] is! String) {
        return null;
      }
      return SessionCreatedEvent(
        vmId: m['vmId'] as String,
        tempId: m['tempId'] as String,
        sessionId: m['sessionId'] as String,
        cwd: m['cwd'] as String,
        title: m['title'] as String,
        accountId: m['accountId'] as String,
      );
    case 'session_ended':
      if (!_isId(m['vmId']) || !_isId(m['sessionId'])) return null;
      return SessionEndedEvent(vmId: m['vmId'] as String, sessionId: m['sessionId'] as String);
    case 'permission_request':
      if (!_isId(m['vmId']) || !_isId(m['sessionId']) || !_isId(m['requestId']) || !_isId(m['toolName']) || m['input'] is! Map || !_isOptString(m['blockedPath'])) {
        return null;
      }
      return PermissionRequestEvent(
        vmId: m['vmId'] as String,
        sessionId: m['sessionId'] as String,
        requestId: m['requestId'] as String,
        toolName: m['toolName'] as String,
        input: Map<String, dynamic>.from(m['input'] as Map),
        blockedPath: m['blockedPath'] as String?,
      );
    case 'permission_resolved':
      if (!_isId(m['vmId']) || !_isId(m['sessionId']) || !_isId(m['requestId'])) return null;
      return PermissionResolvedEvent(vmId: m['vmId'] as String, sessionId: m['sessionId'] as String, requestId: m['requestId'] as String);
    default:
      return null;
  }
}

// ---------- what the phone sends (the hub refuses anything else) ----------

class Result<T> {
  const Result.ok(T this.value) : error = null;
  const Result.fail(String this.error) : value = null;
  final T? value;
  final String? error;
  bool get ok => error == null;
}

const maxTextChars = 200000;
const maxImages = 10;
const maxImageB64Chars = 15000000;
final _imageType = RegExp(r'^image/(png|jpe?g|gif|webp)$');

class UserInput {
  const UserInput({required this.text, this.images});
  final String text;
  final List<ImageAttachment>? images;
}

class NewSessionInput extends UserInput {
  const NewSessionInput({required super.text, super.images, this.cwd, this.accountId});
  final String? cwd;
  final String? accountId;
}

/// The same checks the hub makes on a message (parseUserInput), so a message it would refuse is never sent.
Result<UserInput> parseUserInput(Map<String, Object?> body) {
  final text = body['text'];
  final images = body['images'];
  if (text != null && text is! String) return const Result.fail('text must be a string');
  if (text is String && text.length > maxTextChars) return const Result.fail('text too long');
  List<ImageAttachment>? parsed;
  if (images != null) {
    if (images is! List) return const Result.fail('images must be an array');
    if (images.length > maxImages) return const Result.fail('at most $maxImages images');
    parsed = [];
    for (final img in images) {
      final ImageAttachment a;
      if (img is ImageAttachment) {
        a = img;
      } else if (img is Map && img['mediaType'] is String && img['dataBase64'] is String) {
        a = ImageAttachment(mediaType: img['mediaType'] as String, dataBase64: img['dataBase64'] as String);
      } else {
        return const Result.fail('each image needs an image/* mediaType and dataBase64');
      }
      if (!_imageType.hasMatch(a.mediaType) || a.dataBase64.isEmpty) {
        return const Result.fail('each image needs an image/* mediaType and dataBase64');
      }
      if (a.dataBase64.length > maxImageB64Chars) return const Result.fail('image too large');
      parsed.add(a);
    }
  }
  final t = (text as String?) ?? '';
  if (t.isEmpty && (parsed == null || parsed.isEmpty)) return const Result.fail('text or images required');
  return Result.ok(UserInput(text: t, images: parsed));
}

/// The checks the hub makes when a chat is started (parseNewSession).
Result<NewSessionInput> parseNewSession(Map<String, Object?> body) {
  final base = parseUserInput(body);
  if (!base.ok) return Result.fail(base.error!);
  final cwd = body['cwd'];
  final accountId = body['accountId'];
  if (cwd != null && (cwd is! String || cwd.length > 1024)) return const Result.fail('cwd must be a string');
  if (accountId != null && !_isId(accountId)) return const Result.fail('accountId must be a string');
  return Result.ok(NewSessionInput(text: base.value!.text, images: base.value!.images, cwd: cwd as String?, accountId: accountId as String?));
}

const permissionModeValues = ['default', 'acceptEdits', 'bypassPermissions', 'plan', 'dontAsk', 'auto'];
const effortLevelValues = ['low', 'medium', 'high', 'xhigh', 'max'];
const permissionBehaviors = ['allow', 'deny'];

bool isPermissionMode(Object? v) => v is String && permissionModeValues.contains(v);
bool isEffortLevel(Object? v) => v is String && effortLevelValues.contains(v);
bool isPermissionBehavior(Object? v) => v is String && permissionBehaviors.contains(v);

// ---------- Escanor on the hub: tokens and the MCP install status ----------

class ApiTokenDto {
  const ApiTokenDto({required this.id, required this.label, required this.createdAt, this.scope, this.token});
  final String id;
  final String label;
  final String createdAt;
  final String? scope;

  /// Only in the answer that created it: it is shown once.
  final String? token;

  static ApiTokenDto? tryParse(Object? j) {
    if (j is! Map || !_isId(j['id'])) return null;
    return ApiTokenDto(
      id: j['id'] as String,
      label: j['label'] is String ? j['label'] as String : '',
      createdAt: j['createdAt'] is String ? j['createdAt'] as String : '',
      scope: j['scope'] as String?,
      token: j['token'] is String ? j['token'] as String : null,
    );
  }

  static List<ApiTokenDto> listFrom(Object? j) => j is List ? [for (final v in j) ?ApiTokenDto.tryParse(v)] : const [];
}

class McpServerStatus {
  const McpServerStatus({required this.name, required this.status, this.error});
  final String name;

  /// configured | connected | pending | needs-auth | failed | disabled
  final String status;
  final String? error;

  static McpServerStatus? tryParse(Object? j) {
    if (j is! Map || !_isId(j['name']) || j['status'] is! String) return null;
    return McpServerStatus(name: j['name'] as String, status: j['status'] as String, error: j['error'] is String ? j['error'] as String : null);
  }
}

class VmMcpStatus {
  const VmMcpStatus({required this.vmId, required this.name, required this.connected, required this.mcpSupported, this.servers = const []});
  final String vmId;
  final String name;
  final bool connected;
  final bool mcpSupported;
  final List<McpServerStatus> servers;

  static VmMcpStatus? tryParse(Object? j) {
    if (j is! Map || !_isId(j['vmId'])) return null;
    return VmMcpStatus(
      vmId: j['vmId'] as String,
      name: j['name'] is String ? j['name'] as String : j['vmId'] as String,
      connected: j['connected'] == true,
      mcpSupported: j['mcpSupported'] == true,
      servers: j['servers'] is List ? [for (final s in j['servers'] as List) ?McpServerStatus.tryParse(s)] : const [],
    );
  }
}

class McpOverview {
  const McpOverview({this.serverNames = const [], this.vms = const []});
  final List<String> serverNames;
  final List<VmMcpStatus> vms;

  factory McpOverview.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return McpOverview(
      serverNames: [
        for (final s in (m['servers'] is List ? m['servers'] as List : const []))
          if (s is Map && s['name'] is String) s['name'] as String,
      ],
      vms: [for (final v in (m['vms'] is List ? m['vms'] as List : const [])) ?VmMcpStatus.tryParse(v)],
    );
  }
}

/// The first agent release that understands `set_mcp_servers`.
const minMcpAgentVersion = '0.3.0';

bool agentSupportsMcp(String? version) {
  if (version == null || version.isEmpty) return false;
  List<int> parse(String v) => v.split('.').map((n) => int.tryParse(RegExp(r'^\d+').stringMatch(n) ?? '') ?? 0).toList();
  final have = parse(version);
  final need = parse(minMcpAgentVersion);
  for (var i = 0; i < (have.length > need.length ? have.length : need.length); i++) {
    final d = (i < have.length ? have[i] : 0) - (i < need.length ? need[i] : 0);
    if (d != 0) return d > 0;
  }
  return true;
}

/// The MCP server Escanor installs on every machine of a hub.
const escanorServerName = 'escanor';

/// Is Escanor installed on this hub?
bool escanorInstalled(McpOverview? o) => o != null && o.serverNames.contains(escanorServerName);

/// Where Escanor stands on one machine (the line in "Connect to Escanor").
String escanorInstallLabel(VmMcpStatus vm) {
  if (!vm.connected) return 'offline — installs when it reconnects';
  if (!vm.mcpSupported) return 'agent needs updating to receive it';
  McpServerStatus? s;
  for (final x in vm.servers) {
    if (x.name == escanorServerName) s = x;
  }
  if (s?.status == 'connected') return 'connected';
  if (s?.status == 'failed' || s?.status == 'needs-auth') return '${s!.status}${s.error != null ? ': ${s.error}' : ''}';
  return 'installing…';
}
