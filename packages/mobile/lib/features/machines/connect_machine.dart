import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'copy_row.dart';
import 'managed.dart';

/// How to put the agent on a VM, with this person's hub address and secret already filled in (ConnectMachine.tsx).
Future<void> showConnectMachineSheet(BuildContext context, ManagedHub hub) =>
    showESheet<void>(context, title: 'Connect a machine', builder: (_) => ConnectMachineBody(hub: hub));

class ConnectMachineBody extends StatefulWidget {
  const ConnectMachineBody({super.key, required this.hub});
  final ManagedHub hub;
  @override
  State<ConnectMachineBody> createState() => _ConnectMachineBodyState();
}

class _ConnectMachineBodyState extends State<ConnectMachineBody> {
  bool _manual = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hub = widget.hub;
    final guide = hub.guideUrl;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(
        'Run this on the server you want to control. It installs the agent and points it at your hub, so it appears here as soon as it starts.',
        style: TextStyle(fontSize: 14, height: 1.45, color: c.body),
      ),
      if (hub.installCommand != null) ...[const SizedBox(height: 16), CopyRow(label: 'Run on your VM', value: hub.installCommand!, secret: true)],
      const SizedBox(height: 16),
      Container(
        decoration: BoxDecoration(border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.md)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _manual = !_manual),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(_manual ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 18, color: c.muted),
                const SizedBox(width: 4),
                Expanded(child: Text('Prefer to enter them yourself?', style: TextStyle(fontSize: 13, color: c.muted))),
              ]),
            ),
          ),
          if (_manual)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (hub.agentUrl != null) CopyRow(label: 'Hub URL', value: hub.agentUrl!),
                if (hub.agentUrl != null && hub.agentToken != null) const SizedBox(height: 12),
                if (hub.agentToken != null) CopyRow(label: 'Secret', value: hub.agentToken!, secret: true),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      const Notice('The secret lets a machine join your hub. Keep it to yourself; it works for your machines only.', tone: NoticeTone.warn),
      if (guide != null && RegExp(r'^https://', caseSensitive: false).hasMatch(guide)) ...[
        const SizedBox(height: 16),
        EButton(label: 'Read the setup guide', expand: true, onPressed: () => launchUrl(Uri.parse(guide), mode: LaunchMode.externalApplication)),
      ],
    ]);
  }
}
