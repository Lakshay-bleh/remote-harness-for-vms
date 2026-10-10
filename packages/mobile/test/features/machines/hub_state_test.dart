import 'package:escanor/features/machines/hub_state.dart';
import 'package:escanor/features/machines/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

MessageDto msg(num id, String session) => MessageDto(id: id, sessionId: session, vmId: 'v', message: {'type': 'user', 'local': true}, createdAt: 't');
const s1 = SessionDto(id: 's1', vmId: 'v', cwd: '/w', title: 'One', createdAt: 'c', lastMessageAt: 'l', status: 'active', accountId: 'a');

void main() {
  test('signing out leaves nothing of the last person behind', () {
    var s = const HubState(authed: true);
    s = reduceHub(s, const SetVms([VmDto(id: 'v', name: 'box', connected: true)]));
    s = reduceHub(s, AppendMessage('s1', msg(1, 's1')));
    s = reduceHub(s, const PermissionResolved('r'));
    s = reduceHub(s, const Select(vmId: 'v', sessionId: 's1', accountId: 'a'));
    s = reduceHub(s, const SetAuthed(false));
    expect(s.authed, isFalse);
    expect(s.vms, isEmpty);
    expect(s.messagesBySession, isEmpty);
    expect(s.resolvedPermissionIds, isEmpty);
    expect(s.selectedVmId, isNull);
  });

  test('signing in keeps what is there', () {
    final s = reduceHub(const HubState(authed: false, vms: [VmDto(id: 'v', name: 'b', connected: false)]), const SetAuthed(true));
    expect((s.authed, s.vms.length), (true, 1));
  });

  test('a machine’s status updates it, or adds it when new', () {
    var s = const HubState(authed: true, vms: [VmDto(id: 'v', name: 'box', connected: false, lastSeenAt: 'x')]);
    s = reduceHub(s, const VmStatus(vmId: 'v', name: 'box', connected: true, accounts: [ClaudeAccount(id: 'a', label: 'A')]));
    expect((s.vms.single.connected, s.vms.single.lastSeenAt, s.vms.single.accounts.length), (true, 'x', 1));
    s = reduceHub(s, const VmStatus(vmId: 'w', name: 'new', connected: true, accounts: []));
    expect(s.vms.map((v) => v.name), ['box', 'new']);
  });

  test('a new chat named by its machine takes its messages and stays selected', () {
    var s = const HubState(authed: true, sessionsByVm: {'v': [s1]});
    s = reduceHub(s, const Select(vmId: 'v', sessionId: 'temp', accountId: 'a'));
    s = reduceHub(s, AppendMessage('temp', msg(1, 'temp')));
    s = reduceHub(s, AppendMessage('real', msg(2, 'real')));
    s = reduceHub(
        s, SessionCreated(vmId: 'v', tempId: 'temp', sessionId: 'real', cwd: '/w', title: 'New', accountId: 'a', now: DateTime.utc(2026, 10, 7)));
    expect(s.selectedSessionId, 'real');
    expect(s.messagesBySession.containsKey('temp'), isFalse);
    expect(s.messagesBySession['real']!.map((m) => m.id), [1, 2]);
    expect(s.sessionsByVm['v']!.map((x) => x.id), ['real', 's1']);
    expect(s.sessionsByVm['v']!.first.status, 'active');
    expect(s.sessionsByVm['v']!.first.createdAt, '2026-10-07T00:00:00.000Z');
  });

  test('another chat being named does not move the selection', () {
    var s = const HubState(authed: true, selectedSessionId: 's1');
    s = reduceHub(s, const SessionCreated(vmId: 'v', tempId: 't', sessionId: 'x', cwd: '', title: '', accountId: 'a'));
    expect(s.selectedSessionId, 's1');
  });

  test('an ended session goes idle; an unknown machine is ignored', () {
    var s = const HubState(authed: true, sessionsByVm: {'v': [s1]});
    s = reduceHub(s, const SessionWentIdle('v', 's1'));
    expect(s.sessionsByVm['v']!.single.status, 'idle');
    expect(identical(reduceHub(s, const SessionWentIdle('nope', 's1')), s), isTrue);
  });

  test('an ended session closes its running turn with a marker row, so the chat stops spinning', () {
    final at = DateTime.utc(2026, 10, 7, 10);
    var s = HubState(authed: true, sessionsByVm: const {'v': [s1]}, messagesBySession: {'s1': [msg(1, 's1')]});
    s = reduceHub(s, SessionWentIdle('v', 's1', now: at));
    final rows = s.messagesBySession['s1']!;
    expect(rows.length, 2);
    expect((rows.last.message as Map)['type'], sessionEndedType);
    expect(rows.last.id, -at.millisecondsSinceEpoch);
    expect(s.sessionsByVm['v']!.single.status, 'idle');
    // a machine this phone has no list for still gets the marker on a chat it has open
    s = reduceHub(HubState(authed: true, messagesBySession: {'s2': [msg(1, 's2')]}), SessionWentIdle('gone', 's2', now: at));
    expect(s.messagesBySession['s2']!.length, 2);
  });

  test('answered prompts are remembered, and can be reopened', () {
    var s = reduceHub(const HubState(authed: true), const PermissionResolved('a'));
    s = reduceHub(s, const PermissionResolved('b'));
    s = reduceHub(s, const PermissionReopened(['a']));
    expect(s.resolvedPermissionIds, {'b'});
  });

  test('hub events become changes', () {
    var n = 0;
    num next() => ++n;
    expect(actionForEvent(const SdkMessageEvent(vmId: 'v', sessionId: 's', message: {}, createdAt: 't'), next), isA<AppendMessage>());
    final p = actionForEvent(const PermissionRequestEvent(vmId: 'v', sessionId: 's', requestId: 'r', toolName: 'Bash', input: {'command': 'ls'}), next)
        as AppendMessage;
    expect((p.message.message as Map)['type'], 'permission_request');
    expect((p.message.message as Map).containsKey('blockedPath'), isFalse);
    expect(p.message.id, 2);
    expect(actionForEvent(const PermissionResolvedEvent(vmId: 'v', sessionId: 's', requestId: 'r'), next), isA<PermissionResolved>());
    expect(actionForEvent(const SessionEndedEvent(vmId: 'v', sessionId: 's'), next), isA<SessionWentIdle>());
  });
}
