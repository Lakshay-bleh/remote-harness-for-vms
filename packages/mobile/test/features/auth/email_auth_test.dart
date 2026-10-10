import 'dart:convert';

import 'package:escanor/core/storage.dart';
import 'package:escanor/core/theme.dart';
import 'package:escanor/features/auth/email_auth.dart';
import 'package:escanor/features/auth/email_auth_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget themed(Widget child) => MaterialApp(
      theme: buildTheme(EscanorColors.of(ThemeName.dark, AccentName.gold), reduceMotion: true),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUp(() async => Storage.initForTest());

  late List<({String path, Map<String, dynamic> body})> calls;
  EmailAuthApi fakeApi({bool available = true}) {
    calls = [];
    return EmailAuthApi('https://api.test', client: MockClient((req) async {
      final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
      calls.add((path: req.url.path, body: body));
      switch (req.url.path) {
        case '/auth/email/status':
          return http.Response(jsonEncode({'available': available}), 200);
        case '/auth/email/login':
          return body['password'] == 'right-password-1'
              ? http.Response(jsonEncode({'status': 'ok', 'code': 'esc_code', 'redirect_uri': 'x'}), 200)
              : http.Response(jsonEncode({'detail': 'Incorrect email or password.'}), 401);
        case '/auth/email/register':
          return http.Response(jsonEncode({'status': 'verification_sent', 'resend_after': 30, 'dev_code': '123456'}), 200);
        case '/auth/email/verify':
          return http.Response(jsonEncode({'status': 'ok', 'code': 'esc_new', 'redirect_uri': 'x'}), 200);
      }
      return http.Response('{}', 404);
    }));
  }

  testWidgets('no mail on the server: password sign-in still works; sign-up and reset, which need a mailed code, are hidden', (tester) async {
    final codes = <String>[];
    await tester.pumpWidget(themed(EmailAuth(begin: () => 'ch', onCode: codes.add, authApi: fakeApi(available: false))));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Forgot password?'), findsNothing);
    expect(find.textContaining('Creating an account with email is not available right now'), findsOneWidget);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'ada@example.com');
    await tester.enterText(fields.at(1), 'right-password-1');
    await tester.tap(find.widgetWithText(InkWell, 'Sign in').last);
    await tester.pumpAndSettle();
    expect(codes, ['esc_code']);
  });

  testWidgets('signs in with email and password, sending this app’s PKCE challenge', (tester) async {
    final codes = <String>[];
    await tester.pumpWidget(themed(EmailAuth(begin: () => 'challenge-1', onCode: codes.add, authApi: fakeApi())));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'not an email');
    await tester.tap(find.widgetWithText(InkWell, 'Sign in').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    await tester.enterText(fields.at(0), 'ada@example.com');
    await tester.enterText(fields.at(1), 'wrong');
    await tester.tap(find.widgetWithText(InkWell, 'Sign in').last);
    await tester.pumpAndSettle();
    expect(find.text('Incorrect email or password.'), findsOneWidget);

    await tester.enterText(fields.at(1), 'right-password-1');
    await tester.tap(find.widgetWithText(InkWell, 'Sign in').last);
    await tester.pumpAndSettle();
    expect(codes, ['esc_code']);
    final login = calls.lastWhere((c) => c.path == '/auth/email/login').body;
    expect(login['platform'], 'mobile');
    expect(login['code_challenge'], 'challenge-1');
    expect(login['redirect_uri'], 'https://www.escanor.in/auth/mobile/login');
  });

  testWidgets('creating an account checks the password, then verifies the mailed code', (tester) async {
    final codes = <String>[];
    await tester.pumpWidget(themed(EmailAuth(begin: () => 'ch', onCode: codes.add, authApi: fakeApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'Ada');
    await tester.enterText(fields.at(1), 'ada@example.com');
    await tester.enterText(fields.at(2), 'password');
    await tester.pump();
    expect(find.text('Weak'), findsOneWidget);
    await tester.tap(find.widgetWithText(InkWell, 'Create account').last);
    await tester.pumpAndSettle();
    expect(find.text('That password is too easy to guess.'), findsOneWidget);

    await tester.enterText(fields.at(2), 'Correct-Horse-9-Battery');
    await tester.pump();
    expect(find.text('Strong'), findsOneWidget);
    await tester.tap(find.widgetWithText(InkWell, 'Create account').last);
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text('Email is not configured on this server. Development code: 123456'), findsOneWidget);
    expect(find.text('resend in 30s'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123 456');
    await tester.pumpAndSettle();
    expect(codes, ['esc_new']);
    expect(calls.last.body, {'email': 'ada@example.com', 'code': '123456'});
    await tester.pump(const Duration(seconds: 31));
  });
}
