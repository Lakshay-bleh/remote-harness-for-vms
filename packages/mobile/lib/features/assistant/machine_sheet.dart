import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/load.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'assistant_api.dart';
import 'chat_state.dart';

const _labels = {
  'running': 'Running',
  'starting': 'Starting',
  'sleeping': 'Asleep, wakes when you chat',
  'stopped': 'Stopped',
  'unavailable': 'Unavailable',
  'unknown': 'Not started yet',
};
const _events = {
  'machine.started': 'Machine started',
  'machine.woke': 'Machine woke up',
  'machine.slept': 'Machine went to sleep',
  'git.push': 'Pushed a branch',
  'git.push_blocked': 'A push to a protected branch was blocked',
};

String machineLabel(String state) => _labels[state] ?? state;

Color machineTone(EscanorColors c, String state) => switch (state) {
      'running' => c.success,
      'unavailable' => c.error,
      'sleeping' => c.mutedSoft,
      _ => c.amber,
    };

/// What the assistant's machine is doing, and what it has done: the cloud side of "make this change".
Future<void> showMachineSheet(BuildContext context) =>
    showESheet<void>(context, title: 'Your assistant’s machine', builder: (_) => const _MachineBody());

class _MachineBody extends StatefulWidget {
  const _MachineBody();
  @override
  State<_MachineBody> createState() => _MachineBodyState();
}

class _MachineBodyState extends State<_MachineBody> {
  late final Loader<MachineView> _machine = Loader(() => api.assistantMachine(logs: true), every: const Duration(seconds: 3));

  @override
  void initState() {
    super.initState();
    _machine.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _machine.removeListener(_changed);
    _machine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = _machine.data;
    final heading = TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: c.muted);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (_machine.loading && m == null) const Padding(padding: EdgeInsets.all(16), child: Center(child: Spinner())),
      if (_machine.error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Notice(_machine.error!, tone: NoticeTone.error)),
      if (m != null) ...[
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: machineTone(c, m.state), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(machineLabel(m.state), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink))),
        ]),
        if (m.detail.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(m.detail, style: TextStyle(fontSize: 14, color: c.body))),
        if (!m.available) const Padding(padding: EdgeInsets.only(top: 12), child: Notice('Live details appear once your assistant’s machine service is connected.')),
        if (m.events.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('RECENT ACTIVITY', style: heading),
          const SizedBox(height: 6),
          for (final e in m.events.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: _events[e.kind] ?? e.kind, style: TextStyle(color: c.ink)),
                    if (e.detail.isNotEmpty) TextSpan(text: ' · ${e.detail}'),
                  ]), style: TextStyle(fontSize: 14, color: c.body)),
                ),
                const SizedBox(width: 12),
                Text(ago(e.at), style: TextStyle(fontSize: 12, color: c.mutedSoft)),
              ]),
            ),
        ],
        if ((m.logs ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('LIVE OUTPUT', style: heading),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 256),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.code, borderRadius: BorderRadius.circular(Radii.md)),
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(m.logs!, style: TextStyle(fontFamily: monoFamily, fontSize: 11, height: 1.5, color: c.onCode)),
            ),
          ),
        ],
      ],
    ]);
  }
}
