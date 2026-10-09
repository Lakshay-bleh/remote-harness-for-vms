import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'animals.dart';
import 'companion.dart';
import 'sound_player.dart';
import 'sprites.dart';

/// How long it reacts to a tap, in milliseconds.
const int reactMs = 2000;

/// Plays the sound of a tap. Swappable so tests do not reach for the audio plugin.
int Function(Animal animal) voicePlayer = playVoice;

/// The size of one sprite pixel, in logical pixels: [scale] brought down to a whole number of device pixels (at least
/// one), so every pixel of the picture lands on the screen's own pixels and stays crisp.
double crispScale(double scale, double devicePixelRatio) {
  final device = math.max(1, (scale * devicePixelRatio + 1e-6).floor());
  return device / devicePixelRatio;
}

/// Paints one frame of pixels, [scale] logical pixels per sprite pixel, nothing smoothed.
class PixelPainter extends CustomPainter {
  PixelPainter({required this.frame, required this.scale, required this.palette});
  final Frame frame;
  final double scale;
  final Map<String, int> palette;

  static final Map<int, Paint> _paints = {};

  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0; y < frame.length; y++) {
      final row = frame[y];
      var x = 0;
      while (x < row.length) {
        final c = row[x];
        final colour = palette[c];
        var end = x + 1;
        while (end < row.length && row[end] == c) {
          end++;
        }
        if (colour != null) {
          final paint = _paints.putIfAbsent(colour, () => Paint()
            ..color = Color(0xFF000000 | colour)
            ..isAntiAlias = false);
          canvas.drawRect(Rect.fromLTWH(x * scale, y * scale, (end - x) * scale, scale), paint);
        }
        x = end;
      }
    }
  }

  @override
  bool shouldRepaint(PixelPainter old) => !identical(old.frame, frame) || old.scale != scale || !identical(old.palette, palette);
}

final Map<Animal, Map<String, int>> _palettes = {};
Map<String, int> _paletteOf(Animal a) => _palettes.putIfAbsent(a, () => paletteFor(a));

/// A companion playing one scene. Pauses while the app is in the background or the screen it is on is hidden, and
/// holds still (one frame) for people who asked for less motion. Tap or touch it and it answers in its own way: the
/// scene changes to its `react` scene (the dog spins, the hamster squeaks), a speech bubble says what it says
/// ("Woof!"), and it makes its sound unless that is switched off in Settings > Companion. Loading spinners and other
/// tiny ones are not tappable.
class PixelDog extends StatefulWidget {
  const PixelDog({super.key, required this.scene, this.scale = 6, this.animal, this.interactive, this.bubble = true, this.onTap});
  final Scene scene;

  /// Logical pixels per sprite pixel (brought down to whole device pixels so it stays crisp).
  final double scale;

  /// Which animal; the one chosen in Settings when left out.
  final Animal? animal;

  /// Answers a tap (default for anything not tiny).
  final bool? interactive;

  /// Show its own speech bubble (the roaming companion draws its own).
  final bool bubble;
  final void Function(String say)? onTap;

  @override
  State<PixelDog> createState() => _PixelDogState();
}

class _PixelDogState extends State<PixelDog> with WidgetsBindingObserver {
  Timer? _tick;
  Timer? _reactTimer;
  int _frame = 0;
  bool _reacting = false;
  String? _say;
  String _side = 'centre';
  bool _still = false;
  bool _shown = true;
  String _playing = '';

  Animal get _which => widget.animal ?? companionChoice.value;
  Scene get _scene => _reacting ? Scene.react : widget.scene;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    companionChoice.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _shown = TickerMode.valuesOf(context).enabled;
    _restart();
  }

  @override
  void didUpdateWidget(PixelDog old) {
    super.didUpdateWidget(old);
    if (old.scene != widget.scene || old.animal != widget.animal) _restart();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _restart();

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _restart();
  }

  /// Start the frames over for what is showing now, or stop them when nobody can see them move.
  void _restart() {
    final key = '${_which.name}:${_scene.name}';
    if (key != _playing) {
      _playing = key;
      _frame = 0;
    }
    _tick?.cancel();
    _tick = null;
    final life = WidgetsBinding.instance.lifecycleState;
    final awake = life == null || life == AppLifecycleState.resumed;
    if (_still || !_shown || !awake) return;
    final def = sceneFrames(_scene, _which);
    _tick = Timer.periodic(Duration(milliseconds: def.frameMs), (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % def.frames.length);
    });
  }

  void _tap(PointerDownEvent e) {
    final which = _which;
    final lines = animalInfo(which).says;
    final line = lines[math.Random().nextInt(lines.length)];
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final left = box.localToGlobal(Offset.zero).dx;
      final right = left + box.size.width;
      final screen = MediaQuery.sizeOf(context).width;
      _side = left < 70 ? 'left' : right > screen - 70 ? 'right' : 'centre';
    }
    setState(() {
      _say = line;
      _reacting = true;
    });
    _restart();
    if (companionSound.value) voicePlayer(which);
    widget.onTap?.call(line);
    _reactTimer?.cancel();
    _reactTimer = Timer(const Duration(milliseconds: reactMs), () {
      if (!mounted) return;
      setState(() {
        _reacting = false;
        _say = null;
      });
      _restart();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _reactTimer?.cancel();
    companionChoice.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final s = crispScale(widget.scale, dpr);
    final def = sceneFrames(_scene, _which);
    final frame = def.frames[_frame % def.frames.length];
    final picture = ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(W * s, H * s),
          painter: PixelPainter(frame: frame, scale: s, palette: _paletteOf(_which)),
        ),
      ),
    );
    final interactive = widget.interactive ?? widget.scale >= 2;
    if (!interactive) return picture;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _tap,
      child: Stack(clipBehavior: Clip.none, children: [
        picture,
        if (widget.bubble && _say != null)
          Positioned(
            bottom: H * s + 4,
            left: _side == 'left' ? 0 : null,
            right: _side == 'right' ? 0 : null,
            child: _side == 'centre'
                ? FractionalTranslation(translation: const Offset(-0.5, 0), child: Transform.translate(offset: Offset(W * s / 2, 0), child: SpeechBubble(_say!)))
                : SpeechBubble(_say!),
          ),
      ]),
    );
  }
}

/// What a companion says when tapped: a small white bubble with a black edge, like a comic.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFF111111), width: 2),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Color(0x59000000), offset: Offset(2, 2))],
            ),
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1, color: Color(0xFF111111), decoration: TextDecoration.none),
            ),
          ),
        ),
      );
}
