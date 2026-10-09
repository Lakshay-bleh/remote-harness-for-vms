import 'dart:convert';

import 'protocol.dart';

/// Turns a session's raw rows (SDK messages, the hub's own permission requests) into what the chat draws, the
/// way the Claude Code CLI does: tool calls paired with their results, reads/searches folded together, subagent
/// calls hung off their parent (groupMessages.ts).

typedef Block = Map<String, dynamic>;

class ToolResult {
  const ToolResult(this.text, this.isError);
  final String text;
  final bool isError;
}

sealed class DisplayItem {
  const DisplayItem(this.key);
  final String key;
}

class UserItem extends DisplayItem {
  const UserItem(super.key, this.createdAt, this.blocks);
  final String createdAt;
  final List<Block> blocks;
}

class TextItem extends DisplayItem {
  const TextItem(super.key, this.text);
  final String text;
}

class ThinkingItem extends DisplayItem {
  const ThinkingItem(super.key, this.text);
  final String text;
}

class ToolItem extends DisplayItem {
  const ToolItem(super.key, this.block, this.result, this.sub);

  /// The tool_use block.
  final Block block;
  final ToolResult? result;

  /// tool_use blocks a subagent ran on behalf of this call.
  final List<Block> sub;

  String get name => '${block['name'] ?? ''}';
  Map<String, dynamic> get input => asMap(block['input']);
}

class GroupItem extends DisplayItem {
  const GroupItem(super.key, this.tools);
  final List<ToolItem> tools;
}

class TurnEndItem extends DisplayItem {
  const TurnEndItem(super.key, this.data);
  final Map<String, dynamic> data;
}

class SystemItem extends DisplayItem {
  const SystemItem(super.key, this.text);
  final String text;
}

class PermissionItem extends DisplayItem {
  const PermissionItem(super.key, this.createdAt, this.data);
  final String createdAt;
  final Map<String, dynamic> data;

  String get requestId => '${data['requestId'] ?? ''}';
  String get toolName => '${data['toolName'] ?? ''}';
  Map<String, dynamic> get input => asMap(data['input']);
}

class ErrorItem extends DisplayItem {
  const ErrorItem(super.key, this.text);
  final String text;
}

Map<String, dynamic> asMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Tools the CLI folds into "Searched for 2 patterns, read 3 files".
const collapsibleTools = {'Read', 'Grep', 'Glob'};

/// TodoWrite is shown as a pinned task list, never as a tool line.
const hiddenTools = {'TodoWrite', 'AskUserQuestion', 'ExitPlanMode'};

List<Block> normalizeBlocks(Object? content) {
  if (content is List) return [for (final b in content) if (b is Map) Map<String, dynamic>.from(b)];
  if (content is String) return [{'type': 'text', 'text': content}];
  return const [];
}

String resultText(Object? content) {
  if (content is String) return content;
  if (content is List) {
    return content.map((c) {
      if (c is Map && c['type'] == 'text') return '${c['text'] ?? ''}';
      if (c is Map && c['type'] == 'image') return '[Image]';
      return jsonEncode(c);
    }).join('\n');
  }
  return '';
}

Map<String, dynamic>? _msg(MessageDto row) => row.message is Map ? Map<String, dynamic>.from(row.message as Map) : null;
Object? _content(Map<String, dynamic> m) => m['message'] is Map ? (m['message'] as Map)['content'] : null;
bool _truthy(Object? v) => v != null && v != false && v != '' && v != 0;

