import 'dart:convert';

import 'diff.dart';
import 'group_messages.dart';
import 'protocol.dart';

/// How a machine chat words things (Message.tsx and ChatView.tsx), mirroring the Claude Code CLI's tool UI.

/// A path relative to the session's folder, like the CLI shows it.
String displayPath(Object? p, String cwd) {
  if (p is! String) return '';
  if (cwd.isNotEmpty && p.startsWith('$cwd/')) return p.substring(cwd.length + 1);
  return p;
}

String plural(int n, String word, [String? pluralWord]) => '$n ${n == 1 ? word : (pluralWord ?? '${word}s')}';

String fmtDuration(num ms) {
  final s = ms ~/ 1000;
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  if (m < 60) return '${m}m ${s % 60}s';
  return '${m ~/ 60}h ${m % 60}m ${s % 60}s';
}

final _mcpName = RegExp(r'^mcp__(.+?)__(.+)$');
final _mcpServer = RegExp(r'^mcp__(.+?)__');

String toolName(String name, Map<String, dynamic> input) {
  switch (name) {
    case 'Edit':
    case 'MultiEdit':
      return input['old_string'] == '' ? 'Create' : 'Update';
    case 'Glob':
    case 'Grep':
      return 'Search';
    case 'Task':
      return input['subagent_type'] is String ? input['subagent_type'] as String : 'Agent';
    default:
      final mcp = _mcpName.firstMatch(name);
      return mcp != null ? mcp.group(2)! : name;
  }
}

String _s(Object? v) => v == null ? '' : '$v';

String toolArgs(String name, Map<String, dynamic> input, String cwd) {
  switch (name) {
    case 'Bash':
      final cmd = _s(input['command']);
      final lines = cmd.split('\n');
      final shown = lines.take(2).join('\n');
      if (shown.length > 160 || lines.length > 2) {
        return '${(shown.length > 160 ? shown.substring(0, 160) : shown).trimRight()}…';
      }
      return shown;
    case 'Read':
    case 'Edit':
    case 'MultiEdit':
    case 'Write':
      return displayPath(input['file_path'], cwd);
    case 'NotebookEdit':
      return displayPath(input['notebook_path'], cwd);
    case 'Glob':
    case 'Grep':
      final parts = ['pattern: "${input['pattern']}"'];
      if (_s(input['path']).isNotEmpty) parts.add('path: "${displayPath(input['path'], cwd)}"');
      return parts.join(', ');
    case 'WebFetch':
      return _s(input['url']);
    case 'WebSearch':
      return '"${input['query']}"';
    case 'Task':
    case 'Agent':
      return _s(input['description']);
    default:
      if (input.isEmpty) return '';
      final first = input.values.first;
      return first is String ? (first.length > 80 ? first.substring(0, 80) : first) : '';
  }
}

String? mcpServer(String name) => _mcpServer.firstMatch(name)?.group(1);

int nonEmptyLines(String t) => t.split('\n').where((l) => l.trim().isNotEmpty).length;

/// The person said no, or stopped it.
bool isRejected(String text) => RegExp(r"^(The user doesn't want|Denied by user|\[Request interrupted)").hasMatch(text.trim());

/// The old/new pairs an Edit (or each edit of a MultiEdit, or a Write) changes.
List<({String o, String n})> editPairs(String name, Map<String, dynamic> input) {
  if (name == 'MultiEdit' && input['edits'] is List) {
    return [
      for (final e in input['edits'] as List)
        (o: e is Map ? _s(e['old_string']) : '', n: e is Map ? _s(e['new_string']) : ''),
    ];
  }
  return [(o: _s(input['old_string']), n: _s(input['new_string'] ?? input['content']))];
}

List<DiffLine> editDiff(String name, Map<String, dynamic> input) => [for (final p in editPairs(name, input)) ...diffLines(p.o, p.n)];

({int additions, int removals}) editSummary(String name, Map<String, dynamic> input) => diffStat(editDiff(name, input));

/// "Added 3 lines, removed 1 line", or "Updated" when nothing changed.
String editSummaryText(String name, Map<String, dynamic> input) {
  final s = editSummary(name, input);
  final parts = <String>[];
  if (s.additions > 0) parts.add('Added ${s.additions} ${s.additions == 1 ? 'line' : 'lines'}');
  if (s.removals > 0) parts.add('${parts.isNotEmpty ? 'removed' : 'Removed'} ${s.removals} ${s.removals == 1 ? 'line' : 'lines'}');
  return parts.isEmpty ? 'Updated' : parts.join(', ');
}

