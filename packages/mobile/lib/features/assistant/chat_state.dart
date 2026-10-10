/// The Escanor assistant: the API's shapes and the pure chat-state functions (the port of shared/src/escanor.ts).
/// No I/O and no Flutter, so the behaviour that matters (merging polls, showing a message at once, what to draw) is tested.
library;

// ---------------------------------------------------------------------------- API shapes

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _list(Object? v) => v is List ? v : const [];
String _str(Object? v, [String fallback = '']) => v is String ? v : (v == null ? fallback : '$v');
String? _strOrNull(Object? v) => v is String ? v : null;
int _int(Object? v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
bool _bool(Object? v) => v == true;

/// Where the assistant is: not_configured | not_started | setting_up | ready | reconnecting | error.
class AssistantStatus {
  const AssistantStatus({required this.state, required this.ready, required this.message});
  final String state;
  final bool ready;
  final String message;

  factory AssistantStatus.fromJson(Object? json) {
    final j = _map(json);
    return AssistantStatus(state: _str(j['state'], 'not_started'), ready: _bool(j['ready']), message: _str(j['message']));
  }
}

class AssistantConversation {
  const AssistantConversation({required this.id, required this.title, this.createdAt, this.updatedAt});
  final String id;

  /// What the server calls it.
  final String title;
  final String? createdAt;
  final String? updatedAt;

  factory AssistantConversation.fromJson(Object? json) {
    final j = _map(json);
    return AssistantConversation(id: _str(j['id']), title: _str(j['title']), createdAt: _strOrNull(j['created_at']), updatedAt: _strOrNull(j['updated_at']));
  }

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'created_at': createdAt, 'updated_at': updatedAt};
}

/// pending | allowed | denied | expired
typedef ApprovalStatus = String;

/// One thing said or done in a conversation. [kind]: user | assistant | activity | error | notice | done | approval.
/// A `notice` is a quiet line from the server about the turn itself: "Stopped.", or "X wasn't available, so Y is answering".
/// "Let Escanor pick the model for each message."
const autoModel = 'auto';

/// One model the assistant can answer with.
class AssistantModel {
  const AssistantModel({required this.id, required this.label, this.available = true, this.provider = ''});
  final String id;
  final String label;
  final bool available;
  final String provider;
}

/// What `/ai/models` says: every model, and Auto.
class AssistantModels {
  const AssistantModels({this.models = const [], this.autoAvailable = true});
  final List<AssistantModel> models;
  final bool autoAvailable;

  /// The ones that can answer now: what the picker offers after Auto.
  List<AssistantModel> get usable => [for (final m in models) if (m.available) m];

  factory AssistantModels.fromJson(Object? json) {
    final j = _map(json);
    final list = j['models'];
    final auto = _map(j['auto']);
    return AssistantModels(
      models: [
        if (list is List)
          for (final m in list.map(_map))
            if (_str(m['id']).isNotEmpty)
              AssistantModel(id: _str(m['id']), label: _str(m['label'], _str(m['model'])), available: m['available'] != false, provider: _str(m['provider_label'])),
      ],
      autoAvailable: auto.isEmpty || auto['available'] != false,
    );
  }
}

/// A chat the server found for a search, with the words that matched.
class ChatHit {
  const ChatHit({required this.id, this.snippet = '', this.match = ''});
  final String id;

  /// The sentence from the chat that matched best ("" when only the title did).
  final String snippet;

  /// title | words | semantic
  final String match;
}

class ChatSearch {
  const ChatSearch({this.hits = const [], this.semantic = false});
  final List<ChatHit> hits;

  /// Found by meaning as well as by words.
  final bool semantic;

  factory ChatSearch.fromJson(Object? json) {
    final j = _map(json);
    final list = j['results'];
    return ChatSearch(
      hits: [
        if (list is List)
          for (final r in list.map(_map))
            if (_str(r['id']).isNotEmpty) ChatHit(id: _str(r['id']), snippet: _str(r['snippet']), match: _str(r['match'])),
      ],
      semantic: _bool(j['semantic']),
    );
  }
}

