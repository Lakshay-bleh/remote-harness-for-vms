import 'group_messages.dart' show asMap, normalizeBlocks;
import 'protocol.dart';

/// Autonomous chats: Escanor is told the work and does it. It answers its own permission prompts (except for a short list of things
/// that cannot be taken back), checks its own work, fixes what failed and goes again until the work is done, and only stops when it is
/// done, truly stuck, or the person says Stop.
///
/// Everything here is pure (no I/O, no Flutter), so what matters is tested: what is refused, and when it goes round again.

/// Marks the instructions Escanor adds to what you typed, and the nudges it sends itself. Chat hides both.
const autoMarker = '[escanor:auto]';

const doneMarker = 'ESCANOR_DONE';
const blockedMarker = 'ESCANOR_BLOCKED';

/// How many times Escanor goes round again by itself after one request.
const maxAutoRounds = 8;

/// The modes that work on their own. (Bypass asks for nothing either, so the loop applies there too.)
bool isAutonomousMode(String mode) => mode == 'auto' || mode == 'bypassPermissions';

const autonomyBrief = '''$autoMarker
You are working autonomously. Do not ask me questions or for permission: make sensible decisions yourself and carry on. Do the work, then check it yourself: run the tests, read the logs, look at the actual output. If anything fails or the goal is not fully met, fix it and check again, and repeat until it works. When the work is done and verified, end your final message with a line "$doneMarker: <one-line summary>". If it is truly impossible, end with "$blockedMarker: <why>". Never delete data, force-push, spend money or change who has access unless you were told to.''';

/// What the person typed, with the standing instructions added for the machine.
String withAutonomyBrief(String typed) => '${typed.trimRight()}\n\n$autonomyBrief';

/// What the person typed, without what was added to it (for showing in the chat). Null when the whole message was Escanor's own nudge.
String? shownUserText(String text) {
  final at = text.indexOf(autoMarker);
  if (at < 0) return text;
  final typed = text.substring(0, at).trim();
  return typed.isEmpty ? null : typed;
}

// ---------------------------------------------------------------------------------------------- answering prompts

class Verdict {
  const Verdict.allow() : allow = true, reason = '';
  const Verdict.deny(this.reason) : allow = false;
  final bool allow;
  final String reason;
}

final _rm = RegExp(r'\brm\s+(?:-[a-zA-Z]*[rRfF][a-zA-Z]*\s+)+(?:--no-preserve-root\s+)?(?:"?/"?|"?/\*"?|"?~/?"?|"?\$HOME/?"?|"?/(?:home|root|etc|usr|var|boot|bin|lib|opt)/?"?)(?:\s|$|;|&|\|)');

final List<(RegExp, String)> _blockedCommands = [
  (_rm, 'wipes the machine or a home folder'),
  (RegExp(r'\bmkfs(\.\w+)?\b'), 'formats a disk'),
  (RegExp(r'\bdd\b[^\n|;&]*\bof=/dev/'), 'writes straight onto a disk'),
  (RegExp(r'>\s*/dev/(?:sd|nvme|vd|xvd|hd)\w*'), 'writes straight onto a disk'),
  (RegExp(r':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:'), 'a fork bomb'),
  (RegExp(r'\bchmod\s+(?:-\w+\s+)*[0-7]*777\s+/(?:\s|$)'), 'opens up every file on the machine'),
  (RegExp(r'\b(?:shutdown|poweroff|halt)\b|\breboot\b'), 'turns the machine off'),
  (RegExp(r'\bgit\s+push\b[^\n;&|]*(?:--force\b|--force-with-lease\b|\s-f\b)[^\n;&|]*\b(?:main|master|production|prod|release)\b'), 'force-pushes over a main branch'),
  (RegExp(r'\bgit\s+push\b[^\n;&|]*\b(?:main|master|production|prod|release)\b[^\n;&|]*(?:--force\b|--force-with-lease\b|\s-f\b)'), 'force-pushes over a main branch'),
  (RegExp(r'\bdrop\s+(?:database|schema)\b', caseSensitive: false), 'drops a whole database'),
  (RegExp(r'\btruncate\s+table\b', caseSensitive: false), 'empties a table'),
  (RegExp(r'\b(?:userdel|deluser|passwd\s+-d)\b'), 'changes who can log in'),
  (RegExp(r'\biptables\s+-F\b|\bufw\s+disable\b'), 'turns the firewall off'),
];

final List<(RegExp, String)> _blockedPaths = [
  (RegExp(r'^/(?:etc/(?:shadow|sudoers|passwd|ssh/sshd_config)|boot/|dev/|proc/|sys/)'), 'a system file'),
  (RegExp(r'(?:^|/)\.ssh/(?:authorized_keys|id_[a-z0-9]+)$'), 'who can log in'),
];

