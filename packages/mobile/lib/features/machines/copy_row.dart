import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';

/// A value to copy (an address, a command, a secret), with Show/Hide for secrets.
class CopyRow extends StatefulWidget {
  const CopyRow({super.key, required this.label, required this.value, this.secret = false});
  final String label;
  final String value;
  final bool secret;

  @override
  State<CopyRow> createState() => _CopyRowState();
}

class _CopyRowState extends State<CopyRow> {
  bool _copied = false;
  bool _shown = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    haptic();
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(widget.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.muted)),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(color: c.canvas, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.md)),
        child: Row(children: [
          Expanded(
            child: Text(
              widget.secret && !_shown ? '•' * 24 : widget.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: monoFamily, fontSize: 12.5, color: c.ink),
            ),
          ),
          if (widget.secret)
            TextButton(
              onPressed: () => setState(() => _shown = !_shown),
              style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(_shown ? 'Hide' : 'Show', style: TextStyle(fontSize: 12, color: c.muted)),
            ),
          const SizedBox(width: 4),
          Material(
            color: c.surfaceCard,
            borderRadius: BorderRadius.circular(Radii.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.md),
              onTap: _copy,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(_copied ? 'Copied' : 'Copy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.ink)),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}
