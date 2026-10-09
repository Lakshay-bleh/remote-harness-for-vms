/// The pixel toolkit every animal is drawn with: a grid of characters (one per pixel), a few shapes, and an automatic
/// outline. Nothing here touches the screen.
// ignore_for_file: constant_identifier_names
library;

/// One picture: [h] rows of [w] characters, one per pixel. `.` is clear.
typedef Frame = List<String>;

const int W = 36;
const int H = 22;
const int groundY = 20;

/// The characters that belong to the animal itself: only these get an outline.
const Set<String> bodyColours = {'f', 'd', 'c', 'n', 't', 'T', 'w', 'M', 'N', 'H', 'p', 'y', 'u', 'j', 'x'};

/// JavaScript's `Math.round` (halves go up, also for negatives), so the pictures come out exactly as on the web.
int jsRound(num v) => (v + 0.5).floor();

class Pix {
  Pix([this.w = W, this.h = H]) : cells = List.generate(h, (_) => List<String>.filled(w, '.'));

  final int w;
  final int h;
  final List<List<String>> cells;

  void px(num x, num y, String c) {
    final xi = jsRound(x);
    final yi = jsRound(y);
    if (xi >= 0 && xi < w && yi >= 0 && yi < h) cells[yi][xi] = c;
  }

  void rect(num x, num y, num rw, num rh, String c, [bool round = false]) {
    for (var j = 0; j < rh; j++) {
      for (var i = 0; i < rw; i++) {
        if (round && (i == 0 || i == rw - 1) && (j == 0 || j == rh - 1)) continue;
        px(x + i, y + j, c);
      }
    }
  }

  /// A filled ellipse around a centre, for round bodies.
  void oval(num cx, num cy, num rx, num ry, String c) {
    for (var y = (cy - ry).floor(); y <= (cy + ry).ceil(); y++) {
      for (var x = (cx - rx).floor(); x <= (cx + rx).ceil(); x++) {
        final dx = (x - cx) / (rx + 0.35);
        final dy = (y - cy) / (ry + 0.35);
        if (dx * dx + dy * dy <= 1) px(x, y, c);
      }
    }
  }

  /// A line of single pixels.
  void line(num x0, num y0, num x1, num y1, String c) {
    final steps = [(x1 - x0).abs(), (y1 - y0).abs(), 1].reduce((a, b) => a > b ? a : b);
    for (var i = 0; i <= steps; i++) {
      px(x0 + ((x1 - x0) * i) / steps, y0 + ((y1 - y0) * i) / steps, c);
    }
  }

  /// A limb: 2x2 squares along the points, so a leg can lean and bend.
  void limb(List<(num, num)> points, String c, [String paw = 'c']) {
    for (var i = 0; i < points.length; i++) {
      rect(points[i].$1, points[i].$2, 2, 2, i == points.length - 1 ? paw : c);
    }
  }

  String _at(int x, int y) => (y < 0 || y >= h || x < 0 || x >= w) ? '.' : cells[y][x];

  /// Put a 1-pixel outline around the animal's own colours.
  void outline() {
    final mark = <(int, int)>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (cells[y][x] != '.') continue;
        if (bodyColours.contains(_at(x - 1, y)) ||
            bodyColours.contains(_at(x + 1, y)) ||
            bodyColours.contains(_at(x, y - 1)) ||
            bodyColours.contains(_at(x, y + 1))) {
          mark.add((x, y));
        }
      }
    }
    for (final (x, y) in mark) {
      cells[y][x] = 'o';
    }
  }

  /// Draw a small picture (rows of characters) at a position.
  void stamp(num x, num y, List<String> rows) {
    for (var j = 0; j < rows.length; j++) {
      final row = rows[j];
      for (var i = 0; i < row.length; i++) {
        final c = row[i];
        if (c != '.' && c != ' ') px(x + i, y + j, c);
      }
    }
  }

  /// Flip the whole picture left to right (the animal turns round).
  void mirror() {
    for (var j = 0; j < cells.length; j++) {
      cells[j] = cells[j].reversed.toList();
    }
  }

  Frame frame() => [for (final r in cells) r.join()];
}

typedef RectFn = void Function(num x, num y, num w, num h, String c, [bool round]);
typedef PxFn = void Function(num x, num y, String c);

/// Where a scene is drawn: positions are in the scene's own coordinates, shifted to the standard place on the picture.
class Brush {
  const Brush(this.r, this.p);
  final RectFn r;
  final PxFn p;
}

enum View { side, sit, sleep, dig, front }

/// One cell of a tail: where, and what colour.
typedef Cell = (num, num, String);

class EarOpts {
  const EarOpts({this.blown = false, this.side});
  final bool blown;

  /// 'left' or 'right', for the front view.
  final String? side;
}

/// What makes one four-legged animal different from another, as a few hooks into the shared drawing. A hook that is
/// missing leaves the dog's own part in place. Coordinates are those of the dog's part in the same scene, so a species
/// draws relative to them.
class Skin {
  const Skin({this.ear, this.tail, this.head, this.snout, this.body});

  /// Replaces the floppy ear. `x, y` is where the dog's ear starts; `blown` when the wind has it back (running).
  /// For the front view `side` says which ear.
  final void Function(Brush b, View view, num x, num y, EarOpts o)? ear;

  /// Replaces the tail path with the cells to draw (x, y, colour).
  final List<Cell> Function(List<(num, num)> path, View view)? tail;

  /// Extras on the head: `x, y, w, h` is the head's box.
  final void Function(Brush b, View view, num x, num y, num w, num h)? head;

  /// Extras on the muzzle (whiskers, a trunk): `x, y` is the 4x4 muzzle's top left.
  final void Function(Brush b, View view, num x, num y)? snout;

  /// Extras on the body, drawn after it: a mane, stripes. `x, y, w, h` is the main body box.
  final void Function(Brush b, View view, num x, num y, num w, num h)? body;

  /// This skin with the hooks [over] defines put on top (`{...this, ...over}`).
  Skin merge(Skin over) => Skin(
        ear: over.ear ?? ear,
        tail: over.tail ?? tail,
        head: over.head ?? head,
        snout: over.snout ?? snout,
        body: over.body ?? body,
      );
}
