import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636, S256). The sign-in returns through a custom-scheme link that any installed app can
/// also register, so the one-time login code is bound to a secret only this app holds.

String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String challengeFor(String verifier) => b64url(sha256.convert(ascii.encode(verifier)).bytes);

({String verifier, String challenge}) createPkcePair([Random? random]) {
  final r = random ?? Random.secure();
  final verifier = b64url(List<int>.generate(32, (_) => r.nextInt(256)));
  return (verifier: verifier, challenge: challengeFor(verifier));
}
