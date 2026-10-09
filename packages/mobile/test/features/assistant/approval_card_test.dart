import 'package:escanor/core/storage.dart';
import 'package:escanor/features/assistant/approval_card.dart';
import 'package:escanor/features/assistant/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUp(() async => Storage.initForTest());

  const ask = AssistantItem(id: 1, kind: 'approval', requestId: 'r1', title: 'Run a command', detail: 'ls -la', raw: 'bash: ls -la');

  testWidgets('asks in plain words, shows the details on request, and answers', (tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(themed(ApprovalCard(item: ask, onAnswer: answers.add)));
    expect(find.text('NEEDS YOUR OK'), findsOneWidget);
    expect(find.text('Run a command'), findsOneWidget);
    expect(find.text('bash: ls -la'), findsNothing);
    await tester.tap(find.text('Show details'));
    await tester.pump();
    expect(find.text('bash: ls -la'), findsOneWidget);
    expect(find.text('Hide details'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.tap(find.text('Don’t do this'));
    expect(answers, [true, false]);
  });

  testWidgets('a risky step is marked, and an answered one says what was said', (tester) async {
    await tester.pumpWidget(themed(ApprovalCard(item: const AssistantItem(id: 1, kind: 'approval', requestId: 'r', title: 'Delete', risk: 'high', status: 'denied'), onAnswer: (_) {})));
    expect(find.text('NEEDS YOUR CARE'), findsOneWidget);
    expect(find.text('You said no.'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });
}
