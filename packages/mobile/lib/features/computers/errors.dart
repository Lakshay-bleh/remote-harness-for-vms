import 'protocol/failure.dart';

/// Where the fix is: on this phone, on the computer, or on both.
enum FixWhere { phone, computer, both }

class Explained {
  const Explained({required this.title, required this.where, required this.steps, this.askGroupLabel});

  /// What happened, in one line.
  final String title;
  final FixWhere where;

  /// What to do, in order. Each step says which device it is on.
  final List<String> steps;

  /// If the failure is "this is switched off for phones", the group's label: the phone can offer to ask the computer to allow it.
  final String? askGroupLabel;
}

final _off = RegExp(r'^[“"](.+?)[”"] is turned off for (phones|Escanor’s voice assistant)');

/// Turn what failed into: what happened, where to change it (this app or Escanor Desktop), and the steps. No error in the app is
/// allowed to say "enable it in settings" without saying which settings: this is where that is enforced.
Explained explainComputerFailure(Object? raw) {
  final m = failureText(raw).trim();
  bool has(String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(m);

  final off = _off.firstMatch(m);
  if (off != null) {
    final phones = off.group(2) == 'phones';
    final label = off.group(1)!;
    return Explained(
      title: '“$label” is switched off for ${phones ? 'phones' : 'voice'}',
      where: FixWhere.computer,
      steps: [
        'On your computer: open Escanor Desktop → Settings → Permissions.',
        'Find “$label” and switch it on in the ${phones ? 'Phone' : 'Escanor (voice)'} column.',
        'Then try again here.',
      ],
      askGroupLabel: phones ? label : null,
    );
  }

  if (has('too old for that|Update Escanor Desktop')) {
    return const Explained(
      title: 'Your computer’s Escanor Desktop is out of date',
      where: FixWhere.computer,
      steps: ['Update Escanor Desktop on your computer to the latest version, then reopen it.', 'Then try again here.'],
    );
  }

  if (has('session ended|sign in again|not signed in')) {
    return const Explained(title: 'You were signed out of Escanor', where: FixWhere.phone, steps: ['In this app: open Settings → Account and sign in again.']);
  }

  if (m == 'Not allowed.' || has('no longer paired|not paired|revoked|That is not your computer')) {
    return const Explained(
      title: 'This computer no longer recognises this phone',
      where: FixWhere.both,
      steps: [
        'On your computer: open Escanor Desktop → Phone → Pair a phone.',
        'In this app: remove this computer (menu at the top right), then add it again with the new code.',
      ],
    );
  }

  if (has('did not answer|not reachable|could not reach|offline|timed out|not on and online')) {
    return const Explained(
      title: 'Your computer is not answering',
      where: FixWhere.computer,
      steps: [
        'On your computer: make sure Escanor Desktop is open and signed in to the same account.',
        'In Escanor Desktop → Phone: turn on “Away from home”, or be on the same Wi-Fi as this phone.',
        'Then tap Try again here.',
      ],
    );
  }

  if (has('pair|code') && has('expired|not showing|did not match|No pairing')) {
    return const Explained(
      title: 'That pairing code did not work',
      where: FixWhere.computer,
      steps: [
        'On your computer: open Escanor Desktop → Phone → Pair a phone to get a fresh code (it lasts 5 minutes and works once).',
        'In this app: enter the new code.',
      ],
    );
  }

  return Explained(
    title: m.isEmpty ? 'That did not work' : m,
    where: FixWhere.both,
    steps: const ['Try again. If it keeps failing, check that Escanor Desktop is open on your computer and that both are signed in to the same account.'],
  );
}

/// One sentence for the ear (the voice assistant): what is wrong, and where to fix it (this app or the computer).
String spokenProblem(Object? raw) {
  final e = explainComputerFailure(raw);
  final where = switch (e.where) {
    FixWhere.computer => 'On your computer',
    FixWhere.phone => 'In this app',
    FixWhere.both => 'On your phone and computer',
  };
  return '${e.title}. $where: ${e.steps.first.replaceFirst(RegExp(r'^On your computer:\s*', caseSensitive: false), '')}';
}
