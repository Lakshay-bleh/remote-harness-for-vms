import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';

/// Small pieces shared by the Settings and account pages.

/// The version this build was made from, e.g. "1.0.0 (12)". "dev" until it is read.
final ValueNotifier<String> appVersion = ValueNotifier<String>('dev');
bool _versionAsked = false;

void loadAppVersion() {
  if (_versionAsked) return;
  _versionAsked = true;
  PackageInfo.fromPlatform().then((p) {
    appVersion.value = p.buildNumber.isEmpty || p.buildNumber == p.version ? p.version : '${p.version} (${p.buildNumber})';
  }).catchError((_) {});
}

/// "Android" / "iOS" / "Web", for the About page.
String platformName() {
  if (kIsWeb) return 'Web';
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iOS';
  return Platform.operatingSystem;
}

/// "Android app" / "iOS app", for debug details.
String platformLabel() => kIsWeb ? 'browser' : '${platformName()} app';

String? osVersion() => kIsWeb ? null : Platform.operatingSystemVersion;

/// The phone's own settings app, by name, for instructions ("Android Settings", "iPhone Settings").
String phoneSettingsName() => !kIsWeb && Platform.isIOS ? 'iPhone Settings' : 'Android Settings';

/// "412x915 @2.6x".
String screenText(BuildContext context) {
  final mq = MediaQuery.of(context);
  return '${mq.size.width.round()}x${mq.size.height.round()} @${mq.devicePixelRatio.toStringAsFixed(mq.devicePixelRatio % 1 == 0 ? 0 : 1)}x';
}

/// The small uppercase heading over a section that is not a [Group].
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: c.muted))),
        ?trailing,
      ]),
    );
  }
}

/// A footnote line under a section.
class Footnote extends StatelessWidget {
  const Footnote(this.text, {super.key, this.center = false, this.soft = false});
  final String text;
  final bool center;
  final bool soft;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(text,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: TextStyle(fontSize: 12, height: 1.45, color: soft ? context.c.mutedSoft : context.c.muted)),
      );
}

/// A card that holds a list of rows (like [Group] but with no title), for lists that load.
class RowsCard extends StatelessWidget {
  const RowsCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, thickness: 1, color: c.hairline));
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.xl)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }
}

/// A plain line of text inside a [RowsCard] ("No keys yet.").
class CardText extends StatelessWidget {
  const CardText(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(text, style: TextStyle(fontSize: 14, color: error ? context.c.error : context.c.muted)),
      );
}

/// The spinner in a block of its own.
class BlockSpinner extends StatelessWidget {
  const BlockSpinner({super.key, this.padding = 24});
  final double padding;
  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.symmetric(vertical: padding), child: const Center(child: Spinner(size: 32)));
}

/// A labelled text field, as on the website's forms.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.maxLength,
    this.maxLines = 1,
    this.mono = false,
    this.autofocus = false,
    this.keyboardType,
    this.capitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.onSubmitted,
    this.onChanged,
    this.autofillHints,
  });
  final String? label;
  final TextEditingController controller;
  final String? hint;
  final int? maxLength;
  final int maxLines;
  final bool mono;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  final bool autocorrect;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final field = TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      minLines: maxLines > 1 ? maxLines : null,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      autocorrect: autocorrect,
      enableSuggestions: autocorrect,
      autofillHints: autofillHints,
      inputFormatters: [if (maxLength != null) LengthLimitingTextInputFormatter(maxLength)],
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      style: mono
          ? TextStyle(fontFamily: monoFamily, fontSize: 18, letterSpacing: 3, color: c.ink)
          : TextStyle(fontSize: 15, color: c.ink),
      decoration: InputDecoration(hintText: hint, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
    );
    if (label == null) return field;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(label!, style: TextStyle(fontSize: 14, color: c.body)),
      const SizedBox(height: 4),
      field,
    ]);
  }
}

/// Copy text and say so.
Future<bool> copyText(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}

/// A value that shows "Copied" for two seconds after something is copied.
class CopiedFlag extends ValueNotifier<String?> {
  CopiedFlag() : super(null);
  Timer? _t;
  Future<void> copy(String what, String text) async {
    if (await copyText(text)) {
      value = what;
      _t?.cancel();
      _t = Timer(const Duration(seconds: 2), () {
        if (value == what) value = null;
      });
    } else {
      value = null;
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}

/// A coloured progress bar, 0..1.
class MeterBar extends StatelessWidget {
  const MeterBar({super.key, required this.value, required this.color, this.label});
  final double value;
  final Color color;
  final String? label;
  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        value: '${(value * 100).round()}%',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 8, color: color, backgroundColor: context.c.canvas),
        ),
      );
}

/// A pill showing a status ("Active", "Cancelling").
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(Radii.pill)),
        child: Text(text, style: TextStyle(fontSize: 12, color: color)),
      );
}

/// "7/10/2026" style short date for a list row.
String shortDate(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  if (t == null) return '';
  final l = t.toLocal();
  return '${l.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][l.month - 1]} ${l.year}';
}

/// Date and time for a timeline entry.
String dateTime(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  if (t == null) return '';
  final l = t.toLocal();
  return '${shortDate(iso)}, ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
