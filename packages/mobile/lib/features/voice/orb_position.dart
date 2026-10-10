/// Where the voice button sits. It is stored as a fraction of the free space (0 = left or top edge, 1 = right or bottom edge), so it
/// lands in the same place on a rotated phone, with the keyboard gone, or on another screen size, and never off-screen.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../../core/storage.dart';

class OrbPos {
  const OrbPos(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) => other is OrbPos && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => 'OrbPos($x, $y)';
}

const orbSize = 56.0;

/// Breathing room between the button and the screen's edge.
const orbMargin = 6.0;
const _key = 'escanor.orb.v1';

/// Out of the way of the message box and its send button: right edge, a little above the middle.
const defaultOrb = OrbPos(1, 0.4);

double _clamp01(double n) => n.isNaN ? 0 : math.min(1, math.max(0, n));

class OrbView {
  const OrbView({required this.width, required this.height, this.insetTop = 0, this.insetBottom = 0});
  final double width;
  final double height;

  /// Space the system keeps for itself at the top (status bar) and bottom (gesture bar, tab bar).
  final double insetTop;
  final double insetBottom;
}

/// The fraction for the button's centre being at a point on the screen.
OrbPos posFromPoint(double x, double y, OrbView v, {double size = orbSize}) {
  final spanX = math.max(1.0, v.width - size - orbMargin * 2);
  final spanY = math.max(1.0, v.height - v.insetTop - v.insetBottom - size - orbMargin * 2);
  return OrbPos(_clamp01((x - size / 2 - orbMargin) / spanX), _clamp01((y - size / 2 - v.insetTop - orbMargin) / spanY));
}

/// Where the button's top-left corner goes for a position, in the view: follows the screen's size and keeps clear of the insets.
({double left, double top}) orbOffset(OrbPos p, OrbView v, {double size = orbSize}) {
  final x = _clamp01(p.x);
  final y = _clamp01(p.y);
  final spanX = math.max(0.0, v.width - size - orbMargin * 2);
  final spanY = math.max(0.0, v.height - v.insetTop - v.insetBottom - size - orbMargin * 2);
  return (left: orbMargin + x * spanX, top: v.insetTop + orbMargin + y * spanY);
}

OrbPos? parseOrb(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final v = jsonDecode(raw);
    if (v is! Map) return null;
    final x = v['x'], y = v['y'];
    if (x is! num || y is! num || !x.isFinite || !y.isFinite) return null;
    return OrbPos(_clamp01(x.toDouble()), _clamp01(y.toDouble()));
  } catch (_) {
    return null;
  }
}

OrbPos loadOrb() {
  try {
    return parseOrb(Storage.instance.getString(_key)) ?? defaultOrb;
  } catch (_) {
    return defaultOrb;
  }
}

void saveOrb(OrbPos p) {
  try {
    Storage.instance.setString(_key, jsonEncode({'x': _clamp01(p.x), 'y': _clamp01(p.y)}));
  } catch (_) {
    // not remembered; it still stays where it was dropped for this visit
  }
}

/// Moving less than this is a tap, not a drag.
const dragSlopPx = 8.0;
bool movedFar(double dx, double dy) => math.sqrt(dx * dx + dy * dy) > dragSlopPx;
