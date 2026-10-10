import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/api.dart';
import '../../core/prefs.dart' show currentPrefs;
import '../machines/autonomy.dart';
import '../composer/attachments.dart';
import 'assistant_api.dart';
import 'chat_state.dart';

/// What [Conversation] needs from the server, so tests can stand in for it.
abstract class ConversationBackend {
  Future<AssistantMessages> messages(String id, int after);
  Future<String> send(String text, String? conversationId, List<ApiAttachment> attachments, {String? model});
  Future<void> answer(String id, String requestId, bool allow);

  /// Stop the turn. False when it had already finished (the poll shows the ending either way).
  Future<bool> stop(String id);
}

class ApiConversationBackend implements ConversationBackend {
  const ApiConversationBackend();
  @override
  Future<AssistantMessages> messages(String id, int after) => api.assistantMessages(id, after);
  @override
  Future<String> send(String text, String? conversationId, List<ApiAttachment> attachments, {String? model}) =>
      api.assistantSend(text, conversationId: conversationId, attachments: attachments, model: model);
  @override
  Future<void> answer(String id, String requestId, bool allow) => api.assistantAnswer(id, requestId, allow);
  @override
  Future<bool> stop(String id) => api.assistantStop(id);
}

/// The first message of a new chat, while the server has not yet said which conversation it made: a Stop pressed now is kept here.
class _Creating {
  bool stop = false;
}

/// One conversation: what has been said, whether the assistant is working, and how to talk to it (the web app's
/// `useConversation`). Polls quickly while the assistant works and patiently otherwise; a stop works mid-run (even before the new
/// chat has an id), a stop the server does not act on can be sent again, and a server that stops answering is reported.
class Conversation extends ChangeNotifier {
  Conversation({String? id, required this.onCreated, ConversationBackend? backend, int Function()? now})
      : _backend = backend ?? const ApiConversationBackend(),
        _now = now ?? _wallClock {
    _id = id;
    if (id != null) _poll();
  }

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  final ConversationBackend _backend;
  final int Function() _now;

  /// Called once the server has made the new conversation a first message started.
  void Function(String id) onCreated;

  String? _id;
  String? get id => _id;

  ChatState state = emptyChat;

  // What the person did that failed (send, stop, answer), kept until they do something else; polls never clear it.
  String? _error;
  // Polls that keep failing: said once, cleared by the next one that works.
  bool _unreachable = false;
  StopPhase _stopPhase = StopPhase.idle;
  bool _stuck = false;
  _Creating? _creating;

  Timer? _timer;
  int _generation = 0;
  int? _inFlight; // the generation whose poll is on its way
  bool _again = false;
  int _failures = 0;
  bool _disposed = false;

  /// What to tell the person: what they did that failed, a stop that is not taking, or a server that cannot be reached.
  String? get error =>
      _error ??
      (_stuck
          ? 'It is taking a long time to stop. You can send a new message, or try Stop again.'
          : _unreachable
              ? 'Can’t reach your assistant. Retrying…'
              : null);

  /// A stop is on its way (or queued until the chat has an id): the stop button shows it is working.
  bool get stopping => _stopPhase.kind != StopKind.idle && state.running && !_stuck;

  /// Send stays usable while a turn looks lost (a stop the server did not act on, or a server that stopped answering).
  bool get canSend => canSendNow(state, stuck: _stuck, unreachable: _unreachable);

  StopPhase get stopPhase => _stopPhase;

  /// Show another conversation (null = a new chat). Switching starts from nothing: a cursor from the previous one would hide
  /// this one's history. The conversation this one just created is not a switch: the message and a stop pressed stay.
  void open(String? id) {
    if (id == _id) return;
    _generation++;
    _timer?.cancel();
    _id = id;
    state = emptyChat;
    _error = null;
    _unreachable = false;
    _stopPhase = StopPhase.idle;
    _stuck = false;
    _failures = 0;
    _again = false;
    _creating = null;
    _notify();
    if (id != null) _poll();
  }

  Future<void> _poll() async {
    final id = _id;
    if (id == null || _disposed) return;
    final gen = _generation;
    if (_inFlight == gen) {
      _again = true;
      return;
    }
    _timer?.cancel();
    _inFlight = gen;
    try {
      final res = await _backend.messages(id, state.lastId);
      if (_disposed || gen != _generation) return;
      state = applyMessages(state, res);
      _answerOwnApprovals();
      _failures = 0;
      _unreachable = false;
      final s = stopStatus(_stopPhase, state.running, _now());
      _stopPhase = s.phase;
      _stuck = s.stuck;
      _notify();
    } on SessionEnded {
      return; // the session notifier already sent the person to sign-in
    } catch (_) {
      if (_disposed || gen != _generation) return;
      _failures++;
      if (_failures >= pollFailuresToReport && !_unreachable) {
        _unreachable = true;
        _notify();
      }
    } finally {
      if (_inFlight == gen) _inFlight = null;
    }
    if (_disposed || gen != _generation) return;
    // Failing: back off a little each time, but never give up (the server or the network comes back on its own).
    final base = pollDelayMs(state);
    final delay = _again
        ? 0
        : _failures > 0
            ? math.min(8000, base * (1 << math.min(_failures, 4)))
            : base;
    _again = false;
    _timer = Timer(Duration(milliseconds: delay), _poll);
  }

