import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';

class MenuEntry {
  const MenuEntry(this.label, this.onTap, {this.icon, this.danger = false, this.divider = false});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool danger;

  /// A line above this entry (it starts a group of its own, such as the destructive one).
  final bool divider;
}

/// The "⋮" menu of a card or a screen (the web app's OverflowMenu).
class OverflowMenu extends StatelessWidget {
  const OverflowMenu({super.key, required this.label, required this.items});

  /// What a screen reader says for the button: "Options for Work Laptop".
  final String label;
  final List<MenuEntry> items;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final entries = <PopupMenuEntry<int>>[];
    for (final (i, e) in items.indexed) {
      if (e.divider && i > 0) entries.add(const PopupMenuDivider());
      final color = e.danger ? c.error : c.ink;
      entries.add(
        PopupMenuItem<int>(
          value: i,
          child: Row(
            children: [
              if (e.icon != null) ...[Icon(e.icon, size: 18, color: e.danger ? c.error : c.body), const SizedBox(width: 12)] else const SizedBox(width: 30),
              Flexible(
                child: Text(
                  e.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: color),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return PopupMenuButton<int>(
      tooltip: label,
      icon: Icon(Icons.more_vert_rounded, color: c.body),
      color: c.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: c.hairline),
      ),
      onOpened: haptic,
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (_) => entries,
    );
  }
}
