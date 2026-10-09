import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/chat_parts.dart';
import '../../ui/widgets.dart';
import '../composer/attachments.dart';
import '../companion/companion_floor.dart';
import '../composer/chat_composer.dart';
import 'chat_store.dart';
import 'error_card.dart';
import 'errors.dart';
import 'protocol/failure.dart';
import 'protocol/protocol.dart';

typedef ComputerRequest = Future<List<Msg>> Function(Msg msg);

/// A chat's text goes to the computer in one message; this is the most it accepts.
const maxChatChars = 4000;
const _suggestions = ['What is using my memory?', 'Show my containers', 'Volume up', 'Open YouTube'];

/// Which chat each computer's assistant is currently holding in mind, so a different one starts over instead of mixing two.
final Map<String, String> _served = {};

final _rand = Random();
String _uid() => List.generate(8, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[_rand.nextInt(36)]).join();

/// The message and any text files, as one body for the computer, or null when that is more than it takes.
/// (The same as the composer's `inlineText`, kept here so this screen does not depend on when that lands.)
String? inlineChatText(String message, List<Attachment> list, int maxChars) {
  final parts = [
    message.trim(),
    for (final a in list)
      if (a.kind == AttachmentKind.text) '[${a.name}]\n${a.text ?? ''}',
  ].where((p) => p.isNotEmpty).toList();
  final out = parts.join('\n\n');
  return out.length <= maxChars ? out : null;
}

/// The chat's own buttons (history, new chat), shown in the section bar above so no row of their own takes space.
class ChatActions extends ChangeNotifier {
  VoidCallback? _history;
  VoidCallback? _newChat;
  bool _canNew = false;

  /// There is something to start over from (the open chat has messages).
  bool get canNew => _canNew;
  bool get ready => _history != null;
  void history() => _history?.call();
  void newChat() => _newChat?.call();

  void _set(VoidCallback? history, VoidCallback? newChat, bool canNew) {
    final changed = _canNew != canNew || (_history == null) != (history == null);
    _history = history;
    _newChat = newChat;
    _canNew = canNew;
    if (changed) notifyListeners();
  }
}

/// Talking to the assistant on one computer. Every chat is kept on the phone, so closing the app or leaving the tab never loses one,
/// and earlier chats are a tap away in the history list.
class ComputerChat extends StatefulWidget {
  const ComputerChat({super.key, required this.computerId, required this.request, required this.online, required this.onAsk, this.actions});
  final String computerId;
  final ComputerRequest request;
  final bool online;
  final Future<String> Function(String groupLabel) onAsk;
  final ChatActions? actions;

  @override
  State<ComputerChat> createState() => _ComputerChatState();
}

class _ComputerChatState extends State<ComputerChat> {
  late List<Chat> _chats = loadChats(widget.computerId);

  // The chat on screen is chosen by id. A chat with no messages yet is a draft: it exists only here, not in the saved list.
  late String _activeId;
  Chat? _draft;

  /// Which chats the computer is still working on (since when): a reply belongs to the chat it was asked in, wherever the person
  /// has gone since.
  final Map<String, int> _working = {};

  /// The request each chat is waiting on. Stop (or deleting the chat) forgets it, so a late reply is dropped instead of landing.
  final Map<String, String> _asked = {};

  @override
  void initState() {
    super.initState();
    if (_chats.isNotEmpty) {
      _activeId = _chats.first.id;
    } else {
      _draft = newChat();
      _activeId = _draft!.id;
    }
    _publishActions();
  }

  @override
  void dispose() {
    widget.actions?._set(null, null, false);
    super.dispose();
  }

  Chat get _chat {
    for (final c in _chats) {
      if (c.id == _activeId) return c;
    }
    final d = _draft;
    if (d != null && d.id == _activeId) return d;
    return _draft ??= newChat();
  }

  bool get _busy => _working.containsKey(_chat.id);