  /// Ask for news now instead of at the next tick (after a stop, so it shows at once).
  void _pollNow() {
    if (_disposed || _id == null) return;
    _timer?.cancel();
    _poll();
  }

  /// Ask again soon (the person just did something).
  void _pollSoon() {
    if (_disposed || _id == null) return;
    _timer?.cancel();
    final gen = _generation;
    _timer = Timer(const Duration(milliseconds: 400), () {
      if (gen == _generation) _poll();
    });
  }

  Future<void> _sendStop(String conversationId) async {
    if (_id == conversationId) {
      _stopPhase = StopPhase.sending;
      _notify();
    }
    try {
      await _backend.stop(conversationId);
      if (_disposed || _id != conversationId) return;
      // `false` means it had already finished: the poll shows the ending either way.
      _stopPhase = StopPhase.sent(_now());
      _notify();
      _pollNow();
    } on SessionEnded {
      return;
    } catch (e) {
      if (_disposed || _id != conversationId) return;
      _stopPhase = StopPhase.idle;
      _error = 'Could not stop it. ${errorText(e, 'Try again.')}';
      _notify();
    }
  }

  /// The model to answer with (null or Auto: Escanor picks for each message).
  String? model;

  Future<void> send(String text, [List<Attachment> attachments = const []]) async {
    final clean = text.trim();
    if (clean.isEmpty && attachments.isEmpty) return;
    _error = null;
    _stopPhase = StopPhase.idle;
    _stuck = false;
    state = addOptimisticMessage(state, withAttachmentNote(clean, attachments));
    _notify();
    final gen = _generation;
    final making = _id == null ? _Creating() : null;
    if (making != null) _creating = making;
    try {
      final cid = await _backend.send(clean, _id, toApi(attachments), model: model);
      if (_disposed || gen != _generation) return;
      if (_id == null) {
        _id = cid;
        onCreated(cid);
      }
      // Stop was pressed before there was a conversation to stop: stop it now that there is.
      if (making != null && making.stop) {
        unawaited(_sendStop(cid));
      } else {
        _pollSoon();
      }
    } on SessionEnded {
      return;
    } catch (e) {
      if (_disposed || gen != _generation) return;
      state = dropOptimisticMessages(state);
      _stopPhase = StopPhase.idle;
      _error = errorText(e, 'Could not send that.');
      _notify();
    } finally {
      if (making != null && identical(_creating, making)) _creating = null;
    }
  }

  final Set<String> _autoAnswered = {};

  /// Escanor works on its own: when the person has not asked to be consulted, it says yes to what the assistant asks to go ahead with,
  /// except what the server marks high risk or what cannot be taken back. Those wait for the person, as they always did.
  void _answerOwnApprovals() {
    bool autonomous;
    try {
      autonomous = isAutonomousMode(currentPrefs().defaultMode);
    } catch (_) {
      autonomous = false; // storage not ready (tests): ask the person
    }
    if (!autonomous) return;
    for (final item in state.items) {
      if (item.kind != 'approval' || item.status != 'pending' || item.requestId.isEmpty || _autoAnswered.contains(item.requestId)) continue;
      final v = decideApprovalText('${item.title}\n${item.detail}\n${item.raw}', risk: item.risk);
      if (!v.allow) continue;
      _autoAnswered.add(item.requestId);
      unawaited(answer(item.requestId, true));
    }
  }

  Future<void> answer(String requestId, bool allow) async {
    final id = _id;
    if (id == null) return;
    state = markAnswered(state, requestId, allow);
    _notify();
    try {
      await _backend.answer(id, requestId, allow);
      _pollSoon();
    } on SessionEnded {
      return;
    } catch (e) {
      if (_disposed) return;
      _error = errorText(e, 'Could not send your answer.');
      _notify();
    }
  }

  /// Stop the turn: sent now, or (a new chat the server has not named yet) the moment it has an id. Pressing again does not send
  /// twice, except for a stop the server took but did not act on.
  Future<void> stop() async {
    final r = pressStop(_stopPhase, _id != null, _stuck);
    if (r.phase == _stopPhase) return;
    _error = null;
    _stuck = false;
    final id = _id;
    if (r.send && id != null) return _sendStop(id);
    _creating?.stop = true;
    _stopPhase = r.phase;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
