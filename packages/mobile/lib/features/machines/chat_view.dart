import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart' show errorText;
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/chat_parts.dart';
import '../../ui/widgets.dart';
import '../companion/dog_state.dart';
import '../composer/attachments.dart' show Attachment, AttachmentKind;
import '../companion/companion_floor.dart';
import '../composer/chat_composer.dart';
import 'autonomy.dart';
import 'group_messages.dart';
import 'hub_store.dart';
import 'message_format.dart';
import 'message_view.dart';
import 'protocol.dart';
import 'settings_sheets.dart';

/// Labels as the chat's own pickers word them (the defaults read "Default model", not "Machine default").
final chatModeOptions = [for (final m in permissionModes) (value: m.value, label: m.label)];
final chatModelOptions = [for (final m in models) (value: m.value, label: m.value.isEmpty ? 'Default model' : m.label)];
final chatEffortOptions = [for (final e in efforts) (value: e.value, label: e.value.isEmpty ? 'Default effort' : e.label)];

/// One chat with Claude on a machine (ChatView.tsx): the conversation as it streams, the permission prompt pinned
/// above the message box, and the chat's machine, account, folder, mode, model and effort.
class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, this.onBack});

  /// The back arrow on a phone (the chat is a step inside the machines list). Null side by side.
  final VoidCallback? onBack;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final store = HubStore.instance;
  late String _mode;
  late String _model;
  late String _effort;
  String _project = '';
  List<String> _projects = const [];
  String? _sessionId;
  String? _vmId;
  bool _stopping = false;
  bool _loadingEarlier = false;
  List<MessageDto>? _rowsMemo;

  /// The first message of a new chat is on its way: the chat it becomes keeps this one's choices.
  bool _starting = false;
  List<DisplayItem> _itemsMemo = const [];

  @override
  void initState() {
    super.initState();
    _defaults();
    _sessionId = store.state.selectedSessionId;
    _vmId = store.state.selectedVmId;
    _restore();
    store.addListener(_changed);
    _vmChanged(store.state.selectedVmId);
    _refreshOpenChat();
  }

  /// A chat that exists keeps what was chosen for it, so coming back to it shows (and runs with) the same mode.
  void _restore() {
    final vmId = _vmId ?? store.state.selectedVmId;
    final sessionId = _sessionId;
    if (vmId == null || sessionId == null || store.isTemporary(sessionId)) return;
    final saved = store.savedChoices(vmId, sessionId);
    if (saved == null) return;
    _mode = saved.mode;
    _model = saved.model;
    _effort = saved.effort;
  }

  /// Coming into a chat asks the hub for what is new in it, whatever was kept from last time.
  void _refreshOpenChat() {
    final vmId = store.state.selectedVmId;
    final sessionId = store.state.selectedSessionId;
    if (vmId == null || sessionId == null || store.isTemporary(sessionId)) return;
    unawaited(store.refreshSession(vmId, sessionId).catchError((Object e) {
      if (mounted && (store.state.messagesBySession[sessionId] ?? const []).isEmpty) _problem(e);
    }));
  }

  void _reload() {
    final vmId = store.state.selectedVmId;
    final sessionId = store.state.selectedSessionId;
    if (vmId == null || sessionId == null) return;
    haptic();
    unawaited(store.refreshSession(vmId, sessionId).catchError(_problem));
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  /// A new chat starts with what the person chose in Settings > New chats.
  void _defaults() {
    final p = ref.read(prefsProvider);
    final vmId = store.state.selectedVmId;
    final own = vmId == null ? null : store.machineDefaults(vmId);
    _mode = own?.mode ?? p.defaultMode;
    _model = own?.model ?? p.defaultModel;
    _effort = own?.effort ?? p.defaultEffort;
    _project = vmId == null ? '' : store.machineSettings(vmId).folder;
  }

  void _changed() {
    final s = store.state;
    if (s.selectedSessionId != _sessionId) {
      final prev = _sessionId;
      _sessionId = s.selectedSessionId;
      // Sending the first message of a new chat, or the machine naming it, is the same chat: keep what was picked for it.
      final started = prev == null && _starting;
      final renamed = prev != null && _sessionId != null && store.namedAs(prev) == _sessionId;
      _starting = false;
      if (!started && !renamed) {
        _defaults();
        _vmId = s.selectedVmId;
        _restore();
      }
    }
    if (s.selectedVmId != _vmId) _vmChanged(s.selectedVmId);
    if (mounted) setState(() {});
  }

  void _vmChanged(String? vmId) {
    _vmId = vmId;
    _projects = const [];
    _project = vmId == null ? '' : store.machineSettings(vmId).folder; // another machine has other folders
    if (vmId == null) return;
    store.api.listProjects(vmId).then((p) {
      if (mounted && _vmId == vmId) setState(() => _projects = p);
    }).catchError((_) {
      if (mounted && _vmId == vmId) setState(() => _projects = const []);
    });
  }

  void _problem(Object e) {
    if (mounted) toast(context, errorText(e));
  }

  Future<void> _earlier(String vmId, String sessionId) async {
    if (_loadingEarlier) return;
    setState(() => _loadingEarlier = true);
    try {
      await store.loadEarlier(vmId, sessionId);
    } catch (e) {
      _problem(e);
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  void _send(String typed, List<Attachment> attached, String vmId, String? sessionId, String? accountId) {
    // The hub takes photos as images and everything else as words, so a text or code file goes into the message under its name.
    final images = [
      for (final a in attached)
        if (a.kind == AttachmentKind.image && a.data != null) ImageAttachment(mediaType: a.mime, dataBase64: a.data!),
    ];
    final files = [for (final a in attached) if (a.kind == AttachmentKind.text) (name: a.name, text: a.text ?? '')];
    var text = inlineText(typed, files, maxTextChars) ?? typed;
    // An autonomous chat is told once more, with each request, to work on its own and check its work (chat does not show this).
    if (isAutonomousMode(_mode) && text.trim().isNotEmpty) text = withAutonomyBrief(text);
    if (sessionId != null) {
      final input = parseUserInput({'text': text, 'images': images.isEmpty ? null : images});
      if (!input.ok) return _problem(StateError(input.error!));
      unawaited(store.sendMessage(vmId, sessionId, input.value!).catchError(_problem));
    } else {
      final input = parseNewSession({'text': text, 'images': images.isEmpty ? null : images, 'cwd': _project.isEmpty ? null : _project, 'accountId': accountId});
      if (!input.ok) return _problem(StateError(input.error!));
      _starting = true;
      unawaited(store.startNewChat(vmId, input.value!, choices: ChatChoices(mode: _mode, model: _model, effort: _effort)).catchError((Object e) {
        _starting = false;
        _problem(e);
        return '';
      }));
    }
  }

  void _choose({String? mode, String? model, String? effort}) {
    setState(() {
      _mode = mode ?? _mode;
      _model = model ?? _model;
      _effort = effort ?? _effort;
    });
    final vmId = _vmId;
    final sessionId = _sessionId;
    if (vmId == null || sessionId == null) return;
    if (store.isTemporary(sessionId)) {
      store.updatePendingChoices(sessionId, ChatChoices(mode: _mode, model: _model, effort: _effort));
      return;
    }
    if (mode != null) unawaited(store.setPermissionMode(vmId, sessionId, mode).catchError(_problem));
    if (model != null) unawaited(store.setModel(vmId, sessionId, model).catchError(_problem));
    if (effort != null) unawaited(store.setEffort(vmId, sessionId, effort).catchError(_problem));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = store.state;
    final vmId = s.selectedVmId;
    final sessionId = s.selectedSessionId;
    if (vmId == null) {
      return Material(
        color: c.canvas,
        child: Column(children: [
          if (widget.onBack != null) ScreenHeader(title: 'Machines', onBack: widget.onBack),
          const Expanded(child: Center(child: DogState(scene: 'sit', scale: 4, title: 'Pick a machine', text: 'Choose one from the list to chat with it.'))),
        ]),
      );
    }

    final rows = sessionId == null ? const <MessageDto>[] : (s.messagesBySession[sessionId] ?? const <MessageDto>[]);
    if (!identical(rows, _rowsMemo)) {
      _rowsMemo = rows;
      _itemsMemo = groupMessages(rows);
    }
    final items = _itemsMemo;
    final startedAt = busySince(rows);
    final busy = startedAt != null;
    final todos = latestTodos(rows);
    Todo? inProgress;
    for (final t in todos ?? const <Todo>[]) {
      if (t.status == 'in_progress') {
        inProgress = t;
        break;
      }
    }
    final unresolved = livePermissions(items, s.resolvedPermissionIds);
    final pending = unresolved.isEmpty ? null : unresolved.last;
    VmDto? vm;
    for (final v in s.vms) {
      if (v.id == vmId) vm = v;
    }
    SessionDto? session;
    for (final x in s.sessionsByVm[vmId] ?? const <SessionDto>[]) {
      if (x.id == sessionId) session = x;
    }
    final accounts = vm != null && vm.accounts.isNotEmpty ? vm.accounts : defaultAccounts;
    final accountId = session?.accountId ?? s.selectedAccountId ?? accounts.first.id;
    var accountLabel = accountId;
    for (final a in accounts) {
      if (a.id == accountId) accountLabel = a.label;
    }

    final rounds = sessionId == null ? 0 : store.roundsFor(sessionId);
    final loading = sessionId != null && store.isLoading(sessionId);
    final place = [if (vm != null) store.nameOf(vm), if ((session?.cwd ?? '').isNotEmpty) session!.cwd].join(' · ');

    return Material(
      color: c.canvas,
      child: CwdScope(
        cwd: session?.cwd ?? '',
        child: Column(children: [
          ChatHeader(
            title: session == null ? 'New chat' : store.titleOf(session),
            place: place,
            dot: vm == null ? null : (vm.connected ? c.success : c.mutedSoft),
            onBack: widget.onBack,
            actions: [
              if (sessionId != null)
                loading
                    ? const Padding(padding: EdgeInsets.all(14), child: Spinner(size: 18))
                    : IconButton(onPressed: _reload, tooltip: 'Refresh', icon: Icon(Icons.refresh_rounded, size: 22, color: c.body)),
              if (session != null) IconButton(onPressed: () => showChatSettings(context, vmId, session!), tooltip: 'Chat settings', icon: Icon(Icons.tune_rounded, size: 22, color: c.body)),
            ],
          ),
          Expanded(
            child: ChatMessageList(
              empty: sessionId != null
                  ? ChatEmptyState(
                      title: loading ? 'Loading…' : 'No messages yet',
                      text: loading ? 'Getting this chat from your machine.' : 'Say something and it shows up here.',
                    )
                  : ChatEmptyState(
                      title: 'Start a new chat on ${vm?.name ?? 'this machine'}',
                      text: 'Ask for a change, a fix or an explanation. It runs on that machine.',
                      suggestions: machineSuggestions,
                      onPick: (t) => _send(t, const [], vmId, sessionId, accountId),
                    ),
              children: [
                if (sessionId != null && items.isNotEmpty && store.hasEarlier(sessionId))
                  Padding(
                    key: const ValueKey('earlier'),
                    padding: const EdgeInsets.only(bottom: chatGap),
                    child: Center(
                      child: EButton(
                        label: 'Show earlier messages',
                        icon: Icons.expand_less_rounded,
                        kind: ButtonKind.quiet,
                        busy: _loadingEarlier,
                        onPressed: () => _earlier(vmId, sessionId),
                      ),
                    ),
                  ),
                for (final item in items) MessageView(key: ValueKey(item.key), item: item, live: busy, waitingForPermission: pending != null),
                if (busy && pending == null)
                  BusySpinner(
                    key: ValueKey('spin-$startedAt'),
                    startedAt: startedAt,
                    thinking: lastIsThinking(rows),
                    task: inProgress?.activeForm ?? inProgress?.content,
                    rounds: rounds,
                  ),
                if (todos != null && todos.isNotEmpty) TodoListView(todos: todos),
              ],
            ),
          ),
          CompanionFloor(
            child: ChatBottom(
              above: [
                if (pending != null)
                  PermissionPanel(
                    key: ValueKey(pending.requestId),
                    toolName: pending.toolName,
                    input: pending.input,
                    onAnswer: (behavior) => store.resolvePermission(vmId, sessionId ?? '', pending.requestId, behavior,
                        twins: permissionTwins(unresolved, pending)),
                  ),
              ],
              composer: ChatComposer(
                key: ValueKey('$vmId:${sessionId ?? 'new'}'),
                attach: 'media',
                running: busy,
                stopping: _stopping,
                sendWhileRunning: true,
                onStop: () {
                  if (sessionId == null || _stopping) return;
                  setState(() => _stopping = true);
                  unawaited(store.interrupt(vmId, sessionId).catchError(_problem).whenComplete(() {
                    if (mounted) setState(() => _stopping = false);
                  }));
                },
                onSend: (typed, attached) => _send(typed, attached, vmId, sessionId, accountId),
                placeholder: sessionId != null ? 'Message Claude' : 'Start a new conversation',
                chips: ChatChips(children: [
                  ChatChip(icon: Icons.dns_outlined, label: vm == null ? '' : store.nameOf(vm)),
                  ChatChip(icon: Icons.person_outline_rounded, label: accountLabel),
                  if (sessionId == null)
                    ChatDropdownChip(
                      icon: Icons.folder_outlined,
                      title: 'Folder',
                      value: _project,
                      options: [(value: '', label: 'Workspace root'), for (final p in _projects) (value: p, label: p)],
                      onChanged: (v) => setState(() => _project = v),
                    ),
                  ChatDropdownChip(icon: Icons.shield_outlined, title: 'Permission mode', value: _mode, options: chatModeOptions, onChanged: (v) => _choose(mode: v)),
                  ChatDropdownChip(icon: Icons.auto_awesome_outlined, title: 'Model', value: _model, options: chatModelOptions, onChanged: (v) => _choose(model: v)),
                  ChatDropdownChip(icon: Icons.speed_rounded, title: 'Effort', value: _effort, options: chatEffortOptions, onChanged: (v) => _choose(effort: v)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Ways to start a chat on a machine.
const machineSuggestions = [
  'Explain what this project does',
  'Find and fix the failing tests',
  'Review my uncommitted changes',
  'What changed in the last few commits?',
];
