import 'package:escanor/core/storage.dart';
import 'package:escanor/features/composer/attachments.dart';
import 'package:escanor/features/composer/chat_composer.dart';
import 'package:escanor/features/voice/voice_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../assistant/harness.dart';

void main() {
  setUp(() async => Storage.initForTest());

  testWidgets('typed words are sent trimmed, and the box empties', (tester) async {
    final sent = <(String, List<Attachment>)>[];
    await tester.pumpWidget(themed(Align(alignment: Alignment.bottomCenter, child: ChatComposer(placeholder: 'Message your assistant', onSend: (t, a) => sent.add((t, a))))));
    expect(find.text('Message your assistant'), findsOneWidget);
    // nothing typed: voice mode where the phone can do it, else a send button that does nothing yet
    expect(find.byTooltip(voiceModeAvailable ? 'Talk to Escanor' : 'Send'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  check the build  ');
    await tester.pump();
    expect(find.byTooltip('Send'), findsOneWidget);
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(sent.single.$1, 'check the build');
    expect(sent.single.$2, isEmpty);
    expect(find.text('check the build'), findsNothing);
  });

  testWidgets('while the assistant works there is a stop button and nothing can be sent', (tester) async {
    var stopped = 0;
    final sent = <String>[];
    await tester.pumpWidget(themed(ChatComposer(placeholder: 'x', running: true, onSend: (t, _) => sent.add(t), onStop: () => stopped++)));
    await tester.enterText(find.byType(TextField), 'more');
    await tester.pump();
    expect(find.byTooltip('Send'), findsNothing);
    expect(find.byTooltip('Speak your message'), findsNothing);
    await tester.tap(find.byTooltip('Stop'));
    expect(stopped, 1);
    expect(sent, isEmpty);
  });

  testWidgets('a stop on its way shows it is working and cannot be pressed twice', (tester) async {
    var stopped = 0;
    await tester.pumpWidget(themed(ChatComposer(placeholder: 'x', running: true, stopping: true, onSend: (_, _) {}, onStop: () => stopped++)));
    expect(find.byTooltip('Stop'), findsNothing);
    await tester.tap(find.byTooltip('Stopping'));
    expect(stopped, 0);
  });

  testWidgets('a turn that looks lost lets the person send again, with stop still beside it', (tester) async {
    final sent = <String>[];
    var stopped = 0;
    await tester.pumpWidget(themed(ChatComposer(placeholder: 'x', running: true, sendWhileRunning: true, onSend: (t, _) => sent.add(t), onStop: () => stopped++)));
    expect(find.byTooltip('Send'), findsNothing, reason: 'nothing typed yet');
    await tester.enterText(find.byType(TextField), 'try again');
    await tester.pump();
    expect(find.byTooltip('Stop'), findsOneWidget);
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(sent, ['try again']);
    await tester.tap(find.byTooltip('Stop'));
    expect(stopped, 1);
  });

  testWidgets('running without a way to stop shows no stop button', (tester) async {
    await tester.pumpWidget(themed(ChatComposer(placeholder: 'x', running: true, onSend: (_, _) {})));
    expect(find.byTooltip('Stop'), findsNothing);
  });

  testWidgets('the attach menu offers what this chat takes', (tester) async {
    await tester.pumpWidget(themed(Align(alignment: Alignment.bottomCenter, child: ChatComposer(placeholder: 'x', onSend: (_, _) {}))));
    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);

    await tester.pumpWidget(themed(Align(alignment: Alignment.bottomCenter, child: ChatComposer(key: const ValueKey('text'), placeholder: 'x', attach: 'text', onSend: (_, _) {}))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    expect(find.text('Photos'), findsNothing);
    expect(find.text('Text or code file'), findsOneWidget);

    await tester.pumpWidget(themed(ChatComposer(key: const ValueKey('none'), placeholder: 'x', attach: 'none', onSend: (_, _) {})));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Attach'), findsNothing);
  });
}
