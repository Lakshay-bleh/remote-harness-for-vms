import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart' show errorText;
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../companion/dog_state.dart';
import 'connect_machine.dart';
import 'escanor_connect.dart';
import 'hub_scope.dart';
import 'hub_store.dart';
import 'message_format.dart';
import 'protocol.dart';
import 'settings_sheets.dart';

/// How many chats a machine (or account) lists before "Show more".
const sessionsFirst = 8;

/// The machines, each with its chats, grouped by Claude account when a machine has more than one (Sidebar.tsx).
class HubSidebar extends StatefulWidget {
  const HubSidebar({super.key, required this.onSelectSession});

  /// A chat (or a new chat) was picked: on a phone, open it.
  final VoidCallback onSelectSession;

  @override
  State<HubSidebar> createState() => _HubSidebarState();
}

class _HubSidebarState extends State<HubSidebar> {
  final store = HubStore.instance;
  final _query = TextEditingController();
  String? _expandedVmId;
  final Map<String, int> _more = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    _query.addListener(() => setState(() {}));
    _refresh();
    _changed();
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    _query.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await store.refreshVms();
      if (mounted && _error != null) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  void _changed() {
    final vms = store.state.vms;
    if (_expandedVmId == null && vms.isNotEmpty) {
      // Open the machine already picked (coming back to the list), else the first.
      final picked = store.state.selectedVmId;
      final vmId = picked != null && vms.any((v) => v.id == picked) ? picked : vms.first.id;
      _expandedVmId = vmId;
      if (picked != vmId) _selectVm(vmId);
    }
    if (mounted) setState(() {});
  }

  void _selectVm(String vmId) {
    unawaited(store.selectVm(vmId).catchError((Object e) {
      if (mounted) toast(context, errorText(e));
    }));
  }

  void _toggleVm(String vmId) {
    haptic();
    final opening = _expandedVmId != vmId;
    setState(() => _expandedVmId = opening ? vmId : null);
    if (opening) _selectVm(vmId);
  }

  void _pickSession(String vmId, SessionDto s) {
    haptic();
    // Always ask the hub for what is new: what is kept from the last visit shows meanwhile.
    final cached = store.state.messagesBySession[s.id] != null;
    unawaited(store.openSession(vmId, s).catchError((Object e) {
      if (mounted && !cached) toast(context, errorText(e));
    }));
    widget.onSelectSession();
  }

