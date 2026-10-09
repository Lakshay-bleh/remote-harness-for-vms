import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/busy.dart';
import 'animals.dart';
import 'busy_scene.dart';
import 'companion_floor.dart';
import 'pixel_dog.dart';
import 'roam.dart';
import 'sprites.dart';

/// How long with no touch or key before the companion falls asleep.
const Duration sleepAfter = Duration(seconds: 60);

/// While awake and not working it sits, and now and then has a sniff around.
const Duration _sitFor = Duration(seconds: 18);
const Duration _sniffFor = Duration(seconds: 5);

/// The companion, always there: a small one in the corner of every screen. It runs while anything is loading ([busy],
/// or the shared count from `trackBusy`), sits and sniffs about when all is quiet, and falls asleep when nobody has
/// touched the screen for a minute. Every minute or two (a random while) it goes for an outing: a stroll along the
/// bottom, a lap right round the edge of the screen (up a side, upside down along the top, down the other side), a peek
/// in from the edge, a spin and a dash, or a nap in the far corner. Tap it and it answers. People who asked for less
/// motion get it standing still in its corner.
///
/// It is a direct child of the shell's Stack: it fills it (so it can roam anywhere) but only the companion itself takes
/// taps. Phones: bottom left, just above the tab bar, or just above the message box on a screen that has one. Wide
/// screens: bottom right. It stays in its corner while the keyboard is up (no outings over what is being typed), and an
/// outing carries on along the same edge when the screen changes size under it.
class Buddy extends StatefulWidget {
  const Buddy({super.key, this.busy = false, this.scale = 2, this.animal, this.eager = false, this.only});
  final bool busy;
  final double scale;
  final Animal? animal;

  /// Go on outings every few seconds instead of every minute or two (for trying it out).
  final bool eager;

  /// Always this outing (for trying it out).
  final Excursion? only;

  @override
  State<Buddy> createState() => _BuddyState();
}

