import 'package:flutter/material.dart';

import '../../core/nav.dart';
import '../../core/prefs.dart' show haptic;
import '../../core/theme.dart';
import '../computers/computers_screen.dart';
import 'machines_screen.dart';

/// Servers and computers are one place. Your servers (VMs running the Escanor agent, reached through your hub) and your computers
/// (running Escanor Desktop, paired with a code) are both "a machine Escanor works on", so they share one tab with a switch,
/// instead of two tabs that look alike.
class MachinesHome extends StatefulWidget {
  const MachinesHome({super.key});
  @override
  State<MachinesHome> createState() => _MachinesHomeState();
}

class _MachinesHomeState extends State<MachinesHome> {
  final Set<int> _opened = {};

  @override
  void initState() {
    super.initState();
    _opened.add(machinesSegment.value);
    machinesSegment.addListener(_changed);
  }

  @override
  void dispose() {
    machinesSegment.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() => _opened.add(machinesSegment.value));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final seg = machinesSegment.value;
    Widget chip(int i, String label, IconData icon) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            selected: seg == i,
            showCheckmark: false,
            avatar: Icon(icon, size: 16, color: seg == i ? c.primary : c.muted),
            label: Text(label),
            onSelected: (_) {
              haptic();
              machinesSegment.value = i;
            },
          ),
        );
    return Material(
      color: c.canvas,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            chip(0, 'Servers', Icons.dns_outlined),
            chip(1, 'Computers', Icons.laptop_outlined),
          ]),
        ),
        Expanded(
          child: IndexedStack(index: seg, children: [
            _opened.contains(0) ? const MachinesScreen() : const SizedBox.shrink(),
            _opened.contains(1) ? const ComputersScreen() : const SizedBox.shrink(),
          ]),
        ),
      ]),
    );
  }
}
