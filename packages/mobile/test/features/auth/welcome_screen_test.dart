import 'package:escanor/core/api.dart';
import 'package:escanor/core/storage.dart';
import 'package:escanor/core/theme.dart';
import 'package:escanor/features/auth/auth_shell.dart';
import 'package:escanor/features/auth/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() async {
    await Storage.initForTest();
    api = Api(base: 'https://api.test', client: MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('welcomes, offers Google, and leads to your own hub', (tester) async {
    var advanced = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTheme(EscanorColors.of(ThemeName.dark, AccentName.gold), reduceMotion: true),
        home: WelcomeScreen(onAdvanced: () => advanced++),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Escanor'), findsOneWidget);
    expect(find.text('Sign in once. Your assistant, its machine and your hub are set up for you.'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(GoogleIcon), findsOneWidget);
    expect(find.text('dev email'), findsNothing, reason: 'only a debug build pointed at another server shows it');
    await tester.tap(find.text('I run my own Remote Harness hub'));
    expect(advanced, 1);
  });
}