/// A tool failure as the CLI shows it.
String toolErrorText(String text) {
  final clean = text.replaceAll(RegExp(r'</?tool_use_error>'), '').trim();
  return RegExp(r'^(Error|Cancelled):').hasMatch(clean) ? clean : 'Error: $clean';
}

/// The one-line summary under a finished tool call (null when it is drawn differently: errors, edits, plain output).
({String text, bool expandable, String? expandLabel})? resultSummary(ToolItem tool, String cwd) {
  final r = tool.result;
  if (r == null) return null;
  final text = r.text;
  final input = tool.input;
  switch (tool.name) {
    case 'Read':
      final n = nonEmptyLines(text);
      return (text: 'Read $n ${n == 1 ? 'line' : 'lines'}', expandable: false, expandLabel: null);
    case 'Write':
      final n = _s(input['content']).split('\n').length;
      return (text: 'Wrote $n ${n == 1 ? 'line' : 'lines'} to ${displayPath(input['file_path'], cwd)}', expandable: false, expandLabel: null);
    case 'Glob':
      final n = nonEmptyLines(text.startsWith('No files') ? '' : text);
      return (text: 'Found $n ${n == 1 ? 'file' : 'files'}', expandable: n > 0, expandLabel: 'output');
    case 'Grep':
      final mode = input['output_mode'] ?? 'files_with_matches';
      final empty = RegExp(r'^No (files|matches)').hasMatch(text.trim());
      final n = empty ? 0 : nonEmptyLines(text);
      final unit = mode == 'content' ? (n == 1 ? 'line' : 'lines') : (n == 1 ? 'file' : 'files');
      return (text: 'Found $n $unit', expandable: n > 0, expandLabel: 'output');
    case 'Task':
    case 'Agent':
      return (text: 'Done (${plural(tool.sub.length, 'tool use')})', expandable: text.isNotEmpty, expandLabel: 'response');
  }
  return null;
}

/// "Searched for 2 patterns, read 3 files" (or "Searching for … reading …" while it runs).
String groupSummary(List<ToolItem> tools, bool active) {
  final reads = tools.where((t) => t.name == 'Read').map((t) => t.input['file_path']).toSet().length;
  final searches = tools.where((t) => t.name != 'Read').length;
  final parts = <String>[];
  if (searches > 0) parts.add('${active ? 'searching for' : 'searched for'} ${plural(searches, 'pattern')}');
  if (reads > 0) parts.add('${active ? 'reading' : 'read'} ${plural(reads, 'file')}');
  final joined = parts.join(', ');
  final cap = joined.isEmpty ? joined : joined[0].toUpperCase() + joined.substring(1);
  return cap + (active ? '…' : '');
}

const spinnerVerbs = [
  'Accomplishing', 'Architecting', 'Brewing', 'Calculating', 'Cerebrating', 'Cogitating', 'Computing', 'Concocting', //
  'Crafting', 'Deliberating', 'Elucidating', 'Finagling', 'Forging', 'Hatching', 'Ideating', 'Manifesting', 'Marinating',
  'Musing', 'Noodling', 'Percolating', 'Pondering', 'Processing', 'Puzzling', 'Ruminating', 'Simmering', 'Synthesizing',
  'Thinking', 'Tinkering', 'Working', 'Wrangling',
];

const turnVerbs = ['Baked', 'Brewed', 'Churned', 'Cogitated', 'Cooked', 'Crunched', 'Sautéed', 'Worked'];

/// The quiet line after a turn: "✻ Brewed for 12s", the interruption/error note, or null for a quick turn.
({String text, bool response})? turnEndText(Map<String, dynamic> d) {
  if (d['subtype'] == 'error_during_execution' || _truthy(d['is_error'])) {
    return (
      text: d['subtype'] == 'error_during_execution' ? 'Interrupted · What should Claude do instead?' : 'Turn ended with an error',
      response: true,
    );
  }
  final ms = d['duration_ms'];
  if (ms is! num || ms < 1000) return null;
  final verb = turnVerbs[ms.toInt().abs() % turnVerbs.length];
  return (text: '✻ $verb for ${fmtDuration(ms)}', response: false);
}

bool _truthy(Object? v) => v != null && v != false && v != '' && v != 0;

