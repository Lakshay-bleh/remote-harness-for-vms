import 'dart:convert';

import 'package:escanor/core/api.dart';
import 'package:escanor/core/nav.dart';
import 'package:escanor/core/storage.dart';
import 'package:escanor/core/theme.dart';
import 'package:escanor/features/automations/automations_screen.dart';
import 'package:escanor/features/automations/autopilot_models.dart';
import 'package:escanor/ui/parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget app(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: buildTheme(EscanorColors.of(ThemeName.dark, AccentName.gold), reduceMotion: true),
        home: Scaffold(body: child),
      ),
    );

Map<String, dynamic> overview({bool enabled = true, bool paused = false, bool canManage = true, List<Map<String, dynamic>> runs = const [], List<Map<String, dynamic>> triggers = const []}) => {
      'policy': {
        'enabled': enabled,
        'paused': paused,
        'level': 'balanced',
        'allow_irreversible': false,
        'verify': true,
        'notify_on': ['needs_you', 'failed'],
        'budgets': {'max_runs_per_day': 20},
        'categories': [
          {'id': 'deploy', 'label': 'Deploying', 'mode': 'ask', 'max_mode': 'auto', 'locked': false},
          {'id': 'billing', 'label': 'Money', 'mode': 'block', 'max_mode': 'block', 'locked': true},
        ],
        'levels': [
          {'id': 'ask', 'label': 'Ask me first', 'about': 'Waits for your yes.'},
          {'id': 'balanced', 'label': 'Balanced', 'about': 'Small changes happen on their own.'},
          {'id': 'autonomous', 'label': 'Autonomous', 'about': 'Also deploys.'},
        ],
      },
      'can_manage': canManage,
      'usage': {'auto_approvals_today': 3, 'runs_today': 2, 'active': runs.where((r) => r['status'] == 'running').length},
      'runs': runs,
      'needs_you': [for (final r in runs) if (r['status'] == 'needs_you') r],
      'triggers': triggers,
      'watchers': [
        {'id': 'failed-deployments', 'name': 'Failed deployments', 'about': 'Tells you the moment a deployment fails.', 'enabled': true, 'fix': false,
         'last_found_at': DateTime.now().toUtc().toIso8601String(), 'last_finding': 'Failed deployment: api v3 in production.', 'found_count': 1},
        {'id': 'health', 'name': 'Health drops', 'about': 'Tells you when health falls.', 'enabled': true, 'fix': false},
      ],
      'templates': [
        {'id': 'morning', 'name': 'Every morning, check everything', 'kind': 'schedule', 'config': {'daily_at': '09:00'}, 'goal': 'Check it all.', 'criteria': 'A short report.'},
      ],
      'assistant': {'ready': true, 'state': 'ready', 'message': ''},
    };

Map<String, dynamic> run(String id, String status, {String goal = 'Fix the build'}) => {
      'id': id,
      'goal': goal,
      'criteria': '',
      'origin': 'manual',
      'status': status,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'summary': status == 'succeeded' ? 'Fixed and checked.' : null,
      'waiting': status == 'needs_you' ? {'title': 'Deploy to production', 'category': 'deploy', 'reason': 'Deploys wait for you.'} : null,
      'decisions': [],
    };

