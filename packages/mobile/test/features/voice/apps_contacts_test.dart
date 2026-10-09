import 'package:escanor/features/voice/apps.dart';
import 'package:escanor/features/voice/contacts.dart';
import 'package:flutter_test/flutter_test.dart';

const apps = [
  InstalledApp(label: 'YouTube', package: 'com.google.android.youtube'),
  InstalledApp(label: 'YouTube Music', package: 'com.google.android.apps.youtube.music'),
  InstalledApp(label: 'WhatsApp', package: 'com.whatsapp'),
  InstalledApp(label: 'Maps', package: 'com.google.android.apps.maps'),
  InstalledApp(label: 'Camera', package: 'com.sec.android.app.camera'),
  InstalledApp(label: 'Chrome', package: 'com.android.chrome'),
  InstalledApp(label: 'Samsung Internet', package: 'com.sec.android.app.sbrowser'),
  InstalledApp(label: 'Settings', package: 'com.android.settings'),
  InstalledApp(label: 'Phone', package: 'com.samsung.android.dialer'),
  InstalledApp(label: 'Gmail', package: 'com.google.android.gm'),
  InstalledApp(label: 'Spotify', package: 'com.spotify.music'),
];

const book = [
  Contact(name: 'Tanishq USICT 2027', numbers: ['+919876500001']),
  Contact(name: 'Tanishq Sharma', numbers: ['+919876500002']),
  Contact(name: 'Mom', numbers: ['+919876500003']),
  Contact(name: 'Aman Gupta (College)', numbers: ['+919876500004']),
  Contact(name: 'Amit Gupta', numbers: ['+919876500005']),
  Contact(name: 'Dr. Priya Nair', numbers: ['+919876500006']),
];

ContactChoice pick(String said) => chooseContact(said, book);
String? oneName(ContactChoice c) => c is OneContact ? c.contact.name : null;

void main() {
  group('matchApp', () {
    test('prefers an exact name over a longer one that starts with it', () {
      expect(matchApp('youtube', apps)?.package, 'com.google.android.youtube');
      expect(matchApp('youtube music', apps)?.package, 'com.google.android.apps.youtube.music');
    });
    test('ignores case, spaces and punctuation, so how it was heard does not matter', () {
      expect(matchApp('Whats App', apps)?.package, 'com.whatsapp');
      expect(matchApp('WhatsApp', apps)?.package, 'com.whatsapp');
      expect(matchApp('you tube', apps)?.package, 'com.google.android.youtube');
    });
    test('knows the usual nicknames', () {
      expect(matchApp('google maps', apps)?.package, 'com.google.android.apps.maps');
      expect(matchApp('browser', apps)?.package, 'com.android.chrome');
      expect(matchApp('mail', apps)?.package, 'com.google.android.gm');
      expect(matchApp('dialer', apps)?.package, 'com.samsung.android.dialer');
    });
    test('finds a word inside a longer label', () {
      expect(matchApp('internet', apps)?.package, 'com.sec.android.app.sbrowser');
    });
    test('says nothing found, rather than guessing, for an app that is not installed', () {
      expect(matchApp('tiktok', apps), isNull);
      expect(matchApp('', apps), isNull);
      expect(matchApp('a', apps), isNull); // too short to mean anything
    });
  });

  group('what was heard, as words and numbers', () {
    test('splits letters from digits and drops punctuation', () {
      expect(tokens('Tanishq USICT2027'), ['tanishq', 'usict', '2027']);
      expect(tokens('Dr. Priya Nair'), ['dr', 'priya', 'nair']);
    });
    test('joins a year the way people say it', () {
      expect(tokens('tanishq usic twenty twenty seven'), ['tanishq', 'usic', '2027']);
      expect(tokens('tanishq usic 20 27'), ['tanishq', 'usic', '2027']);
      expect(tokens('tanishq usic two thousand and twenty seven'), ['tanishq', 'usic', '2027']);
    });
    test('drops accents', () {
      expect(tokens('José Müller'), ['jose', 'muller']);
    });
  });

  group('words that sound or are spelled nearly the same', () {
    test('forgives a dropped letter, a cut-off word and a different spelling of the same sound', () {
      expect(wordScore('usic', 'usict'), greaterThanOrEqualTo(0.8));
      expect(wordScore('tanisha', 'tanishq'), greaterThanOrEqualTo(0.7));
      expect(wordScore('kumar', 'kumaar'), greaterThanOrEqualTo(0.8));
    });
    test('never treats two different numbers as alike', () {
      expect(wordScore('2026', '2027'), 0);
      expect(wordScore('2027', 'usict'), 0);
    });
  });

  group('choosing the contact', () {
    test('finds "Tanishq USICT 2027" from the very sentences that failed before', () {
      for (final said in ['tanishq usic 2027', 'tanishq usict 2027', 'Tanishq USIC 20 27', 'tanishq u s i c t twenty twenty seven']) {
        final c = pick(said);
        expect(c, isA<OneContact>(), reason: said);
        expect(oneName(c), 'Tanishq USICT 2027', reason: said);
      }
    });
    test('finds the right one among similar names', () {
      expect(oneName(pick('mom')), 'Mom');
      expect(oneName(pick('doctor priya nair')), 'Dr. Priya Nair');
    });
    test('asks which one when two fit about equally, and says none when nothing does', () {
      final c = pick('gupta');
      expect(c, isA<AskContact>());
      expect((c as AskContact).options.map((x) => x.name).toList()..sort(), ['Aman Gupta (College)', 'Amit Gupta']);
      expect(pick('zebra crossing'), isA<NoContact>());
    });
    test('prefers the saved name that says more of what was said', () {
      expect(rankContacts('tanishq', book).length, greaterThanOrEqualTo(2));
    });
  });
}
