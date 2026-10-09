/// Doing what was said, and what to say back. Pure: everything it reaches (the phone, the computer, the assistant, the server) comes
/// in through [AssistantDeps], so it is tested without any of them.
library;

import 'dart:async';

import '../computers/computer_api.dart' show isSwitchedOffReply, spokenProblem;
import 'actions.dart';
import 'commands.dart';
import 'contacts.dart';
import 'server_plan.dart';

class AssistantDeps {
  AssistantDeps({
    required this.device,
    required this.hasComputer,
    required this.toComputer,
    required this.toAssistant,
    required this.go,
    this.phone = const PhoneOptions(),
    this.resolve,
    this.ack,
    this.interim,
    this.openLink,
  });

  /// The phone's native tools; null where there are none.
  final DevicePlugin? device;
  final bool hasComputer;

  /// Run a sentence on the paired computer; resolves with what it said back.
  final Future<String> Function(String text) toComputer;

  /// Hand a sentence to the Escanor assistant; resolves with its answer when it has one (null/empty when it only started working).
  final Future<String?> Function(String text) toAssistant;
  final void Function(VoiceTab tab) go;

  /// How the person wants the phone to behave (calling directly).
  final PhoneOptions phone;

  /// Ask the server's brain what a sentence means and which of this phone's apps it names. Null when it cannot be asked.
  final Future<ServerPlan?> Function(String text)? resolve;

  /// Say something now, while work continues (the short acknowledgement before a task finishes).
  final Future<void> Function(String text)? ack;

  /// Show something on screen now, while work continues.
  final void Function(String text)? interim;

  /// Open a web link where there is no phone plugin.
  final Future<bool> Function(String url)? openLink;
}

enum ReplyKind { phone, computer, assistant, chat, go, stop }

class Reply {
  const Reply({required this.ok, required this.say, this.kind, this.needs, this.ask = false});
  final bool ok;

  /// What to say out loud and show.
  final String say;
  final ReplyKind? kind;

  /// What the person has to turn on to make this work; voice mode shows a button for it.
  final Needs? needs;

  /// The reply is a question: speak it, then listen for the answer.
  final bool ask;

  @override
  bool operator ==(Object other) => other is Reply && other.ok == ok && other.say == say && other.kind == kind && other.needs == needs && other.ask == ask;
  @override
  int get hashCode => Object.hash(ok, say, kind, needs, ask);
  @override
  String toString() => 'Reply(ok: $ok, say: $say, kind: $kind${needs != null ? ', needs: $needs' : ''}${ask ? ', ask' : ''})';
}

const _tabNames = <VoiceTab, String>{
  VoiceTab.assistant: 'Chat',
  VoiceTab.computers: 'Computers',
  VoiceTab.connections: 'Connections',
  VoiceTab.machines: 'Machines',
  VoiceTab.settings: 'Settings',
};

String _orNull(String? s) => (s ?? '').trim();

/// Ask the server about a sentence the phone's own rules did not settle, and do what it says. Returns null when the server has
/// nothing to do on the device (so the caller carries on as before), or could not be reached.
Future<Reply?> _viaServer(String text, AssistantDeps d) async {
  ServerPlan? plan;
  try {
    plan = await d.resolve?.call(text);
  } catch (_) {
    plan = null;
  }
  if (plan == null) return null;
  if (plan.needs == 'clarify' && plan.say.isNotEmpty) return Reply(ok: true, say: plan.say, kind: ReplyKind.phone, ask: true);
  // Small talk or a general question: the server's fast model already answered it.
  if (plan.chat && plan.say.isNotEmpty) return Reply(ok: true, say: plan.say, kind: ReplyKind.chat);
  // A job for the full assistant: say so at once, and let it work while that is being said.
  if (plan.delegate) {
    final work = d.toAssistant(text);
    d.interim?.call(plan.say);
    try {
      final ack = d.ack?.call(plan.say) ?? Future<void>.value();
      await Future.any<void>([ack, work.then((_) {})]);
    } catch (_) {
      // the acknowledgement could not be spoken: the answer still is
    }
    final answer = _orNull(await work);
    return Reply(ok: true, say: answer.isNotEmpty ? answer : (plan.say.isNotEmpty ? plan.say : 'Asking your Escanor assistant.'), kind: ReplyKind.assistant);
  }
  final (:actions, :skipped) = planToActions(plan.actions);
  if (actions.isNotEmpty) {
    final results = <ActionOutcome>[];
    for (final a in actions) {
      results.add(await runPhoneAction(a, d.device, openLink: d.openLink));
    }
    final bad = results.where((r) => !r.ok).firstOrNull;
    return Reply(ok: bad == null, say: bad != null ? bad.say : (plan.say.isNotEmpty ? plan.say : results.first.say), kind: ReplyKind.phone);
  }
  if (skipped > 0) return const Reply(ok: false, say: 'I understood that, but this phone cannot do it yet.', kind: ReplyKind.phone);
  if (plan.source == 'error' && plan.say.isNotEmpty) return Reply(ok: false, say: plan.say, kind: ReplyKind.phone);
  if (plan.say.isNotEmpty && !plan.notDevice) return Reply(ok: false, say: plan.say, kind: ReplyKind.phone); // e.g. "I couldn't find an app called X. Did you mean …?"
  return null;
}

