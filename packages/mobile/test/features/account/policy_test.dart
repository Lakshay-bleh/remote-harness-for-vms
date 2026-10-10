import 'package:escanor/features/account/policy.dart';
import 'package:flutter_test/flutter_test.dart';

// Port of packages/web/src/escanor/account/policy.test.ts.
ConsentState s(String purpose, [String version = 'v2', String recordedAt = '2026-10-01T00:00:00Z']) =>
    ConsentState(purpose: purpose, granted: true, noticeVersion: version, recordedAt: recordedAt);

void main() {
  test('acceptance is needed until both records exist at the current version', () {
    expect(needsAcceptance([], 'v2'), true);
    expect(needsAcceptance([s('terms')], 'v2'), true);
    expect(needsAcceptance([s('terms'), s('privacy_notice')], 'v2'), false);
    expect(needsAcceptance([s('terms', 'v1'), s('privacy_notice', 'v1')], 'v2'), true);
    expect(needsAcceptance([s('terms'), const ConsentState(purpose: 'privacy_notice', granted: false, noticeVersion: 'v2', recordedAt: '')], 'v2'), true,
        reason: 'withdrawn is not accepted');
  });

  test('a newer version accepted elsewhere (website, desktop) counts: an app one version behind must not ask again', () {
    // Every app writes the same consent records. Asking whenever the version differs made two apps on different versions take
    // turns overwriting each other, so "I am 18 or older…" came back every time the person switched between them.
    expect(needsAcceptance([s('terms', '2026-10-08'), s('privacy_notice', '2026-10-08')], '2026-10-07'), false);
    expect(needsAcceptance([s('terms', '2026-10-08'), s('privacy_notice', '2026-10-06')], '2026-10-07'), true);
  });

  test('the highest accepted version counts, so an older app recording its version afterwards does not make this one ask', () {
    // The desktop (2026-10-08) granted after this app (2026-10-10): the latest event is 10-08, the accepted one 10-10.
    ConsentState after(String p) =>
        ConsentState(purpose: p, granted: true, noticeVersion: '2026-10-08', recordedAt: '', acceptedVersion: '2026-10-10');
    expect(needsAcceptance([after('terms'), after('privacy_notice')], '2026-10-10'), false);
    expect(needsAcceptance([after('terms'), after('privacy_notice')], '2026-10-11'), true);
    // An older API sends no accepted_version: notice_version is used.
    expect(needsAcceptance([s('terms', '2026-10-08'), s('privacy_notice', '2026-10-08')], '2026-10-10'), true);
    final parsed = ConsentState.fromJson({'purpose': 'terms', 'granted': true, 'notice_version': '2026-10-08', 'accepted_version': '2026-10-10', 'recorded_at': ''});
    expect(parsed.acceptedVersion, '2026-10-10');
    expect(ConsentState.fromJson({'purpose': 'terms', 'granted': true, 'notice_version': 'x', 'accepted_version': null}).acceptedVersion, isNull);
  });

  test('the rules reminder comes back after 90 days', () {
    final now = DateTime.parse('2026-10-07T00:00:00Z');
    expect(needsRulesNotice([], now), true);
    expect(needsRulesNotice([s('rules_notice', 'x', '2026-09-01T00:00:00Z')], now), false);
    expect(needsRulesNotice([s('rules_notice', 'x', '2026-06-01T00:00:00Z')], now), true);
  });

  test('consent records are read from the server’s shape', () {
    final c = ConsentState.fromJson({'purpose': 'terms', 'granted': true, 'notice_version': '2026-10-07', 'recorded_at': '2026-10-07T10:00:00Z'});
    expect([c.purpose, c.granted, c.noticeVersion, c.recordedAt], ['terms', true, '2026-10-07', '2026-10-07T10:00:00Z']);
    expect(ConsentState.fromJson(null).purpose, '');
  });
}