void main() {
  final sent = <http.Request>[];
  late Map<String, dynamic> data;

  setUp(() async {
    await Storage.initForTest();
    sent.clear();
    data = overview(runs: [run('r1', 'succeeded'), run('r2', 'needs_you', goal: 'Ship the fix')]);
    api = Api(
      base: 'https://api.test',
      client: MockClient((req) async {
        sent.add(req);
        final p = req.url.path;
        if (p == '/autopilot' && req.method == 'GET') return http.Response(jsonEncode(data), 200);
        if (p == '/autopilot/runs' && req.method == 'POST') return http.Response(jsonEncode(run('r3', 'running', goal: jsonDecode(req.body)['goal'] as String)), 200);
        if (p.endsWith('/approve') || p.endsWith('/deny') || p == '/autopilot/pause' || p == '/autopilot/resume') return http.Response('{}', 200);
        if (p == '/autopilot/policy') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          if (body.containsKey('enabled')) (data['policy'] as Map)['enabled'] = body['enabled'];
          if (body.containsKey('level')) (data['policy'] as Map)['level'] = body['level'];
          return http.Response(jsonEncode(data['policy']), 200);
        }
        if (p.startsWith('/autopilot/watchers/') && req.method == 'PATCH') {
          final id = p.split('/').last;
          final w = (data['watchers'] as List).cast<Map<String, dynamic>>().firstWhere((w) => w['id'] == id);
          w.addAll(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(w), 200);
        }
        if (p == '/autopilot/triggers' && req.method == 'POST') {
          final t = {...jsonDecode(req.body) as Map<String, dynamic>, 'id': 't1', 'fired_count': 0};
          data['triggers'] = [t];
          return http.Response(jsonEncode(t), 200);
        }
        return http.Response('{"detail":"not found"}', 404);
      }),
    );
    api.tokens.set('access', 'refresh', 900);
  });

  test('the overview is read from the server’s own shapes, and a missing field never breaks it', () {
    final o = AutopilotOverview.fromJson(overview(runs: [run('r1', 'needs_you')]));
    expect(o.policy.levelLabel, 'Balanced');
    expect(o.needsYou.single.waiting!.title, 'Deploy to production');
    expect(o.canManage, isTrue);
    expect(AutopilotOverview.fromJson(null).runs, isEmpty);
    expect(AutopilotOverview.fromJson({'policy': 5, 'runs': 'x'}).policy.enabled, isFalse);
  });

  test('the headline says what is happening in plain words', () {
    const p = AutopilotPolicy(enabled: true, level: 'balanced');
    expect(autopilotHeadline(const AutopilotPolicy(paused: true), 0, 0), startsWith('Stopped'));
    expect(autopilotHeadline(const AutopilotPolicy(), 0, 0), startsWith('Off'));
    expect(autopilotHeadline(p, 0, 2), '2 things need your answer.');
    expect(autopilotHeadline(p, 1, 0), 'Working on 1 goal.');
  });

  test('a trigger reads as a sentence', () {
    Trigger t(String kind, Map<String, dynamic> config) => Trigger.fromJson({'id': 'a', 'name': 'n', 'kind': kind, 'config': config});
    expect(t('schedule', {'every_minutes': 30}).when, 'Every 30 minutes');
    expect(t('schedule', {'every_minutes': 120}).when, 'Every 2 hours');
    expect(t('schedule', {'daily_at': '09:00'}).when, 'Every day at 09:00 UTC');
    expect(t('health_below', {'threshold': 60}).when, 'When health is below 60');
    expect(t('incident_opened', {}).when, 'When an incident opens');
  });

  test('automatic checks are read defensively, and an older server simply has none', () {
    final o = AutopilotOverview.fromJson(overview());
    expect(o.watchers.map((w) => w.id), ['failed-deployments', 'health']);
    expect(o.watchers.first.foundCount, 1);
    expect(o.watchers.first.lastFinding, contains('api v3'));
    expect(AutopilotOverview.fromJson({...overview()}..remove('watchers')).watchers, isEmpty);
    final w = Watcher.fromJson({'id': 'x'});
    expect(w.enabled, isTrue, reason: 'a check is on unless switched off');
    expect(w.fix, isFalse, reason: 'it only tells you unless asked to fix');
    expect(originLabels['check'], 'An automatic check');
  });

  test('a category can only be set as far as its ceiling', () {
    expect(modesUpTo('block'), ['block']);
    expect(modesUpTo('ask'), ['block', 'ask']);
    expect(modesUpTo('auto'), ['block', 'ask', 'auto']);
  });

  test('the old Computers tab is the second half of Machines', () {
    machinesSegment.value = 0;
    expect(tabFromName('computers'), AppTab.machines);
    expect(machinesSegment.value, 1);
    expect(tabFromName('automations'), AppTab.automations);
    machinesSegment.value = 0;
  });

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows what is running, what needs an answer, and answers it', (tester) async {
    tall(tester);
    await tester.pumpWidget(app(const AutomationsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('1 thing needs your answer.'), findsWidgets);
    expect(find.text('Deploy to production'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(sent.any((r) => r.url.path == '/autopilot/runs/r2/approve' && r.method == 'POST'), isTrue);
  });

  testWidgets('a goal can be handed over, and it starts a run', (tester) async {
    tall(tester);
    await tester.pumpWidget(app(const AutomationsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Give it a goal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Make the site healthy');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    final post = sent.lastWhere((r) => r.url.path == '/autopilot/runs' && r.method == 'POST');
    expect(jsonDecode(post.body)['goal'], 'Make the site healthy');
  });

  testWidgets('automations: a ready-made one can be added, and the rules show the level', (tester) async {
    tall(tester);
    await tester.pumpWidget(app(const AutomationsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automations').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add an automation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every morning, check everything'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final post = sent.lastWhere((r) => r.url.path == '/autopilot/triggers' && r.method == 'POST');
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['kind'], 'schedule');
    expect(body['config'], {'daily_at': '09:00'});
    expect(find.text('Every morning, check everything'), findsOneWidget);

    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    expect(find.text('Balanced'), findsOneWidget);
    await tester.tap(find.text('Autonomous'));
    await tester.pumpAndSettle();
    expect(sent.any((r) => r.url.path == '/autopilot/policy' && jsonDecode(r.body)['level'] == 'autonomous'), isTrue);
  });

  testWidgets('two kinds of automation: the automatic checks can be switched and told to fix, next to the ones you set', (tester) async {
    tall(tester);
    await tester.pumpWidget(app(const AutomationsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automations').last);
    await tester.pumpAndSettle();
    expect(find.text('ALWAYS CHECKING'), findsOneWidget);
    expect(find.text('SET BY YOU'), findsOneWidget);
    expect(find.text('Failed deployments'), findsOneWidget);
    expect(find.textContaining('api v3'), findsOneWidget);
    expect(find.textContaining('Found something'), findsOneWidget);

    // Each card has its on/off switch first, then "also fix it".
    final switches = find.byType(ESwitch);
    await tester.tap(switches.at(1)); // fix, on the failed-deployments card
    await tester.pumpAndSettle();
    final fix = sent.lastWhere((r) => r.url.path == '/autopilot/watchers/failed-deployments' && r.method == 'PATCH');
    expect(jsonDecode(fix.body), {'fix': true});

    await tester.tap(find.byType(ESwitch).at(2)); // the health card's on/off
    await tester.pumpAndSettle();
    final off = sent.lastWhere((r) => r.url.path == '/autopilot/watchers/health' && r.method == 'PATCH');
    expect(jsonDecode(off.body), {'enabled': false});
  });

  testWidgets('someone who cannot manage sees the rules but cannot change them', (tester) async {
    tall(tester);
    data = overview(canManage: false);
    await tester.pumpWidget(app(const AutomationsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only the owner or an admin'), findsOneWidget);
    await tester.tap(find.text('Autonomous'));
    await tester.pumpAndSettle();
    expect(sent.any((r) => r.url.path == '/autopilot/policy'), isFalse);
  });
}
