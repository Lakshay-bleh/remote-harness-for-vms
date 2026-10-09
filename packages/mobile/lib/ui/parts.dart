import 'package:flutter/material.dart';

import '../core/prefs.dart';
import '../core/theme.dart';
import 'widgets.dart';

/// Settings-style building blocks (pages, grouped rows, switches, choice and confirm sheets), shared by
/// Settings, account pages and a computer's settings.

/// One page pushed inside a tab: the shared header with a back arrow, then the scrolling body.
/// The phone's back button steps out of it (it is a route in the tab's navigator).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, this.subtitle, required this.children, this.actions = const [], this.onBack});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> actions;

  /// Defaults to popping this route.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.c.canvas,
      child: Column(children: [
        ScreenHeader(title: title, subtitle: subtitle, onBack: onBack ?? () => Navigator.of(context).maybePop(), actions: actions),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(height: 24),
            itemBuilder: (_, i) => children[i],
          ),
        ),
      ]),
    );
  }
}

/// Push a page inside the current tab.
Future<T?> pushPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

/// A titled card of rows: a small label above, a footnote below.
class Group extends StatelessWidget {
  const Group({super.key, this.title, this.footer, required this.children});
  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, thickness: 1, color: c.hairline));
      rows.add(children[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title!.toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: c.muted)),
        ),
      Container(
        decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.xl)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      ),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 6),
          child: Text(footer!, style: TextStyle(fontSize: 12, height: 1.45, color: c.muted)),
        ),
    ]);
  }
}

/// One row of a [Group].
class SRow extends StatelessWidget {
  const SRow({super.key, required this.label, this.sub, this.value, this.icon, this.onTap, this.danger = false, this.chevron, this.right, this.disabled = false});
  final String label;
  final String? sub;

  /// What is chosen now, shown on the right.
  final String? value;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger;
  final bool? chevron;
  final Widget? right;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(children: [
          if (icon != null) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: danger ? c.error.withValues(alpha: 0.1) : c.canvas, borderRadius: BorderRadius.circular(Radii.lg)),
              child: Icon(icon, size: 18, color: danger ? c.error : c.body),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: danger ? c.error : c.ink)),
              if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: TextStyle(fontSize: 12, height: 1.35, color: c.muted))),
            ]),
          ),
          if (value != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(fontSize: 14, color: c.muted)),
              ),
            ),
          ?right,
          if (onTap != null && chevron != false) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.chevron_right_rounded, size: 20, color: c.mutedSoft)),
        ]),
      ),
    );
    if (onTap == null) return body;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: InkWell(
        onTap: disabled
            ? null
            : () {
                haptic();
                onTap!();
              },
        child: body,
      ),
    );
  }
}

class ESwitch extends StatelessWidget {
  const ESwitch({super.key, required this.on, required this.onChanged, this.disabled = false});
  final bool on;
  final ValueChanged<bool> onChanged;
  final bool disabled;
  @override
  Widget build(BuildContext context) => Switch(
        value: on,
        onChanged: disabled
            ? null
            : (v) {
                haptic();
                onChanged(v);
              },
      );
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.label, this.sub, required this.on, required this.onChanged, this.disabled = false, this.icon});
  final String label;
  final String? sub;
  final bool on;
  final ValueChanged<bool> onChanged;
  final bool disabled;
  final IconData? icon;
  @override
  Widget build(BuildContext context) =>
      SRow(label: label, sub: sub, icon: icon, right: ESwitch(on: on, onChanged: onChanged, disabled: disabled));
}

class Choice<T> {
  const Choice(this.value, this.label, [this.hint]);
  final T value;
  final String label;
  final String? hint;
}

/// Pick one of a few options from a bottom sheet. Returns the picked value, or null when dismissed.
Future<T?> showChoiceSheet<T>(BuildContext context, {required String title, required List<Choice<T>> options, required T value}) {
  return showESheet<T>(context, title: title, builder: (ctx) {
    final c = ctx.c;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final o in options)
        InkWell(
          onTap: () {
            haptic();
            Navigator.of(ctx).pop(o.value);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.label, style: TextStyle(fontSize: 15, color: c.ink)),
                  if (o.hint != null) Text(o.hint!, style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: o.value == value ? c.primary : Colors.transparent,
                  border: Border.all(color: o.value == value ? c.primary : c.lineStrong),
                ),
                child: o.value == value ? Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: c.onPrimary))) : null,
              ),
            ]),
          ),
        ),
    ]);
  });
}

/// A confirm step for things that cannot be undone. [onConfirm] runs while the sheet shows "Working…";
/// the sheet closes when it completes and returns true. An error it throws is shown in the sheet.
Future<bool> showConfirmSheet(BuildContext context, {required String title, required String body, required String action, required Future<void> Function() onConfirm}) async {
  final r = await showESheet<bool>(context, title: title, builder: (ctx) => _ConfirmBody(body: body, action: action, onConfirm: onConfirm));
  return r ?? false;
}

class _ConfirmBody extends StatefulWidget {
  const _ConfirmBody({required this.body, required this.action, required this.onConfirm});
  final String body;
  final String action;
  final Future<void> Function() onConfirm;
  @override
  State<_ConfirmBody> createState() => _ConfirmBodyState();
}

class _ConfirmBodyState extends State<_ConfirmBody> {
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(widget.body, style: TextStyle(fontSize: 14, height: 1.5, color: c.body)),
      if (_error != null) ...[const SizedBox(height: 12), Notice(_error!, tone: NoticeTone.error)],
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: EButton(label: 'Cancel', kind: ButtonKind.quiet, expand: true, onPressed: () => Navigator.of(context).pop(false))),
        const SizedBox(width: 8),
        Expanded(
          child: EButton(
            label: _busy ? 'Working…' : widget.action,
            kind: ButtonKind.danger,
            expand: true,
            onPressed: _busy
                ? null
                : () async {
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      await widget.onConfirm();
                      if (context.mounted) Navigator.of(context).pop(true);
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          _busy = false;
                          _error = e.toString();
                        });
                      }
                    }
                  },
          ),
        ),
      ]),
    ]);
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.name, this.email, this.size = 56});
  final String? name;
  final String? email;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = (name?.isNotEmpty == true ? name! : (email?.isNotEmpty == true ? email! : '?'));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.canvas, border: Border.all(color: c.hairline)),
      child: Text(s.substring(0, 1).toUpperCase(), style: TextStyle(fontSize: size * 0.42, color: c.ink)),
    );
  }
}
