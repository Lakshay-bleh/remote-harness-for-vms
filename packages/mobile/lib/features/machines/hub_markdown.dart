import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';

/// What Claude wrote on a machine (SafeMarkdown.tsx). Its output is untrusted (prompt injection can steer it): a remote
/// image is never fetched (that would leak data with no click), only its alt text is shown; links must be http(s) and
/// open outside the app. Fenced code with a language is syntax-highlighted.
class HubMarkdown extends StatelessWidget {
  const HubMarkdown(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final base = TextStyle(fontSize: 14, height: 1.6, color: c.ink, fontFamily: fontFamily);
    final mono = TextStyle(fontFamily: monoFamily, fontSize: 12.5, height: 1.5);
    return MarkdownBody(
      data: text,
      selectable: true,
      softLineBreak: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (text, href, title) {
        if (href != null && isSafeLink(href)) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      },
      imageBuilder: (uri, title, alt) => Text(blockedImageText(alt), style: base.copyWith(color: c.mutedSoft)),
      builders: {'code': _CodeBuilder(mono)},
      styleSheet: MarkdownStyleSheet(
        p: base,
        a: base.copyWith(color: c.primary, decoration: TextDecoration.underline, decorationColor: c.primary),
        strong: base.copyWith(fontWeight: FontWeight.w600),
        em: base.copyWith(fontStyle: FontStyle.italic),
        h1: base.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
        h2: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
        h3: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        h4: base.copyWith(fontWeight: FontWeight.w600),
        listBullet: base,
        code: mono.copyWith(fontSize: 13, color: c.inlineCode, backgroundColor: c.surfaceCard),
        codeblockDecoration: BoxDecoration(color: c.code, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.md)),
        codeblockPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

/// Only http(s) links are opened (never javascript:, file:, intent: ...).
bool isSafeLink(String href) => RegExp(r'^https?://', caseSensitive: false).hasMatch(href.trim());

/// What stands in for a markdown image.
String blockedImageText(String? alt) => '[image${alt != null && alt.isNotEmpty ? ': $alt' : ''}]';

class _CodeBuilder extends MarkdownElementBuilder {
  _CodeBuilder(this.mono);
  final TextStyle mono;

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final cls = element.attributes['class'] ?? '';
    if (!cls.startsWith('language-')) return null; // inline code, or a block with no language: drawn as usual
    final lang = cls.substring('language-'.length);
    final code = element.textContent.replaceAll(RegExp(r'\n$'), '');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableText.rich(highlightCode(code, lang, mono.copyWith(color: context.c.onCode))),
    );
  }
}

final Highlight _highlight = Highlight()..registerLanguages(builtinLanguages);
final Map<String, TextSpan> _spans = {};

/// Code coloured for [language] (dark, like every code window), or plain when the language is unknown.
TextSpan highlightCode(String code, String language, TextStyle style) {
  final key = '$language\u0000${style.color?.toARGB32()}\u0000$code';
  final hit = _spans[key];
  if (hit != null) return hit;
  TextSpan span;
  if (_highlight.getLanguage(language.toLowerCase()) == null || code.length > 60000) {
    span = TextSpan(text: code, style: style);
  } else {
    try {
      final result = _highlight.highlight(code: code, language: language.toLowerCase());
      final renderer = TextSpanRenderer(style, atomOneDarkTheme);
      result.render(renderer);
      span = renderer.span ?? TextSpan(text: code, style: style);
    } catch (_) {
      span = TextSpan(text: code, style: style);
    }
  }
  if (_spans.length > 200) _spans.remove(_spans.keys.first);
  _spans[key] = span;
  return span;
}
