import 'package:escanor/features/composer/attachments.dart';
import 'package:escanor/features/composer/spoken.dart';
import 'package:flutter_test/flutter_test.dart';

Attachment att(String name, {String mime = 'text/plain', int size = 10, AttachmentKind kind = AttachmentKind.text, String? data, String? text = 'hello'}) =>
    Attachment(id: name, name: name, mime: mime, size: size, kind: kind, data: data, text: text);

({String name, String type, int size}) file(String name, String type, int size) => (name: name, type: type, size: size);

void main() {
  group('classify', () {
    test('knows photos, PDFs and text or code', () {
      expect(classify('a.jpg', 'image/jpeg'), AttachmentKind.image);
      expect(classify('a.heic', 'image/heic'), AttachmentKind.image);
      expect(classify('r.pdf', 'application/pdf'), AttachmentKind.pdf);
      expect(classify('r.pdf', ''), AttachmentKind.pdf);
      expect(classify('notes.md', ''), AttachmentKind.text);
      expect(classify('main.py', 'text/x-python'), AttachmentKind.text);
      expect(classify('data', 'application/json'), AttachmentKind.text);
    });
    test('refuses what it cannot read', () {
      expect(classify('a.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'), isNull);
      expect(classify('movie.mp4', 'video/mp4'), isNull);
      expect(classify('a.exe', 'application/octet-stream'), isNull);
    });
  });

  group('canAdd', () {
    test('says why a file cannot be attached', () {
      expect(canAdd([], file('a.docx', '', 1)), unsupported);
      expect(canAdd([att('1'), att('2'), att('3'), att('4')], file('x.txt', 'text/plain', 1)), contains('up to 4'));
      expect(canAdd([], file('big.pdf', 'application/pdf', LIMITS.bytesEach + 1)), contains('too big'));
      expect(canAdd([att('a.txt', size: 5)], file('a.txt', 'text/plain', 5)), contains('already attached'));
    });
    test('lets a photo in however big it is, because it is shrunk before sending', () {
      expect(canAdd([], file('p.jpg', 'image/jpeg', 30 * 1024 * 1024)), isNull);
    });
    test('in a words-only chat, takes only text and code', () {
      expect(canAdd([], file('a.log', '', 100), 'text'), isNull);
      expect(canAdd([], file('p.jpg', 'image/jpeg', 100), 'text'), contains('text and code'));
    });
    test('machines take photos and text, not PDFs', () {
      expect(canAdd([], file('r.pdf', 'application/pdf', 100), 'media'), contains('To send a PDF'));
      expect(canAdd([], file('p.jpg', 'image/jpeg', 100), 'media'), isNull);
    });
  });

  group('what is sent', () {
    test('sends the bytes of photos and PDFs and the words of text files, and nothing else', () {
      final list = [att('a.txt'), att('p.jpg', kind: AttachmentKind.image, mime: 'image/jpeg', data: 'QUJD', text: null)];
      expect(toApi(list).map((a) => a.toJson()).toList(), [
        {'name': 'a.txt', 'mime': 'text/plain', 'kind': 'text', 'text': 'hello'},
        {'name': 'p.jpg', 'mime': 'image/jpeg', 'kind': 'image', 'data': 'QUJD'},
      ]);
    });
    test('puts text files into a words-only message, under their names, if it fits', () {
      expect(inlineText('what is wrong?', [att('err.log', text: 'boom')], 100), 'what is wrong?\n\n[err.log]\nboom');
      expect(inlineText('x', [att('big.log', text: 'a' * 200)], 100), isNull);
    });
    test('cuts a long text file and says so', () {
      final short = clipText('short');
      expect((short.text, short.cut), ('short', false));
      final r = clipText('a' * (LIMITS.textChars + 5));
      expect(r.text.length, LIMITS.textChars);
      expect(r.cut, true);
    });
    test('a message with files says what was attached', () {
      expect(withAttachmentNote('look', [att('a.txt'), att('b.png')]), 'look\n\n[Attached: a.txt, b.png]');
      expect(withAttachmentNote('  ', [att('a.txt')]), '[Attached: a.txt]');
      expect(withAttachmentNote('just words', []), 'just words');
    });
    test('totals add up', () => expect(totalBytes([att('a', size: 3), att('b', size: 4)]), 7));
  });

  group('fitWithin', () {
    test('shrinks to the longest side, keeping the shape', () {
      expect(fitWithin(4000, 2000), (width: 1568, height: 784));
      expect(fitWithin(2000, 4000), (width: 784, height: 1568));
    });
    test('never enlarges', () => expect(fitWithin(800, 600), (width: 800, height: 600)));
  });

  test('humanSize', () {
    expect(humanSize(900), '900 B');
    expect(humanSize(2048), '2 KB');
    expect(humanSize(5.5 * 1024 * 1024), '5.5 MB');
  });

  test('prepared photos are named for what they are', () {
    expect(sniffImageMime([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
    expect(sniffImageMime([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), 'image/png');
    expect(sniffImageMime([1, 2, 3]), isNull);
    expect(photoName('IMG_1.HEIC', 'image/jpeg'), 'IMG_1.jpg');
    expect(photoName('', 'image/png'), 'photo.png');
    expect(mimeFromName('notes.MD'), 'text/markdown');
    expect(mimeFromName('noext'), '');
  });

  group('joinSpoken', () {
    test('adds what was heard after what was typed, with one space', () {
      expect(joinSpoken('open the', 'pod bay doors'), 'open the pod bay doors');
      expect(joinSpoken('trailing   ', 'words'), 'trailing words');
    });
    test('is just the speech when nothing was typed, and just the text when nothing was heard', () {
      expect(joinSpoken('', 'hello'), 'hello');
      expect(joinSpoken('typed', ''), 'typed');
      expect(joinSpoken('', ''), '');
    });
  });
}
