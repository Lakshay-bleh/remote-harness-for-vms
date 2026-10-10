import 'dart:convert';

import 'package:escanor/features/auth/email_auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('passwords are judged the way the server judges them', () {
    expect(passwordProblem('short'), contains('at least 8'));
    expect(passwordProblem('password'), contains('easy to guess'));
    expect(passwordProblem('aaaaaaaaaa'), contains('easy to guess'));
    expect(passwordProblem('ada@example.com', 'Ada@Example.com'), contains('easy to guess'));
    expect(passwordProblem('correct horse battery'), isNull);
    expect(passwordProblem('x' * 200), contains('at most 128'));
  });

  test('the strength meter rises with length and variety and is zero for nothing', () {
    expect(passwordStrength(''), 0);
    expect(passwordStrength('abc'), 0);
    expect(passwordStrength('password'), 1);
    expect(passwordStrength('correct horse battery'), greaterThan(passwordStrength('hunter22x')));
    expect(passwordStrength('Correct-Horse-9-Battery'), 4);
  });

  test('a pasted code keeps only its digits', () {
    expect(digitsOnly('123 456'), '123456');
    expect(digitsOnly('12-34-56-78'), '123456');
    expect(digitsOnly('abc'), '');
  });

  test('email shape', () {
    expect(isEmail(' ada@example.com '), true);
    for (final bad in ['ada', 'ada@', '@example.com', 'ada@example', 'a b@example.com']) {
      expect(isEmail(bad), false, reason: bad);
    }
  });

  test('a finished sign-in goes back to the callback with its code, and the page that wanted the person back', () {
    expect(callbackWithCode('https://www.escanor.in/auth/callback', 'esc_code_x'), 'https://www.escanor.in/auth/callback?code=esc_code_x');
    expect(callbackWithCode('http://localhost:3000/auth/callback', 'c', '/dashboard/billing'), 'http://localhost:3000/auth/callback?code=c&next=%2Fdashboard%2Fbilling');
  });

  test('the calls send what the server expects and surface its words and its wait', () async {
    final seen = <({String url, Object? body})>[];
    final fake = MockClient((req) async {
      final url = req.url.toString();
      seen.add((url: url, body: req.body.isEmpty ? null : jsonDecode(req.body)));
      if (url.endsWith('/auth/email/login')) return http.Response(jsonEncode({'detail': 'Incorrect email or password.', 'code': 'bad_credentials'}), 401);
      if (url.endsWith('/auth/email/resend')) return http.Response(jsonEncode({'detail': 'Wait 30 seconds.', 'code': 'cooldown', 'retry_after': 30}), 429);
      if (url.endsWith('/auth/email/status')) return http.Response(jsonEncode({'available': true}), 200);
      return http.Response(jsonEncode({'status': 'verification_sent', 'resend_after': 45}), 200);
    });
    final api = EmailAuthApi('https://api.test/api/v1', client: fake);

    expect(await api.available(), true);
    final sent = await api.register(email: 'a@b.co', password: 'x', name: 'A', flow: const AuthFlow(redirectUri: 'https://site/auth/callback'));
    expect(sent.status, 'verification_sent');
    expect(sent.resendAfter, 45);
    expect(seen[1].url, 'https://api.test/api/v1/auth/email/register');
    expect(seen[1].body, {'email': 'a@b.co', 'password': 'x', 'name': 'A', 'redirect_uri': 'https://site/auth/callback', 'platform': 'web'});

    await expectLater(
      api.login(email: 'a@b.co', password: 'no', flow: const AuthFlow(redirectUri: 'https://site/auth/callback')),
      throwsA(isA<EmailAuthError>().having((e) => e.status, 'status', 401).having((e) => e.message, 'message', 'Incorrect email or password.')),
    );
    await expectLater(api.resend('a@b.co'), throwsA(isA<EmailAuthError>().having((e) => e.retryAfter, 'retryAfter', 30).having((e) => e.code, 'code', 'cooldown')));
  });

  test('an app sends its platform and PKCE challenge with the flow', () async {
    Map<String, dynamic> body = {};
    final fake = MockClient((req) async {
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'status': 'verification_sent', 'resend_after': 45}), 200);
    });
    await EmailAuthApi('https://api.test', client: fake).register(
      email: 'a@b.co',
      password: 'x',
      name: 'A',
      flow: const AuthFlow(redirectUri: 'https://www.escanor.in/auth/mobile/login', platform: 'mobile', challenge: 'abc'),
    );
    expect(body['platform'], 'mobile');
    expect(body['code_challenge'], 'abc');
    expect(body['code_challenge_method'], 'S256');
  });

  test('an unreachable server reads as a connection problem, and "available" fails closed', () async {
    final down = MockClient((_) async => throw http.ClientException('fetch failed'));
    final api = EmailAuthApi('https://api.test', client: down);
    expect(await api.available(), false);
    await expectLater(api.forgot('a@b.co'), throwsA(isA<EmailAuthError>().having((e) => e.code, 'code', 'network')));
  });

  test('a finished sign-in hands back its one-time code', () async {
    final fake = MockClient((_) async => http.Response(jsonEncode({'status': 'ok', 'code': 'esc_1', 'redirect_uri': 'x'}), 200));
    final f = await EmailAuthApi('https://api.test', client: fake).verify(email: 'a@b.co', code: '123456');
    expect(f.code, 'esc_1');
  });
}