class _BuddyState extends State<Buddy> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _rand = math.Random();
  bool _asleep = false;
  bool _sniffing = false;
  int _busy = busyCount.value;

  Timer? _sleepTimer;
  Timer? _routine;

  // the outings
  late final Ticker _ticker = createTicker(_onTick);
  Timer? _outing;
  Plan? _plan;

  /// The screen the outing was planned on; where it is now is worked out from that and the screen as it is now.
  Geometry? _planned;
  Sample? _at;
  Excursion? _last;
  Geometry? _geometry;
  bool _still = false;

  // what it said, drawn upright wherever it is
  ({String text, double x, double y, bool below})? _said;
  Timer? _saidTimer;

  final _sprite = GlobalKey();
  final _area = GlobalKey();

  // How far above the bottom of its area the controls along the bottom of the screen begin (a message box): it rests above
  // them, not on them. Null on a screen without any.
  double? _lift;
  bool _keyboard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    busyCount.addListener(_onBusy);
    companionFloor.addListener(_onFloor);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFloor());
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    _wake();
    _routineStep(false);
    _scheduleOuting(widget.eager ? 1500 : nextDelay(_rand.nextDouble, true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still && _plan != null) {
      // less motion was just asked for: back to its corner at once (this build puts it there)
      if (_ticker.isActive) _ticker.stop();
      _plan = null;
      _at = null;
      _scheduleOuting(nextDelay(_rand.nextDouble));
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final keyboard = View.of(context).viewInsets.bottom > 0;
    // The keyboard came up: whoever is typing does not want it running about over the message, so it goes home at once.
    if (keyboard && !_keyboard && _plan != null) _endOuting(schedule: true);
    _keyboard = keyboard;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFloor());
  }

  /// The bottom controls moved, came or went: where they begin, measured from the bottom of the companion's area.
  void _onFloor() {
    if (!mounted) return;
    final floor = companionFloor.value;
    final area = _area.currentContext?.findRenderObject() as RenderBox?;
    double? lift;
    if (floor != null && area != null && area.attached && area.hasSize) {
      final bottom = area.localToGlobal(Offset(0, area.size.height)).dy;
      lift = math.max(0, bottom - floor);
    }
    if (lift != _lift) setState(() => _lift = lift);
  }

  void _onBusy() {
    if (mounted) setState(() => _busy = busyCount.value);
  }

  // asleep after a minute of nobody; any touch or key wakes it
  void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent || e is PointerMoveEvent || e is PointerScrollEvent || e is PointerPanZoomUpdateEvent) _wake();
  }

  bool _onKey(KeyEvent e) {
    _wake();
    return false;
  }

  void _wake() {
    if (_asleep && mounted) setState(() => _asleep = false);
    _sleepTimer?.cancel();
    _sleepTimer = Timer(sleepAfter, () {
      if (mounted) setState(() => _asleep = true);
    });
  }

  // the sit, sniff, sit routine
  void _routineStep(bool sniff) {
    if (!mounted) return;
    if (sniff != _sniffing) setState(() => _sniffing = sniff);
    _routine = Timer(sniff ? _sniffFor : _sitFor, () => _routineStep(!sniff));
  }

  void _scheduleOuting(int ms) {
    _outing?.cancel();
    _outing = Timer(Duration(milliseconds: ms), _go);
  }

  void _go() {
    if (!mounted) return;
    final g = _geometry;
    final life = WidgetsBinding.instance.lifecycleState;
    final hidden = life != null && life != AppLifecycleState.resumed;
    // not now: the app is in the background, it is asleep, it is busy working, or it should keep still
    final typing = View.of(context).viewInsets.bottom > 0;
    if (g == null || hidden || typing || _asleep || widget.busy || _busy > 0 || _still) return _scheduleOuting(20000);
    final kind = widget.only ?? pickExcursion(_rand.nextDouble, _last);
    _last = kind;
    setState(() {
      _planned = g;
      _plan = planExcursion(kind, g, _rand.nextDouble);
      _at = sample(_plan!, g.home, 0);
    });
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final plan = _plan;
    if (plan == null || !mounted) return;
    final s = sample(plan, _planned!.home, elapsed.inMicroseconds / 1000);
    if (s.done) {
      _endOuting(schedule: true);
      return;
    }
    setState(() => _at = s);
  }

  void _endOuting({required bool schedule}) {
    if (_ticker.isActive) _ticker.stop();
    if (mounted) {
      setState(() {
        _plan = null;
        _at = null;
        _planned = null;
      });
    }
    if (schedule) _scheduleOuting(widget.eager ? 4000 : nextDelay(_rand.nextDouble));
  }

  // a tap: its own speech bubble, drawn upright wherever it is (the picture may be sideways or upside down)
  void _tapped(String text) {
    final box = _sprite.currentContext?.findRenderObject() as RenderBox?;
    final stack = context.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.hasSize) return;
    final r = MatrixUtils.transformRect(box.getTransformTo(stack), Offset.zero & box.size);
    final width = stack.size.width;
    final x = math.min(width - 56, math.max(56.0, r.center.dx));
    final below = r.top < 56;
    setState(() => _said = (text: text, x: x, y: below ? r.bottom + 6 : r.top - 6, below: below));
    _saidTimer?.cancel();
    _saidTimer = Timer(const Duration(milliseconds: reactMs - 200), () {
      if (mounted) setState(() => _said = null);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _outing?.cancel();
    _routine?.cancel();
    _sleepTimer?.cancel();
    _saidTimer?.cancel();
    busyCount.removeListener(_onBusy);
    companionFloor.removeListener(_onFloor);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    final s = crispScale(widget.scale, dpr);
    final sw = W * s;
    final sh = H * s;
    final wide = mq.size.width >= 768;
    final pad = mq.padding;

    return Positioned.fill(
      child: LayoutBuilder(key: _area, builder: (context, box) {
        final vw = box.maxWidth;
        final vh = box.maxHeight;
        // where it rests: its own corner, clear of the notch, the home bar, the keyboard (the area already ends above it)
        // and a message box
        final left = wide ? vw - pad.right - 12 - sw : pad.left + 4;
        final lift = _lift;
        final bottom = wide ? math.max(pad.bottom + 12, lift == null ? 0.0 : lift + 8) : (lift == null ? 8.0 : lift + 4);
        // never above the top edge, however short the area gets
        final home = Vec(left + sw / 2, math.max(pad.top + 4 + sh / 2, vh - bottom - sh / 2));
        final g = _geometry = Geometry(vw: vw, vh: vh, sw: sw, sh: sh, home: home, top: pad.top + 4);

        final at = _at;
        final planned = _planned;
        final scene = at?.leg.scene ?? buddyScene(busy: widget.busy || _busy > 0, asleep: _asleep, sniffing: _sniffing);
        final pos = at == null ? home : (planned == null ? at.pos : refit(at.pos, planned, g));
        final turn = at == null ? (rotate: 0, mirror: false) : orientation(at.leg.feet, at.leg.face);
        final transform = Matrix4.rotationZ(turn.rotate * math.pi / 180)..multiply(Matrix4.diagonal3Values(turn.mirror ? -1 : 1, 1, 1));
        final said = _said;

        return Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: pos.x - sw / 2,
            top: pos.y - sh / 2,
            width: sw,
            height: sh,
            child: Transform(
              key: _sprite,
              alignment: Alignment.center,
              transform: transform,
              child: PixelDog(animal: widget.animal, scene: scene, scale: widget.scale, bubble: false, interactive: true, onTap: _tapped),
            ),
          ),
          if (said != null)
            Positioned(
              left: said.x,
              top: said.y,
              child: FractionalTranslation(translation: Offset(-0.5, said.below ? 0 : -1), child: SpeechBubble(said.text)),
            ),
        ]);
      }),
    );
  }
}
