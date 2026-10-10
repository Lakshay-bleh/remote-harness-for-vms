import 'dart:convert';

import 'package:escanor/features/machines/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('frames from the hub', () {
    test('every message type the hub pushes is understood', () {
      expect(parseHubFrame(jsonEncode({'type': 'vm_status', 'vmId': 'v', 'name': 'box', 'connected': true, 'accounts': [{'id': 'a', 'label': 'Work'}]})),
          isA<VmStatusEvent>().having((e) => e.accounts.single.label, 'account', 'Work'));
      expect(parseHubFrame(jsonEncode({'type': 'sdk_message', 'vmId': 'v', 'sessionId': 's', 'message': {'type': 'assistant'}, 'createdAt': 't'})),
          isA<SdkMessageEvent>());
      expect(parseHubFrame(jsonEncode({'type': 'session_created', 'vmId': 'v', 'tempId': 't', 'sessionId': 's', 'cwd': '/w', 'title': 'T', 'accountId': 'a'})),
          isA<SessionCreatedEvent>());
      expect(parseHubFrame(jsonEncode({'type': 'session_ended', 'vmId': 'v', 'sessionId': 's'})), isA<SessionEndedEvent>());
      expect(
          parseHubFrame(jsonEncode({'type': 'permission_request', 'vmId': 'v', 'sessionId': 's', 'requestId': 'r', 'toolName': 'Bash', 'input': {'command': 'ls'}})),
          isA<PermissionRequestEvent>().having((e) => e.input['command'], 'command', 'ls'));
      expect(parseHubFrame(jsonEncode({'type': 'permission_resolved', 'vmId': 'v', 'sessionId': 's', 'requestId': 'r'})), isA<PermissionResolvedEvent>());
    });

    test('anything else is dropped, not guessed at', () {
      for (final bad in [
        'pong',
        '{',
        '[]',
        jsonEncode({'type': 'nope'}),
        jsonEncode({'type': 'vm_status', 'vmId': 'v'}),
        jsonEncode({'type': 'sdk_message', 'vmId': 'v', 'sessionId': ''}),
        jsonEncode({'type': 'sdk_message', 'vmId': 'v', 'sessionId': 'x' * 257}),
        jsonEncode({'type': 'session_created', 'vmId': 'v', 'tempId': 't', 'sessionId': 's', 'cwd': 1, 'title': 'T', 'accountId': 'a'}),
        jsonEncode({'type': 'permission_request', 'vmId': 'v', 'sessionId': 's', 'requestId': 'r', 'toolName': 'Bash', 'input': 'ls'}),
        jsonEncode({'type': 'permission_resolved', 'vmId': 'v', 'sessionId': 's'}),
      ]) {
        expect(parseHubFrame(bad), isNull, reason: bad);
      }
      expect(parseHubFrame(42), isNull);
    });
  });

  group('rows from the hub', () {
    test('malformed rows are skipped', () {
      expect(VmDto.listFrom([{'id': 'v', 'name': 'box', 'connected': true, 'lastSeenAt': null, 'accounts': []}, {'name': 'no id'}, 'x']).length, 1);
      expect(VmDto.listFrom('nope'), isEmpty);
      final s = SessionDto.listFrom([{'id': 's', 'vmId': 'v', 'cwd': '/w', 'title': 'T', 'createdAt': 'c', 'lastMessageAt': 'l', 'status': 'weird', 'accountId': 'a'}]).single;
      expect(s.status, 'idle');
      expect(MessageDto.listFrom([{'id': 1, 'sessionId': 's', 'vmId': 'v', 'message': {}, 'createdAt': 'c'}, {'id': 'x'}]).length, 1);
    });
  });

  group('parseUserInput', () {
    const img = ImageAttachment(mediaType: 'image/png', dataBase64: 'AAAA');
    test('accepts text only, images only, and both', () {
      final t = parseUserInput({'text': 'hi'});
      expect((t.ok, t.value!.text, t.value!.images), (true, 'hi', null));
      final i = parseUserInput({'images': [img]});
      expect((i.ok, i.value!.text, i.value!.images!.length), (true, '', 1));
      expect(parseUserInput({'images': [{'mediaType': 'image/jpeg', 'dataBase64': 'AA'}]}).ok, isTrue);
    });
    test('rejects empty input', () {
      expect(parseUserInput({}).ok, isFalse);
      expect(parseUserInput({'text': '', 'images': []}).ok, isFalse);
    });
    test('rejects a string for images and object text', () {
      expect(parseUserInput({'images': 'abc'}).ok, isFalse);
      expect(parseUserInput({'text': {'a': 1}}).ok, isFalse);
    });
    test('rejects malformed images, non-image media types, too many images, and too much text', () {
      expect(parseUserInput({'images': [const ImageAttachment(mediaType: 'text/html', dataBase64: 'AAAA')]}).ok, isFalse);
      expect(parseUserInput({'images': [{'mediaType': 'image/png'}]}).ok, isFalse);
      expect(parseUserInput({'images': [null]}).ok, isFalse);
      expect(parseUserInput({'images': List.filled(11, img)}).ok, isFalse);
      expect(parseUserInput({'text': 'x' * (maxTextChars + 1)}).error, 'text too long');
    });
  });

  test('parseNewSession validates optional cwd/accountId types', () {
    expect(parseNewSession({'text': 'hi', 'cwd': 5}).ok, isFalse);
    expect(parseNewSession({'text': 'hi', 'accountId': {}}).ok, isFalse);
    expect(parseNewSession({'text': 'hi', 'cwd': 'x' * 1025}).ok, isFalse);
    final r = parseNewSession({'text': 'hi', 'cwd': 'app', 'accountId': 'a'});
    expect((r.value!.text, r.value!.images, r.value!.cwd, r.value!.accountId), ('hi', null, 'app', 'a'));
  });

  test('permission mode / effort / behavior', () {
    expect(isPermissionMode('default'), isTrue);
    expect(isPermissionMode('bypassPermissions'), isTrue);
    expect(isPermissionMode('rm -rf'), isFalse);
    expect(isPermissionMode(null), isFalse);
    expect(isEffortLevel('max'), isTrue);
    expect(isEffortLevel('extreme'), isFalse);
    expect(isPermissionBehavior('allow'), isTrue);
    expect(isPermissionBehavior('yes'), isFalse);
    expect(isIdString(''), isFalse);
    expect(isIdString('a'), isTrue);
  });

  test('an agent receives Escanor’s tools from 0.3.0', () {
    expect(agentSupportsMcp('0.3.0'), isTrue);
    expect(agentSupportsMcp('0.10.1'), isTrue);
    expect(agentSupportsMcp('0.2.9'), isFalse);
    expect(agentSupportsMcp(null), isFalse);
    expect(agentSupportsMcp('1'), isTrue);
  });

  test('where Escanor stands on each machine', () {
    VmMcpStatus vm({bool connected = true, bool mcp = true, String? status, String? error}) => VmMcpStatus(
        vmId: 'v', name: 'box', connected: connected, mcpSupported: mcp, servers: [if (status != null) McpServerStatus(name: 'escanor', status: status, error: error)]);
    expect(escanorInstallLabel(vm(connected: false)), 'offline — installs when it reconnects');
    expect(escanorInstallLabel(vm(mcp: false)), 'agent needs updating to receive it');
    expect(escanorInstallLabel(vm(status: 'connected')), 'connected');
    expect(escanorInstallLabel(vm(status: 'failed', error: 'boom')), 'failed: boom');
    expect(escanorInstallLabel(vm(status: 'needs-auth')), 'needs-auth');
    expect(escanorInstallLabel(vm()), 'installing…');
    expect(escanorInstalled(McpOverview.fromJson({'servers': [{'name': 'escanor'}], 'vms': []})), isTrue);
    expect(escanorInstalled(McpOverview.fromJson({'servers': [], 'vms': []})), isFalse);
    expect(escanorInstalled(null), isFalse);
  });
}