  void _publishActions() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) widget.actions?._set(_openHistory, _startNew, _chat.turns.isNotEmpty);
  });

  /// Change one chat by id, wherever it is (the list, or the draft that has not been saved yet), and save the list.
  void _change(String id, Chat Function(Chat c) edit) {
    Chat? listed;
    for (final c in _chats) {
      if (c.id == id) listed = c;
    }
    final base = listed ?? (_draft != null && _draft!.id == id ? _draft! : newChat().copyWith(id: id));
    final next = upsert(_chats, edit(base));
    if (listed == null) _draft = null;
    _chats = next;
    saveChats(widget.computerId, next);
    if (mounted) setState(() {});
    _publishActions();
  }

  Future<void> _send(String message, List<Attachment> files) async {
    final id = _chat.id;
    if (_working.containsKey(id) || !widget.online) return;
    final names = [for (final f in files) f.name];
    final body = inlineChatText(message, files, maxChatChars);
    final now = DateTime.now().millisecondsSinceEpoch;
    _change(
      id,
      (c) => addTurn(c, Turn(who: Who.you, text: message.trim().isNotEmpty ? message : '(${names.join(', ')})', files: names.isEmpty ? null : names, at: now)),
    );
    if (body == null) {
      _change(
        id,
        (c) => addTurn(
          c,
          Turn(
            who: Who.computer,
            text:
                'That is too long for this computer to take in one message (the limit is ${NumberFormat.decimalPattern('en').format(maxChatChars)} characters). Attach a smaller file, or part of it.',
            problem: true,
            at: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      return;
    }
    setState(() => _working[id] = now);
    final fresh = _served[widget.computerId] != id; // the assistant on the computer is holding a different conversation in mind
    final ask = _uid();
    _asked[id] = ask;
    Turn turn;
    try {
      final out = await widget.request(ClientMsg.chat(ask, body, fresh: fresh));
      _served[widget.computerId] = id;
      final reply = firstOf(out, const {'reply', 'error'});
      final said = reply == null ? 'Done.' : (reply['t'] == 'reply' ? '${reply['reply'] ?? ''}' : '${reply['message'] ?? ''}');
      // A reply that is really "that is switched off" (or any other error in words) is shown as an explained error with its fix.
      turn = Turn(
        who: Who.computer,
        text: said,
        problem: reply?['t'] == 'error' || explainComputerFailure(said).askGroupLabel != null,
        at: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      final text = failureText(e);
      turn = Turn(who: Who.computer, text: text.isEmpty ? 'That did not work.' : text, problem: true, at: DateTime.now().millisecondsSinceEpoch);
    }
    // Stopped, or the chat was deleted while the computer worked: the answer has nowhere to go (and must not bring the chat back).
    if (_asked[id] != ask) return;
    _asked.remove(id);
    if (_chats.any((c) => c.id == id)) _change(id, (c) => addTurn(c, turn)); // into the chat it was asked in, even if another is open now
    _working.remove(id);
    if (mounted) setState(() {});
  }

  /// Stop waiting on the computer for this chat. The computer may still finish the job; its answer is not shown.
  void _stopWaiting(String id) {
    if (_asked.remove(id) == null) return;
    _working.remove(id);
    _change(id, (c) => addTurn(c, Turn(who: Who.computer, text: 'Stopped waiting. The computer may still finish what it was doing.', at: DateTime.now().millisecondsSinceEpoch)));
    if (mounted) setState(() {});
  }

  void _deleteChat(Chat c) {
    _asked.remove(c.id);
    _working.remove(c.id);
    final next = removeChat(_chats, c.id);
    setState(() => _chats = next);
    saveChats(widget.computerId, next);
    if (c.id == _activeId) _startNew();
  }

  void _open(Chat c) {
    setState(() => _activeId = c.id);
    _publishActions();
  }

  void _startNew() {
    final fresh = newChat();
    setState(() {
      _draft = fresh;
      _activeId = fresh.id;
    });
    _publishActions();
  }

  void _openHistory() {
    haptic();
    showESheet<void>(
      context,
      title: 'Chats with this computer',
      builder: (ctx) => _History(
        chats: () => _chats,
        activeId: () => _activeId,
        onOpen: (c) {
          Navigator.of(ctx).pop();
          _open(c);
        },
        onNew: () {
          Navigator.of(ctx).pop();
          _startNew();
        },
        onDelete: _deleteChat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final busy = _busy;
    return Column(
      children: [
        Expanded(
          child: ChatMessageList(
            empty: ChatEmptyState(
              scene: 'lick',
              title: 'Say something, I’m listening',
              text: 'Ask your computer to do anything. It runs on its own hardware; you just see the result.',
              suggestions: _suggestions,
              onPick: !widget.online || busy ? null : (s) => _send(s, const []),
            ),
            children: [
              for (final t in chat.turns)
                Padding(
                  padding: const EdgeInsets.only(top: chatGap),
                  child: t.problem
                      ? FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: 0.94, child: ErrorCard(error: t.text, onAsk: widget.onAsk))
                      : t.who == Who.you
                          ? UserBubble(text: t.text, note: t.files == null || t.files!.isEmpty ? null : 'Attached: ${t.files!.join(', ')}')
                          : AnswerText(t.text),
                ),
              if (busy)
                Padding(
                  padding: const EdgeInsets.only(top: chatGap),
                  child: WorkingLine(
                    text: 'Working on your computer',
                    startedAtMs: _working[chat.id],
                    slowHint: 'Still going. Bigger jobs take a while, and the cloud route adds a moment each way.',
                  ),
                ),
            ],
          ),
        ),
        CompanionFloor(
          child: ChatBottom(
            composer: ChatComposer(
              key: ValueKey(chat.id),
              placeholder: widget.online ? 'Message your computer' : 'Computer offline',
              disabled: !widget.online,
              running: busy,
              attach: 'text',
              onSend: (t, f) => _send(t, f),
              onStop: () => _stopWaiting(chat.id),
            ),
          ),
        ),
      ],
    );
  }
}

class _History extends StatefulWidget {
  const _History({required this.chats, required this.activeId, required this.onOpen, required this.onNew, required this.onDelete});
  final List<Chat> Function() chats;
  final String Function() activeId;
  final void Function(Chat c) onOpen;
  final VoidCallback onNew;
  final void Function(Chat c) onDelete;
  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final chats = widget.chats();
    final rows = <Widget>[];
    for (final (i, chat) in chats.indexed) {
      if (i == 0 || dayLabel(chats[i - 1].updatedAt) != dayLabel(chat.updatedAt)) {
        rows.add(
          Container(
            width: double.infinity,
            color: c.surfaceSoft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(
              dayLabel(chat.updatedAt).toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.6, color: c.muted),
            ),
          ),
        );
      } else {
        rows.add(Divider(height: 1, color: c.hairline));
      }
      final last = chat.turns.isEmpty ? '' : chat.turns.last.text;
      rows.add(
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => widget.onOpen(chat),
                child: Container(
                  color: chat.id == widget.activeId() ? c.surfaceCard : null,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: c.ink),
                      ),
                      Text(
                        '${chat.turns.length} message${chat.turns.length == 1 ? '' : 's'} · ${last.length > 40 ? last.substring(0, 40) : last}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete ${chat.title}',
              icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.muted),
              onPressed: () {
                widget.onDelete(chat);
                setState(() {});
              },
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.xl),
            side: BorderSide(color: c.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onNew,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.edit_note_rounded, size: 20, color: c.primary),
                  const SizedBox(width: 12),
                  Text('New chat', style: TextStyle(fontSize: 15, color: c.ink)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (chats.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Your chats with this computer will be listed here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: c.hairline),
              borderRadius: BorderRadius.circular(Radii.xl),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
          ),
      ],
    );
  }
}
