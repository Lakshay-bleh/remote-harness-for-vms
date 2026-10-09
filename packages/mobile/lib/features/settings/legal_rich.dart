import 'legal_content.dart' show legalDocuments;

/// One run of a legal paragraph: plain text, bold text, a link to another document in the app, or a link to someone else's site.
class RichPart {
  const RichPart(this.text, {this.bold = false, this.href, this.doc});
  final String text;
  final bool bold;

  /// An https:// address of another organisation (a regulator, a payment provider), opened in a browser view; null for anything else.
  final String? href;

  /// Another document or page inside the app ([legalDocuments] key, or [privacyRequestsDoc]); null for anything else.
  final String? doc;

  @override
  bool operator ==(Object other) => other is RichPart && other.text == text && other.bold == bold && other.href == href && other.doc == doc;

  @override
  int get hashCode => Object.hash(text, bold, href, doc);

  @override
  String toString() => 'RichPart(${bold ? '**' : ''}$text${bold ? '**' : ''}${href == null ? '' : ' -> $href'}${doc == null ? '' : ' => $doc'})';
}

/// The page where a person makes a request about their data (a page of the app, not a stored document).
const privacyRequestsDoc = 'privacy-requests';

/// A site path in a document ("/privacy", "/refunds") as the page of the app that holds it; null when the app has no such page.
String? docForSitePath(String path) {
  final clean = path.split('#').first.split('?').first.replaceAll(RegExp(r'^/+|/+$'), '');
  if (clean == 'privacy/requests') return privacyRequestsDoc;
  return legalDocuments.containsKey(clean) ? clean : null;
}

final _marks = RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)|\*\*([^*]+)\*\*');

/// The two inline marks the policies use: [label](href) and **bold** (legal/LegalBody.tsx Rich).
/// Site paths ("/privacy") open the same document inside the app; a path the app has no page for, and anything else that is not an
/// https:// link, is its label as plain text. Nothing here sends the person to the website.
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
      if (raw.startsWith('/')) {
        final doc = docForSitePath(raw);
        parts.add(doc != null ? RichPart(m.group(1)!, doc: doc) : RichPart(m.group(1)!));
      } else {
        parts.add(raw.startsWith('https://') ? RichPart(m.group(1)!, href: raw) : RichPart(m.group(1)!));
      }
    }
    last = m.end;
  }
  if (last < text.length) parts.add(RichPart(text.substring(last)));
  return parts;
}