class AssistantItem {
  const AssistantItem({
    required this.id,
    required this.kind,
    this.text = '',
    this.at,
    this.requestId = '',
    this.status = 'pending',
    this.title = '',
    this.detail = '',
    this.risk = 'normal',
    this.raw = '',
    this.optimistic = false,
  });

  final int id;
  final String kind;
  final String text;
  final String? at;

  // approvals
  final String requestId;
  final ApprovalStatus status;
  final String title;
  final String detail;

  /// normal | high
  final String risk;
  final String raw;

  /// Shown at once, before the server has heard of it.
  final bool optimistic;

  AssistantItem copyWith({ApprovalStatus? status}) => AssistantItem(
        id: id,
        kind: kind,
        text: text,
        at: at,
        requestId: requestId,
        status: status ?? this.status,
        title: title,
        detail: detail,
        risk: risk,
        raw: raw,
        optimistic: optimistic,
      );

  factory AssistantItem.fromJson(Object? json) {
    final j = _map(json);
    return AssistantItem(
      id: _int(j['id']),
      kind: _str(j['kind']),
      text: _str(j['text']),
      at: _strOrNull(j['at']),
      requestId: _str(j['request_id']),
      status: _str(j['status'], 'pending'),
      title: _str(j['title']),
      detail: _str(j['detail']),
      risk: _str(j['risk'], 'normal'),
      raw: _str(j['raw']),
    );
  }
}

/// What the assistant is doing right now, e.g. "Asking GPT OSS 120b · step 2", and since when (ISO 8601).
class AssistantProgress {
  const AssistantProgress({required this.text, required this.since, this.step});
  final String text;
  final String since;
  final int? step;

  /// Null for anything that is not a progress object with some text (older servers send none).
  static AssistantProgress? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    if (text is! String) return null;
    return AssistantProgress(text: text, since: _str(json['since']), step: _intOrNull(json['step']));
  }

  @override
  bool operator ==(Object other) => other is AssistantProgress && other.text == text && other.since == since && other.step == step;

  @override
  int get hashCode => Object.hash(text, since, step);

  @override
  String toString() => 'AssistantProgress($text, $since, $step)';
}

class AssistantMessages {
  const AssistantMessages({this.items = const [], this.approvals = const [], this.running = false, this.pending = 0, this.lastId = 0, this.progress});
  final List<AssistantItem> items;
  final List<({String requestId, ApprovalStatus status})> approvals;
  final bool running;
  final int pending;
  final int lastId;

  /// Absent from servers older than this field: null.
  final AssistantProgress? progress;

  factory AssistantMessages.fromJson(Object? json) {
    final j = _map(json);
    return AssistantMessages(
      items: [for (final i in _list(j['items'])) AssistantItem.fromJson(i)],
      approvals: [
        for (final a in _list(j['approvals']))
          (requestId: _str(_map(a)['request_id']), status: _str(_map(a)['status'], 'pending')),
      ],
      running: _bool(j['running']),
      pending: _int(j['pending']),
      lastId: _int(j['last_id']),
      progress: AssistantProgress.fromJson(j['progress']),
    );
  }
}

class AssistantUsage {
  const AssistantUsage({
    required this.source,
    required this.messagesToday,
    this.messageLimit,
    required this.todayRequests,
    required this.todayTokens,
    this.todayRequestLimit,
    this.todayTokenLimit,
    required this.monthRequests,
    required this.monthInputTokens,
    required this.monthOutputTokens,
    this.costIsEstimate = false,
    this.unpricedModels = const [],
  });

  /// escanor-ai | local
  final String source;
  final int messagesToday;
  final int? messageLimit;
  final int todayRequests;
  final int todayTokens;
  final int? todayRequestLimit;
  final int? todayTokenLimit;
  final int monthRequests;
  final int monthInputTokens;
  final int monthOutputTokens;
  final bool costIsEstimate;
  final List<String> unpricedModels;

