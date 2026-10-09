/// Email and password sign-in, as the website talks to it (escanor/emailAuth.ts). The server does the real checking
/// (passwords are hashed there, codes are mailed and limited there); what is here is the same set of rules in the form's own
/// words, so a problem is shown before the request, plus the calls themselves.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

const passwordMin = 8;
const passwordMax = 128;
const codeLength = 6;

const _common = {
  'password', '12345678', '123456789', '1234567890', 'qwertyuiop', 'iloveyou', '11111111', 'password1', 'abcd1234', 'letmein1', //
  'escanor123',
};
final _email = RegExp(r'^[^@\s]{1,64}@[^@\s]{1,255}\.[^@\s.]{2,}$');

bool isEmail(String value) => _email.hasMatch(value.trim());

/// What is wrong with this password, in words for the person typing it, or null when it will be accepted.
String? passwordProblem(String password, [String email = '']) {
  final length = password.runes.length;
  if (length < passwordMin) return 'Use at least $passwordMin characters.';
  if (length > passwordMax) return 'Use at most $passwordMax characters.';
  final lowered = password.toLowerCase();
  if (_common.contains(lowered) || (email.isNotEmpty && lowered == email.trim().toLowerCase()) || password.runes.toSet().length < 4) {
    return 'That password is too easy to guess.';
  }
  return null;
}

/// 0 (nothing or refused) to 4. A guide for the meter only; the server's rules are the ones that count.
int passwordStrength(String password) {
  if (password.isEmpty || passwordProblem(password) != null) return password.runes.length >= passwordMin ? 1 : 0;
  var score = 1;
  if (password.length >= 12) score += 1;
  if (RegExp('[a-z]').hasMatch(password) && RegExp('[A-Z]').hasMatch(password)) score += 1;
  if (RegExp(r'\d').hasMatch(password) && RegExp('[^A-Za-z0-9]').hasMatch(password)) {
    score += 1;
  } else if (password.length >= 16) {
    score += 1;
  }
  return score > 4 ? 4 : score;
}

/// The digits of whatever was typed or pasted ("123 456", "123-456"), cut to one code's length.
String digitsOnly(String value) {
  final d = value.replaceAll(RegExp(r'\D'), '');
  return d.length > codeLength ? d.substring(0, codeLength) : d;
}

/// Where a finished sign-in goes: the callback with the one-time code, and the page that wanted the person back.
String callbackWithCode(String redirectUri, String code, [String? next]) {
  final uri = Uri.parse(redirectUri);
  final q = Map<String, String>.of(uri.queryParameters)..['code'] = code;
  if (next != null && next.isNotEmpty) q['next'] = next;
  // Encoded the way the browser's URLSearchParams does it.
  final query = q.entries.map((e) => '${_formEncode(e.key)}=${_formEncode(e.value)}').join('&');
  return uri.replace(query: query).toString();
}

String _formEncode(String s) => Uri.encodeQueryComponent(s);

class EmailAuthError implements Exception {
  EmailAuthError(this.message, this.code, this.status, this.retryAfter);
  final String message;
  final String code;
  final int status;
  final int? retryAfter;
  @override
  String toString() => message;
}

class Finished {
  const Finished({required this.status, required this.code, required this.redirectUri});
  final String status;
  final String code;
  final String redirectUri;
  factory Finished.fromJson(Map<String, dynamic> j) => Finished(status: '${j['status'] ?? ''}', code: '${j['code'] ?? ''}', redirectUri: '${j['redirect_uri'] ?? ''}');
}

class CodeSent {
  const CodeSent({required this.status, this.email, required this.resendAfter, this.expiresIn, this.devCode});

  /// verification_sent | sent
  final String status;
  final String? email;
  final int resendAfter;
  final int? expiresIn;
  final String? devCode;
  factory CodeSent.fromJson(Map<String, dynamic> j) => CodeSent(
        status: '${j['status'] ?? ''}',
        email: j['email'] as String?,
        resendAfter: (j['resend_after'] as num?)?.toInt() ?? 0,
        expiresIn: (j['expires_in'] as num?)?.toInt(),
        devCode: j['dev_code'] as String?,
      );
}

/// Where a finished sign-in goes. The website only needs [redirectUri]. The apps also say which platform they are and send a
/// PKCE challenge, so the one-time code that comes back can only be redeemed by the app instance that asked for it.
class AuthFlow {
  const AuthFlow({required this.redirectUri, this.platform, this.challenge});
  final String redirectUri;

  /// web | mobile
  final String? platform;
  final String? challenge;

  Map<String, dynamic> toJson() => {
        'redirect_uri': redirectUri,
        'platform': platform ?? 'web',
        if (challenge != null && challenge!.isNotEmpty) ...{'code_challenge': challenge, 'code_challenge_method': 'S256'},
      };
}

class EmailAuthApi {
  EmailAuthApi(this.base, {http.Client? client}) : _http = client ?? http.Client();
  final String base;
  final http.Client _http;

  Future<Map<String, dynamic>> _call(String path, [Map<String, dynamic>? body]) async {
    http.Response res;
    try {
      final uri = Uri.parse('$base$path');
      res = body == null ? await _http.get(uri) : await _http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    } catch (_) {
      throw EmailAuthError('Could not reach Escanor. Check your connection and try again.', 'network', 0, null);
    }
    Object? data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }
    final map = data is Map ? Map<String, dynamic>.from(data) : null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = map?['detail'] is String ? map!['detail'] as String : 'Something went wrong (${res.statusCode}).';
      final retry = map?['retry_after'] is num ? (map!['retry_after'] as num).toInt() : null;
      throw EmailAuthError(detail, map?['code'] is String ? map!['code'] as String : 'error', res.statusCode, retry);
    }
    return map ?? <String, dynamic>{};
  }

  /// Whether this server can send mail. Fails closed: no answer means no email sign-in.
  Future<bool> available() async {
    try {
      return (await _call('/auth/email/status'))['available'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<CodeSent> register({required String email, required String password, required String name, required AuthFlow flow}) async =>
      CodeSent.fromJson(await _call('/auth/email/register', {'email': email, 'password': password, 'name': name, ...flow.toJson()}));

  Future<Finished> verify({required String email, required String code}) async =>
      Finished.fromJson(await _call('/auth/email/verify', {'email': email, 'code': code}));

  Future<Finished> login({required String email, required String password, required AuthFlow flow}) async =>
      Finished.fromJson(await _call('/auth/email/login', {'email': email, 'password': password, ...flow.toJson()}));

  Future<CodeSent> resend(String email) async => CodeSent.fromJson(await _call('/auth/email/resend', {'email': email}));

  Future<CodeSent> forgot(String email) async => CodeSent.fromJson(await _call('/auth/email/forgot', {'email': email}));

  Future<Finished> reset({required String email, required String code, required String password, required AuthFlow flow}) async =>
      Finished.fromJson(await _call('/auth/email/reset', {'email': email, 'code': code, 'password': password, ...flow.toJson()}));
}
