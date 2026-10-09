// Ports of computer/activity.test.ts, activityPaging.test.ts, link.test.ts, permissions.test.ts, errors.test.ts,
// computerPrefs.test.ts (pure parts), nativeScan.test.ts and useRemote.test.ts.
import 'dart:async';

import 'package:escanor/core/api.dart' show isRecentlySeen;
import 'package:escanor/features/computers/activity_label.dart';
import 'package:escanor/features/computers/activity_paging.dart';
import 'package:escanor/features/computers/computer_prefs.dart';
import 'package:escanor/features/computers/errors.dart';
import 'package:escanor/features/computers/link.dart';
import 'package:escanor/features/computers/permissions.dart';
import 'package:escanor/features/computers/protocol/client.dart';
import 'package:escanor/features/computers/protocol/failure.dart';
import 'package:escanor/features/computers/protocol/protocol.dart';
import 'package:escanor/features/computers/remote.dart';
import 'package:escanor/features/computers/scan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

ActivityItem a(String at, [String id = 'ui.navigate']) => ActivityItem(at: at, capabilityId: id, caller: 'voice', risk: 'read', outcome: 'ok', ms: 5);

void main() {
  group('activityLabel', () {
    test('names the common actions in plain English', () {
      expect(activityLabel('os.open_url'), 'Opened a website');
      expect(activityLabel('os.open_app'), 'Opened an app');
      expect(activityLabel('system.stats'), 'Checked how busy it is');
      expect(activityLabel('shell.exec'), 'Ran a command');
    });
    test('turns any other id into something readable, never the raw id', () {
      expect(activityLabel('docker.restart_container'), 'Docker: restart container');
      expect(activityLabel('weird'), 'Weird');
      expect(activityLabel(''), 'Something');
    });
  });

  group('mergeActivity', () {
    test('keeps newest first and drops repeats when the first page is refreshed', () {
      final loaded = [a('2026-10-04T10:03:00Z'), a('2026-10-04T10:02:00Z'), a('2026-10-04T10:01:00Z')];
      final fresh = [a('2026-10-04T10:04:00Z'), a('2026-10-04T10:03:00Z')];
      expect(mergeActivity(loaded, fresh).map((x) => x.at.substring(11, 16)), ['10:04', '10:03', '10:02', '10:01']);
    });
    test('appends an older page', () {
      final merged = mergeActivity([a('2026-10-04T10:03:00Z')], [a('2026-10-04T09:00:00Z'), a('2026-10-04T08:00:00Z')]);
      expect(merged.length, 3);
      expect(oldest(merged), '2026-10-04T08:00:00Z');
    });
    test('keeps two different things that happened at the same moment', () {
      expect(mergeActivity([a('2026-10-04T10:00:00Z', 'os.open_url')], [a('2026-10-04T10:00:00Z', 'ui.navigate')]).length, 2);
    });
  });

  group('nextStep', () {
    test('reveals what is already loaded before asking for more', () => expect(nextStep(40, 20, true), NextStep.reveal));
    test('asks the computer for older entries once everything loaded is shown', () => expect(nextStep(40, 40, true), NextStep.fetch));
    test('stops when there is nothing more, and for an older computer that sent it all', () {
      expect(nextStep(40, 40, false), NextStep.done);
      expect(nextStep(40, 40, null), NextStep.done);
    });
  });

  group('retryDelayMs', () {
    test('starts quick, doubles, and settles at 30 seconds', () {
      expect([1, 2, 3, 4, 5, 6, 20].map(retryDelayMs), [3000, 6000, 12000, 24000, 30000, 30000, 30000]);
    });
    test('treats nonsense attempts as the first', () {
      expect(retryDelayMs(0), 3000);
      expect(retryDelayMs(-4), 3000);
    });
  });

  group('shouldShowOffline', () {
    test('forgives one failed request and gives up on the second in a row', () {
      expect(offlineAfterFailures, 2);
      expect(shouldShowOffline(0), isFalse);
      expect(shouldShowOffline(1), isFalse);
      expect(shouldShowOffline(2), isTrue);
    });
  });

  group('offlineMessage', () {
    test('points at the likely cause for the cloud route', () {
      expect(
        offlineMessage(const ComputerError('The computer did not answer. Is it on and online?'), ComputerRoute.cloud),
        contains('Escanor Desktop is open and signed in'),
      );
    });
    test('keeps a sign-in problem as it is', () {
      expect(
        offlineMessage(const ComputerError('Your Escanor session ended. Please sign in again.'), ComputerRoute.cloud),
        'Your Escanor session ended. Please sign in again.',
      );
    });
    test('has something to say when it has nothing', () => expect(offlineMessage(null, null).length, greaterThan(10)));
  });

  group('isRecentlySeen', () {
    final now = DateTime.parse('2026-10-03T12:00:00Z');
    test('counts an online computer, and one heard from within ten minutes', () {
      expect(isRecentlySeen('online', null, now: now), isTrue);
      expect(isRecentlySeen('offline', '2026-10-03T11:55:00Z', now: now), isTrue);
    });
    test('does not count one that went quiet long ago, or has never been heard from', () {
      expect(isRecentlySeen('offline', '2026-10-03T11:40:00Z', now: now), isFalse);
      expect(isRecentlySeen('offline', null, now: now), isFalse);
      expect(isRecentlySeen('offline', 'garbage', now: now), isFalse);
      expect(isRecentlySeen('offline', '2026-10-03T12:30:00Z', now: now), isFalse); // a clock in the future is not "seen"
    });
  });

  const groups = [
    PermissionGroup(id: 'os', label: 'Open apps and websites', about: 'x', enabled: false),
    PermissionGroup(id: 'docker', label: 'Docker', about: 'y', enabled: true),
    PermissionGroup(id: 'shell', label: 'Terminal and commands', about: 'z', enabled: false),
  ];

  group('describeGroupRequest (what to tell the person after they ask)', () {
    test('says where the question appeared and what to do with it', () {
      final m = describeGroupRequest(GroupRequestStatus.asked, 'Open apps and websites');
      expect(m, contains('Escanor Desktop'));
      expect(m, contains('Open apps and websites'));
      expect(m, matches(RegExp('Allow|allow|OK')));
    });
    test('tells you to open Escanor Desktop when it has no window to ask in', () {
      expect(describeGroupRequest(GroupRequestStatus.unavailable, 'Docker'), contains('Open Escanor Desktop'));
    });
    test('covers the other answers plainly', () {
      expect(describeGroupRequest(GroupRequestStatus.alreadyOn, 'Docker'), matches(RegExp('already', caseSensitive: false)));
      expect(describeGroupRequest(GroupRequestStatus.busy, 'Docker'), matches(RegExp('already (been )?asked|waiting', caseSensitive: false)));
      expect(describeGroupRequest(GroupRequestStatus.unknown, 'Docker'), matches(RegExp('does not recognise|not recognise|update', caseSensitive: false)));
    });
    test('reads the wire status words', () {
      expect(groupRequestStatusOf('already_on'), GroupRequestStatus.alreadyOn);
      expect(groupRequestStatusOf('asked'), GroupRequestStatus.asked);
      expect(groupRequestStatusOf('what'), GroupRequestStatus.unknown);
    });
  });

  group('findGroup', () {
    test('matches a label exactly, ignoring case and the curly or straight quotes', () {
      expect(findGroup(groups, 'open apps and websites')?.id, 'os');
      expect(findGroup(groups, ' Docker ')?.id, 'docker');
      expect(findGroup(groups, '“Docker”')?.id, 'docker');
      expect(findGroup(groups, 'Nothing like it'), isNull);
    });
  });

  group('sortGroups', () {
    test('puts what is switched off first, then by name', () => expect(sortGroups(groups).map((g) => g.id), ['os', 'shell', 'docker']));
    test('does not change the list it is given', () {
      final copy = [...groups];
      sortGroups(groups);
      expect(groups, copy);
    });
  });

  group('explainComputerFailure: every error says what happened and WHERE to change it', () {
    test('a permission switched off for phones names the setting, the place on the computer, and offers to ask', () {
      const msg =
          '“Open apps and websites” is turned off for phones. On your computer, open Escanor Desktop, go to Settings, then Permissions, and switch it on in the Phone column.';
      final e = explainComputerFailure(msg);
      expect(e.where, FixWhere.computer);
      expect(e.title, contains('Open apps and websites'));
      expect(e.steps.any((s) => s.contains('Escanor Desktop') && s.contains('Permissions')), isTrue);
      expect(e.askGroupLabel, 'Open apps and websites');
    });
    test('switched off for the voice assistant points at the voice column and does not offer to ask', () {
      final e = explainComputerFailure('“Docker” is turned off for Escanor’s voice assistant.');
      expect(e.title, '“Docker” is switched off for voice');
      expect(e.steps.join(' '), contains('Escanor (voice)'));
      expect(e.askGroupLabel, isNull);
    });
    test('a computer that did not answer is a computer-side problem with its checklist', () {
      final e = explainComputerFailure('The computer did not answer. Is it on and online?');
      expect(e.where, FixWhere.computer);
      expect(e.steps.join(' '), matches(RegExp('open', caseSensitive: false)));
      expect(e.steps.join(' '), contains('Away from home'));
    });
    test('a dead sign-in is a this-app problem', () {
      final e = explainComputerFailure(const ComputerError('Your Escanor session ended. Please sign in again.'));
      expect(e.where, FixWhere.phone);
      expect(e.steps.join(' '), matches(RegExp('Settings|sign in', caseSensitive: false)));
    });
    test('a phone the computer no longer knows must be paired again, on both sides', () {
      final e = explainComputerFailure('Not allowed.');
      expect(e.where, FixWhere.both);
      expect(e.steps.join(' '), contains('Pair a phone'));
    });
    test('an old desktop is told to update the desktop', () {
      final e = explainComputerFailure('This computer’s Escanor Desktop is too old for that. Update Escanor Desktop on the computer, then try again.');
      expect(e.where, FixWhere.computer);
      expect(e.steps.join(' '), contains('Update Escanor Desktop'));
    });
    test('a pairing code that expired says to get a fresh one', () {
      expect(explainComputerFailure('That pairing code has expired. Create a new one on the computer.').title, 'That pairing code did not work');
    });
    test('anything unknown still says something useful and never shows a blank', () {
      for (final raw in <Object?>['', 'boom', null, Exception('weird thing'), StateError('x')]) {
        final e = explainComputerFailure(raw);
        expect(e.title, isNotEmpty);
        expect(FixWhere.values, contains(e.where));
      }
      expect(explainComputerFailure(Exception('weird thing')).title, 'weird thing');
    });
    test('one sentence for the voice assistant names the place', () {
      expect(
        spokenProblem('Not allowed.'),
        'This computer no longer recognises this phone. On your phone and computer: open Escanor Desktop → Phone → Pair a phone.',
      );
    });
  });

  const computer = PairedComputer(id: 'd1', name: 'Work Laptop', key: 'k', lan: ['192.168.1.5:47625'], agentId: 'a1', pairedAt: '2026-10-01T00:00:00Z');

  group('parseComputerPrefs', () {
    test('gives plain defaults for nothing, damage or junk', () {
      for (final raw in [null, '', '{bad', '[]', '"x"', '5']) {
        expect(parseComputerPrefs(raw), const ComputerPrefs(), reason: '$raw');
      }
    });
    test('keeps a valid alias and route, and ignores wrong types field by field', () {
      expect(parseComputerPrefs('{"alias":"Home PC","route":"cloud"}'), const ComputerPrefs(alias: 'Home PC', route: RoutePref.cloud));
      expect(parseComputerPrefs('{"alias":5,"route":"teleport"}'), const ComputerPrefs());
    });
  });

  group('cleanName', () {
    test('trims, collapses spaces and limits the length', () {
      expect(cleanName('  My   laptop  '), 'My laptop');
      expect(cleanName('x' * 100).length, 40);
      expect(cleanName('   '), '');
    });
    test('drops control characters', () => expect(cleanName('Lap\u0000top\n'), 'Laptop'));
  });

  group('displayName', () {
    test('uses the chosen name, else the name the computer gave itself', () {
      expect(displayName(computer, const ComputerPrefs(alias: 'Desk')), 'Desk');
      expect(displayName(computer, const ComputerPrefs()), 'Work Laptop');
    });
  });

  group('applyRoute (the connection preference)', () {
    test('automatic keeps both routes', () {
      final r = applyRoute(computer, RoutePref.auto);
      expect(r.computer, computer);
      expect(r.cloud, isTrue);
    });
    test('cloud only forgets the Wi-Fi addresses for this connection', () {
      final r = applyRoute(computer, RoutePref.cloud);
      expect(r.computer.lan, isEmpty);
      expect(r.cloud, isTrue);
      expect(computer.lan, ['192.168.1.5:47625']); // the stored computer is untouched
    });
    test('Wi-Fi only turns the cloud route off', () {
      expect(applyRoute(computer, RoutePref.lan).cloud, isFalse);
      expect(applyRoute(computer, RoutePref.lan).computer.lan, computer.lan);
    });
  });

  group('classifyScanError', () {
    test('treats the person closing the scanner as a cancel, not an error', () {
      for (final m in ['scan canceled.', 'Scan cancelled', 'User canceled', 'SCAN_CANCELED']) {
        expect(classifyScanError(Exception(m)), ScanFailure.cancelled, reason: m);
      }
    });
    test('recognises a phone that cannot scan here', () {
      for (final m in [
        'Google Barcode Scanner Module is not available.',
        'not implemented on web',
        'ModuleNotInstalled',
        'Google Play services are not available',
      ]) {
        expect(classifyScanError(Exception(m)), ScanFailure.unavailable, reason: m);
      }
      expect(classifyScanError(const MobileScannerException(errorCode: MobileScannerErrorCode.unsupported)), ScanFailure.unavailable);
    });
    test('knows a refused camera permission', () {
      expect(classifyScanError(const MobileScannerException(errorCode: MobileScannerErrorCode.permissionDenied)), ScanFailure.denied);
      expect(cameraProblemText(const MobileScannerException(errorCode: MobileScannerErrorCode.permissionDenied)), contains('phone’s settings'));
    });
    test('calls anything else a failure, whatever shape it comes in', () {
      for (final e in <Object?>[Exception('boom'), 'plain string', null, 7, const MobileScannerException(errorCode: MobileScannerErrorCode.genericError)]) {
        expect(classifyScanError(e), ScanFailure.failed, reason: '$e');
      }
    });
  });

  group('firstQr', () {
    test('takes the first readable value, ignoring empty ones', () => expect(firstQr(['', 'hello', 'later']), 'hello'));
    test('returns null when nothing was read', () {
      for (final r in <List<String?>?>[
        [],
        ['', null],
        null,
      ]) {
        expect(firstQr(r), isNull);
      }
      expect(firstQrOf(null), isNull);
      expect(
        firstQrOf(
          const BarcodeCapture(
            barcodes: [
              Barcode(rawValue: ''),
              Barcode(rawValue: '{"v":1}'),
            ],
          ),
        ),
        '{"v":1}',
      );
    });
  });

  group('retryDelay', () {
    test('waits longer each time, and gives up after three tries', () {
      expect([0, 1, 2, 3, 4].map((n) => retryDelay(n)?.inMilliseconds), [1500, 4000, 9000, null, null]);
    });
  });

  group('withDeadline', () {
    test('passes the answer through when it comes in time', () async => expect(await withDeadline(Future.value(7), const Duration(milliseconds: 50)), 7));
    test('fails with a readable message when it does not', () async {
      await expectLater(withDeadline(Completer<int>().future, const Duration(milliseconds: 10)), throwsA(predicate((e) => '$e'.contains('took too long'))));
    });
    test('passes a failure through unchanged', () async {
      await expectLater(
        withDeadline(Future<int>.error(const ComputerError('nope')), const Duration(milliseconds: 50)),
        throwsA(predicate((e) => '$e' == 'nope')),
      );
    });
  });
}