  factory AssistantUsage.fromJson(Object? json) {
    final j = _map(json);
    final today = _map(j['today']);
    final month = _map(j['month']);
    return AssistantUsage(
      source: _str(j['source'], 'escanor-ai'),
      messagesToday: _int(j['messages_today']),
      messageLimit: _intOrNull(j['message_limit']),
      todayRequests: _int(today['requests']),
      todayTokens: _int(today['tokens']),
      todayRequestLimit: _intOrNull(today['request_limit']),
      todayTokenLimit: _intOrNull(today['token_limit']),
      monthRequests: _int(month['requests']),
      monthInputTokens: _int(month['input_tokens']),
      monthOutputTokens: _int(month['output_tokens']),
      costIsEstimate: _bool(j['cost_is_estimate']),
      unpricedModels: [for (final m in _list(j['unpriced_models'])) _str(m)],
    );
  }
}

class CapabilityIntegration {
  const CapabilityIntegration({
    required this.providerId,
    required this.name,
    required this.connected,
    required this.authMethod,
    this.availableToAssistant,
    this.needsReconnect = false,
  });
  final String providerId;
  final String name;
  final bool connected;
  final String authMethod;

  /// true: the assistant will see it; false: connected but it has no tools for it yet; null: could not check.
  final bool? availableToAssistant;
  final bool needsReconnect;
}

/// What the assistant can reach right now. The same answer on every device.
class AssistantCapabilities {
  const AssistantCapabilities({
    required this.assistantState,
    required this.assistantReady,
    required this.machineState,
    required this.machineDetail,
    required this.machineSource,
    required this.mcpInstalled,
    required this.mcpChecked,
    required this.integrations,
    required this.codeHosts,
    required this.canChangeCode,
    required this.protectedBranches,
    required this.summary,
  });
  final String assistantState;
  final bool assistantReady;
  final String machineState;
  final String machineDetail;
  final String machineSource;
  final bool mcpInstalled;
  final bool mcpChecked;
  final List<CapabilityIntegration> integrations;
  final List<({String host, bool connected})> codeHosts;
  final bool canChangeCode;
  final String protectedBranches;
  final String summary;

  factory AssistantCapabilities.fromJson(Object? json) {
    final j = _map(json);
    final a = _map(j['assistant']);
    final m = _map(j['machine']);
    final mcp = _map(j['mcp']);
    final code = _map(j['code']);
    return AssistantCapabilities(
      assistantState: _str(a['state']),
      assistantReady: _bool(a['ready']),
      machineState: _str(m['state'], 'unknown'),
      machineDetail: _str(m['detail']),
      machineSource: _str(m['source']),
      mcpInstalled: _bool(mcp['installed']),
      mcpChecked: _bool(mcp['checked']),
      integrations: [
        for (final i in _list(j['integrations']))
          CapabilityIntegration(
            providerId: _str(_map(i)['provider_id']),
            name: _str(_map(i)['name']),
            connected: _bool(_map(i)['connected']),
            authMethod: _str(_map(i)['auth_method']),
            availableToAssistant: _map(i)['available_to_assistant'] is bool ? _map(i)['available_to_assistant'] as bool : null,
            needsReconnect: _bool(_map(i)['needs_reconnect']),
          ),
      ],
      codeHosts: [for (final h in _list(code['hosts'])) (host: _str(_map(h)['host']), connected: _bool(_map(h)['connected']))],
      canChangeCode: _bool(code['can_change_code']),
      protectedBranches: _str(code['protected_branches']),
      summary: _str(j['summary']),
    );
  }
}

class MachineEvent {
  const MachineEvent({required this.at, required this.kind, required this.detail});

  /// Seconds since 1970.
  final num at;
  final String kind;
  final String detail;
}

class MachineView {
  const MachineView({required this.state, required this.detail, required this.available, required this.events, this.logs});
  final String state;
  final String detail;
  final bool available;
  final List<MachineEvent> events;
  final String? logs;

