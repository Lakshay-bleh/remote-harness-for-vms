import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'errors.dart';

const _where = <FixWhere, (String, IconData)>{
  FixWhere.computer: ('Fix it on your computer', Icons.desktop_windows_rounded),
  FixWhere.phone: ('Fix it in this app', Icons.smartphone_rounded),
  FixWhere.both: ('Check both devices', Icons.sync_alt_rounded),
};

/// An error, explained: what happened, which device the fix is on, and the steps. When the cause is a permission switched off for
/// phones it also offers to ask the computer to allow it (the computer's owner then says yes there; the phone cannot grant itself).
class ErrorCard extends StatefulWidget {
  const ErrorCard({super.key, required this.error, this.onRetry, this.onAsk});
  final Object? error;
  final VoidCallback? onRetry;
  final Future<String> Function(String groupLabel)? onAsk;

  @override
  State<ErrorCard> createState() => _ErrorCardState();
}

class _ErrorCardState extends State<ErrorCard> {
  bool _asking = false;
  String? _answer;

  Future<void> _ask(String label) async {
    final onAsk = widget.onAsk;
    if (onAsk == null) return;
    setState(() {
      _asking = true;
      _answer = null;
    });
    String answer;
    try {
      answer = await onAsk(label);
    } catch (err) {
      answer = explainComputerFailure(err).title;
    }
    if (mounted) {
      setState(() {
        _asking = false;
        _answer = answer;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final e = explainComputerFailure(widget.error);
    final (label, icon) = _where[e.where]!;
    final canAsk = e.askGroupLabel != null && widget.onAsk != null;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.warning.withValues(alpha: 0.05),
          border: Border.all(color: c.warning.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(icon, size: 14, color: c.muted),
                const SizedBox(width: 6),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.6, color: c.muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final (i, s) in e.steps.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text('${i + 1}.', style: TextStyle(fontSize: 14, height: 1.35, color: c.body)),
                    ),
                    Expanded(
                      child: Text(s, style: TextStyle(fontSize: 14, height: 1.35, color: c.body)),
                    ),
                  ],
                ),
              ),
            if (canAsk || widget.onRetry != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canAsk) EButton(label: _asking ? 'Asking…' : 'Ask my computer to allow it', onPressed: _asking ? null : () => _ask(e.askGroupLabel!)),
                  if (widget.onRetry != null) EButton(label: 'Try again', kind: ButtonKind.quiet, onPressed: widget.onRetry),
                ],
              ),
            ],
            if (_asking)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Spinner(size: 24),
                    const SizedBox(width: 8),
                    Text('Sending the request…', style: TextStyle(fontSize: 13, color: c.muted)),
                  ],
                ),
              ),
            if (_answer != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_answer!, style: TextStyle(fontSize: 13, height: 1.35, color: c.body)),
              ),
          ],
        ),
      ),
    );
  }
}
