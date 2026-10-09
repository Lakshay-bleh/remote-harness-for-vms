import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../features/companion/dog_spinner.dart';

/// The shared building blocks every screen uses, so the app looks like one app.

/// The Escanor mark. Use this everywhere; do not draw another mark.
class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/images/brand-mark.png', width: size, height: size, fit: BoxFit.contain, excludeFromSemantics: true);
}

enum ButtonKind { primary, quiet, danger }

/// A pill button. [onPressed] null = disabled.
class EButton extends StatelessWidget {
  const EButton({super.key, required this.label, this.onPressed, this.kind = ButtonKind.primary, this.icon, this.busy = false, this.expand = false});
  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg, border) = switch (kind) {
      ButtonKind.primary => (c.primary, c.onPrimary, Colors.transparent),
      ButtonKind.quiet => (Colors.transparent, c.ink, c.lineStrong),
      ButtonKind.danger => (Colors.transparent, c.error, c.error.withValues(alpha: 0.4)),
    };
    final enabled = onPressed != null && !busy;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          Padding(padding: const EdgeInsets.only(right: 8), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg)))
        else if (icon != null)
          Padding(padding: const EdgeInsets.only(right: 8), child: Icon(icon, size: 18, color: fg)),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg))),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11), child: child),
        ),
      ),
    );
  }
}

enum NoticeTone { info, error, warn }

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.tone = NoticeTone.info, this.child});
  final String text;
  final NoticeTone tone;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (border, bg, fg) = switch (tone) {
      NoticeTone.error => (c.error.withValues(alpha: 0.3), c.error.withValues(alpha: 0.1), c.error),
      NoticeTone.warn => (c.warning.withValues(alpha: 0.3), c.warning.withValues(alpha: 0.1), c.bodyStrong),
      NoticeTone.info => (c.hairline, c.surfaceSoft, c.body),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(Radii.md)),
      child: child ?? Text(text, style: TextStyle(fontSize: 13, color: fg)),
    );
  }
}

/// Loading, wherever a spinner would go: the companion running on the spot.
class Spinner extends StatelessWidget {
  const Spinner({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => DogSpinner(size: size);
}

/// The title bar every screen shares: a back arrow (or the chats menu), the title with an optional line
/// under it, then any actions.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.onBack, this.onMenu, this.actions = const []});
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onMenu;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))),
      child: Row(children: [
        if (onBack != null)
          IconButton(onPressed: onBack, tooltip: 'Back', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: c.body))
        else if (onMenu != null)
          IconButton(onPressed: onMenu, tooltip: 'Chats', icon: Icon(Icons.menu_rounded, size: 22, color: c.body))
        else
          const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 21, height: 1.2, color: c.ink, fontWeight: FontWeight.w500)),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

/// A bottom sheet with a title, the app's way of showing a step that does not need its own screen.
Future<T?> showESheet<T>(BuildContext context, {required String title, required WidgetBuilder builder, bool scroll = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final c = ctx.c;
      final body = builder(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(children: [
                Expanded(child: Text(title, style: TextStyle(fontSize: 20, color: c.ink, fontWeight: FontWeight.w500))),
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Close', style: TextStyle(color: c.muted))),
              ]),
            ),
            Divider(height: 1, color: c.hairline),
            Flexible(
              child: scroll
                  ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), child: body)
                  : Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), child: body),
            ),
          ]),
        ),
      );
    },
  );
}

/// Ask a yes/no question. Returns true only when confirmed.
Future<bool> confirm(BuildContext context, {required String title, String? message, String ok = 'OK', bool danger = false}) async {
  final c = context.c;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: TextStyle(color: c.ink, fontSize: 18)),
      content: message == null ? null : Text(message, style: TextStyle(color: c.body)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: c.muted))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok, style: TextStyle(color: danger ? c.error : c.primary))),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

/// "just now", "5m ago", "3h ago", "2d ago". Accepts an ISO string, epoch seconds (num) or DateTime.
String ago(Object? when, {DateTime? now}) {
  if (when == null) return '';
  DateTime? t;
  if (when is DateTime) {
    t = when;
  } else if (when is num) {
    t = DateTime.fromMillisecondsSinceEpoch((when * 1000).round());
  } else if (when is String) {
    t = DateTime.tryParse(when);
  }
  if (t == null) return '';
  final m = (now ?? DateTime.now()).difference(t).inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '${m}m ago';
  final h = m ~/ 60;
  return h < 24 ? '${h}h ago' : '${h ~/ 24}d ago';
}

/// An assistant answer. Markdown only: raw HTML is never rendered, and links must be http(s).
class Md extends StatelessWidget {
  const Md(this.text, {super.key, this.selectable = true});
  final String text;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final base = TextStyle(fontSize: 15, height: 1.55, color: c.bodyStrong, fontFamily: fontFamily);
    return MarkdownBody(
      data: text,
      selectable: selectable,
      softLineBreak: true,
      onTapLink: (text, href, title) {
        if (href != null && RegExp(r'^https?://', caseSensitive: false).hasMatch(href)) {
          launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
        }
      },
      imageBuilder: (uri, title, alt) => Text(alt ?? '', style: base), // no remote images
      styleSheet: MarkdownStyleSheet(
        p: base,
        a: base.copyWith(color: c.primary, decoration: TextDecoration.underline, decorationColor: c.primary),
        strong: base.copyWith(fontWeight: FontWeight.w600, color: c.ink),
        em: base.copyWith(fontStyle: FontStyle.italic),
        h1: base.copyWith(fontSize: 22, fontWeight: FontWeight.w600, color: c.ink),
        h2: base.copyWith(fontSize: 19, fontWeight: FontWeight.w600, color: c.ink),
        h3: base.copyWith(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink),
        h4: base.copyWith(fontWeight: FontWeight.w600, color: c.ink),
        listBullet: base,
        code: TextStyle(fontFamily: monoFamily, fontSize: 13, color: c.inlineCode, backgroundColor: c.surfaceCard),
        codeblockDecoration: BoxDecoration(color: c.code, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.lg)),
        codeblockPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        blockquote: base.copyWith(color: c.body),
        blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: c.lineStrong, width: 3))),
        tableBorder: TableBorder.all(color: c.hairline),
        tableHead: base.copyWith(fontWeight: FontWeight.w600),
        tableBody: base,
        horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: c.hairline))),
      ),
    );
  }
}

/// A card: rounded, hairline border, card surface.
class ECard extends StatelessWidget {
  const ECard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl), side: BorderSide(color: c.hairline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// A centred empty/error state with an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.action, this.icon});
  final String title;
  final String? message;
  final Widget? action;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Icon(icon, size: 36, color: c.muted),
          if (icon != null) const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: c.ink, fontWeight: FontWeight.w500)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.body, height: 1.4)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}
