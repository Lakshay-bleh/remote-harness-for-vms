import 'package:escanor/features/machines/group_messages.dart';
import 'package:escanor/features/machines/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

var _id = 0;
MessageDto row(Map<String, dynamic> message, {String at = '2026-10-07T10:00:00.000Z'}) =>
    MessageDto(id: ++_id, sessionId: 's', vmId: 'v', message: message, createdAt: at);

MessageDto prompt(String text) => row({'type': 'user', 'local': true, 'message': {'role': 'user', 'content': [{'type': 'text', 'text': text}]}});
MessageDto assistant(List<Map<String, dynamic>> content, {String? parent}) =>
    row({'type': 'assistant', 'parent_tool_use_id': ?parent, 'message': {'content': content}});
Map<String, dynamic> use(String id, String name, [Map<String, dynamic> input = const {}]) => {'type': 'tool_use', 'id': id, 'name': name, 'input': input};
MessageDto result(String id, Object content, {bool error = false}) => row({
      'type': 'user',
      'message': {
        'content': [{'type': 'tool_result', 'tool_use_id': id, 'content': content, 'is_error': error}],
      },
    });

void main() {
  test('a prompt, an answer and a tool call paired with its result', () {
    final items = groupMessages([
      prompt('fix it'),
      assistant([{'type': 'text', 'text': 'On it.'}, use('t1', 'Bash', {'command': 'ls'})]),
      result('t1', 'a\nb'),
      row({'type': 'result', 'duration_ms': 4200}),
    ]);
    expect(items.map((i) => i.runtimeType), [UserItem, TextItem, ToolItem, TurnEndItem]);
    final tool = items[2] as ToolItem;
    expect(tool.result!.text, 'a\nb');
    expect(tool.result!.isError, isFalse);
  });

  test('reads and searches in a row fold into one group; thinking inside waits until after it', () {
    final items = groupMessages([
      assistant([use('r1', 'Read', {'file_path': '/a'}), {'type': 'thinking', 'thinking': 'hmm'}, use('g1', 'Grep', {'pattern': 'x'})]),
      assistant([{'type': 'text', 'text': 'Found it'}]),
    ]);
    expect(items.map((i) => i.runtimeType), [GroupItem, ThinkingItem, TextItem]);
    expect((items[0] as GroupItem).tools.length, 2);
  });

  test('a single read stays a plain tool line', () {
    final items = groupMessages([assistant([use('r1', 'Read', {'file_path': '/a'})])]);
    expect(items.single, isA<ToolItem>());
  });

  test('TodoWrite and friends are never tool lines; empty text and thinking are dropped', () {
    final items = groupMessages([
      assistant([use('t', 'TodoWrite', {'todos': []}), use('q', 'AskUserQuestion'), use('p', 'ExitPlanMode'), {'type': 'text', 'text': '  '}, {'type': 'thinking', 'thinking': ''}]),
    ]);
    expect(items, isEmpty);
  });

  test('a subagent’s calls hang off the call that started it', () {
    final items = groupMessages([
      assistant([use('a1', 'Task', {'description': 'look around'})]),
      assistant([use('s1', 'Bash', {'command': 'pwd'})], parent: 'a1'),
      assistant([use('s2', 'Read', {'file_path': '/x'})], parent: 'a1'),
    ]);
    final task = items.single as ToolItem;
    expect(task.sub.map((b) => b['id']), ['s1', 's2']);
  });

  test('the session start is shown once; a compaction is noted', () {
    final items = groupMessages([
      row({'type': 'system', 'subtype': 'init', 'model': 'opus', 'cwd': '/w'}),
      row({'type': 'system', 'subtype': 'init', 'model': 'opus', 'cwd': '/w'}),
      row({'type': 'system', 'subtype': 'compact_boundary'}),
      row({'type': 'system', 'subtype': 'other'}),
    ]);
    expect(items.map((i) => (i as SystemItem).text), ['Session started · opus · /w', 'Conversation compacted']);
  });

  test('permission requests and errors come through; unknown chatter does not', () {
    final items = groupMessages([
      row({'type': 'permission_request', 'requestId': 'r1', 'toolName': 'Bash', 'input': {'command': 'rm x'}}),
      row({'type': 'error', 'message': 'VM went away'}),
      row({'type': 'stream_event'}),
      const MessageDto(id: 99, sessionId: 's', vmId: 'v', message: 'not a map', createdAt: ''),
    ]);
    expect(items.map((i) => i.runtimeType), [PermissionItem, ErrorItem]);
    expect((items[0] as PermissionItem).requestId, 'r1');
    expect((items[1] as ErrorItem).text, 'VM went away');
  });

  test('a string content is one text block; tool results are flattened to text', () {
    expect(normalizeBlocks('hi'), [{'type': 'text', 'text': 'hi'}]);
    expect(resultText([{'type': 'text', 'text': 'a'}, {'type': 'image'}, {'x': 1}]), 'a\n[Image]\n{"x":1}');
    expect(resultText(null), '');
  });

  test('the task list is the latest one since the last prompt', () {
    final todos = [{'content': 'one', 'status': 'completed'}, {'content': 'two', 'status': 'in_progress', 'activeForm': 'Doing two'}];
    final rows = [prompt('go'), assistant([use('t', 'TodoWrite', {'todos': todos})])];
    final list = latestTodos(rows)!;
    expect(list.map((t) => t.content), ['one', 'two']);
    expect(list[1].activeForm, 'Doing two');
    expect(latestTodos([...rows, prompt('next')]), isNull);
    expect(latestTodos([assistant([use('t', 'TodoWrite', {'todos': todos})], parent: 'x')]), isNull, reason: 'a subagent’s list is not the chat’s');
  });
}
