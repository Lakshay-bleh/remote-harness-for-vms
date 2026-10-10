import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cache.dart';
import '../../core/load.dart';
import '../../core/nav.dart';
import '../../core/prefs.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../account/billing_page.dart';
import '../account/help_page.dart';
import '../account/plan_changes.dart';
import '../account/privacy_data_page.dart';
import '../account/security_page.dart';
import '../account/workspace_page.dart';
import '../assistant/chat_state.dart' show AssistantUsage, describeAssistantUsage;
import '../companion/companion.dart' show companionChoice;
import '../companion/companion_settings_page.dart';
import '../computers/computer_api.dart';
import '../voice/voice_settings_page.dart';
import 'account_pages.dart';
import 'developer_page.dart';
import 'info_pages.dart';
import 'notifications_page.dart';
import 'preference_pages.dart';
import 'settings_api.dart';
import 'settings_widgets.dart';

const usageCache = CachePolicy('ai-usage', ttl: Duration(minutes: 1), maxAge: Duration(hours: 24));

/// The sign-out step, shared by Settings and Account. Signing out also forgets the computers paired with this phone.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) => showConfirmSheet(
      context,
      title: 'Sign out?',
      body: 'You will need to sign in again. The computers paired with this phone are removed from it too (you can pair them again any '
          'time). Nothing on those computers is changed.',
      action: 'Sign out',
      onConfirm: () => ref.read(sessionProvider.notifier).signOut(),
    );

/// Settings, laid out like a phone's own: who you are at the top, then groups that each open a page. Everything an account needs
/// (plan and billing, team, security, data and help) is here, inside the app: nothing sends the person to the website.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final Loader<Map<String, dynamic>> _usage;

  @override
  void initState() {
    super.initState();
    loadAppVersion();
    _usage = Loader(fetchUsage, every: const Duration(minutes: 2), cache: usageCache);
    planChanges.addListener(_usage.reload);
  }

  @override
  void dispose() {
    planChanges.removeListener(_usage.reload);
    _usage.dispose();
    super.dispose();
  }

  void _to(Widget page) => pushPage(context, page);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final user = ref.watch(sessionProvider).user;
    final prefs = ref.watch(prefsProvider);
    final computers = loadComputers().length;
    final themeValue = switch (prefs.theme) {
      ThemeChoice.system => 'Match phone',
      ThemeChoice.dark => null,
      ThemeChoice.light => 'Light',
      ThemeChoice.black => 'Pure black',
    };

    return Material(
      color: c.canvas,
      child: Column(children: [
        const ScreenHeader(title: 'Settings'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              ECard(
                padding: const EdgeInsets.all(14),
                onTap: () {
                  haptic();
                  _to(const AccountPage());
                },
                child: Row(children: [
                  Avatar(name: user?.name, email: user?.email),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, color: c.ink)),
                      Text(user?.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.muted)),
                    ]),
                  ),
                  Text('Account', style: TextStyle(fontSize: 13, color: c.muted)),
                ]),
              ),
              const SizedBox(height: 24),
              ListenableBuilder(
                listenable: _usage,
                builder: (context, _) {
                  final u = _usage.data == null ? null : describeAssistantUsage(AssistantUsage.fromJson(_usage.data));
                  return Group(title: 'Plan', children: [
                    SRow(icon: Icons.account_balance_wallet_outlined, label: 'Plan and billing', onTap: () => _to(const BillingPage())),
                    SRow(icon: Icons.account_balance_wallet_outlined, label: 'Usage', sub: u?.messages, onTap: () => _to(const UsagePage())),
                  ]);
                },
              ),
              const SizedBox(height: 24),
              Group(title: 'Account', children: [
                SRow(icon: Icons.groups_outlined, label: 'Workspace and team', onTap: () => _to(const WorkspacePage())),
                SRow(icon: Icons.lock_outline_rounded, label: 'Security', sub: 'Two-step verification, delete account', onTap: () => _to(const SecurityPage())),
                SRow(
                  icon: Icons.verified_user_outlined,
                  label: 'Privacy and your data',
                  sub: 'Choices, copy of your data, requests',
                  onTap: () => _to(const PrivacyDataPage()),
                ),
              ]),
              const SizedBox(height: 24),
              Group(title: 'Preferences', children: [
                SRow(icon: Icons.notifications_none_rounded, label: 'Notifications', onTap: () => _to(const NotificationsPage())),
                SRow(icon: Icons.brush_outlined, label: 'Appearance and feel', value: themeValue, onTap: () => _to(const AppearancePage())),
                ValueListenableBuilder(
                  valueListenable: companionChoice,
                  builder: (context, _, _) =>
                      SRow(icon: Icons.pets_rounded, label: 'Companion', value: companionLabel(), onTap: () => _to(const CompanionSettingsPage())),
                ),
                SRow(icon: Icons.chat_outlined, label: 'New chats', sub: 'Permissions, model and effort', onTap: () => _to(const ChatDefaultsPage())),
                SRow(
                  icon: Icons.graphic_eq_rounded,
                  label: 'Voice and phone control',
                  sub: 'Hey Escanor, calling, controlling your phone',
                  onTap: () => _to(const VoiceSettingsPage()),
                ),
              ]),
              const SizedBox(height: 24),
              Group(title: 'Connected', children: [
                SRow(
                  icon: Icons.dns_outlined,
                  label: 'Machines and computers',
                  value: computers > 0 ? '$computers paired' : null,
                  onTap: () => ref.read(navProvider.notifier).go(AppTab.machines),
                ),
                SRow(icon: Icons.bolt_rounded, label: 'Automations', onTap: () => ref.read(navProvider.notifier).go(AppTab.automations)),
                SRow(icon: Icons.cable_rounded, label: 'Connections', onTap: () => ref.read(navProvider.notifier).go(AppTab.connections)),
              ]),
              const SizedBox(height: 24),
              ValueListenableBuilder<String>(
                valueListenable: appVersion,
                builder: (context, version, _) => Group(title: 'More', children: [
                  SRow(icon: Icons.support_outlined, label: 'Help', onTap: () => _to(const HelpPage())),
                  SRow(icon: Icons.code_rounded, label: 'Developer', onTap: () => _to(const DeveloperPage())),
                  SRow(icon: Icons.verified_user_outlined, label: 'Privacy and legal', onTap: () => _to(const PrivacyPage())),
                  SRow(icon: Icons.info_outline_rounded, label: 'About', value: version, onTap: () => _to(const AboutPage())),
                ]),
              ),
              const SizedBox(height: 24),
              Group(children: [
                SRow(icon: Icons.logout_rounded, label: 'Sign out', danger: true, onTap: () => confirmSignOut(context, ref)),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}