  void _newChat(String vmId, String accountId) {
    haptic();
    store.selectSession(vmId, null, accountId);
    widget.onSelectSession();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final managed = HubScope.managedOf(context);
    final embedded = HubScope.embeddedOf(context);
    final s = store.state;
    final q = _query.text.trim().toLowerCase();
    bool matches(SessionDto x) => !store.isSessionHidden(x.vmId.isEmpty ? (s.selectedVmId ?? '') : x.vmId, x.id) && (q.isEmpty || store.titleOf(x).toLowerCase().contains(q));
    void connect() => showConnectMachineSheet(context, managed!);

    return Material(
      color: c.surfaceSoft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (managed != null || embedded)
          ScreenHeader(title: 'Servers', actions: [
            if (managed != null)
              Padding(padding: const EdgeInsets.only(right: 4), child: EButton(label: 'Add', icon: Icons.add_rounded, onPressed: connect)),
          ])
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(children: [
              const Logo(size: 32),
              const SizedBox(width: 10),
              Text('Escanor', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            style: TextStyle(fontSize: 14, color: c.ink),
            decoration: InputDecoration(
              hintText: 'Search',
              fillColor: c.canvas,
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: c.mutedSoft),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: c.hairline)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: c.hairline)),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _refresh();
              final vm = _expandedVmId;
              if (vm != null) {
                try {
                  await store.selectVm(vm);
                } catch (_) {}
              }
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
              children: [
                if (_error != null && s.vms.isEmpty) Padding(padding: const EdgeInsets.all(4), child: Notice(_error!, tone: NoticeTone.error)),
                if (s.vms.isEmpty)
                  managed != null
                      ? DogState(
                          scene: 'sleep',
                          title: 'Waiting for a machine',
                          text: 'Put the agent on a server and it shows up here, ready to chat with. Your hub and secret are already set up.',
                          action: Column(mainAxisSize: MainAxisSize.min, children: [
                            EButton(label: 'Connect a machine', expand: true, onPressed: connect),
                          ]),
                        )
                      : const DogState(scene: 'sleep', title: 'No machines yet', text: 'Install the agent on a server to see it here.'),
                for (final vm in s.vms.where((v) => !store.isVmHidden(v.id))) _vmCard(context, vm, q, matches),
                if (s.vms.isNotEmpty && q.isEmpty)
                  DogState(
                    scene: 'sit',
                    scale: 4,
                    title: s.vms.length == 1 ? 'Your machine is all set' : 'Your machines are all set',
                    text: 'Tap one to see its chats, or start a new one.',
                  ),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.hairline))),
          padding: const EdgeInsets.all(10),
          child: managed != null
              // Escanor is already installed on a hosted hub, and signing out is Escanor's, from Settings.
              ? _FooterRow(leading: Text('+', style: TextStyle(fontSize: 16, color: c.primary)), label: 'Connect a machine', onTap: connect)
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const EscanorConnectRow(),
                  _FooterRow(leading: const SizedBox(width: 8), label: 'Sign out', muted: true, onTap: store.logout),
                ]),
        ),
      ]),
    );
  }

  Widget _vmCard(BuildContext context, VmDto vm, String q, bool Function(SessionDto) matches) {
    final c = context.c;
    final state = store.state;
    final sessions = [for (final x in state.sessionsByVm[vm.id] ?? const <SessionDto>[]) if (!store.isSessionHidden(vm.id, x.id)) x];
    final expanded = _expandedVmId == vm.id;
    final accounts = vm.accounts.isNotEmpty ? vm.accounts : defaultAccounts;
    final multi = accounts.length > 1;

    List<Widget> list(List<SessionDto> all, String moreKey, String accountId, {required String emptyText}) {
      final filtered = all.where(matches).toList();
      final limit = _more[moreKey] ?? sessionsFirst;
      final shown = q.isEmpty ? filtered.take(limit).toList() : filtered;
      return [
        if (q.isEmpty) _NewChatRow(onTap: () => _newChat(vm.id, accountId)),
        for (final x in shown)
          _SessionRow(
              session: x,
              title: store.titleOf(x),
              active: state.selectedSessionId == x.id,
              onTap: () => _pickSession(vm.id, x),
              onSettings: () => showChatSettings(context, vm.id, x)),
        if (q.isEmpty && filtered.length > limit)
          _TextRow(text: 'Show more', color: c.primary, onTap: () => setState(() => _more[moreKey] = limit + 20)),
        // One account: "no chats" whenever the machine has none. Several: per account, when not searching.
        if (multi ? filtered.isEmpty && q.isEmpty : all.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Text(emptyText, style: TextStyle(fontSize: multi ? 12 : 13, color: c.mutedSoft))),
      ];
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: expanded ? c.primary.withValues(alpha: 0.4) : c.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            expanded: expanded,
            button: true,
            child: InkWell(
              onTap: () => _toggleVm(vm.id),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: c.canvas),
                        child: Icon(Icons.desktop_windows_outlined, size: 20, color: c.muted),
                      ),
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: vm.connected ? c.success : c.hairline,
                            border: Border.all(color: c.surfaceCard, width: 2),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(store.nameOf(vm), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink)),
                      Text(
                        '${machineStatus(vm.connected, vm.lastSeenAt)} · ${sessions.length} ${sessions.length == 1 ? 'chat' : 'chats'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Machine settings',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      haptic();
                      showMachineSettings(context, vm, onNewChat: () => _newChat(vm.id, accounts.first.id));
                    },
                    icon: Icon(Icons.tune_rounded, size: 20, color: c.muted),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.chevron_right_rounded, size: 18, color: c.mutedSoft),
                  ),
                ]),
              ),
            ),
          ),
          if (expanded)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 8, 8),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: c.hairline))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!multi)
                  ...list(sessions, vm.id, accounts.first.id, emptyText: 'No chats yet. Start one with New chat.')
                else
                  for (final account in accounts) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                      child: Row(children: [
                        Icon(Icons.person_outline_rounded, size: 12, color: c.mutedSoft),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(account.label.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, letterSpacing: 0.5, fontWeight: FontWeight.w500, color: c.mutedSoft)),
                        ),
                      ]),
                    ),
                    ...list(sessions.where((x) => x.accountId == account.id).toList(), vm.id + account.id, account.id,
                        emptyText: 'No sessions yet'),
                  ],
              ]),
            ),
        ]),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.title, required this.active, required this.onTap, required this.onSettings});
  final SessionDto session;
  final String title;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: active ? c.surfaceStrong : Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        onLongPress: () {
          haptic();
          onSettings();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (session.status == 'active') const Padding(padding: EdgeInsets.only(right: 6), child: _PulseDot()),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: active ? c.ink : c.body, fontWeight: active ? FontWeight.w500 : FontWeight.w400)),
              ),
            ]),
            const SizedBox(height: 2),
            Text('${relativeTime(session.lastMessageAt)} ago · ${session.cwd}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.mutedSoft)),
          ]),
        ),
      ),
    );
  }
}

/// A chat that is working right now.
class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: context.c.primary));
    if (MediaQuery.of(context).disableAnimations) return dot;
    if (!_a.isAnimating) _a.repeat(reverse: true);
    return FadeTransition(opacity: Tween(begin: 1.0, end: 0.3).animate(_a), child: dot);
  }
}

class _NewChatRow extends StatelessWidget {
  const _NewChatRow({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(children: [
          Text('+', style: TextStyle(fontSize: 16, height: 1, color: c.primary)),
          const SizedBox(width: 8),
          Text('New chat', style: TextStyle(fontSize: 13, color: c.primary)),
        ]),
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  const _TextRow({required this.text, required this.color, required this.onTap});
  final String text;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Text(text, style: TextStyle(fontSize: 13, color: color))),
      );
}

class _FooterRow extends StatelessWidget {
  const _FooterRow({required this.leading, required this.label, required this.onTap, this.muted = false});
  final Widget leading;
  final String label;
  final VoidCallback onTap;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () {
        haptic();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          leading,
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: muted ? c.muted : c.body))),
        ]),
      ),
    );
  }
}
