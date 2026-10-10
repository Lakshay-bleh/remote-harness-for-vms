import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs.dart';

/// The places, in the order they appear on the phone's tab bar.
enum AppTab { assistant, machines, automations, connections, settings }

/// Which half of the Machines tab is showing: 0 your servers (VMs), 1 your computers running Escanor Desktop. They are one place now.
final ValueNotifier<int> machinesSegment = ValueNotifier<int>(0);

/// A tab by name. The old "computers" tab is the Desktops half of Machines.
AppTab tabFromName(String? name) {
  if (name == 'computers') {
    machinesSegment.value = 1;
    return AppTab.machines;
  }
  return AppTab.values.firstWhere((t) => t.name == name, orElse: () => AppTab.assistant);
}

class NavState {
  const NavState({required this.tab, this.conversationId, this.resets = const {}, this.visited = const {}});
  final AppTab tab;

  /// The open assistant conversation; null = a new chat.
  final String? conversationId;

  /// Bumped when the tab you are already on is pressed again: that tab goes back to its first screen.
  final Map<AppTab, int> resets;

  /// Tabs opened at least once (they stay mounted after that, so going back keeps their place).
  final Set<AppTab> visited;

  NavState copyWith({AppTab? tab, String? conversationId, bool clearConversation = false, Map<AppTab, int>? resets, Set<AppTab>? visited}) => NavState(
        tab: tab ?? this.tab,
        conversationId: clearConversation ? null : (conversationId ?? this.conversationId),
        resets: resets ?? this.resets,
        visited: visited ?? this.visited,
      );
}

class NavNotifier extends Notifier<NavState> {
  @override
  NavState build() {
    final start = tabFromName(currentPrefs().startTab);
    return NavState(tab: start, visited: {AppTab.assistant, start});
  }

  /// Go to a tab. Pressing the tab you are on takes it back to its first screen.
  void go(AppTab t) {
    final resets = Map<AppTab, int>.of(state.resets);
    if (state.tab == t) resets[t] = (resets[t] ?? 0) + 1;
    state = state.copyWith(tab: t, resets: resets, visited: {...state.visited, t});
  }

  /// Open an assistant conversation (null = new chat) on the Chat tab.
  void openChat(String? id) {
    state = NavState(tab: AppTab.assistant, conversationId: id, resets: state.resets, visited: {...state.visited, AppTab.assistant});
  }

  void setConversation(String? id) => state = id == null ? state.copyWith(clearConversation: true) : state.copyWith(conversationId: id);
}

final navProvider = NotifierProvider<NavNotifier, NavState>(NavNotifier.new);

/// One navigator per tab, so a page pushed inside a tab (Settings > Billing) keeps the tab bar and is
/// popped by the back button first.
final tabNavigatorKeys = {for (final t in AppTab.values) t: GlobalKey<NavigatorState>(debugLabel: 'tab-${t.name}')};

/// Opens the phone's chat drawer (set by the shell; null where the sidebar is always visible).
final ValueNotifier<VoidCallback?> openChatDrawer = ValueNotifier<VoidCallback?>(null);
