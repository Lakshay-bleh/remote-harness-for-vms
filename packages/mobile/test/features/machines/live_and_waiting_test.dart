// The reply shown as it is written, and chats waiting for the person's OK (badges, banner, notification taps).
import 'package:escanor/features/machines/hub_state.dart';
import 'package:escanor/features/machines/hub_store.dart' show describeTool;
import 'package:escanor/features/machines/protocol.dart';
import 'package:escanor/features/push/push_logic.dart';
import 'package:flutter_test/flutter_test.dart';

MessageDto row(num id, Map<String, dynamic> m, {String session = 's1'}) => MessageDto(id: id, sessionId: session, vmId: 'v', message: m, createdAt: 't');
const s1 = SessionDto(id: 's1', vmId: 'v', cwd: '/w', title: 'One', createdAt: 'c', lastMessageAt: 'l', status: 'active', accountId: 'a');
num _ids = 1e15;
num next() => ++_ids;

void main() {
  test('the hub\'s live text is parsed, shown, and replaced by the finished message', () {
    final e = parseHubFrame('{"type":"sdk_partial","vmId":"v","sessionId":"s1","text":"Hel"}');
    expect(e, isA<SdkPartialEvent>());
    var s = reduceHub(const HubState(authed: true), actionForEvent(e!, next)!);
    expect(s.partialBySession['s1'], 'Hel');
    s = reduceHub(s, actionForEvent(const SdkPartialEvent(vmId: 'v', sessionId: 's1', text: 'Hello'), next)!);
    expect(s.partialBySession['s1'], 'Hello');
    // the person's own echo does not end it; Claude's finished message does
    s = reduceHub(s, AppendMessage('s1', row(next(), {'type': 'user', 'local': true})));
    expect(s.partialBySession['s1'], 'Hello');
    s = reduceHub(s, AppendMessage('s1', row(next(), {'type': 'assistant', 'message': {'content': []}})));
    expect(s.partialBySession.containsKey('s1'), isFalse);
  });

  test('a stopped run drops its live text', () {
    var s = reduceHub(const HubState(authed: true), const SetPartial('s1', 'abc'));
    s = reduceHub(s, const SessionWentIdle('v', 's1'));
    expect(s.partialBySession, isEmpty);
  });

  test('a permission prompt marks the chat waiting until it is answered', () {
    var s = const HubState(authed: true, sessionsByVm: {'v': [s1]});
    s = reduceHub(
        s,
        actionForEvent(
            const PermissionRequestEvent(vmId: 'v', sessionId: 's1', requestId: 'r1', toolName: 'Bash', input: {'command': 'ls'}), next)!);
    expect(s.waiting, {'s1': 'v'});
    s = reduceHub(s, actionForEvent(const PermissionResolvedEvent(vmId: 'v', sessionId: 's1', requestId: 'r1'), next)!);
    expect(s.waiting, isEmpty);
  });

  test('an answer that did not arrive puts the chat back to waiting', () {
    var s = reduceHub(const HubState(authed: true), AppendMessage('s1', row(next(), {'type': 'permission_request', 'requestId': 'r1'})));
    s = reduceHub(s, const PermissionResolved('r1', sessionId: 's1'));
    expect(s.waiting, isEmpty);
    s = reduceHub(s, const PermissionReopened(['r1']));
    expect(s.waiting, {'s1': 'v'});
  });

  test('the hub\'s list and a fetched chat say which chats wait', () {
    var s = reduceHub(const HubState(authed: true), SetSessions('v', [s1.copyWith(status: 'waiting')]));
    expect(s.waiting, {'s1': 'v'});
    expect(SessionDto.tryParse({'id': 's1', 'vmId': 'v', 'cwd': '/', 'title': 't', 'createdAt': 'c', 'status': 'waiting'})!.status, 'waiting');
    // the chat itself shows the prompt was answered and the turn ended
    s = reduceHub(s, SetMessages('s1', [row(1, {'type': 'permission_request', 'requestId': 'r1'}), row(2, {'type': 'result'})]));
    expect(s.waiting, isEmpty);
    s = reduceHub(s, SetMessages('s1', [row(1, {'type': 'permission_request', 'requestId': 'r2'})]));
    expect(s.waiting, {'s1': 'v'});
    s = reduceHub(s, const SessionWentIdle('v', 's1'));
    expect(s.waiting, isEmpty);
  });

  test('describes what Claude wants to do like the notification does', () {
    expect(describeTool('Bash', {'command': 'npm test\nmore'}), 'Run: npm test');
    expect(describeTool('Edit', {'file_path': '/a/b/app.ts'}), 'Edit: app.ts');
    expect(describeTool('Task', {}), 'Use Task');
  });

  test('a machine-chat notification opens Machines and names its chat', () {
    final data = {'kind': 'machine_chats', 'event': 'approval', 'vm_id': 'v', 'session_id': 's1', 'request_id': 'r'};
    expect(routeFor(data), PushDest.machines);
    expect(machineChatFor(data), (vmId: 'v', sessionId: 's1'));
    expect(machineChatFor({'kind': 'checks', 'vm_id': 'v', 'session_id': 's1'}), isNull);
    expect(machineChatFor({'kind': 'machine_chats', 'vm_id': '', 'session_id': 's1'}), isNull);
  });
}