List<DisplayItem> groupMessages(List<MessageDto> rows) {
  // Pass 1: index every tool_result by the tool_use it answers.
  final results = <String, ToolResult>{};
  for (final row in rows) {
    final m = _msg(row);
    if (m == null || m['type'] != 'user' || _truthy(m['local'])) continue;
    for (final b in normalizeBlocks(_content(m))) {
      if (b['type'] == 'tool_result' && b['tool_use_id'] is String) {
        results[b['tool_use_id'] as String] = ToolResult(resultText(b['content']), _truthy(b['is_error']));
      }
    }
  }

  // Pass 2: subagent tool uses hang off their parent Agent/Task call.
  final subByParent = <String, List<Block>>{};
  for (final row in rows) {
    final m = _msg(row);
    if (m == null || m['type'] != 'assistant' || m['parent_tool_use_id'] is! String) continue;
    final list = subByParent.putIfAbsent(m['parent_tool_use_id'] as String, () => []);
    for (final b in normalizeBlocks(_content(m))) {
      if (b['type'] == 'tool_use') list.add(b);
    }
  }

  final items = <DisplayItem>[];
  var sawInit = false;
  var pending = <ToolItem>[]; // open read/search group
  var deferred = <DisplayItem>[]; // thinking absorbed into the open group

  void flush() {
    if (pending.length == 1) {
      items.add(pending.first);
    } else if (pending.length > 1) {
      items.add(GroupItem('g-${pending.first.key}', pending));
    }
    items.addAll(deferred);
    pending = [];
    deferred = [];
  }

  for (final row in rows) {
    final m = _msg(row);
    final key = 'm${row.id}';
    if (m == null) continue;
    final type = m['type'];

    if (type == 'user' && _truthy(m['local'])) {
      flush();
      items.add(UserItem(key, row.createdAt, normalizeBlocks(_content(m))));
      continue;
    }
    if (type == 'assistant') {
      if (_truthy(m['parent_tool_use_id'])) continue;
      final blocks = normalizeBlocks(_content(m));
      for (var i = 0; i < blocks.length; i++) {
        final b = blocks[i];
        final bk = '$key-$i';
        if (b['type'] == 'tool_use') {
          final name = '${b['name'] ?? ''}';
          if (hiddenTools.contains(name)) continue;
          final id = b['id'] is String ? b['id'] as String : null;
          final tool = ToolItem(id ?? bk, b, id == null ? null : results[id], id == null ? const [] : (subByParent[id] ?? const []));
          if (collapsibleTools.contains(name)) {
            pending.add(tool);
          } else {
            flush();
            items.add(tool);
          }
        } else if (b['type'] == 'thinking') {
          final text = '${b['thinking'] ?? ''}'.trim();
          if (text.isEmpty) continue;
          final item = ThinkingItem(bk, text);
          if (pending.isNotEmpty) {
            deferred.add(item);
          } else {
            items.add(item);
          }
        } else if (b['type'] == 'text') {
          final text = b['text'] is String ? b['text'] as String : '';
          if (text.trim().isEmpty) continue;
          flush();
          items.add(TextItem(bk, text));
        }
      }
      continue;
    }
    if (type == 'system') {
      if (m['subtype'] == 'init') {
        if (sawInit) continue;
        sawInit = true;
        flush();
        items.add(SystemItem(key, 'Session started · ${m['model']} · ${m['cwd']}'));
      } else if (m['subtype'] == 'compact_boundary') {
        flush();
        items.add(SystemItem(key, 'Conversation compacted'));
      }
      continue;
    }
    if (type == 'result') {
      flush();
      items.add(TurnEndItem(key, m));
      continue;
    }
    if (type == 'permission_request') {
      items.add(PermissionItem(key, row.createdAt, m));
      continue;
    }
    if (type == 'error') {
      flush();
      items.add(ErrorItem(key, '${m['message'] ?? ''}'));
    }
    // user tool_result rows, stream_event and other SDK chatter are consumed above or ignored.
  }
  flush();
  return items;
}

class Todo {
  const Todo({required this.content, required this.status, this.activeForm});
  final String content;

  /// pending | in_progress | completed
  final String status;
  final String? activeForm;
}

/// The latest TodoWrite list issued after the most recent prompt.
List<Todo>? latestTodos(List<MessageDto> rows) {
  List<Todo>? todos;
  for (final row in rows) {
    final m = _msg(row);
    if (m == null) continue;
    if (m['type'] == 'user' && _truthy(m['local'])) todos = null;
    if (m['type'] != 'assistant' || _truthy(m['parent_tool_use_id'])) continue;
    for (final b in normalizeBlocks(_content(m))) {
      final input = b['input'];
      if (b['type'] == 'tool_use' && b['name'] == 'TodoWrite' && input is Map && input['todos'] is List) {
        todos = [
          for (final t in input['todos'] as List)
            if (t is Map)
              Todo(
                content: '${t['content'] ?? ''}',
                status: '${t['status'] ?? 'pending'}',
                activeForm: t['activeForm'] is String ? t['activeForm'] as String : null,
              ),
        ];
      }
    }
  }
  return todos;
}
