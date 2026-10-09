import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart' show errorText;
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../companion/dog_state.dart';
import '../composer/attachments.dart' show Attachment, AttachmentKind;
import '../composer/chat_composer.dart';
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

  void _send(String typed, List<Attachment> attached, String vmId, String? sessionId, String? accountId) {
    // The hub takes photos as images and everything else as words, so a text or code file goes into the message under its name.
    final images = [
      for (final a in attached)
        if (a.kind == AttachmentKind.image && a.data != null) ImageAttachment(mediaType: a.mime, dataBase64: a.data!),
    ];
    final files = [for (final a in attached) if (a.kind == AttachmentKind.text) (name: a.name, text: a.text ?? '')];
    final text = inlineText(typed, files, maxTextChars) ?? typed;
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

    // Newest at the bottom: the list is drawn from the bottom up, so new output shows without scrolling.
    final tail = <Widget>[
      if (busy && pending == null)
        BusySpinner(key: ValueKey('spin-$startedAt'), startedAt: startedAt, thinking: lastIsThinking(rows), task: inProgress?.activeForm ?? inProgress?.content),
      if (todos != null && todos.isNotEmpty) TodoListView(todos: todos),
    ];

    return Material(
      color: c.canvas,
      child: CwdScope(
        cwd: session?.cwd ?? '',
        child: Column(children: [
          _ChatHeader(
              title: session == null ? 'New chat' : store.titleOf(session),
              onSettings: session == null ? null : () => showChatSettings(context, vmId, session!),
              vm: vm,
              cwd: session?.cwd,
              onBack: widget.onBack,
              onRefresh: sessionId == null ? null : _reload,
              refreshing: sessionId != null && store.isLoading(sessionId)),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: DogState(
                        scene: 'sit',
                        scale: 4,
                        title: sessionId != null ? (store.isLoading(sessionId) ? 'Loading…' : 'No messages yet') : 'Start a new chat on ${vm?.name ?? 'this machine'}',
                        text: sessionId != null
                            ? (store.isLoading(sessionId) ? 'Getting this chat from your machine.' : 'Say something and it shows up here.')
                            : 'Ask for a change, a fix or an explanation. It runs on that machine.',
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: items.length + tail.length,
                    itemBuilder: (context, i) {
                      if (i < tail.length) return tail[tail.length - 1 - i];
                      final item = items[items.length - 1 - (i - tail.length)];
                      return MessageView(key: ValueKey(item.key), item: item, live: busy, waitingForPermission: pending != null);
                    },
                  ),
          ),
          if (pending != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: PermissionPanel(
                key: ValueKey(pending.requestId),
                toolName: pending.toolName,
                input: pending.input,
                onAnswer: (behavior) => store.resolvePermission(vmId, sessionId ?? '', pending.requestId, behavior,
                    twins: permissionTwins(unresolved, pending)),
              ),
            ),
          Container(
            decoration: BoxDecoration(color: c.canvas, border: Border(top: BorderSide(color: c.hairline))),
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: ChatComposer(
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
              placeholder: sessionId != null ? 'Message Claude…' : 'Start a new conversation…',
              chips: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _Chip(icon: Icons.dns_outlined, label: vm == null ? '' : store.nameOf(vm)),
                  _Chip(icon: Icons.person_outline_rounded, label: accountLabel),
                  if (sessionId == null)
                    _DropdownChip(
                      icon: Icons.folder_outlined,
                      title: 'Folder',
                      value: _project,
                      options: [(value: '', label: 'Workspace root'), for (final p in _projects) (value: p, label: p)],
                      onChanged: (v) => setState(() => _project = v),
                    ),
                  _DropdownChip(icon: Icons.shield_outlined, title: 'Permission mode', value: _mode, options: chatModeOptions, onChanged: (v) => _choose(mode: v)),
                  _DropdownChip(icon: Icons.auto_awesome_outlined, title: 'Model', value: _model, options: chatModelOptions, onChanged: (v) => _choose(model: v)),
                  _DropdownChip(icon: Icons.speed_rounded, title: 'Effort', value: _effort, options: chatEffortOptions, onChanged: (v) => _choose(effort: v)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.title, required this.vm, this.cwd, this.onBack, this.onRefresh, this.onSettings, this.refreshing = false});
  final String title;
  final VmDto? vm;
  final String? cwd;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;
  final VoidCallback? onSettings;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sub = TextStyle(fontSize: 12, color: c.muted);
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: EdgeInsets.fromLTRB(onBack != null ? 8 : 16, 6, 8, 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))),
      child: Row(children: [
        if (onBack != null) IconButton(onPressed: onBack, tooltip: 'Back', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: c.body)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: onBack != null ? 21 : 18, height: 1.2, color: c.ink, fontWeight: FontWeight.w500)),
            Row(children: [
              if (vm != null) Flexible(child: Text(vm!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sub)),
              if (vm != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: vm!.connected ? c.success : c.hairline)),
                ),
              if (cwd != null && cwd!.isNotEmpty) Flexible(child: Text('  · $cwd', maxLines: 1, overflow: TextOverflow.ellipsis, style: sub)),
            ]),
          ]),
        ),
        if (onRefresh != null)
          refreshing
              ? const Padding(padding: EdgeInsets.all(14), child: Spinner(size: 18))
              : IconButton(onPressed: onRefresh, tooltip: 'Refresh', icon: Icon(Icons.refresh_rounded, size: 22, color: c.body)),
        if (onSettings != null) IconButton(onPressed: onSettings, tooltip: 'Chat settings', icon: Icon(Icons.tune_rounded, size: 22, color: c.body)),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: c.muted),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
          ),
        ]),
      ),
    );
  }
}

class _DropdownChip extends StatelessWidget {
  const _DropdownChip({required this.icon, required this.title, required this.value, required this.options, required this.onChanged});
  final IconData icon;
  final String title;
  final String value;
  final List<({String value, String label})> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    var current = value;
    for (final o in options) {
      if (o.value == value) current = o.label;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: PopupMenuButton<String>(
        tooltip: title,
        initialValue: value,
        onSelected: (v) {
          haptic();
          onChanged(v);
        },
        color: c.canvas,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: c.hairline)),
        position: PopupMenuPosition.over,
        itemBuilder: (_) => [
          for (final o in options)
            PopupMenuItem<String>(
              value: o.value,
              height: 40,
              child: Text(o.label,
                  style: TextStyle(fontSize: 13, color: o.value == value ? c.primary : c.body, fontWeight: o.value == value ? FontWeight.w500 : FontWeight.w400)),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.pill)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: c.body),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(current, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.body)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 14, color: c.body),
          ]),
        ),
      ),
    );
  }
}
