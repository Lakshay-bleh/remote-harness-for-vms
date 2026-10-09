import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'attachments.dart';

/// A file the person picked, before it is read: enough to decide whether it may be attached at all ([canAdd]).
class Picked {
  Picked({required this.name, required this.type, required this.size, required this.read});
  final String name;
  final String type;
  final int size;

  /// Read it into something ready to send. Throws a sentence the person can read.
  final Future<Attachment> Function() read;
}

final _images = ImagePicker();

/// A photo, shrunk to a size worth sending (the picker resizes to [LIMITS.imageEdge] and re-encodes as JPEG; a photo with
/// transparency stays PNG).
Future<Attachment> _readImage(XFile file) async {
  final bytes = await file.readAsBytes();
  final mime = sniffImageMime(bytes);
  if (mime == null) throw Exception('Could not open ${file.name.isEmpty ? 'that photo' : file.name}. Try a JPEG or PNG.');
  if (bytes.length > LIMITS.bytesEach) {
    throw Exception('${file.name} is too big (${humanSize(bytes.length)}). The limit is ${humanSize(LIMITS.bytesEach)}.');
  }
  return Attachment(name: photoName(file.name, mime), mime: mime, size: bytes.length, kind: AttachmentKind.image, data: base64Encode(bytes), preview: bytes);
}

Future<Picked> _pickedImage(XFile x) async {
  int size;
  try {
    size = await x.length();
  } catch (_) {
    size = 0;
  }
  final type = (x.mimeType != null && x.mimeType!.startsWith('image/')) ? x.mimeType! : (mimeFromName(x.name).startsWith('image/') ? mimeFromName(x.name) : 'image/jpeg');
  return Picked(name: x.name, type: type, size: size, read: () => _readImage(x));
}

/// Photos from the gallery (up to [limit]).
Future<List<Picked>> pickPhotos({int limit = LIMITS.files}) async {
  const edge = LIMITS.imageEdge * 1.0;
  final List<XFile> files;
  if (limit >= 2) {
    files = await _images.pickMultiImage(maxWidth: edge, maxHeight: edge, imageQuality: 85, limit: limit);
  } else {
    final one = await _images.pickImage(source: ImageSource.gallery, maxWidth: edge, maxHeight: edge, imageQuality: 85);
    files = [?one];
  }
  return [for (final f in files) await _pickedImage(f)];
}

/// A new photo from the camera.
Future<List<Picked>> takePhoto() async {
  const edge = LIMITS.imageEdge * 1.0;
  final one = await _images.pickImage(source: ImageSource.camera, maxWidth: edge, maxHeight: edge, imageQuality: 85);
  return one == null ? [] : [await _pickedImage(one)];
}

/// PDFs and text or code files (or only text when [allow] is 'text').
Future<List<Picked>> pickFiles({String allow = 'all'}) async {
  final files = await FilePicker.pickFiles(type: FileType.any);
  final out = <Picked>[];
  for (final f in files) {
    final name = f.name;
    final x = f.xFile;
    final type = (x.mimeType != null && x.mimeType!.isNotEmpty) ? x.mimeType! : mimeFromName(name);
    final size = f.lengthSync() ?? (await f.length()) ?? 0;
    out.add(Picked(
      name: name,
      type: type,
      size: size,
      read: () async {
        final kind = classify(name, type);
        if (kind == null) throw Exception(unsupported);
        final Uint8List bytes;
        try {
          bytes = await f.readAsBytes();
        } catch (_) {
          throw Exception('Could not read that file.');
        }
        if (kind == AttachmentKind.image) {
          final mime = sniffImageMime(bytes);
          if (mime == null) throw Exception('Could not open $name. Try a JPEG or PNG.');
          if (bytes.length > LIMITS.bytesEach) throw Exception('$name is too big (${humanSize(bytes.length)}). The limit is ${humanSize(LIMITS.bytesEach)}.');
          return Attachment(name: name, mime: mime, size: bytes.length, kind: kind, data: base64Encode(bytes), preview: bytes);
        }
        if (kind == AttachmentKind.pdf) {
          return Attachment(name: name, mime: 'application/pdf', size: bytes.length, kind: kind, data: base64Encode(bytes));
        }
        final clipped = clipText(utf8.decode(bytes, allowMalformed: true));
        return Attachment(
          name: clipped.cut ? '$name (first part)' : name,
          mime: type.isEmpty ? 'text/plain' : type,
          size: clipped.text.length,
          kind: kind,
          text: clipped.text,
        );
      },
    ));
  }
  return out;
}
