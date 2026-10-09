/// CONTRACT (owned by the assistant/composer feature; keep these signatures, add freely).
///
/// Things a person attaches to a message: photos, PDFs, and text or code files. This file decides what is allowed and how each
/// kind is sent. Nothing here touches the screen or the network, so the rules are tested; picking and reading a file on the
/// phone is `read_file.dart`.
library;

import 'dart:typed_data';

enum AttachmentKind { image, pdf, text }

int _nextId = 0;

class Attachment {
  Attachment({required this.name, required this.mime, required this.kind, required this.size, this.data, this.text, String? id, this.preview})
      : id = id ?? 'a${++_nextId}';
  final String name;
  final String mime;
  final AttachmentKind kind;

  /// Bytes on the phone (before encoding).
  final int size;

  /// base64 contents (images and PDFs).
  final String? data;

  /// The contents of a text file.
  final String? text;

  /// Tells two attachments apart in the message box.
  final String id;

  /// A small picture to show in the message box (images only): encoded image bytes.
  final Uint8List? preview;
}

/// The limits of one message's attachments.
abstract final class LIMITS {
  static const files = 4;

  /// What one image or PDF may weigh once ready to send.
  static const bytesEach = 5 * 1024 * 1024;
  static const bytesTotal = 8 * 1024 * 1024;
  static const textChars = 60000;

  /// Longest side of a photo, in pixels (bigger gains the assistant nothing and costs time).
  static const imageEdge = 1568;
}

const _imageTypes = {'image/jpeg', 'image/png', 'image/gif', 'image/webp'};
final _textExt = RegExp(
  r'\.(txt|md|markdown|csv|tsv|json|jsonl|yaml|yml|toml|ini|env|log|xml|html|css|scss|js|jsx|ts|tsx|py|rb|go|rs|java|kt|swift|c|h|cpp|hpp|cs|php|sh|bash|zsh|sql|tf|dockerfile|gradle|properties|conf)$',
  caseSensitive: false,
);
final _pdfExt = RegExp(r'\.pdf$', caseSensitive: false);

/// Extensions the file picker offers for text and code files.
const textExtensions = [
  'txt', 'md', 'csv', 'json', 'yaml', 'yml', 'log', 'xml', 'env', 'toml', 'sql', 'sh', 'py', 'js', 'jsx', 'ts', 'tsx', 'go', 'rs', //
  'java', 'kt', 'tf',
];

/// What a file is, or null when Escanor cannot read it.
AttachmentKind? classify(String name, String mime) {
  final m = mime.toLowerCase();
  if (_imageTypes.contains(m)) return AttachmentKind.image;
  if (m.startsWith('image/')) return AttachmentKind.image; // heic and friends: converted when the photo is prepared
  if (m == 'application/pdf' || _pdfExt.hasMatch(name)) return AttachmentKind.pdf;
  if (m.startsWith('text/') || m == 'application/json' || m == 'application/xml' || _textExt.hasMatch(name)) return AttachmentKind.text;
  return null;
}

const unsupported = 'Escanor can read photos, PDFs and text or code files. Word and Excel files are not supported yet: save them as PDF first.';

