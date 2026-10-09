/// Waiting for the Escanor assistant to answer a sentence sent by voice, and turning the answer into something to read aloud. Pure.
library;

import 'package:collection/collection.dart';

import '../assistant/chat_state.dart';
import 'cancel.dart';

class AnswerDeps {
  AnswerDeps({required this.fetch, required this.wait, required this.now});

  /// The conversation's messages after message id `after` (GET /ai/conversations/{id}/messages?after=).
  final Future<AssistantMessages> Function(int after) fetch;
  final Future<void> Function(Duration d) wait;
  final DateTime Function() now;
}

/// What the assistant said back to the sentence just sent: its words, or why there are none yet.
class Answer {
  const Answer({required this.text, required this.needsApproval, required this.timedOut});
  final String text;

  /// It stopped to ask the person for an OK, which can only be given in the chat.
  final bool needsApproval;
  final bool timedOut;

  @override
  bool operator ==(Object other) => other is Answer && other.text == text && other.needsApproval == needsApproval && other.timedOut == timedOut;
  @override
  int get hashCode => Object.hash(text, needsApproval, timedOut);
  @override
  String toString() => 'Answer($text, needsApproval: $needsApproval, timedOut: $timedOut)';
}

/// After a sentence is sent to the assistant, wait until it has finished answering that sentence and return what it said. Looks for
/// the person's own sentence first (so an earlier answer in the same conversation is never mistaken for the new one), then waits
/// for the assistant to stop working.
Future<Answer> waitForAnswer(AnswerDeps deps, String sent, {Duration timeout = const Duration(seconds: 90), VoiceCancel? cancel}) async {
  final until = deps.now().add(timeout);
  var state = emptyChat;
  while (deps.now().isBefore(until) && !(cancel?.aborted ?? false)) {
    try {
      state = applyMessages(state, await deps.fetch(state.lastId));
    } catch (_) {
      // a blip: look again
    }
    final blocks = toDisplay(state);
    var at = -1;
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].type == BlockType.user && blocks[i].text.trim() == sent.trim()) at = i;
    }
    if (at >= 0) {
      final after = blocks.sublist(at + 1);
      if (after.any((b) => b.type == BlockType.approval)) return const Answer(text: '', needsApproval: true, timedOut: false);
      final words = after.where((b) => b.type == BlockType.assistant || b.type == BlockType.error).map((b) => b.text).join('\n\n').trim();
      if (words.isNotEmpty && !state.running && !isThinking(state)) return Answer(text: words, needsApproval: false, timedOut: false);
      // Ended with no words, only a note about the turn ("Stopped."): that is the answer, not a reason to wait on.
      final note = after.lastWhereOrNull((b) => b.type == BlockType.notice);
      if (note != null && !state.running) return Answer(text: note.text, needsApproval: false, timedOut: false);
    }
    await deps.wait(const Duration(milliseconds: 1200));
  }
  return Answer(text: '', needsApproval: false, timedOut: !(cancel?.aborted ?? false));
}

/// Markdown and code are for the eye: leave them out of what is read aloud, and keep it short enough to listen to.
String forSpeech(String markdown, [int maxChars = 420]) {
  final plain = markdown
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' (some code) ')
      .replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m[1]!)
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'[*_~|]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (plain.length <= maxChars) return plain;
  final cut = plain.substring(0, maxChars);
  final end = [cut.lastIndexOf('. '), cut.lastIndexOf('! '), cut.lastIndexOf('? ')].reduce((a, b) => a > b ? a : b);
  return '${end > maxChars / 2 ? cut.substring(0, end + 1) : cut.replaceFirst(RegExp(r'\s+\S*$'), '')} The rest is in the chat.';
}