  factory MachineView.fromJson(Object? json) {
    final j = _map(json);
    return MachineView(
      state: _str(j['state'], 'unknown'),
      detail: _str(j['detail']),
      available: _bool(j['available']),
      events: [
        for (final e in _list(j['events']))
          MachineEvent(at: _map(e)['at'] is num ? _map(e)['at'] as num : 0, kind: _str(_map(e)['kind']), detail: _str(_map(e)['detail'])),
      ],
      logs: _strOrNull(j['logs']),
    );
  }
}

// ---------------------------------------------------------------------------- chat state

class ChatState {
  const ChatState({this.items = const [], this.lastId = 0, this.running = false, this.pending = 0, this.progress});
  final List<AssistantItem> items;

  /// Highest server message id seen; the next poll asks for everything after it.
  final int lastId;
  final bool running;
  final int pending;

  /// What the server last said it is doing; null when it is not working or did not say.
  final AssistantProgress? progress;

  ChatState copyWith({List<AssistantItem>? items, int? lastId, bool? running, int? pending, AssistantProgress? Function()? progress}) => ChatState(
        items: items ?? this.items,
        lastId: lastId ?? this.lastId,
        running: running ?? this.running,
        pending: pending ?? this.pending,
        progress: progress != null ? progress() : this.progress,
      );
}

const emptyChat = ChatState();

int _optimisticCounter = 0;

/// Show the person's message at once, before the server has heard of it.
ChatState addOptimisticMessage(ChatState state, String text) {
  _optimisticCounter += 1;
  return state.copyWith(
    items: [...state.items, AssistantItem(id: -_optimisticCounter, kind: 'user', text: text, optimistic: true)],
    running: true,
  );
}

/// Take the optimistic message back, e.g. when sending failed.
ChatState dropOptimisticMessages(ChatState state) =>
    state.copyWith(items: state.items.where((i) => !i.optimistic).toList(), running: false, progress: () => null);

/// Merge one poll into the state. Safe to apply the same response twice.
ChatState applyMessages(ChatState state, AssistantMessages res) {
  final fresh = res.items.where((i) => i.id > state.lastId).toList();

  // Each real user message replaces one optimistic copy of it (matched by text, oldest first).
  var items = List<AssistantItem>.of(state.items);
  for (final incoming in fresh) {
    if (incoming.kind != 'user') continue;
    final at = items.indexWhere((i) => i.optimistic && i.kind == 'user' && i.text == incoming.text);
    if (at >= 0) items.removeAt(at);
  }
  items = [...items, ...fresh];

  final answers = {for (final a in res.approvals) a.requestId: a.status};
  items = [
    for (final i in items) (i.kind == 'approval' && answers.containsKey(i.requestId)) ? i.copyWith(status: answers[i.requestId]) : i,
  ];

  final p = res.progress;
  final progress = res.running && p != null && p.text.isNotEmpty ? p : null;
  return ChatState(
    items: items,
    lastId: state.lastId > res.lastId ? state.lastId : res.lastId,
    running: res.running,
    pending: res.pending,
    progress: progress,
  );
}

/// Reflect the person's answer immediately, before the next poll confirms it.
ChatState markAnswered(ChatState state, String requestId, bool allow) {
  final status = allow ? 'allowed' : 'denied';
  return state.copyWith(
    items: [
      for (final i in state.items) (i.kind == 'approval' && i.requestId == requestId && i.status == 'pending') ? i.copyWith(status: status) : i,
    ],
    pending: state.pending - 1 < 0 ? 0 : state.pending - 1,
  );
}

enum BlockType { user, assistant, error, activity, notice, approval }

class DisplayBlock {
  DisplayBlock({required this.key, required this.type, this.text = '', this.optimistic = false, this.live = false, this.item});
  final String key;
  final BlockType type;
  final String text;
  final bool optimistic;

  /// Only the latest activity line pulses while work is happening.
  bool live;

  /// The question, for approvals.
  final AssistantItem? item;
}

