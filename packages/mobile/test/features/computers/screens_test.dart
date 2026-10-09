// The Computers screens: the list, pairing, a computer's sections over the (in-memory) cloud route, and the error card.
import 'dart:async';

import 'package:escanor/core/storage.dart';
import 'package:escanor/core/theme.dart';
import 'package:escanor/features/composer/attachments.dart';
import 'package:escanor/features/computers/chat_store.dart';
import 'package:escanor/features/computers/computer_chat.dart';
import 'package:escanor/features/computers/computer_detail.dart';
import 'package:escanor/features/computers/computer_prefs.dart';
import 'package:escanor/features/computers/computers_screen.dart';
import 'package:escanor/features/computers/error_card.dart';
import 'package:escanor/features/computers/pair_sheet.dart';
import 'package:escanor/features/computers/protocol/client.dart';
import 'package:escanor/features/computers/protocol/failure.dart';
import 'package:escanor/features/computers/protocol/secure.dart';
import 'package:escanor/features/computers/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_desktop.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildTheme(EscanorColors.of(ThemeName.dark, AccentName.gold), reduceMotion: true),
  home: Scaffold(body: child),
);

Future<void> settle(WidgetTester t, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

class _Cloud implements CloudDirectory {
  _Cloud(this.desktop, this.agentId);
  final FakeDesktop desktop;
  final String agentId;
  @override
  Future<List<DesktopEntry>> computers() async => [DesktopEntry(id: agentId, name: 'Work Laptop', online: true)];
  @override
  Future<({String deviceId, String sealedKey})> pair(
    String id, {
    required String sel,
    required String nonce,
    required String proof,
    required String name,
  }) async {
    try {
      final r = desktop.cloudPair({'sel': sel, 'nonce': nonce, 'proof': proof, 'name': name});
      return (deviceId: r['deviceId'] as String, sealedKey: r['sealedKey'] as String);
    } on Exception catch (e) {
      throw ComputerError(failureText(e));
    }
  }
}

void main() {
  setUp(() async {
    await Storage.initForTest();
    resetComputerPrefsCache();
  });

  void phoneSize(WidgetTester t) {
    t.view.physicalSize = const Size(1200, 2700); // 400 x 900, a tall phone
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  testWidgets('with nothing paired, the tab invites you to add your computer', (t) async {
    await t.pumpWidget(app(const ComputersScreen()));
    expect(find.text('Computers'), findsOneWidget);
    expect(find.text('Waiting for your computer'), findsOneWidget);
    expect(find.text('Add your computer'), findsOneWidget);
  });

  testWidgets('paired computers are listed with how they were paired, and follow renames', (t) async {
    saveComputer(PairedComputer(id: 'd1', name: 'Work Laptop', key: B64u.encode(List.filled(32, 1)), agentId: 'agent-1', pairedAt: '2026-10-01T10:00:00Z'));
    await t.pumpWidget(app(const ComputersScreen()));
    expect(find.text('Work Laptop'), findsOneWidget);
    expect(find.textContaining('works away from home'), findsOneWidget);
    expect(find.text('Your computer is all set'), findsOneWidget);
    setComputerPrefs('d1', alias: 'Desk');
    await t.pump();
    expect(find.text('Desk'), findsOneWidget);
    removeComputer('d1');
    await t.pump();
    expect(find.text('Waiting for your computer'), findsOneWidget);
  });

  testWidgets('pairing: a bad code is explained, a good one pairs through the cloud', (t) async {
    final desktop = FakeDesktop.cloudOnly();
    final code = desktop.createOffer();
    PairedComputer? paired;
    phoneSize(t);
    await t.pumpWidget(
      app(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showPairSheet(context, onPaired: (c) => paired = c, cloud: _Cloud(desktop, 'agent-1')),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await settle(t, 10);
    expect(find.text('Add your computer'), findsOneWidget);
    expect(find.text('Scan the QR code instead'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'hello');
    await t.pump();
    await t.tap(find.text('Pair'));
    await t.pump();
    expect(find.textContaining('That is not a valid pairing code'), findsOneWidget);

    await t.enterText(find.byType(TextField), code.toLowerCase());
    await t.tap(find.text('Pair'));
    await settle(t);
    expect(paired, isNotNull);
    expect(paired!.agentId, 'agent-1');
    expect(paired!.key, B64u.encode(desktop.devices[paired!.id]!.key));
    expect(find.text('Add your computer'), findsNothing, reason: 'the sheet closed');
  });

  testWidgets('pairing on the same Wi-Fi asks for the address', (t) async {
    await t.pumpWidget(
      app(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showPairSheet(context, onPaired: (_) {}),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await settle(t, 10);
    await t.tap(find.text('On the same Wi-Fi? Pair with just its address'));
    await t.pump();
    expect(find.text('Computer address'), findsOneWidget);
    expect(find.text('Ask to pair'), findsOneWidget);
    await t.tap(find.text('Back to pairing from anywhere'));
    await t.pump();
    expect(find.text('Pairing code'), findsOneWidget);
  });

  testWidgets('a computer: connects through the cloud, chats, shows permissions, activity and approvals', (t) async {
    final desktop = FakeDesktop.cloudOnly();
    final device = desktop.addDevice('My Phone');
    final computer = PairedComputer(id: device.id, name: 'Work Laptop', key: B64u.encode(device.key), agentId: 'agent-1', pairedAt: '2026-10-01T10:00:00Z');
    saveComputer(computer);
    Future<String> relay({required String agentId, required String deviceId, required String sealed}) => desktop.relay(deviceId, sealed);
    phoneSize(t);
    await t.pumpWidget(app(ComputerDetail(computer: computer, relay: relay)));
    await settle(t);
    expect(find.text('Connected through the cloud'), findsOneWidget);
    expect(find.text('Say something, I’m listening'), findsOneWidget);
    // a pending approval was fetched: a badge and a banner
    expect(find.text('Delete: waiting for your OK.'), findsOneWidget);

    await t.tap(find.text('Volume up'));
    await settle(t);
    expect(find.text('heard: Volume up'), findsOneWidget);

    await t.ensureVisible(find.text('Permissions'));
    await t.tap(find.text('Permissions'));
    await settle(t);
    expect(find.text('Open apps and websites'), findsOneWidget);
    await t.tap(find.text('Ask to allow'));
    await settle(t);
    expect(find.textContaining('A question just appeared in Escanor Desktop'), findsOneWidget);

    await t.ensureVisible(find.text('Activity'));
    await t.tap(find.text('Activity'));
    await settle(t);
    expect(find.text('Opened a website'), findsOneWidget);

    await t.ensureVisible(find.text('Approvals'));
    await t.tap(find.text('Approvals'));
    await settle(t);
    expect(find.text('NEEDS YOUR CARE'), findsOneWidget);
    await t.tap(find.text('Continue'));
    await settle(t, 5);
    expect(desktop.approvalsAnswered, [('p1', true)]);

    await t.ensureVisible(find.text('Chat'));
    await t.tap(find.text('Chat'));
    await settle(t, 5);
    expect(find.text('heard: Volume up'), findsOneWidget, reason: 'the chat stayed as it was');

    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  });

  testWidgets('a computer that cannot be reached says where to fix it, and offers to try again', (t) async {
    final computer = PairedComputer(id: 'gone', name: 'Old PC', key: B64u.encode(List.filled(32, 3)), agentId: 'agent-1', pairedAt: '2026-10-01T10:00:00Z');
    Future<String> relay({required String agentId, required String deviceId, required String sealed}) async =>
        throw const ComputerError('The computer did not answer. Is it on and online?');
    await t.pumpWidget(app(ComputerDetail(computer: computer, relay: relay)));
    await settle(t);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Your computer is not answering'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  });

  testWidgets('the error card offers to ask the computer when something is switched off for phones', (t) async {
    final asked = <String>[];
    await t.pumpWidget(
      app(
        ErrorCard(
          error: '“Open apps and websites” is turned off for phones.',
          onAsk: (label) async {
            asked.add(label);
            return 'Asked.';
          },
        ),
      ),
    );
    expect(find.text('“Open apps and websites” is switched off for phones'), findsOneWidget);
    expect(find.text('FIX IT ON YOUR COMPUTER'), findsOneWidget);
    await t.tap(find.text('Ask my computer to allow it'));
    await t.pump();
    await t.pump();
    expect(asked, ['Open apps and websites']);
    expect(find.text('Asked.'), findsOneWidget);
  });

  testWidgets('computer settings: the route choice applies to the live connection', (t) async {
    final desktop = FakeDesktop.cloudOnly();
    final device = desktop.addDevice('My Phone');
    final computer = PairedComputer(id: device.id, name: 'Work Laptop', key: B64u.encode(device.key), agentId: 'agent-1', pairedAt: '2026-10-01T10:00:00Z');
    saveComputer(computer);
    Future<String> relay({required String agentId, required String deviceId, required String sealed}) => desktop.relay(deviceId, sealed);
    phoneSize(t);
    await t.pumpWidget(
      app(
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => ComputerDetail(computer: computer, relay: relay),
          ),
        ),
      ),
    );
    await settle(t);
    await t.tap(find.byTooltip('Options for Work Laptop'));
    await settle(t, 5);
    await t.tap(find.text('Computer settings'));
    await settle(t);
    expect(find.text('Settings for this computer'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Connected · cloud'), findsOneWidget);
    expect(find.text('No: Wi-Fi only'), findsNothing);
    await t.tap(find.text('How to reach it'));
    await settle(t, 5);
    await t.tap(find.text('Wi-Fi only'));
    await settle(t);
    expect(getComputerPrefs(device.id).route, RoutePref.lan);
    expect(find.text('Offline'), findsOneWidget, reason: 'no Wi-Fi address and the cloud is now off for it');
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  });

  testWidgets('a chat: Stop stops waiting and drops the late answer; a chat deleted mid-run does not come back', (t) async {
    phoneSize(t);
    final asked = <Completer<List<Map<String, dynamic>>>>[];
    final ids = <String>[];
    final actions = ChatActions();
    Future<List<Map<String, dynamic>>> request(Map<String, dynamic> m) {
      ids.add('${m['id']}');
      final c = Completer<List<Map<String, dynamic>>>();
      asked.add(c);
      return c.future;
    }

    await t.pumpWidget(app(ComputerChat(computerId: 'pc1', request: request, online: true, onAsk: (_) async => '', actions: actions)));
    await settle(t, 2);
    await t.enterText(find.byType(TextField), 'restart the server');
    await settle(t, 2);
    await t.tap(find.byTooltip('Send'));
    await settle(t, 2);
    expect(asked, hasLength(1));
    expect(find.byTooltip('Stop'), findsOneWidget, reason: 'while the computer works there is a way to stop waiting');
    await t.tap(find.byTooltip('Stop'));
    await settle(t, 2);
    expect(find.text('Stopped waiting. The computer may still finish what it was doing.'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsNothing);
    asked.first.complete([
      {'t': 'reply', 'id': ids.first, 'reply': 'Restarted.'},
    ]);
    await settle(t, 2);
    expect(find.text('Restarted.'), findsNothing, reason: 'a late answer is dropped');

    // ask again, then delete the chat while the computer works on it
    await t.enterText(find.byType(TextField), 'and again');
    await settle(t, 2);
    await t.tap(find.byTooltip('Send'));
    await settle(t, 2);
    expect(asked, hasLength(2));
    actions.history();
    await settle(t, 6);
    await t.tap(find.byTooltip('Delete restart the server'));
    await settle(t, 6);
    asked.last.complete([
      {'t': 'reply', 'id': ids.last, 'reply': 'Done again.'},
    ]);
    await settle(t, 2);
    expect(loadChats('pc1'), isEmpty, reason: 'the answer must not bring the deleted chat back');
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  });

  test('a chat body never exceeds what the computer takes', () {
    final file = Attachment(name: 'notes.txt', mime: 'text/plain', kind: AttachmentKind.text, size: 5, text: 'hello');
    final photo = Attachment(name: 'p.jpg', mime: 'image/jpeg', kind: AttachmentKind.image, size: 5, data: 'AAAA');
    expect(inlineChatText('  look  ', [file, photo], maxChatChars), 'look\n\n[notes.txt]\nhello');
    expect(inlineChatText('', [file], maxChatChars), '[notes.txt]\nhello');
    expect(inlineChatText('x' * 4001, const [], maxChatChars), isNull);
  });
}
