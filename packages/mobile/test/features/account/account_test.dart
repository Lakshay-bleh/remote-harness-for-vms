import 'package:escanor/features/account/data_export.dart';
import 'package:escanor/features/account/money.dart';
import 'package:escanor/features/account/privacy.dart';
import 'package:escanor/features/account/security.dart';
import 'package:flutter_test/flutter_test.dart';

// Port of packages/web/src/escanor/account/account.test.ts.
void main() {
  group('privacy', () {
    test('keeps the website’s four optional consents and its request types', () {
      expect(optionalConsents.map((c) => c.purpose), ['marketing', 'product_updates', 'analytics', 'ai_improvement']);
      expect(requestTypes.map((r) => r.value).toList()..sort(), ['access', 'consent_withdrawal', 'correction', 'erasure', 'grievance', 'nomination']);
    });
    test('describes deadlines in days and hours, before and after they pass', () {
      final now = DateTime.parse('2026-10-03T12:00:00Z');
      expect(describeDue('2026-10-05T13:00:00Z', now: now), 'due in 2 days');
      expect(describeDue('2026-10-03T17:00:00Z', now: now), 'due in 5 hours');
      expect(describeDue('2026-10-03T12:20:00Z', now: now), 'due in 1 hour');
      expect(describeDue('2026-10-02T11:00:00Z', now: now), 'overdue by 1 day');
      expect(describeDue('garbage', now: now), '');
    });
    test('labels statuses and knows when one is finished', () {
      expect(statusLabel('fulfilled'), 'Completed');
      expect(statusLabel('rejected'), 'Declined');
      expect(statusLabel('something_new'), 'something_new');
      expect(isFinished('fulfilled') && isFinished('rejected'), true);
      expect(isFinished('in_progress'), false);
    });
    test('checks a request against the server’s limits before sending', () {
      expect(requestProblem(subject: 'My data', details: ''), null);
      expect(requestProblem(subject: ' a ', details: ''), contains('at least 3'));
      expect(requestProblem(subject: 'x' * 201, details: ''), contains('shorter'));
      expect(requestProblem(subject: 'My data', details: 'x' * 5001), contains('too long'));
    });
    test('reads a request with its timeline, and knows which deadline matters', () {
      final r = PrivacyRequest.fromJson({
        'id': '1',
        'reference': 'PR-2026-0001',
        'request_type': 'grievance',
        'status': 'received',
        'subject': 'Hello',
        'acknowledge_by': 'a',
        'resolve_by': 'b',
        'events': [
          {'from_status': null, 'to_status': 'received', 'note': null, 'created_at': '2026-10-03T12:00:00Z'}
        ],
      });
      expect(r.nextDue, 'a');
      expect(r.events.single.toStatus, 'received');
      expect(requestTypeLabel(r.requestType), 'Make a complaint or report a problem');
      expect(requestTypeLabel('new_kind'), 'new_kind');
    });
  });

  group('security', () {
    test('reads a six-digit code or a backup code, however it was typed, and nothing else', () {
      expect(parseCodeInput('123 456'), '123456');
      expect(parseCodeInput(' 123456 '), '123456');
      expect(parseCodeInput('abcd-efgh'), 'ABCD-EFGH');
      expect(parseCodeInput('abcd efgh'), 'ABCD-EFGH');
      for (final bad in ['', '12345', '1234567', 'ABCD', 'ABCD-EFG0', 'ABC1-EFGH']) {
        expect(parseCodeInput(bad), null, reason: bad); // 0 and 1 are never in a backup code
      }
    });
    test('confirms the email without fuss about case or spaces, and never when there is none', () {
      expect(emailConfirmed(' A@Example.com ', 'a@example.com'), true);
      expect(emailConfirmed('b@example.com', 'a@example.com'), false);
      expect(emailConfirmed('', ''), false);
      expect(emailConfirmed('x', null), false);
    });
    test('says how long until a date', () {
      final now = DateTime.parse('2026-10-03T12:00:00Z');
      expect(daysUntil('2026-10-10T11:00:00Z', now: now), 'in 6 days');
      expect(daysUntil('2026-10-04T12:30:00Z', now: now), 'in 1 day');
      expect(daysUntil('2026-10-03T16:00:00Z', now: now), 'in 4 hours');
      expect(daysUntil('2026-10-02T00:00:00Z', now: now), 'now');
      expect(daysUntil('garbage', now: now), '');
    });
    test('tells the person what deletion does and keeps', () {
      expect(deletionFacts.length, 4);
      expect(deletionFacts.any((f) => f.contains('cancel the deletion')) && deletionFacts.any((f) => f.contains('kept')), true);
    });
    test('shows the setup key in groups of four, and the backup codes as a file', () {
      expect(groupKey('ABCDEFGHIJ'), 'ABCD EFGH IJ');
      expect(backupCodesText(['AAAA-BBBB', 'CCCC-DDDD']), 'Escanor backup codes (each works once)\n\nAAAA-BBBB\nCCCC-DDDD\n');
    });
    test('reads the deletion status', () {
      final s = DeletionStatus.fromJson({'scheduled': true, 'scheduled_for': '2026-10-10T00:00:00Z', 'two_factor_enabled': true, 'reference': 'DEL-1'});
      expect([s.scheduled, s.twoFactorEnabled, s.reference, s.graceDays], [true, true, 'DEL-1', 7]);
      expect(DeletionStatus.fromJson({}).scheduled, false);
    });
  });

  group('data export', () {
    test('names the file by date, and writes readable JSON', () {
      expect(exportFileName(DateTime.parse('2026-10-03T23:59:00Z')), 'escanor-my-data-2026-10-03.json');
      expect(exportText({'a': 1}), '{\n  "a": 1\n}');
    });
    test('says how big it is', () {
      expect(sizeLabel('x' * 500), '500 bytes');
      expect(sizeLabel('x' * 2048), '2.0 KB');
      expect(sizeLabel('x' * (50 * 1024)), '50 KB');
      expect(sizeLabel('é' * 10), '20 bytes'); // bytes, not characters
      expect(sizeLabel('x' * (3 * 1024 * 1024)), '3.0 MB');
    });
  });

  group('numbers', () {
    test('groups the Indian way and in threes', () {
      expect(groupIndian(999), '999');
      expect(groupIndian(1000), '1,000');
      expect(groupIndian(100000), '1,00,000');
      expect(groupIndian(12345678), '1,23,45,678');
      expect(groupThousands(1234567), '1,234,567');
      expect(groupThousands(12), '12');
    });
  });
}