/// What to actually draw. A run of "Checking which services are available" x9 is one quiet line, the turn-finished marker is not
/// drawn, and only the latest activity line pulses while work is happening.
List<DisplayBlock> toDisplay(ChatState state) {
  final blocks = <DisplayBlock>[];
  for (var index = 0; index < state.items.length; index++) {
    final item = state.items[index];
    final key = '${item.id}:$index';
    switch (item.kind) {
      case 'user':
        blocks.add(DisplayBlock(key: key, type: BlockType.user, text: item.text, optimistic: item.optimistic));
      case 'assistant':
        blocks.add(DisplayBlock(key: key, type: BlockType.assistant, text: item.text));
      case 'error':
        blocks.add(DisplayBlock(key: key, type: BlockType.error, text: item.text));
      case 'notice':
        blocks.add(DisplayBlock(key: key, type: BlockType.notice, text: item.text));
      case 'approval':
        // A question nobody needs to answer any more (the turn ended) is noise.
        if (item.status != 'expired') blocks.add(DisplayBlock(key: key, type: BlockType.approval, item: item));
      case 'activity':
        final previous = blocks.isEmpty ? null : blocks.last;
        if (previous != null && previous.type == BlockType.activity && previous.text == item.text) break; // the same thing again
        blocks.add(DisplayBlock(key: key, type: BlockType.activity, text: item.text));
      default:
        break; // 'done' and anything unknown
    }
  }

  if (state.running && state.pending == 0 && blocks.isNotEmpty && blocks.last.type == BlockType.activity) {
    blocks.last.live = true;
  }
  return blocks;
}

/// Are we waiting on the assistant (as opposed to on the person)? Drives the "thinking" indicator.
bool isThinking(ChatState state) {
  if (!state.running || state.pending > 0) return false;
  final blocks = toDisplay(state);
  if (blocks.isEmpty) return true;
  // A notice mid-turn ("X wasn't available, so Y is answering") is still waiting on the answer.
  final last = blocks.last.type;
  return last == BlockType.user || last == BlockType.activity || last == BlockType.notice;
}

/// Whole seconds since an ISO time, never negative (a phone clock a little ahead of the server's), or null when unreadable.
int? secondsSince(String? iso, [int? nowMs]) {
  final t = iso == null || iso.isEmpty ? null : DateTime.tryParse(iso);
  if (t == null) return null;
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final secs = ((now - t.millisecondsSinceEpoch) / 1000).floor();
  return secs < 0 ? 0 : secs;
}

/// The thinking line: what the server says it is doing, with how long it has been at it ("Asking GPT OSS 120b · step 2 · 14s").
/// Without progress (older servers) the time counts from [startedAtMs], when this phone first saw it working.
String thinkingLabel(AssistantProgress? progress, [int? nowMs, int? startedAtMs]) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  int? secs;
  if (progress != null) {
    secs = secondsSince(progress.since, now);
  } else if (startedAtMs != null) {
    final s = ((now - startedAtMs) / 1000).floor();
    secs = s < 0 ? 0 : s;
  }
  final text = progress?.text.trim() ?? '';
  final what = text.isEmpty ? 'Thinking…' : text;
  return secs == null ? what : '$what · ${secs}s';
}

// ---------------------------------------------------------------------------- stopping a turn, and a server that stops answering

/// After a stop the server confirmed, how long it may still say "running" before the person is told and may send again.
const stopGraceMs = 10000;

/// Message polls that fail in a row before the person is told the assistant cannot be reached.
const pollFailuresToReport = 4;

enum StopKind {
  /// Nothing asked.
  idle,

  /// Stop pressed before the server gave the new chat an id: sent the moment it does.
  queued,

  /// On its way to the server.
  sending,

  /// The server took it at [StopPhase.at] (ms); waiting for the turn to end.
  sent,
}

class StopPhase {
  const StopPhase._(this.kind, [this.at = 0]);
  static const idle = StopPhase._(StopKind.idle);
  static const queued = StopPhase._(StopKind.queued);
  static const sending = StopPhase._(StopKind.sending);
  const StopPhase.sent(int at) : this._(StopKind.sent, at);