/// Would an autonomous chat say yes to this? Almost always: the work is what it is there for. The exceptions are things that
/// cannot be undone or that hand the machine to someone else. A "no" is passed to Claude, which then finds another way.
Verdict decideAutonomously(String tool, Map<String, dynamic> input) {
  if (tool == 'AskUserQuestion') {
    // Nobody is there to answer: turn it back into Claude's own decision.
    return const Verdict.deny('Do not ask. Decide yourself and carry on.');
  }
  if (tool == 'Bash') {
    final command = '${input['command'] ?? ''}';
    for (final (re, why) in _blockedCommands) {
      if (re.hasMatch(command)) return Verdict.deny('That $why.');
    }
    return const Verdict.allow();
  }
  if (tool == 'Write' || tool == 'Edit' || tool == 'MultiEdit' || tool == 'NotebookEdit') {
    final path = '${input['file_path'] ?? input['notebook_path'] ?? ''}';
    for (final (re, why) in _blockedPaths) {
      if (re.hasMatch(path)) return Verdict.deny('That changes $why.');
    }
  }
  return const Verdict.allow();
}

/// The same question for an approval the assistant on the Chat tab shows as text (its title, detail and the raw command), where there
/// is no tool name to look at. [risk] is what the server itself called it: anything it marks high waits for the person.
Verdict decideApprovalText(String text, {String risk = 'normal'}) {
  if (risk == 'high') return const Verdict.deny('The server marked this as high risk.');
  for (final (re, why) in _blockedCommands) {
    if (re.hasMatch(text)) return Verdict.deny('That $why.');
  }
  return const Verdict.allow();
}

// ---------------------------------------------------------------------------------------------- going round again

class Nudge {
  const Nudge(this.reason, this.text);

  /// error | unfinished | asked
  final String reason;
  final String text;
}

String _nudgeText(String lead) =>
    '$autoMarker\n$lead Check the logs and the actual results yourself. If anything failed or the goal is not fully met, fix it and try again. '
    'Do not ask me anything: decide yourself. When it is done and verified, end with "$doneMarker: <summary>"; if it is truly impossible, end with "$blockedMarker: <why>".';

bool _truthy(Object? v) => v != null && v != false && v != '' && v != 0;

/// Look at the chat after a turn ended and say whether Escanor should go round once more by itself. Null: it is done, stuck, stopped,
/// or has gone round enough. [halted] is set when the person pressed Stop.
Nudge? nextNudge(List<MessageDto> rows, {required int rounds, required bool halted, int maxRounds = maxAutoRounds}) {
  if (halted || rounds >= maxRounds || rows.isEmpty) return null;

  // The turn is whatever came after the latest prompt (typed by the person, or one of our own nudges).
  var start = -1;
  for (var i = rows.length - 1; i >= 0; i--) {
    final m = rows[i].message;
    if (m is Map && m['type'] == 'user' && _truthy(m['local'])) {
      start = i;
      break;
    }
  }
  if (start < 0) return null;
  final turn = rows.sublist(start + 1);
  if (turn.isEmpty) return null;

  // The turn has ended only if its last row is the result (a still-running turn is not ours to judge).
  final last = turn.last.message;
  if (last is! Map || last['type'] != 'result') return null;
  final result = asMap(last);
  final subtype = '${result['subtype'] ?? ''}';

  var toolsUsed = false;
  String lastText = '';
  for (final row in turn) {
    final m = row.message;
    if (m is! Map || m['type'] != 'assistant' || _truthy(m['parent_tool_use_id'])) continue;
    final inner = m['message'];
    for (final b in normalizeBlocks(inner is Map ? inner['content'] : null)) {
      if (b['type'] == 'tool_use') toolsUsed = true;
      if (b['type'] == 'text' && '${b['text'] ?? ''}'.trim().isNotEmpty) lastText = '${b['text']}';
    }
  }
  final said = '$lastText\n${result['result'] ?? ''}';
  if (said.contains(doneMarker) || said.contains(blockedMarker)) return null;

  // Interrupted (here or elsewhere): the person wants it to stop.
  if (subtype == 'error_during_execution') return null;
  final failed = _truthy(result['is_error']) || subtype.startsWith('error');
  if (failed) return Nudge('error', _nudgeText('That stopped with an error.'));
  if (toolsUsed) return Nudge('unfinished', _nudgeText('You did some work but have not said it is finished.'));
  // A task that was answered with a question gets one nudge to decide for itself. A greeting or a short question is just a chat.
  var typed = '';
  final promptMessage = rows[start].message;
  if (promptMessage is Map) {
    final inner = promptMessage['message'];
    for (final b in normalizeBlocks(inner is Map ? inner['content'] : null)) {
      if (b['type'] == 'text' && b['text'] is String) typed += shownUserText(b['text'] as String) ?? '';
    }
  }
  if (rounds == 0 && typed.trim().length >= 25 && lastText.trimRight().endsWith('?')) {
    return Nudge('asked', _nudgeText('You asked me something; I am not available, so decide yourself.'));
  }
  return null;
}

/// "Round 2 of 8" for the chat header.
String roundsText(int rounds) => rounds <= 0 ? '' : 'Checking its work · round ${rounds + 1} of ${maxAutoRounds + 1}';
