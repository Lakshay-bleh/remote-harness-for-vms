import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../companion/dog_state.dart';
import 'protocol/protocol.dart';

/// Actions on the computer that are waiting for a person's OK. With none waiting, a dog keeps watch.
class ApprovalsTab extends StatelessWidget {
  const ApprovalsTab({super.key, required this.items, required this.onAnswer, required this.online});
  final List<Approval> items;
  final void Function(Approval a, bool ok) onAnswer;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (items.isEmpty) {
      return SingleChildScrollView(
        child: online
            ? const DogState(
                scene: 'sit',
                title: 'All clear',
                text: 'Nothing is waiting for your OK. When your computer needs a yes before it does something, it will ask here.',
              )
            : const DogState(scene: 'sleep', title: 'Your computer is offline', text: 'Approvals will show up here once it is back.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        for (final a in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (a.risk == 'destructive' ? c.error : c.permission).withValues(alpha: 0.05),
                border: Border.all(color: (a.risk == 'destructive' ? c.error : c.permission).withValues(alpha: a.risk == 'destructive' ? 0.4 : 0.3)),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    (a.risk == 'destructive' ? 'Needs your care' : 'Needs your OK').toUpperCase(),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.6, color: c.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    a.describe,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 128),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.code, borderRadius: BorderRadius.circular(Radii.sm)),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(a.input),
                        style: TextStyle(fontFamily: monoFamily, fontSize: 12, color: c.onCode),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      EButton(label: 'Continue', onPressed: () => onAnswer(a, true)),
                      EButton(label: 'Don’t do this', kind: ButtonKind.quiet, onPressed: () => onAnswer(a, false)),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
