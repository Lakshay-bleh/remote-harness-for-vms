import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart' show errorText;
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../companion/dog_state.dart';
import 'connect_machine.dart';
import 'escanor_connect.dart';
import 'hub_app.dart' show hubWideWidth;
import 'hub_scope.dart';
import 'hub_store.dart';
import 'machines_home.dart';
import 'message_format.dart';
import 'protocol.dart';
import 'session_search.dart';
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

  // Content search: the hub's hits per machine, for the query in [_hitsQuery]. Each new query bumps [_searchSeq], so an
  // answer to an older one is dropped when it arrives.
  Timer? _searchTimer;
  int _searchSeq = 0;
  String _lastQuery = '';
  String _hitsQuery = '';
  Map<String, List<SessionSearchHit>> _hits = const {};

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    _query.addListener(_queryChanged);
    _refresh();
    _changed();
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    _searchTimer?.cancel();
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

  // Titles filter as the person types; once typing pauses, each machine's hub is asked what was said in its chats.
  void _queryChanged() {
    final q = _query.text.trim();
    if (q == _lastQuery) return; // only the cursor moved
    _lastQuery = q;
    _searchTimer?.cancel();
    final seq = ++_searchSeq;
    if (q.length >= contentSearchMinLength) _searchTimer = Timer(contentSearchDelay, () => _searchContent(q, seq));
    setState(() {});
  }

  Future<void> _searchContent(String q, int seq) async {
    final vmIds = [for (final v in store.state.vms) if (!store.isVmHidden(v.id)) v.id];
    final found = await Future.wait([for (final id in vmIds) store.searchSessions(id, q)]);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _hitsQuery = q;
      _hits = {for (var i = 0; i < vmIds.length; i++) vmIds[i]: found[i]};
    });
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
    // Hits for an older query are never shown: until the hub answers this one, only titles match.
    final hits = _hitsQuery.isNotEmpty && _hitsQuery == _query.text.trim() ? _hits : const <String, List<SessionSearchHit>>{};
    void connect() => showConnectMachineSheet(context, managed!);
    // The Servers half of the Machines tab: its header (and Add) is the tab's.
    final half = MachinesHalf.offerAdd(context, managed != null ? connect : null);

    return Material(
      // a sidebar beside the chat on a wide screen; on a phone, the page itself
      color: half && MediaQuery.sizeOf(context).width < hubWideWidth ? c.canvas : c.surfaceSoft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (half)
          const SizedBox.shrink()
        else if (managed != null || embedded)
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
                for (final vm in s.vms.where((v) => !store.isVmHidden(v.id))) _vmCard(context, vm, q, hits[vm.id]),
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

  Widget _vmCard(BuildContext context, VmDto vm, String q, List<SessionSearchHit>? hits) {
    final c = context.c;
    final state = store.state;
    final sessions = [for (final x in state.sessionsByVm[vm.id] ?? const <SessionDto>[]) if (!store.isSessionHidden(vm.id, x.id)) x];
    final expanded = _expandedVmId == vm.id;
    final accounts = vm.accounts.isNotEmpty ? vm.accounts : defaultAccounts;
    final multi = accounts.length > 1;

    List<Widget> list(List<SessionDto> all, String moreKey, String accountId, {required String emptyText}) {
      final filtered = mergeSessionSearch(sessions: all, query: q, titleOf: store.titleOf, hits: hits);
      final limit = _more[moreKey] ?? sessionsFirst;
      final shown = q.isEmpty ? filtered.take(limit).toList() : filtered;
      return [
        if (q.isEmpty) _NewChatRow(onTap: () => _newChat(vm.id, accountId)),
        for (final r in shown)
          _SessionRow(
              session: r.session,
              waiting: state.waiting.containsKey(r.session.id),
              title: store.titleOf(r.session),
              snippet: r.snippet,
              active: state.selectedSessionId == r.session.id,
              onTap: () => _pickSession(vm.id, r.session),
              onSettings: () => showChatSettings(context, vm.id, r.session)),
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
                      Row(children: [
                        Flexible(
                          child: Text(store.nameOf(vm),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink)),
                        ),
                        if (state.waiting.containsValue(vm.id)) ...[
                          const SizedBox(width: 8),
                          WaitingPill(count: state.waiting.values.where((v) => v == vm.id).length, compact: true),
                        ],
                      ]),
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
  const _SessionRow(
      {required this.session, required this.title, this.snippet, required this.active, required this.onTap, required this.onSettings, this.waiting = false});
  final SessionDto session;

  /// Claude in this chat asked for permission and is waiting for an answer.
  final bool waiting;
  final String title;

  /// What was said in the chat that matched the search, when its title did not.
  final String? snippet;
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
              if (!waiting && session.status == 'active') const Padding(padding: EdgeInsets.only(right: 6), child: _PulseDot()),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: active ? c.ink : c.body, fontWeight: active || waiting ? FontWeight.w500 : FontWeight.w400)),
              ),
              if (waiting) const Padding(padding: EdgeInsets.only(left: 6), child: WaitingPill()),
            ]),
            if (snippet != null) ...[
              const SizedBox(height: 2),
              Text(snippet!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
            ],
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

/// "Needs your OK": Claude asked for permission and is stopped until someone answers.
class WaitingPill extends StatelessWidget {
  const WaitingPill({super.key, this.count = 1, this.compact = false});
  final int count;

  /// Just the hand and the count (where space is short, e.g. next to a machine's name).
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: count > 1 ? '$count chats need your OK' : 'Needs your OK',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.permission.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(Radii.pill), border: Border.all(color: c.permission.withValues(alpha: 0.6))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.front_hand_outlined, size: 12, color: c.permission),
          const SizedBox(width: 4),
          ExcludeSemantics(
            child: Text(compact ? '$count' : (count > 1 ? '$count need your OK' : 'Needs your OK'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.permission)),
          ),
        ]),
      ),
    );
  }
}
