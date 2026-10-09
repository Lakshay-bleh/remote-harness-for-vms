import '../../core/config.dart' show websiteBase;

/// One run of a legal paragraph: plain text, bold text, or a link that opens on the web.
class RichPart {
  const RichPart(this.text, {this.bold = false, this.href});
  final String text;
  final bool bold;

  /// An https:// address to open in the browser; null for text that is not a link.
  final String? href;

  @override
  bool operator ==(Object other) => other is RichPart && other.text == text && other.bold == bold && other.href == href;

  @override
  int get hashCode => Object.hash(text, bold, href);

  @override
  String toString() => 'RichPart(${bold ? '**' : ''}$text${bold ? '**' : ''}${href == null ? '' : ' -> $href'})';
}

final _marks = RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)|\*\*([^*]+)\*\*');

/// The two inline marks the policies use: [label](href) and **bold** (legal/LegalBody.tsx Rich).
/// Site paths ("/privacy") open on the website; only https:// links are links, anything else is its label as plain text.
List<RichPart> parseLegalRich(String text) {
  final parts = <RichPart>[];
  var last = 0;
  for (final m in _marks.allMatches(text)) {
    if (m.start > last) parts.add(RichPart(text.substring(last, m.start)));
    final bold = m.group(3);
    if (bold != null) {
      parts.add(RichPart(bold, bold: true));
    } else {
      final raw = m.group(2)!;
      final href = raw.startsWith('/') ? '$websiteBase$raw' : raw;
      parts.add(href.startsWith('https://') ? RichPart(m.group(1)!, href: href) : RichPart(m.group(1)!));
    }
    last = m.end;
  }
  if (last < text.length) parts.add(RichPart(text.substring(last)));
  return parts;
}