  final StopKind kind;

  /// When the server took the stop (ms since epoch); only for [StopKind.sent].
  final int at;

  @override
  bool operator ==(Object other) => other is StopPhase && other.kind == kind && other.at == at;

  @override
  int get hashCode => Object.hash(kind, at);

  @override
  String toString() => kind == StopKind.sent ? 'StopPhase.sent($at)' : 'StopPhase.${kind.name}';
}

/// What pressing Stop does now: queue it until the chat has an id, send it, or nothing (already asked). A stop the server took but
/// did not act on ([stuck]) can be sent again.
({StopPhase phase, bool send}) pressStop(StopPhase phase, bool hasId, [bool stuck = false]) {
  if (phase.kind != StopKind.idle && !(stuck && phase.kind == StopKind.sent)) return (phase: phase, send: false);
  return hasId ? (phase: StopPhase.sending, send: true) : (phase: StopPhase.queued, send: false);
}

/// Where a stop stands after a poll. The turn ending clears it; a turn still "running" well after the server took the stop is
/// `stuck`, so the person is told and can send again rather than wait on a spinner that never ends.
({StopPhase phase, bool stuck}) stopStatus(StopPhase phase, bool running, [int? nowMs]) {
  if (!running && phase.kind == StopKind.sent) return (phase: StopPhase.idle, stuck: false);
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  return (phase: phase, stuck: phase.kind == StopKind.sent && running && now - phase.at > stopGraceMs);
}

/// Is the send button usable? Not while a turn runs, unless the turn looks lost (a stuck stop, or a server that stopped answering).
bool canSendNow(ChatState state, {required bool stuck, required bool unreachable}) => !state.running || stuck || unreachable;

/// How long to wait before asking again (ms). Quick while something is happening, patient otherwise.
int pollDelayMs(ChatState state) {
  if (state.running) return 700;
  if (state.pending > 0) return 1500;
  return 8000;
}

/// Usage, in words a person can act on. Cost is the operator's business and is deliberately not shown.
class UsageSummary {
  const UsageSummary({required this.messages, this.tokens, this.ratio, required this.level});
  final String messages;
  final String? tokens;

  /// 0..1 of the daily message allowance used, or null when there is no limit.
  final double? ratio;

  /// ok | warn | full
  final String level;

  @override
  bool operator ==(Object other) =>
      other is UsageSummary && other.messages == messages && other.tokens == tokens && other.ratio == ratio && other.level == level;

  @override
  int get hashCode => Object.hash(messages, tokens, ratio, level);

  @override
  String toString() => 'UsageSummary($messages, $tokens, $ratio, $level)';
}

String _compact(int n) {
  String trim(String s) => s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  if (n >= 1000000) return '${trim((n / 1000000).toStringAsFixed(1))}M';
  if (n >= 1000) return '${trim((n / 1000).toStringAsFixed(1))}k';
  return '$n';
}

UsageSummary describeUsage({required int messagesToday, int? messageLimit, required int todayTokens}) {
  final used = messagesToday < 0 ? 0 : messagesToday;
  final limit = (messageLimit != null && messageLimit > 0) ? messageLimit : null;
  final double? ratio = limit == null ? null : (used / limit > 1 ? 1.0 : used / limit);
  return UsageSummary(
    messages: limit != null ? '$used of $limit messages today' : '$used message${used == 1 ? '' : 's'} today',
    tokens: todayTokens > 0 ? '${_compact(todayTokens)} tokens' : null,
    ratio: ratio,
    level: ratio == null ? 'ok' : (ratio >= 1 ? 'full' : (ratio >= 0.8 ? 'warn' : 'ok')),
  );
}

/// [describeUsage] for what the server sent.
UsageSummary describeAssistantUsage(AssistantUsage u) =>
    describeUsage(messagesToday: u.messagesToday, messageLimit: u.messageLimit, todayTokens: u.todayTokens);