/// When the turn in flight started (ms since epoch), or null when the session is idle. A turn ends with its result, with an error
/// (the run failed before it could report one), or with the session itself ending (stopped, crashed, or the machine closed it).
int? busySince(List<MessageDto> rows, [int? now]) {
  for (var i = rows.length - 1; i >= 0; i--) {
    final m = rows[i].message;
    if (m is! Map) continue;
    final type = m['type'];
    if (type == 'result' || type == 'error' || type == sessionEndedType) return null;
    if (m['type'] == 'user' && _truthy(m['local'])) {
      return DateTime.tryParse(rows[i].createdAt)?.millisecondsSinceEpoch ?? now ?? DateTime.now().millisecondsSinceEpoch;
    }
  }
  return null;
}

/// Is the model in the middle of thinking (its latest block is a thinking block)?
bool lastIsThinking(List<MessageDto> rows) {
  for (var i = rows.length - 1; i >= 0; i--) {
    final m = rows[i].message;
    if (m is! Map || m['type'] != 'assistant') continue;
    final c = m['message'] is Map ? (m['message'] as Map)['content'] : null;
    return c is List && c.isNotEmpty && c.last is Map && (c.last as Map)['type'] == 'thinking';
  }
  return false;
}

/// The permission requests still waiting: not answered, and no turn ended after them (an aborted tool call never
/// reports back, so those would otherwise linger forever).
List<PermissionItem> livePermissions(List<DisplayItem> items, Set<String> resolved) {
  final out = <PermissionItem>[];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    if (it is! PermissionItem || resolved.contains(it.requestId)) continue;
    if (items.skip(i + 1).any((x) => x is TurnEndItem)) continue;
    out.add(it);
  }
  return out;
}

/// Identical retries of the same tool call: answering one answers them all.
List<String> permissionTwins(List<PermissionItem> unresolved, PermissionItem p) {
  final want = jsonEncode(p.input);
  return [
    for (final u in unresolved)
      if (u.toolName == p.toolName && jsonEncode(u.input) == want) u.requestId,
  ];
}

const permissionTitles = {
  'Bash': 'Bash command',
  'Edit': 'Edit file',
  'MultiEdit': 'Edit file',
  'Write': 'Create file',
  'NotebookEdit': 'Edit notebook',
  'WebFetch': 'Fetch',
  'Read': 'Read file',
  'Task': 'Launch agent',
  'Agent': 'Launch agent',
};

String permissionTitle(String name) {
  final server = mcpServer(name);
  return '${permissionTitles[name] ?? 'Tool use'}${server != null ? ' ($server MCP)' : ''}';
}

String permissionQuestion(String name, String target) {
  if (name == 'Edit' || name == 'MultiEdit') return 'Do you want to make this edit to $target?';
  if (name == 'Write') return 'Do you want to create $target?';
  if (name == 'WebFetch') return 'Do you want to allow Claude to fetch this content?';
  return 'Do you want to proceed?';
}

/// The words of a message with text files attached: the words, then each file under its name. Null when too long.
String? inlineText(String message, List<({String name, String text})> files, int maxChars) {
  final parts = [message.trim(), for (final f in files) '[${f.name}]\n${f.text}'].where((p) => p.isNotEmpty).toList();
  final out = parts.join('\n\n');
  return out.length <= maxChars ? out : null;
}

/// "Online", or when it was last seen: the same plain status a computer card gives.
String machineStatus(bool connected, String? lastSeenAt, {DateTime? now}) {
  if (connected) return 'Online';
  return lastSeenAt != null && lastSeenAt.isNotEmpty ? 'Offline · seen ${timeAgo(lastSeenAt, now: now)}' : 'Offline';
}

/// "now", "5m", "3h", "2d".
String relativeTime(String iso, {DateTime? now}) {
  final t = DateTime.tryParse(iso);
  if (t == null) return 'now';
  final mins = (now ?? DateTime.now()).difference(t).inMinutes;
  if (mins < 1) return 'now';
  if (mins < 60) return '${mins}m';
  final hours = mins ~/ 60;
  if (hours < 24) return '${hours}h';
  return '${hours ~/ 24}d';
}

/// [relativeTime] as a phrase: "just now", "5m ago". (Appending " ago" to [relativeTime] read "now ago" for the first minute.)
String timeAgo(String iso, {DateTime? now}) {
  final r = relativeTime(iso, now: now);
  return r == 'now' ? 'just now' : '$r ago';
}
