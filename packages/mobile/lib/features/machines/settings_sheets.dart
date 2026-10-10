import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart' show errorText;
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import 'chat_choices.dart';
import 'hub_store.dart';
import 'local_overlay.dart';
import 'message_format.dart';
import 'protocol.dart';

/// The settings of one chat and of one machine, each a sheet with everything that can be read or changed about it:
/// create (a new chat), read (details), update (mode, model, effort, name, folder) and delete.

String _label<T>(List<({T value, String label})> all, T value) {
  for (final o in all) {
    if (o.value == value) return o.label;
  }
  return '$value';
}

String _modeLabel(String v) => _label([for (final m in permissionModes) (value: m.value, label: m.label)], v);
String _modelLabel(String v) => v.isEmpty ? 'Machine default' : _label([for (final m in models) (value: m.value, label: m.label)], v);
String _effortLabel(String v) => v.isEmpty ? 'Machine default' : _label([for (final e in efforts) (value: e.value, label: e.label)], v);

Future<String?> _pickMode(BuildContext c, String value) => showChoiceSheet<String>(c,
    title: 'Permissions', value: value, options: [for (final m in permissionModes) Choice(m.value, m.label, m.hint)]);
Future<String?> _pickModel(BuildContext c, String value) =>
    showChoiceSheet<String>(c, title: 'Model', value: value, options: [for (final m in models) Choice(m.value, m.label)]);
Future<String?> _pickEffort(BuildContext c, String value) =>
    showChoiceSheet<String>(c, title: 'Effort', value: value, options: [for (final e in efforts) Choice(e.value, e.label)]);

Future<String?> _askText(BuildContext context, {required String title, required String initial, required String hint, String? note}) =>
    showESheet<String>(context, title: title, builder: (_) => _TextBody(initial: initial, hint: hint, note: note));

class _TextBody extends StatefulWidget {
  const _TextBody({required this.initial, required this.hint, this.note});
  final String initial;
  final String hint;
  final String? note;
  @override
  State<_TextBody> createState() => _TextBodyState();
}

class _TextBodyState extends State<_TextBody> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: _text,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => Navigator.of(context).pop(_text.text.trim()),
        decoration: InputDecoration(hintText: widget.hint, counterText: ''),
        style: TextStyle(fontSize: 16, color: c.ink),
      ),
      if (widget.note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(widget.note!, style: TextStyle(fontSize: 12, height: 1.45, color: c.muted))),
      const SizedBox(height: 12),
      EButton(label: 'Save', expand: true, onPressed: () => Navigator.of(context).pop(_text.text.trim())),
    ]);
  }
}

String _when(String iso) => iso.isEmpty ? '—' : timeAgo(iso);

// ---------------------------------------------------------------------------------------------- one chat

/// Settings of one chat: what it runs with, its details, its name, and removing it.
Future<void> showChatSettings(BuildContext context, String vmId, SessionDto session) =>
    showESheet<void>(context, title: 'Chat settings', builder: (_) => _ChatSettings(vmId: vmId, session: session));

class _ChatSettings extends StatefulWidget {
  const _ChatSettings({required this.vmId, required this.session});
  final String vmId;
  final SessionDto session;
  @override
  State<_ChatSettings> createState() => _ChatSettingsState();
}

class _ChatSettingsState extends State<_ChatSettings> {
  final store = HubStore.instance;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  SessionDto get _session {
    for (final s in store.state.sessionsByVm[widget.vmId] ?? const <SessionDto>[]) {
      if (s.id == widget.session.id) return s;
    }
    return widget.session;
  }

  SavedChoices get _choices => store.savedChoices(widget.vmId, widget.session.id) ?? const SavedChoices();

  Future<void> _change({String? mode, String? model, String? effort}) async {
    final now = _choices;
    final next = SavedChoices(mode: mode ?? now.mode, model: model ?? now.model, effort: effort ?? now.effort);
    try {
      await store.saveChoices(widget.vmId, widget.session.id, next);
    } catch (e) {
      if (mounted) toast(context, 'Saved on this phone, but ${errorText(e)}');
    }
    if (mounted) setState(() {});
  }

