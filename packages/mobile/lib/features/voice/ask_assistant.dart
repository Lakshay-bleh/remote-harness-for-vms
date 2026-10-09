import '../../core/api.dart';
import '../assistant/assistant_api.dart';
import '../assistant/chat_state.dart';
import 'assistant_answer.dart';
import 'cancel.dart';

/// Hand a spoken sentence to the Escanor assistant, in the conversation that is open (or a new one), and wait for its answer: the
/// Shell's askAssistant in the web app. POST /ai/chat, then the conversation's messages until it has finished answering.
///
/// [conversationId] is the open conversation (null = a new chat); [setConversation] is told which one the sentence went into, so
/// the Chat tab shows it.
Future<String> askAssistant(
  String text,
  VoiceCancel cancel, {
  required String? conversationId,
  required void Function(String id) setConversation,
  void Function()? onSent,
  AnswerDeps? deps,
  AskBackend? backend,
}) async {
  final b = backend ?? const AskBackend();
  final open = conversationId;
  String id;
  try {
    id = await b.send(text, open);
  } on ApiError catch (e) {
    // The open chat is still answering something earlier: speaking again means "this instead", so stop that and ask again.
    if (!(e.status == 409 && open != null)) rethrow;
    if (!await stopAndSettle(b, open, cancel, wait: deps?.wait)) {
      return 'I’m still finishing your last request in this chat. Open it to follow along, or stop it there.';
    }
    id = await b.send(text, open);
  }
  if (id.isEmpty || id == 'null') throw ApiError('Escanor did not start that conversation. Try again.', 0);
  onSent?.call();
  setConversation(id);
  // Cancelling voice mode stops the turn it started, not only the waiting for it.
  final forget = cancel.onAbort(() => b.stop(id).catchError((_) => false));
  try {
    final a = await waitForAnswer(
      deps ??
          AnswerDeps(
            fetch: (after) => b.messages(id, after),
            wait: (d) => Future<void>.delayed(d),
            now: DateTime.now,
          ),
      text,
      cancel: cancel,
    );
    if (a.needsApproval) return 'I need your OK to go on. Open the chat to approve it.';
    if (a.timedOut) return 'Still working on it. The answer will be in the chat.';
    return a.text;
  } finally {
    forget();
  }
}

/// What [askAssistant] needs from the server, so tests can stand in for it.
class AskBackend {
  const AskBackend();
  Future<String> send(String text, String? conversationId) => api.assistantSend(text, conversationId: conversationId);
  Future<AssistantMessages> messages(String id, int after) => api.assistantMessages(id, after);
  Future<bool> stop(String id) => api.assistantStop(id);
}

/// Stop a conversation's turn and wait (up to ~10 s) for it to end. True when it has.
Future<bool> stopAndSettle(AskBackend b, String id, VoiceCancel cancel, {Future<void> Function(Duration)? wait}) async {
  try {
    await b.stop(id);
  } catch (_) {}
  final pause = wait ?? (d) => Future<void>.delayed(d);
  for (var i = 0; i < 20 && !cancel.aborted; i++) {
    try {
      final m = await b.messages(id, 9007199254740991);
      if (!m.running) return true;
    } catch (_) {}
    await pause(const Duration(milliseconds: 500));
  }
  return false;
}
