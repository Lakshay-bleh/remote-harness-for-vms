import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import 'activity_tab.dart';
import 'approvals_tab.dart';
import 'cloud.dart';
import 'computer_chat.dart';
import 'computer_link.dart';
import 'computer_prefs.dart';
import 'computer_settings.dart';
import 'error_card.dart';
import 'overflow_menu.dart';
import 'permissions.dart';
import 'permissions_tab.dart';
import 'protocol/client.dart';
import 'protocol/protocol.dart';
import 'rename_sheet.dart';
import 'resources_tab.dart';
import 'storage.dart';

enum DetailTab { chat, resources, approvals, permissions, activity }

const _tabs = <(DetailTab, String, IconData, IconData)>[
  (DetailTab.chat, 'Chat', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
  (DetailTab.resources, 'Resources', Icons.speed_outlined, Icons.speed_rounded),
  (DetailTab.approvals, 'Approvals', Icons.verified_user_outlined, Icons.verified_user_rounded),
  (DetailTab.permissions, 'Permissions', Icons.lock_outline_rounded, Icons.lock_rounded),
  (DetailTab.activity, 'Activity', Icons.history_rounded, Icons.history_rounded),
];

/// One paired computer: chat with it, its resources, what waits for an OK, what it allows, and what it has been doing.
class ComputerDetail extends StatefulWidget {
  const ComputerDetail({super.key, required this.computer, this.relay, this.env = const ClientEnv()});
  final PairedComputer computer;

  /// The cloud route (default: through the signed-in API). Tests give their own.
  final RelayTransport? relay;
  final ClientEnv env;

  @override
  State<ComputerDetail> createState() => _ComputerDetailState();
}

class _ComputerDetailState extends State<ComputerDetail> {
  late RoutePref _route = getComputerPrefs(widget.computer.id).route;
  late final ComputerLink _link;
  DetailTab _tab = DetailTab.chat;
  List<Approval> _approvals = [];
  final _chatActions = ChatActions();
  void Function()? _offPush;
  Timer? _poll;
  bool _polling = false;
  LinkState? _pollState;
  ComputerRoute? _pollRoute;

  RelayTransport get _relay => widget.relay ?? apiRelay();

  @override
  void initState() {
    super.initState();
    final routed = applyRoute(widget.computer, _route);
    _link = ComputerLink(routed.computer, relay: routed.cloud ? _relay : null, env: widget.env);
    // Approvals arrive by push on the local network, and are fetched on a timer over the cloud.
    _offPush = _link.onPush((m) {
      if (!mounted) return;
      if (m['t'] == 'approval') {
        final a = Approval.fromJson(m);
        if (!_approvals.any((x) => x.approvalId == a.approvalId)) setState(() => _approvals = [..._approvals, a]);
      }
      if (m['t'] == 'approval_done') setState(() => _approvals = _approvals.where((x) => x.approvalId != m['approvalId']).toList());
    });
    _link.addListener(_linkChanged);
    computerPrefsChanges.addListener(_prefsChanged);
    _syncPolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _offPush?.call();
    _link.removeListener(_linkChanged);
    computerPrefsChanges.removeListener(_prefsChanged);
    _link.dispose();
    _chatActions.dispose();
    super.dispose();
  }

  void _linkChanged() {
    if (!mounted) return;
    setState(() {});
    _syncPolling();
  }

  /// The person's "how to reach it" choice, applied to this connection only (the stored computer never changes).
  void _prefsChanged() {
    if (!mounted) return;
    final r = getComputerPrefs(widget.computer.id).route;
    if (r != _route) {
      _route = r;
      final routed = applyRoute(widget.computer, r);
      _link.use(routed.computer, routed.cloud ? _relay : null);
    }
    setState(() {});
  }

  /// Keep asking for approvals while connecting or online. (Once it is offline the link retries by itself, so this stays quiet.)
  void _syncPolling() {
    if (_pollState == _link.state && _pollRoute == _link.route && (_poll != null || _link.state == LinkState.offline)) return;
    _pollState = _link.state;
    _pollRoute = _link.route;
    _poll?.cancel();
    _poll = null;
    if (_link.state == LinkState.offline) return;
    if (_link.state == LinkState.online) _pollPending();
    _poll = Timer.periodic(Duration(seconds: _link.route == ComputerRoute.lan ? 15 : 8), (_) => _pollPending());
  }

  Future<void> _pollPending() async {
    if (_polling) return; // over the cloud one answer can take a few seconds: never queue another behind it
    _polling = true;
    try {
      final r = firstOf(await _link.request(ClientMsg.pending()), const {'pending'});
      if (mounted && r != null) {
        setState(
          () => _approvals = [
            for (final a in (r['approvals'] as List? ?? const []))
              if (a is Map) Approval.fromJson(Map<String, dynamic>.from(a)),
          ],
        );
      }
    } catch (_) {
      // the banner says so once it counts as offline
    } finally {
      _polling = false;
    }
  }

  Future<void> _answer(Approval a, bool ok) async {
    setState(() => _approvals = _approvals.where((x) => x.approvalId != a.approvalId).toList());
    try {
      await _link.request(ClientMsg.approve(a.approvalId, ok));
    } catch (_) {}
  }

  /// Ask the computer to switch on a kind of action that was refused, from the error card. Resolves with what to tell the person.
  Future<String> _askToAllow(String groupLabel) async {
    final list = firstOf(await _link.request(ClientMsg.groups()), const {'groups'});
    final groups = list == null
        ? <PermissionGroup>[]
        : [
            for (final g in (list['items'] as List? ?? const []))
              if (g is Map) PermissionGroup.fromJson(Map<String, dynamic>.from(g)),
          ];
    final g = findGroup(groups, groupLabel);
    if (g == null) return describeGroupRequest(GroupRequestStatus.unknown, groupLabel);
    final r = firstOf(await _link.request(ClientMsg.requestGroup(g.id)), const {'group_request'});
    return describeGroupRequest(r == null ? GroupRequestStatus.unknown : groupRequestStatusOf(r['status']), g.label);
  }

  Future<int> _testConnection() async {
    final sw = Stopwatch()..start();
    await _link.request(ClientMsg.ping());
    return sw.elapsedMilliseconds;
  }

  Future<void> _remove() async {
    removeComputer(widget.computer.id);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _openSettings() => pushPage(context, ComputerSettings(computer: widget.computer, link: _link, onTest: _testConnection, onRemove: _remove));

  void _pick(DetailTab t) {
    haptic();
    setState(() => _tab = t);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final prefs = getComputerPrefs(widget.computer.id);
    final name = displayName(widget.computer, prefs);
    final online = _link.state == LinkState.online;
    final subtitle = switch (_link.state) {
      LinkState.connecting => 'Connecting…',
      LinkState.offline => 'Offline',
      LinkState.online => _link.route == ComputerRoute.lan ? 'Connected over Wi-Fi' : 'Connected through the cloud',
    };
    final dot = online ? c.success : (_link.state == LinkState.connecting ? c.warning : c.lineStrong);

    return Material(
      color: c.canvas,
      child: Column(
        children: [
          ScreenHeader(
            title: name,
            subtitle: subtitle,
            onBack: () => Navigator.of(context).maybePop(),
            actions: [
              Semantics(
                label: subtitle,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
              ),
              OverflowMenu(
                label: 'Options for $name',
                items: [
                  MenuEntry(
                    'Rename',
                    () => showRenameSheet(
                      context,
                      current: prefs.alias,
                      original: widget.computer.name,
                      onSave: (alias) => setComputerPrefs(widget.computer.id, alias: alias),
                    ),
                    icon: Icons.edit_outlined,
                  ),
                  MenuEntry('Computer settings', _openSettings, icon: Icons.tune_rounded),
                  MenuEntry('Reconnect', _link.reconnect, icon: Icons.sync_rounded),
                  MenuEntry(
                    'Forget this computer',
                    () => showConfirmSheet(
                      context,
                      title: 'Forget $name?',
                      body: 'This phone will no longer control it. You can pair it again any time with a new code.',
                      action: 'Forget',
                      onConfirm: _remove,
                    ),
                    icon: Icons.delete_outline_rounded,
                    danger: true,
                    divider: true,
                  ),
                ],
              ),
            ],
          ),
          _TabStrip(tab: _tab, onPick: _pick, approvals: _approvals.length, chat: _chatActions),
          if (_link.state == LinkState.offline)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ErrorCard(error: _link.error ?? 'This computer is not reachable.', onRetry: _link.reconnect),
            ),
          if (_approvals.isNotEmpty && _tab != DetailTab.approvals)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: () => _pick(DetailTab.approvals),
                child: Notice('${_approvals.first.describe}: waiting for your OK.', tone: NoticeTone.warn),
              ),
            ),
          Expanded(
            child: IndexedStack(
              // The chat stays mounted while another section is open, so what you were typing and the reply on its way are not lost.
              index: _tab == DetailTab.chat ? 0 : 1,
              children: [
                ComputerChat(computerId: widget.computer.id, request: _link.request, online: online, onAsk: _askToAllow, actions: _chatActions),
                switch (_tab) {
                  DetailTab.chat => const SizedBox.shrink(),
                  DetailTab.resources => ResourcesTab(computerId: widget.computer.id, request: _link.request, online: online, route: _link.route),
                  DetailTab.approvals => ApprovalsTab(items: _approvals, onAnswer: _answer, online: online),
                  DetailTab.permissions => PermissionsTab(computerId: widget.computer.id, request: _link.request, online: online),
                  DetailTab.activity => ActivityTab(computerId: widget.computer.id, request: _link.request, online: online),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The strip of sections: icons with names, a badge where something waits, scrolls sideways if the phone is narrow. The chat's own
/// buttons sit at its end while the chat is open, so no row of their own takes space from the conversation.
class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.tab, required this.onPick, required this.approvals, required this.chat});
  final DetailTab tab;
  final void Function(DetailTab t) onPick;
  final int approvals;
  final ChatActions chat;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final (id, label, icon, activeIcon) in _tabs)
                    Semantics(
                      selected: tab == id,
                      button: true,
                      child: InkWell(
                        onTap: () => onPick(id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: tab == id ? c.primary : Colors.transparent, width: 2)),
                          ),
                          child: Row(
                            children: [
                              Icon(tab == id ? activeIcon : icon, size: 18, color: tab == id ? c.primary : c.muted),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: TextStyle(fontSize: 14, fontWeight: tab == id ? FontWeight.w500 : FontWeight.w400, color: tab == id ? c.ink : c.muted),
                              ),
                              if (id == DetailTab.approvals && approvals > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(Radii.pill)),
                                  child: Text(
                                    '$approvals',
                                    style: TextStyle(fontSize: 11, height: 18 / 11, fontWeight: FontWeight.w600, color: c.onPrimary),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (tab == DetailTab.chat)
            ListenableBuilder(
              listenable: chat,
              builder: (context, _) => !chat.ready
                  ? const SizedBox.shrink()
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Chat history',
                          onPressed: chat.history,
                          icon: Icon(Icons.history_rounded, size: 20, color: c.body),
                        ),
                        IconButton(
                          tooltip: 'New chat',
                          onPressed: chat.canNew ? chat.newChat : null,
                          icon: Icon(Icons.edit_note_rounded, size: 22, color: chat.canNew ? c.body : c.mutedSoft),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