String humanSize(num n) {
  if (n < 1024) return '${n.round()} B';
  if (n < 1024 * 1024) return '${(n / 1024).round()} KB';
  return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Whether another file may be added, and if not, the sentence to show.
/// [allow]: 'all' (photos, PDFs, text), 'media' (photos and text) or 'text'.
String? canAdd(List<Attachment> existing, ({String name, String type, int size}) next, [String allow = 'all']) {
  final kind = classify(next.name, next.type);
  if (kind == null) return unsupported;
  if (allow == 'media' && kind == AttachmentKind.pdf) return 'Machines take photos and text or code files. To send a PDF, use the Escanor assistant chat.';
  if (allow == 'text' && kind != AttachmentKind.text) return 'This chat takes text and code files. To send a photo or PDF, use the Escanor assistant chat.';
  if (existing.length >= LIMITS.files) return 'You can attach up to ${LIMITS.files} files to one message.';
  // photos are shrunk before sending, so only a PDF's own size counts here
  if (kind == AttachmentKind.pdf && next.size > LIMITS.bytesEach) {
    return '${next.name} is too big (${humanSize(next.size)}). The limit is ${humanSize(LIMITS.bytesEach)}.';
  }
  if (kind == AttachmentKind.text && next.size > 2 * 1024 * 1024) return '${next.name} is too big to read as text. Attach a smaller part of it.';
  if (existing.any((a) => a.name == next.name && a.size == next.size)) return '${next.name} is already attached.';
  return null;
}

int totalBytes(List<Attachment> list) => list.fold(0, (n, a) => n + a.size);

/// The shape the Escanor backend takes for `attachments` on a message.
class ApiAttachment {
  const ApiAttachment({required this.name, required this.mime, required this.kind, this.data, this.text});
  final String name;
  final String mime;
  final AttachmentKind kind;
  final String? data;
  final String? text;

  Map<String, dynamic> toJson() => {
        'name': name,
        'mime': mime,
        'kind': kind.name,
        if (data != null && data!.isNotEmpty) 'data': data,
        'text': ?text,
      };
}

List<ApiAttachment> toApi(List<Attachment> list) => [
      for (final a in list)
        ApiAttachment(name: a.name, mime: a.mime, kind: a.kind, data: (a.data != null && a.data!.isNotEmpty) ? a.data : null, text: a.text),
    ];

/// For a chat that only takes words: put each text file's content in the message under its name. Null if it would not fit.
String? inlineText(String message, List<Attachment> list, int maxChars) {
  final parts = [
    message.trim(),
    for (final a in list.where((a) => a.kind == AttachmentKind.text)) '[${a.name}]\n${a.text ?? ''}',
  ].where((p) => p.isNotEmpty);
  final out = parts.join('\n\n');
  return out.length <= maxChars ? out : null;
}

/// A text file's words, cut to the limit (and a note when it was cut).
({String text, bool cut}) clipText(String text) =>
    text.length <= LIMITS.textChars ? (text: text, cut: false) : (text: text.substring(0, LIMITS.textChars), cut: true);

/// The size an image should be drawn at: the same shape, longest side at most [edge].
({int width, int height}) fitWithin(int w, int h, [int edge = LIMITS.imageEdge]) {
  final longest = w > h ? w : h;
  if (longest <= edge) return (width: w, height: h);
  final k = edge / longest;
  int side(int v) {
    final r = (v * k).round();
    return r < 1 ? 1 : r;
  }

  return (width: side(w), height: side(h));
}

/// How a message with files reads in the chat (and on the server, which stores the same line): the words, then what was attached.
String withAttachmentNote(String text, List<Attachment> list) {
  if (list.isEmpty) return text;
  final note = '[Attached: ${list.map((a) => a.name).join(', ')}]';
  return text.trim().isNotEmpty ? '${text.trim()}\n\n$note' : note;
}

/// The kind of image in [bytes] from its first bytes, or null when it is not one Escanor sends as is.
String? sniffImageMime(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'image/jpeg';
  if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'image/png';
  if (bytes.length >= 4 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return 'image/gif';
  if (bytes.length >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

/// A photo's name once prepared: the same name with the extension of what it now is.
String photoName(String original, String mime) {
  final base = (original.isEmpty ? 'photo' : original).replaceFirst(RegExp(r'\.[^.]+$'), '');
  final ext = switch (mime) { 'image/png' => 'png', 'image/gif' => 'gif', 'image/webp' => 'webp', _ => 'jpg' };
  return '${base.isEmpty ? 'photo' : base}.$ext';
}

/// A best guess at a picked file's type from its name, when the phone does not say.
String mimeFromName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'pdf' => 'application/pdf',
    'json' => 'application/json',
    'xml' => 'application/xml',
    'md' || 'markdown' => 'text/markdown',
    'csv' => 'text/csv',
    'html' => 'text/html',
    'txt' || 'log' => 'text/plain',
    _ => '',
  };
}
