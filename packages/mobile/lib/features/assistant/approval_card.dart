import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'chat_state.dart';

/// "Should I go ahead?" in plain words. The only thing the assistant asks a person for.
class ApprovalCard extends StatefulWidget {
  const ApprovalCard({super.key, required this.item, required this.onAnswer});
  final AssistantItem item;
  final void Function(bool allow) onAnswer;

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final item = widget.item;
    final high = item.risk == 'high';
    final answered = item.status != 'pending';
    final tone = high ? c.error : c.permission;

    return Semantics(
      container: true,
      label: 'Permission needed',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.05),
          border: Border.all(color: tone.withValues(alpha: high ? 0.4 : 0.3)),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((high ? 'Needs your care' : 'Needs your OK').toUpperCase(),
              style: TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: c.muted)),
          const SizedBox(height: 4),
          Text(item.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink)),
          if (item.detail.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(item.detail, style: TextStyle(fontSize: 14, color: c.body))),
          if (item.raw.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _details = !_details),
              child: Text(_details ? 'Hide details' : 'Show details',
                  style: TextStyle(fontSize: 12, color: c.muted, decoration: TextDecoration.underline, decorationColor: c.muted)),
            ),
            if (_details)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                constraints: const BoxConstraints(maxHeight: 192),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.code, borderRadius: BorderRadius.circular(Radii.md)),
                child: SingleChildScrollView(
                  child: SelectableText(item.raw, style: TextStyle(fontFamily: monoFamily, fontSize: 12, color: c.onCode)),
                ),
              ),
          ],
          const SizedBox(height: 12),
          if (answered)
            Text(item.status == 'allowed' ? 'You said continue.' : (item.status == 'denied' ? 'You said no.' : ''), style: TextStyle(fontSize: 14, color: c.muted))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              EButton(
                label: 'Continue',
                onPressed: () {
                  haptic();
                  widget.onAnswer(true);
                },
              ),
              EButton(
                label: 'Don’t do this',
                kind: ButtonKind.quiet,
                onPressed: () {
                  haptic();
                  widget.onAnswer(false);
                },
              ),
            ]),
        ]),
      ),
    );
  }
}
