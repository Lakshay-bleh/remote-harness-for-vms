import 'package:escanor/features/machines/group_messages.dart';
import 'package:escanor/features/machines/message_format.dart';
import 'package:escanor/features/machines/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

ToolItem tool(String name, Map<String, dynamic> input, [ToolResult? r, List<Block> sub = const []]) =>
    ToolItem('k', {'type': 'tool_use', 'id': 'k', 'name': name, 'input': input}, r, sub);

void main() {
  test('paths show relative to the chat’s folder', () {
    expect(displayPath('/w/app/a.ts', '/w/app'), 'a.ts');
    expect(displayPath('/other/a.ts', '/w/app'), '/other/a.ts');
    expect(displayPath(5, '/w'), '');
  });

  test('durations read like the CLI', () {
    expect(fmtDuration(5400), '5s');
    expect(fmtDuration(65000), '1m 5s');
    expect(fmtDuration(3723000), '1h 2m 3s');
  });

  test('tool names', () {
    expect(toolName('Edit', {'old_string': ''}), 'Create');
    expect(toolName('Edit', {'old_string': 'x'}), 'Update');
    expect(toolName('Grep', {}), 'Search');
    expect(toolName('Task', {'subagent_type': 'Explore'}), 'Explore');
    expect(toolName('Task', {}), 'Agent');
    expect(toolName('mcp__escanor__escanor_invoke', {}), 'escanor_invoke');
    expect(mcpServer('mcp__escanor__escanor_invoke'), 'escanor');
    expect(mcpServer('Bash'), isNull);
  });

  test('tool arguments', () {
    expect(toolArgs('Bash', {'command': 'ls\npwd\nwhoami'}, ''), 'ls\npwd…');
    expect(toolArgs('Bash', {'command': 'x' * 200}, '').length, 161);
    expect(toolArgs('Read', {'file_path': '/w/a'}, '/w'), 'a');
    expect(toolArgs('Grep', {'pattern': 'foo', 'path': '/w/src'}, '/w'), 'pattern: "foo", path: "src"');
    expect(toolArgs('WebSearch', {'query': 'q'}, ''), '"q"');
    expect(toolArgs('Other', {'a': 'b' * 100}, '').length, 80);
    expect(toolArgs('Other', {'a': 1}, ''), '');
  });

  test('rejections and errors', () {
    expect(isRejected("The user doesn't want to proceed"), isTrue);
    expect(isRejected('[Request interrupted by user]'), isTrue);
    expect(isRejected('fine'), isFalse);
    expect(toolErrorText('<tool_use_error>File missing</tool_use_error>'), 'Error: File missing');
    expect(toolErrorText('Cancelled: no'), 'Cancelled: no');
  });

  test('edit summaries', () {
    expect(editSummaryText('Edit', {'old_string': 'a', 'new_string': 'b\nc'}), 'Added 2 lines, removed 1 line');
    expect(editSummaryText('Edit', {'old_string': 'a', 'new_string': 'a'}), 'Updated');
    expect(editSummaryText('MultiEdit', {'edits': [{'old_string': 'a', 'new_string': ''}]}), 'Added 1 line, removed 1 line');
  });

  test('one-line results', () {
    expect(resultSummary(tool('Read', {}, const ToolResult('a\n\nb', false)), '')!.text, 'Read 2 lines');
    expect(resultSummary(tool('Glob', {}, const ToolResult('No files found', false)), '')!.text, 'Found 0 files');
    final grep = resultSummary(tool('Grep', {'output_mode': 'content'}, const ToolResult('x\ny', false)), '')!;
    expect((grep.text, grep.expandable), ('Found 2 lines', true));
    expect(resultSummary(tool('Task', {}, const ToolResult('done', false), [{}, {}]), '')!.text, 'Done (2 tool uses)');
    expect(resultSummary(tool('Bash', {}, const ToolResult('x', false)), ''), isNull);
    expect(resultSummary(tool('Read', {}), ''), isNull);
  });

  test('a folded group says what it did, or is doing', () {
    final tools = [tool('Read', {'file_path': '/a'}), tool('Read', {'file_path': '/a'}), tool('Grep', {'pattern': 'x'})];
    expect(groupSummary(tools, false), 'Searched for 1 pattern, read 1 file');
    expect(groupSummary(tools, true), 'Searching for 1 pattern, reading 1 file…');
  });

  test('the end of a turn', () {
    expect(turnEndText({'subtype': 'error_during_execution'})!.text, 'Interrupted · What should Claude do instead?');
    expect(turnEndText({'is_error': true})!.text, 'Turn ended with an error');
    expect(turnEndText({'duration_ms': 500}), isNull);
    expect(turnEndText({'duration_ms': 12000})!.text, startsWith('✻ '));
    expect(turnEndText({'duration_ms': 12000})!.text, endsWith(' for 12s'));
  });

  MessageDto r(Map<String, dynamic> m, [String at = '2026-10-07T10:00:00.000Z']) => MessageDto(id: 1, sessionId: 's', vmId: 'v', message: m, createdAt: at);

  test('a chat is busy from a prompt until its result', () {
    final prompt = r({'type': 'user', 'local': true});
    expect(busySince([prompt]), DateTime.parse('2026-10-07T10:00:00.000Z').millisecondsSinceEpoch);
    expect(busySince([prompt, r({'type': 'result'})]), isNull);
    expect(busySince([]), isNull);
    expect(busySince([r({'type': 'user', 'local': true}, 'garbage')], 42), 42);
    expect(busySince([prompt, r({'type': 'assistant', 'message': {'content': []}})]), isNotNull);
  });

  test('a stored error, or the session ending, is the end of the run; a new prompt after it is busy again', () {
    final prompt = r({'type': 'user', 'local': true});
    expect(busySince([prompt, r({'type': 'error', 'message': 'boom'})]), isNull);
    expect(busySince([prompt, r({'type': sessionEndedType})]), isNull);
    expect(busySince([prompt, r({'type': 'error', 'message': 'boom'}), r({'type': 'user', 'local': true}, '2026-10-07T10:05:00.000Z')]),
        DateTime.parse('2026-10-07T10:05:00.000Z').millisecondsSinceEpoch);
  });

  test('thinking is the model’s latest block', () {
    expect(lastIsThinking([r({'type': 'assistant', 'message': {'content': [{'type': 'thinking'}]}})]), isTrue);
    expect(lastIsThinking([r({'type': 'assistant', 'message': {'content': [{'type': 'text'}]}})]), isFalse);
  });

  test('only unanswered prompts with no turn ended after them are live; retries are twins', () {
    PermissionItem p(String id, [String cmd = 'ls']) => PermissionItem('k$id', '', {'requestId': id, 'toolName': 'Bash', 'input': {'command': cmd}});
    final items = <DisplayItem>[p('old'), const TurnEndItem('t', {}), p('a'), p('b'), p('c', 'rm')];
    final live = livePermissions(items, {'b'});
    expect(live.map((x) => x.requestId), ['a', 'c']);
    final all = livePermissions(items, {});
    expect(permissionTwins(all, all.first), ['a', 'b']);
  });

  test('the permission prompt’s words', () {
    expect(permissionTitle('Bash'), 'Bash command');
    expect(permissionTitle('mcp__x__y'), 'Tool use (x MCP)');
    expect(permissionQuestion('Edit', 'a.ts'), 'Do you want to make this edit to a.ts?');
    expect(permissionQuestion('Write', 'b'), 'Do you want to create b?');
    expect(permissionQuestion('WebFetch', ''), 'Do you want to allow Claude to fetch this content?');
    expect(permissionQuestion('Bash', ''), 'Do you want to proceed?');
  });

  test('text files go into the message under their names, within the limit', () {
    expect(inlineText(' hi ', [(name: 'a.txt', text: 'body')], 1000), 'hi\n\n[a.txt]\nbody');
    expect(inlineText('', [], 10), '');
    expect(inlineText('x' * 20, [], 10), isNull);
  });

  test('machine status and times', () {
    final now = DateTime.parse('2026-10-07T12:00:00Z');
    expect(machineStatus(true, null), 'Online');
    expect(machineStatus(false, null), 'Offline');
    expect(machineStatus(false, '2026-10-07T10:00:00Z', now: now), 'Offline · seen 2h ago');
    expect(relativeTime('2026-10-07T11:59:30Z', now: now), 'now');
    expect(relativeTime('2026-10-07T11:55:00Z', now: now), '5m');
    expect(relativeTime('2026-10-05T12:00:00Z', now: now), '2d');
    // As a phrase: never "now ago".
    expect(timeAgo('2026-10-07T11:59:30Z', now: now), 'just now');
    expect(timeAgo('2026-10-07T11:55:00Z', now: now), '5m ago');
  });
}
