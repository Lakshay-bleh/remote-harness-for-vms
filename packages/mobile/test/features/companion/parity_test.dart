import 'package:escanor/features/companion/animals.dart';
import 'package:escanor/features/companion/sprites.dart';
import 'package:flutter_test/flutter_test.dart';

/// FNV-1a fingerprints of every scene as the web app (packages/web/src/escanor/dog) draws it: the port must come out
/// pixel for pixel the same. Made with Node from sprites.ts: frames joined by a blank line, rows by a newline.
const Map<String, String> webFingerprints = {
  'dog:run': 'bfc21eb5',
  'dog:sniff': 'e295bb41',
  'dog:dig': '6f2f1a46',
  'dog:sit': '52ee50ee',
  'dog:sleep': 'a66ad72d',
  'dog:lick': '58d27e69',
  'dog:home': '572f39e3',
  'dog:react': '84f51e9c',
  'unicorn:run': 'd1929f8d',
  'unicorn:sniff': '3d444dac',
  'unicorn:dig': '8c4573b5',
  'unicorn:sit': '92722fe1',
  'unicorn:sleep': 'b82a2723',
  'unicorn:lick': '1f641185',
  'unicorn:home': 'b343a3fc',
  'unicorn:react': 'd61db698',
  'pigeon:run': '980fe674',
  'pigeon:sniff': 'd7f037b1',
  'pigeon:dig': '7715c5d7',
  'pigeon:sit': 'dc0ec960',
  'pigeon:sleep': 'ac31935d',
  'pigeon:lick': 'a67e78a3',
  'pigeon:home': '1f17887f',
  'pigeon:react': '1bb737b3',
  'hamster:run': 'ad5fae5e',
  'hamster:sniff': 'a04541f2',
  'hamster:dig': 'af1b2ec7',
  'hamster:sit': '2b445e3e',
  'hamster:sleep': 'f7f39db9',
  'hamster:lick': '6594eb63',
  'hamster:home': '1db558e3',
  'hamster:react': 'e94157cf',
  'cat:run': '78bdc789',
  'cat:sniff': '57a141f5',
  'cat:dig': 'a9c550ca',
  'cat:sit': 'ccf47276',
  'cat:sleep': 'd1626a31',
  'cat:lick': '4b461120',
  'cat:home': 'c7643677',
  'cat:react': 'e71445ce',
  'elephant:run': 'fc334649',
  'elephant:sniff': 'dfebcfe0',
  'elephant:dig': '45481ae6',
  'elephant:sit': '8daf2d0b',
  'elephant:sleep': '6e49c025',
  'elephant:lick': '24156499',
  'elephant:home': 'deef66cf',
  'elephant:react': 'a80f1ea3',
};

String fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

void main() {
  for (final a in Animal.values) {
    for (final s in Scene.values) {
      test('the ${a.name} ${s.name} scene is drawn exactly as on the web', () {
        final frames = sceneFrames(s, a).frames;
        expect(fnv1a(frames.map((f) => f.join('\n')).join('\n\n')), webFingerprints['${a.name}:${s.name}']);
      });
    }
  }
}
