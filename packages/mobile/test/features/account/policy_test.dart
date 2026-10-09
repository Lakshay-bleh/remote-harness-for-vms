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
