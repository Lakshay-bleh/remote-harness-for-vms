// The Machines tab: one header and a Servers / Computers switch over the two halves.
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:escanor/core/api.dart';
import 'package:escanor/core/nav.dart';
import 'package:escanor/core/storage.dart';
import 'package:escanor/core/theme.dart';
import 'package:escanor/features/computers/computer_prefs.dart';
import 'package:escanor/features/machines/hub_api.dart';
import 'package:escanor/features/machines/hub_socket.dart';
import 'package:escanor/features/machines/hub_store.dart';
import 'package:escanor/features/machines/machines_home.dart';
import 'package:escanor/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

Widget app(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: buildTheme(EscanorColors.of(ThemeName.dark, AccentName.gold), reduceMotion: true),
        home: Scaffold(body: child),
      ),
    );

Future<void> settle(WidgetTester t, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  const creds = HubCredentials();
  final vm = {'id': 'v1', 'name': 'build-box', 'connected': true, 'lastSeenAt': null, 'accounts': []};

  setUp(() async {
    await Storage.initForTest();
    resetComputerPrefsCache();
    machinesSegment.value = 0;
    api = Api(
      base: 'https://api.test',
      client: MockClient((req) async {
        if (req.url.path == '/agent/hub/managed') {
          return http.Response(jsonEncode({'available': true, 'hub_url': 'https://hub.example.test', 'app_token': 'tok', 'install_command': 'curl x'}), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    HubStore.instance = HubStore(
      api: HubApi(
        credentials: creds,
        client: MockClient((req) async {
          final p = req.url.path;
          if (p == '/api/vms') return http.Response(jsonEncode([vm]), 200);
          if (p == '/api/vms/v1/sessions') return http.Response('[]', 200);
          if (p == '/api/vms/v1/projects') return http.Response('[]', 200);
          if (p == '/api/mcp-servers') return http.Response(jsonEncode({'servers': [], 'vms': []}), 200);
          return http.Response('{"ok":true}', 202);
        }),
      ),
      socket: HubSocket(connector: (u, p) => FakeSocket(u, p), token: () => creds.token, hubUrl: () => creds.hubUrl),
      credentials: creds,
    );
  });

  tearDown(() {
    HubStore.instance.logout();
    machinesSegment.value = 0;
  });

  testWidgets('one header with a switch: no second title under it, and Add does what the half on show adds', (t) async {
    t.view.physicalSize = const Size(400, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(const MachinesHome()));
    await settle(t);

    expect(find.text('Machines'), findsOneWidget);
    expect(find.byType(ScreenHeader), findsNothing, reason: 'the halves leave their own headers out');
    expect(find.text('Servers'), findsOneWidget, reason: 'only on the switch');
    expect(find.text('Computers'), findsOneWidget, reason: 'only on the switch');
    expect(find.text('build-box'), findsOneWidget);
    final servers = t.getSemantics(find.ancestor(of: find.text('Servers'), matching: find.byType(Semantics)).first);
    expect(servers.flagsCollection.isSelected, Tristate.isTrue);

    await t.tap(find.text('Add'));
    await settle(t);
    expect(find.text('Connect a machine'), findsWidgets, reason: 'on Servers, Add connects a server');
    await t.tap(find.text('Close'));
    await settle(t);

    await t.tap(find.text('Computers'));
    await settle(t);
    expect(machinesSegment.value, 1);
    expect(find.text('Waiting for your computer'), findsOneWidget);
    expect(find.text('Machines'), findsOneWidget);
    expect(find.byType(ScreenHeader), findsNothing);
    await t.tap(find.text('Add'));
    await settle(t);
    expect(find.text('Add your computer'), findsWidgets, reason: 'on Computers, Add pairs a computer');
    await t.tap(find.text('Close'));
    await settle(t);

    // Opening the old Computers tab by name lands on this half too.
    machinesSegment.value = 0;
    await settle(t);
    expect(find.text('build-box'), findsOneWidget);
    HubStore.instance.logout();
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
  });
}