/// Names offered by the last "Did you mean … ?", so the next sentence can answer it. Forgotten after 40 seconds.
({List<String> options, DateTime at})? _pendingChoice;

/// For tests: forget a pending "Did you mean …?".
void resetPendingChoice() => _pendingChoice = null;

final _ordinals = <(RegExp, int)>[
  (RegExp(r'\b(?:first|1st|one)\b'), 0),
  (RegExp(r'\b(?:second|2nd|two)\b'), 1),
  (RegExp(r'\b(?:third|3rd|three)\b'), 2),
];

/// If the person is answering a "Did you mean …?" (by name or "the second one"), the name they chose.
String? _answerToChoice(String text) {
  final pending = _pendingChoice;
  _pendingChoice = null;
  if (pending == null || DateTime.now().difference(pending.at) > const Duration(seconds: 40)) return null;
  final lower = text.toLowerCase();
  for (final (re, i) in _ordinals) {
    if (re.hasMatch(lower) && i < pending.options.length) return pending.options[i];
  }
  final c = chooseContact(text, [for (final name in pending.options) Contact(name: name, numbers: const [])]);
  return c is OneContact ? c.contact.name : null;
}

/// Do what was said. Returns what to say back; never throws, so the voice layer always has something to speak. Every failure names
/// where the fix is.
Future<Reply> handleUtterance(String text, AssistantDeps d) async {
  final chosen = _answerToChoice(text);
  final cmd = chosen != null ? PhoneCommand(Call(chosen)) : parseVoiceCommand(text, VoiceContext(hasComputer: d.hasComputer));
  try {
    switch (cmd) {
      case EmptyCommand():
        return const Reply(ok: false, say: 'I didn’t catch that. Try again.');
      case StopCommand():
        return const Reply(ok: true, say: 'Okay.', kind: ReplyKind.stop);
      case PhoneCommand(:final action):
        final done = await runPhoneAction(action, d.device, options: d.phone, openLink: d.openLink);
        if (done.ask && action is Call) {
          final named = RegExp(r'^Did you mean (.+)\?$').firstMatch(done.say)?[1];
          if (named != null) _pendingChoice = (options: named.split(RegExp(r', | or ')), at: DateTime.now());
        }
        final reply = Reply(ok: done.ok, say: done.say, kind: ReplyKind.phone, needs: done.needs, ask: done.ask);
        // "open <name>" that the phone's own matching could not find: the server may know the app by another name.
        if (!done.ok && action is OpenApp) return (await _viaServer(text, d)) ?? reply;
        return reply;
      case GoCommand(:final tab):
        d.go(tab);
        return Reply(ok: true, say: 'Opening ${_tabNames[tab]}.', kind: ReplyKind.go);
      case NoComputerCommand():
        return const Reply(ok: false, say: 'You have not paired a computer yet. Open Computers in this app, then add one with the code from Escanor Desktop.');
      case ComputerCommand(text: final said):
        String answer;
        try {
          answer = await d.toComputer(said);
        } catch (e) {
          return Reply(ok: false, say: spokenProblem(e));
        }
        // A reply that is really "that is switched off" is a problem with a fix, not an answer.
        if (isSwitchedOffReply(answer)) return Reply(ok: false, say: spokenProblem(answer), kind: ReplyKind.computer);
        return Reply(ok: true, say: answer.isNotEmpty ? answer : 'Done.', kind: ReplyKind.computer);
      case AssistantCommand(text: final said):
        final served = await _viaServer(text, d);
        if (served != null) return served;
        final answer = _orNull(await d.toAssistant(said));
        return Reply(ok: true, say: answer.isNotEmpty ? answer : 'Asking your Escanor assistant.', kind: ReplyKind.assistant);
    }
  } catch (e) {
    return Reply(ok: false, say: spokenProblem(e));
  }
}
