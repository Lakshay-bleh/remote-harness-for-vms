import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import 'computer_link.dart';
import 'computer_prefs.dart';
import 'computers_screen.dart' show pairedDate;
import 'protocol/client.dart';
import 'rename_sheet.dart';

const routeChoices = <Choice<RoutePref>>[
  Choice(RoutePref.auto, 'Automatic', 'Wi-Fi when the computer is on it, otherwise through the cloud'),
  Choice(RoutePref.cloud, 'Cloud only', 'Always through your Escanor account, from anywhere'),
  Choice(RoutePref.lan, 'Wi-Fi only', 'Only when this phone is on the same network. Nothing goes through the cloud'),
];

String routeLabel(RoutePref r) => routeChoices.firstWhere((c) => c.value == r).label;

/// One computer's own settings: its name here, how to reach it, what the phone knows about it, and forgetting it.
class ComputerSettings extends StatefulWidget {
  const ComputerSettings({super.key, required this.computer, required this.link, required this.onTest, required this.onRemove});
  final PairedComputer computer;
  final ComputerLink link;

  /// Round trip time, in ms.
  final Future<int> Function() onTest;
  final Future<void> Function() onRemove;

  @override
  State<ComputerSettings> createState() => _ComputerSettingsState();
}

class _ComputerSettingsState extends State<ComputerSettings> {
  bool _testing = false;
  String? _testText;

  @override
  void initState() {
    super.initState();
    computerPrefsChanges.addListener(_changed);
    widget.link.addListener(_changed);
  }

  @override
  void dispose() {
    computerPrefsChanges.removeListener(_changed);
    widget.link.removeListener(_changed);
    super.dispose();
  }

  void _changed() => mounted ? setState(() {}) : null;

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _testText = null;
    });
    String text;
    try {
      text = 'Answered in ${await widget.onTest()} ms';
    } catch (_) {
      text = 'Did not answer';
    }
    if (mounted) {
      setState(() {
        _testing = false;
        _testText = text;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final computer = widget.computer;
    final prefs = getComputerPrefs(computer.id);
    final name = displayName(computer, prefs);
    final link = widget.link;
    final status = switch (link.state) {
      LinkState.online => 'Connected · ${link.route == ComputerRoute.lan ? 'Wi-Fi' : 'cloud'}',
      LinkState.connecting => 'Connecting…',
      LinkState.offline => 'Offline',
    };
    return SettingsPage(
      title: name,
      subtitle: 'Settings for this computer',
      children: [
        Group(
          title: 'Name',
          children: [
            SRow(
              icon: Icons.edit_outlined,
              label: 'Name on this phone',
              value: name,
              onTap: () => showRenameSheet(
                context,
                current: prefs.alias,
                original: computer.name,
                onSave: (alias) => setComputerPrefs(computer.id, alias: alias),
              ),
            ),
          ],
        ),
        Group(
          title: 'Connection',
          footer: 'Wi-Fi only never uses the cloud, so it will not work when you are away from home.',
          children: [
            SRow(
              icon: prefs.route == RoutePref.lan ? Icons.wifi_rounded : Icons.cloud_outlined,
              label: 'How to reach it',
              value: routeLabel(prefs.route),
              onTap: () async {
                final r = await showChoiceSheet<RoutePref>(context, title: 'How to reach it', options: routeChoices, value: prefs.route);
                if (r != null) setComputerPrefs(computer.id, route: r);
              },
            ),
            SRow(icon: Icons.monitor_heart_outlined, label: 'Status', value: status),
            SRow(
              icon: Icons.sync_rounded,
              label: 'Test the connection',
              value: _testing ? null : _testText,
              right: _testing ? const Spinner(size: 24) : null,
              chevron: false,
              disabled: _testing,
              onTap: _runTest,
            ),
            SRow(icon: Icons.sync_rounded, label: 'Reconnect now', chevron: false, onTap: link.reconnect),
          ],
        ),
        Group(
          title: 'About this computer',
          children: [
            SRow(icon: Icons.badge_outlined, label: 'Its own name', value: computer.name),
            SRow(label: 'Paired', value: pairedDate(computer.pairedAt)),
            SRow(label: 'Works away from home', value: (computer.agentId ?? '').isNotEmpty ? 'Yes' : 'No: Wi-Fi only'),
            SRow(label: 'Wi-Fi addresses', sub: computer.lan.isNotEmpty ? computer.lan.join(', ') : 'None saved'),
            SRow(
              label: 'This phone’s ID on it',
              right: Text(
                computer.id.length > 8 ? computer.id.substring(0, 8) : computer.id,
                style: TextStyle(fontFamily: monoFamily, fontSize: 14, color: c.muted),
              ),
            ),
          ],
        ),
        Group(
          footer: 'This only removes it from this phone. To stop this phone being able to control the computer at all, also remove the phone on the computer: Escanor Desktop → Phone → Paired phones.',
          children: [
            SRow(
              icon: Icons.delete_outline_rounded,
              label: 'Forget this computer',
              danger: true,
              onTap: () => showConfirmSheet(
                context,
                title: 'Forget $name?',
                body: 'This phone will no longer control it. You can pair it again any time with a new code.',
                action: 'Forget',
                onConfirm: widget.onRemove,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