  Future<void> _rename() async {
    final s = _session;
    final v = await _askText(context, title: 'Rename chat', initial: store.titleOf(s), hint: s.title, note: 'Leave it blank to go back to the name the machine gave it.');
    if (v == null || !mounted) return;
    try {
      final onHub = await store.renameSession(widget.vmId, s, v);
      if (mounted) toast(context, onHub ? 'Renamed.' : 'Renamed on this phone.');
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  Future<void> _reload(SessionDto s) async {
    try {
      await store.refreshSession(widget.vmId, s.id);
      if (mounted) toast(context, 'Up to date.');
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  Future<void> _delete() async {
    final s = _session;
    final ok = await confirm(context,
        title: 'Delete this chat?', message: '“${store.titleOf(s)}” is removed from the list. If your hub keeps chats, it stays there but is hidden on this phone.', ok: 'Delete', danger: true);
    if (!ok || !mounted) return;
    try {
      final onHub = await store.deleteSession(widget.vmId, s);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text(onHub ? 'Chat deleted.' : 'Chat hidden on this phone.')));
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final vm = store.state.vms.where((v) => v.id == widget.vmId).firstOrNull;
    final ch = _choices;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Group(title: 'This chat runs with', footer: 'Kept for this chat, and sent to the machine each time you open it or send a message.', children: [
        SRow(
          icon: Icons.shield_outlined,
          label: 'Permissions',
          value: _modeLabel(ch.mode),
          onTap: () async {
            final v = await _pickMode(context, ch.mode);
            if (v != null) unawaited(_change(mode: v));
          },
        ),
        SRow(
          icon: Icons.auto_awesome_outlined,
          label: 'Model',
          value: _modelLabel(ch.model),
          onTap: () async {
            final v = await _pickModel(context, ch.model);
            if (v != null) unawaited(_change(model: v));
          },
        ),
        SRow(
          icon: Icons.speed_rounded,
          label: 'Effort',
          value: _effortLabel(ch.effort),
          onTap: () async {
            final v = await _pickEffort(context, ch.effort);
            if (v != null) unawaited(_change(effort: v));
          },
        ),
      ]),
      const SizedBox(height: 16),
      Group(title: 'Details', children: [
        SRow(icon: Icons.title_rounded, label: 'Name', value: store.titleOf(s), onTap: _rename),
        SRow(icon: Icons.dns_outlined, label: 'Machine', value: vm == null ? widget.vmId : store.nameOf(vm)),
        SRow(icon: Icons.folder_outlined, label: 'Folder', value: s.cwd.isEmpty ? 'Workspace root' : s.cwd),
        SRow(icon: Icons.person_outline_rounded, label: 'Account', value: s.accountId),
        SRow(icon: Icons.circle_outlined, label: 'Status', value: s.status),
        SRow(icon: Icons.schedule_rounded, label: 'Started', value: _when(s.createdAt)),
        SRow(icon: Icons.history_rounded, label: 'Last message', value: _when(s.lastMessageAt)),
        SRow(
          icon: Icons.copy_rounded,
          label: 'Copy chat id',
          sub: s.id,
          onTap: () {
            unawaited(Clipboard.setData(ClipboardData(text: s.id)));
            toast(context, 'Copied.');
          },
        ),
      ]),
      const SizedBox(height: 16),
      Group(title: 'Manage', children: [
        SRow(
          icon: Icons.refresh_rounded,
          label: 'Reload messages',
          sub: 'Fetch this chat from the machine again.',
          onTap: () => _reload(s),
        ),
        SRow(icon: Icons.delete_outline_rounded, label: 'Delete chat', danger: true, onTap: _delete),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------------------------------ one machine

/// Settings of one machine: its details, what new chats on it start with, its name, and removing it. [onNewChat] starts one.
Future<void> showMachineSettings(BuildContext context, VmDto vm, {VoidCallback? onNewChat}) =>
    showESheet<void>(context, title: 'Machine settings', builder: (_) => _MachineSettings(vmId: vm.id, onNewChat: onNewChat));

class _MachineSettings extends StatefulWidget {
  const _MachineSettings({required this.vmId, this.onNewChat});
  final String vmId;
  final VoidCallback? onNewChat;
  @override
  State<_MachineSettings> createState() => _MachineSettingsState();
}

class _MachineSettingsState extends State<_MachineSettings> {
  final store = HubStore.instance;
  List<String> _folders = const [];

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    store.api.listProjects(widget.vmId).then((p) {
      if (mounted) setState(() => _folders = p);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  VmDto? get _vm => store.state.vms.where((v) => v.id == widget.vmId).firstOrNull;

  MachineOverlay get _o => store.machineSettings(widget.vmId);

  SavedChoices get _defaults {
    final d = _o.defaults;
    if (d != null) return d;
    final p = currentPrefs();
    return SavedChoices(mode: p.defaultMode, model: p.defaultModel, effort: p.defaultEffort);
  }

  void _setDefaults({String? mode, String? model, String? effort}) {
    final d = _defaults;
    store.setMachineSettings(
        widget.vmId, _o.copyWith(defaults: () => SavedChoices(mode: mode ?? d.mode, model: model ?? d.model, effort: effort ?? d.effort)));
  }

  Future<void> _rename(VmDto vm) async {
    final v = await _askText(context, title: 'Rename machine', initial: store.nameOf(vm), hint: vm.name, note: 'Leave it blank to go back to the name the machine reports.');
    if (v == null || !mounted) return;
    try {
      final onHub = await store.renameVm(vm, v);
      if (mounted) toast(context, onHub ? 'Renamed.' : 'Renamed on this phone.');
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  Future<void> _delete(VmDto vm) async {
    final ok = await confirm(context,
        title: 'Remove this machine?',
        message: '“${store.nameOf(vm)}” is removed from your list. A machine whose agent is still running can join again; if the hub does not let it be removed, it is only hidden on this phone.',
        ok: 'Remove',
        danger: true);
    if (!ok || !mounted) return;
    try {
      final onHub = await store.deleteVm(vm);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text(onHub ? 'Machine removed.' : 'Machine hidden on this phone.')));
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    if (vm == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('This machine is no longer here.')));
    final d = _defaults;
    final o = _o;
    final accounts = vm.accounts.isNotEmpty ? vm.accounts : defaultAccounts;
    final hidden = store.hiddenSessionCount(vm.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Group(title: 'Details', children: [
        SRow(icon: Icons.title_rounded, label: 'Name', value: store.nameOf(vm), onTap: () => _rename(vm)),
        SRow(icon: Icons.circle, label: 'Status', value: machineStatus(vm.connected, vm.lastSeenAt)),
        SRow(icon: Icons.person_outline_rounded, label: 'Claude accounts', value: accounts.map((a) => a.label).join(', ')),
        SRow(
          icon: Icons.copy_rounded,
          label: 'Copy machine id',
          sub: vm.id,
          onTap: () {
            unawaited(Clipboard.setData(ClipboardData(text: vm.id)));
            toast(context, 'Copied.');
          },
        ),
      ]),
      const SizedBox(height: 16),
      Group(
        title: 'New chats on this machine',
        footer: o.defaults == null ? 'Using your settings for new chats. Change one to give this machine its own.' : 'This machine has its own settings for new chats.',
        children: [
          SRow(
            icon: Icons.shield_outlined,
            label: 'Permissions',
            value: _modeLabel(d.mode),
            onTap: () async {
              final v = await _pickMode(context, d.mode);
              if (v != null) _setDefaults(mode: v);
            },
          ),
          SRow(
            icon: Icons.auto_awesome_outlined,
            label: 'Model',
            value: _modelLabel(d.model),
            onTap: () async {
              final v = await _pickModel(context, d.model);
              if (v != null) _setDefaults(model: v);
            },
          ),
          SRow(
            icon: Icons.speed_rounded,
            label: 'Effort',
            value: _effortLabel(d.effort),
            onTap: () async {
              final v = await _pickEffort(context, d.effort);
              if (v != null) _setDefaults(effort: v);
            },
          ),
          SRow(
            icon: Icons.folder_outlined,
            label: 'Folder',
            value: o.folder.isEmpty ? 'Workspace root' : o.folder,
            onTap: () async {
              final v = await showChoiceSheet<String>(context,
                  title: 'Folder', value: o.folder, options: [const Choice('', 'Workspace root'), for (final p in _folders) Choice(p, p)]);
              if (v != null) store.setMachineSettings(vm.id, o.copyWith(folder: v));
            },
          ),
          if (o.defaults != null)
            SRow(
              icon: Icons.restart_alt_rounded,
              label: 'Use my settings for new chats',
              onTap: () => store.setMachineSettings(vm.id, o.copyWith(defaults: () => null)),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Group(title: 'Manage', children: [
        if (widget.onNewChat != null)
          SRow(
            icon: Icons.add_comment_outlined,
            label: 'New chat',
            onTap: () {
              Navigator.of(context).pop();
              widget.onNewChat!();
            },
          ),
        if (hidden > 0)
          SRow(
            icon: Icons.visibility_outlined,
            label: 'Show hidden chats',
            value: '$hidden',
            onTap: () => store.showHiddenSessions(vm.id),
          ),
        SRow(icon: Icons.delete_outline_rounded, label: 'Remove machine', danger: true, onTap: () => _delete(vm)),
      ]),
    ]);
  }
}
