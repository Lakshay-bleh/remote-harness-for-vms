import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/nav.dart';
import '../core/prefs.dart';
import '../core/theme.dart';
import '../features/account/deletion_notice.dart';
import '../features/account/policy_gate.dart';
import '../features/assistant/assistant_screen.dart';
import '../features/assistant/chat_drawer.dart';
import '../features/companion/buddy.dart';
import '../features/computers/computers_screen.dart';
import '../features/connections/connections_screen.dart';
import '../features/machines/machines_screen.dart';
import '../features/push/push_host.dart';
import '../features/settings/settings_screen.dart';
import '../features/voice/voice_host.dart';

const _tabs = <(AppTab, String, IconData, IconData)>[
  (AppTab.assistant, 'Chat', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
  (AppTab.computers, 'Computers', Icons.laptop_outlined, Icons.laptop_rounded),
  (AppTab.connections, 'Connections', Icons.cable_outlined, Icons.cable_rounded),
  (AppTab.machines, 'Machines', Icons.dns_outlined, Icons.dns_rounded),
  (AppTab.settings, 'Settings', Icons.settings_outlined, Icons.settings_rounded),
];

Widget _screenFor(AppTab t) => switch (t) {
      AppTab.assistant => const AssistantScreen(),
      AppTab.computers => const ComputersScreen(),
      AppTab.connections => const ConnectionsScreen(),
      AppTab.machines => const MachinesScreen(),
      AppTab.settings => const SettingsScreen(),
    };

/// The signed-in app. Phones get a tab bar along the bottom with the chats in a drawer from the Chat
/// screen; tablets get a side rail, and wide screens the rail plus the chat list.
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => openChatDrawer.value = () => _scaffold.currentState?.openDrawer());
  }

  @override
  void dispose() {
    openChatDrawer.value = null;
    super.dispose();
  }

  void _pick(AppTab t) {
    haptic();
    final nav = ref.read(navProvider);
    if (nav.tab == t) tabNavigatorKeys[t]!.currentState?.popUntil((r) => r.isFirst);
    ref.read(navProvider.notifier).go(t);
  }

  /// The phone's back button: close the drawer, else go back inside the tab, else leave a tab for Chat,
  /// else (nothing left to undo) put the app in the background.
  void _back() {
    final s = _scaffold.currentState;
    if (s != null && s.isDrawerOpen) {
      s.closeDrawer();
      return;
    }
    final tab = ref.read(navProvider).tab;
    final inner = tabNavigatorKeys[tab]!.currentState;
    if (inner != null && inner.canPop()) {
      inner.maybePop();
      return;
    }
    if (tab != AppTab.assistant) {
      ref.read(navProvider.notifier).go(AppTab.assistant);
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(navProvider);
    final c = context.c;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 768;
    final expanded = width >= 1024;

    final stack = IndexedStack(
      index: AppTab.values.indexOf(nav.tab),
      children: [
        for (final t in AppTab.values)
          nav.visited.contains(t)
              ? _TabNavigator(key: ValueKey('${t.name}-${nav.resets[t] ?? 0}'), tab: t, child: _screenFor(t))
              : const SizedBox.shrink(),
      ],
    );

    final body = Row(children: [
      if (wide) _Rail(tab: nav.tab, onPick: _pick, expanded: expanded),
      if (expanded)
        Container(
          width: 300,
          decoration: BoxDecoration(color: c.surfaceSoft, border: Border(right: BorderSide(color: c.hairline))),
          child: const SafeArea(right: false, child: ChatDrawer(inSidebar: true)),
        ),
      Expanded(child: SafeArea(bottom: false, left: !wide, child: stack)),
    ]);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: VoiceHost(
        child: PushHost(
          // Over everything, the tab bar included: an account waiting to be deleted, else the Terms (and the rules every three months).
          child: Stack(fit: StackFit.expand, children: [
            Scaffold(
              key: _scaffold,
              backgroundColor: c.canvas,
              drawer: wide
                  ? null
                  : Drawer(
                      width: (width * 0.88).clamp(0, 320).toDouble(),
                      backgroundColor: c.surfaceSoft,
                      shape: const RoundedRectangleBorder(),
                      child: const SafeArea(right: false, child: ChatDrawer()),
                    ),
              drawerEnableOpenDragGesture: nav.tab == AppTab.assistant,
              body: Stack(children: [
                body,
                const Buddy(),
              ]),
              bottomNavigationBar: wide ? null : _TabBar(tab: nav.tab, onPick: _pick),
            ),
            const DeletionNotice(otherwise: PolicyGate()),
          ]),
        ),
      ),
    );
  }
}

/// Each tab keeps its own stack of pages.
class _TabNavigator extends StatelessWidget {
  const _TabNavigator({super.key, required this.tab, required this.child});
  final AppTab tab;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: tabNavigatorKeys[tab],
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tab, required this.onPick});
  final AppTab tab;
  final void Function(AppTab) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Steps aside while the keyboard is up, so it never sits on top of the message field.
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(color: c.surfaceSoft, border: Border(top: BorderSide(color: c.hairline))),
      child: SafeArea(
        top: false,
        child: Row(children: [
          for (final (t, label, icon, active) in _tabs)
            Expanded(
              child: Semantics(
                selected: tab == t,
                button: true,
                label: label,
                child: InkWell(
                  onTap: () => onPick(t),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 48,
                        height: 28,
                        decoration: BoxDecoration(
                          color: tab == t ? c.primary.withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Icon(tab == t ? active : icon, size: 22, color: tab == t ? c.primary : c.muted),
                      ),
                      const SizedBox(height: 2),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(fontSize: 11, color: tab == t ? c.ink : c.muted, fontWeight: tab == t ? FontWeight.w500 : FontWeight.w400)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.tab, required this.onPick, required this.expanded});
  final AppTab tab;
  final void Function(AppTab) onPick;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(color: c.surfaceSoft, border: Border(right: BorderSide(color: c.hairline))),
      child: SafeArea(
        right: false,
        child: NavigationRail(
          backgroundColor: Colors.transparent,
          selectedIndex: AppTab.values.indexOf(tab),
          onDestinationSelected: (i) => onPick(AppTab.values[i]),
          labelType: NavigationRailLabelType.all,
          indicatorColor: c.primary.withValues(alpha: 0.15),
          selectedIconTheme: IconThemeData(color: c.primary),
          unselectedIconTheme: IconThemeData(color: c.muted),
          selectedLabelTextStyle: TextStyle(color: c.ink, fontSize: 12, fontWeight: FontWeight.w500),
          unselectedLabelTextStyle: TextStyle(color: c.muted, fontSize: 12),
          leading: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Image.asset('assets/images/brand-mark.png', width: 34, height: 34)),
          destinations: [
            for (final (_, label, icon, active) in _tabs)
              NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(active), label: Text(label)),
          ],
        ),
      ),
    );
  }
}
