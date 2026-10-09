import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart' show websiteBase;
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../account/privacy_data_page.dart';
import 'legal_content.dart';
import 'legal_rich.dart';
import 'settings_widgets.dart';

/// Open one legal document as a page inside the current tab.
void openLegalDoc(BuildContext context, String key) => pushPage(context, LegalDocPage(docKey: key));

/// Privacy and legal: every document reads inside the app, and your data and requests have their own page.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPage(title: 'Privacy and legal', children: [
      Group(title: 'Your data', footer: 'Your choices, a copy of your data, and requests to correct or delete it.', children: [
        SRow(icon: Icons.verified_user_outlined, label: 'Privacy and your data', onTap: () => pushPage(context, const PrivacyDataPage())),
      ]),
      Group(title: 'Read in the app', footer: 'Every document is stored in the app, so it reads without a connection.', children: [
        for (final d in legalList)
          SRow(
            icon: d.key == 'terms' ? Icons.description_outlined : (d.key == 'support' ? Icons.support_outlined : Icons.verified_user_outlined),
            label: d.label,
            onTap: () => openLegalDoc(context, d.key),
          ),
      ]),
      const Footnote('If you use a hub that someone else runs, ask its operator about access, storage and deletion of your session data. Their '
          'notices are theirs, not Escanor’s.'),
    ]);
  }
}

/// One legal document, full screen, inside Settings.
class LegalDocPage extends StatelessWidget {
  const LegalDocPage({super.key, required this.docKey});
  final String docKey;
  @override
  Widget build(BuildContext context) => SettingsPage(title: legalLabel(docKey), children: [LegalBody(docKey: docKey)]);
}

/// One legal document, read inside the app: its title and date, then each section. Nothing is fetched.
class LegalBody extends StatelessWidget {
  const LegalBody({super.key, required this.docKey});
  final String docKey;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final doc = legalDocuments[docKey];
    if (doc == null) return Text('This document is not available.', style: TextStyle(fontSize: 14, color: c.muted));
    final body = TextStyle(fontSize: 14.5, height: 1.55, color: c.bodyStrong);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(doc.title, style: TextStyle(fontSize: 24, color: c.ink, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Text(doc.description, style: TextStyle(fontSize: 14, height: 1.5, color: c.muted)),
      const SizedBox(height: 4),
      Text('Last updated $policyDate', style: TextStyle(fontSize: 12, color: c.mutedSoft)),
      for (final s in doc.sections) ...[
        const SizedBox(height: 20),
        Text(s.heading, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
        for (final p in s.paragraphs) ...[
          const SizedBox(height: 8),
          LegalRichText(p, style: body),
        ],
        if (s.items.isNotEmpty) const SizedBox(height: 8),
        for (final item in s.items)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 16, child: Text('•', style: body)),
              Expanded(child: LegalRichText(item, style: body)),
            ]),
          ),
      ],
      const SizedBox(height: 16),
    ]);
  }
}

/// A paragraph with the policies' two inline marks: **bold** in the ink colour, and links that open in the browser.
class LegalRichText extends StatefulWidget {
  const LegalRichText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<LegalRichText> createState() => _LegalRichTextState();
}

class _LegalRichTextState extends State<LegalRichText> {
  late List<RichPart> _parts;
  final List<TapGestureRecognizer> _taps = [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(LegalRichText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _parse();
  }

  void _parse() {
    _dispose();
    _parts = parseLegalRich(widget.text);
    for (final p in _parts) {
      final href = p.href;
      if (href != null) _taps.add(TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication));
    }
  }

  void _dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    var tap = 0;
    return SelectableText.rich(TextSpan(style: widget.style, children: [
      for (final p in _parts)
        if (p.bold)
          TextSpan(text: p.text, style: TextStyle(fontWeight: FontWeight.w600, color: c.ink))
        else if (p.href != null)
          TextSpan(
            text: p.text,
            style: TextStyle(decoration: TextDecoration.underline, decorationColor: widget.style.color),
            recognizer: _taps[tap++],
          )
        else
          TextSpan(text: p.text),
    ]));
  }
}

/// The legal documents as a bottom sheet: a list, then the one you pick. For screens that have no Settings around them (sign-in).
Future<void> showLegalSheet(BuildContext context, {String? start}) {
  if (start != null) {
    return showESheet<void>(context, title: legalLabel(start), builder: (_) => LegalBody(docKey: start));
  }
  return showESheet<void>(context, title: 'Legal and privacy', builder: (ctx) {
    final c = ctx.c;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final d in legalList)
        InkWell(
          onTap: () => showESheet<void>(ctx, title: d.label, builder: (_) => LegalBody(docKey: d.key)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Row(children: [
              Expanded(child: Text(d.label, style: TextStyle(fontSize: 15, color: c.ink))),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.mutedSoft),
            ]),
          ),
        ),
    ]);
  });
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    loadAppVersion();
    return SettingsPage(title: 'About', children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(children: [
          const Logo(size: 72),
          const SizedBox(height: 8),
          Text('Escanor', style: TextStyle(fontSize: 24, color: c.ink, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          ValueListenableBuilder<String>(
            valueListenable: appVersion,
            builder: (_, v, _) => Text('Version $v · ${platformName()}', style: TextStyle(fontSize: 14, color: c.muted)),
          ),
        ]),
      ),
      Group(children: [
        SRow(icon: Icons.headset_mic_outlined, label: 'Get help', onTap: () => openLegalDoc(context, 'support')),
        SRow(icon: Icons.verified_user_outlined, label: 'Privacy policy', onTap: () => openLegalDoc(context, 'privacy')),
        SRow(icon: Icons.description_outlined, label: 'Terms of service', onTap: () => openLegalDoc(context, 'terms')),
        // "about" is a website page, not a stored document: it opens on the web.
        SRow(
          icon: Icons.description_outlined,
          label: 'About Escanor',
          onTap: () => launchUrl(Uri.parse('$websiteBase/about'), mode: LaunchMode.externalApplication),
        ),
      ]),
    ]);
  }
}
