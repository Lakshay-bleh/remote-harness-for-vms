import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nav.dart';
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../assistant/conversations.dart';
import 'actions.dart';
import 'ask_assistant.dart';
import 'cancel.dart';
import 'commands.dart';
import 'device.dart';
import 'orb_position.dart';
import 'phone_control_setup.dart';
import 'voice_mode.dart';
import 'voice_prefs.dart';
import 'voice_session.dart';

/// Escanor's voice, on every screen. The Escanor mark floats where the person last put it: press and drag it anywhere, let go, and
/// it stays. A tap opens voice mode, a full screen of its own (so it never sits on top of the message box), where Escanor listens,
/// does what was said (on this phone, on a computer, or through the assistant), answers out loud, and listens again until the
/// person is done. "Hey Escanor" (Android) opens it too.
class VoiceHost extends ConsumerStatefulWidget {
  const VoiceHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<VoiceHost> createState() => _VoiceHostState();
}

class _VoiceHostState extends ConsumerState<VoiceHost> {
  late final VoiceSession _session;
  late final VoiceConversation _conversation;
  final List<StreamSubscription<void>> _subs = [];
  Route<void>? _route;

  OrbPos _pos = loadOrb();
  ({double x, double y, bool moved})? _drag;
  bool _dragging = false;
  final FocusNode _orbFocus = FocusNode(debugLabel: 'voice-orb');

  @override
  void initState() {
    super.initState();
    _session = VoiceSession(handle: voiceHandler(go: _go, onAssistant: _ask));
    // "Hey Escanor": while voice mode has the microphone the background listener steps aside, and comes back when it is closed.
    _conversation = VoiceConversation(_session, onOpenChanged: (open) => ChannelDevice.instance.wakePause(open));
    _conversation.addListener(_syncRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) => voiceModeOpener.value = _show);

    if (isAndroid) {
      final dev = ChannelDevice.instance;
      // Heard while the app is open, or the "Hey! I'm listening" notification was tapped (escanor://voice): open voice mode.
      _subs.add(dev.wakeHeard.listen((_) => _show()));
      _subs.add(dev.voiceLinks.listen((_) => _takeLink()));
      dev.wakeListen(true);
      // Opened from a closed app by "Hey Escanor": Android hands over the address it started with, once.
      _takeLink();
      // The service ends with the phone's own housekeeping now and then: bring it back if the person left it switched on.
      if (getVoicePrefs().wakeWord) {
        dev.wakeStatus().then((s) {
          if (s != null && s.modelReady && !s.running && s.micAllowed) dev.wakeStart().catchError((_) => const PluginResult(ok: false));
        });
      }
    }
  }

  Future<void> _takeLink() async {
    if (await ChannelDevice.instance.takeVoiceLink() && mounted) _show();
  }

  @override
  void dispose() {
    if (voiceModeOpener.value == _show) voiceModeOpener.value = null;
    for (final s in _subs) {
      s.cancel();
    }
    if (isAndroid) ChannelDevice.instance.wakeListen(false);
    _conversation.removeListener(_syncRoute);
    _conversation.live = false;
    _session.dispose();
    _orbFocus.dispose();
    super.dispose();
  }

  void _go(VoiceTab tab) {
    ref.read(navProvider.notifier).go(AppTab.values.firstWhere((t) => t.name == tab.name, orElse: () => AppTab.assistant));
    _conversation.close();
  }

  Future<String?> _ask(String text, VoiceCancel cancel) {
    final nav = ref.read(navProvider.notifier);
    return askAssistant(
      text,
      cancel,
      conversationId: ref.read(navProvider).conversationId,
      setConversation: nav.setConversation,
      onSent: () => reloadConversations(ref),
    );
  }

  void _show() {
    if (!mounted) return;
    if (currentPrefs().haptics) HapticFeedback.lightImpact();
    _conversation.show();
  }

  /// Voice mode is a page of its own on top of everything, so the phone's back button closes it.
  void _syncRoute() {
    if (!mounted) return;
    if (_conversation.open && _route == null) {
      final route = PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (_, _, _) => VoiceModeScreen(conversation: _conversation, session: _session),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      );
      _route = route;
      Navigator.of(context, rootNavigator: true).push(route).then((_) {
        if (identical(_route, route)) _route = null;
        if (_conversation.open) _conversation.close();
      });
    } else if (!_conversation.open && _route != null) {
      final route = _route!;
      _route = null;
      if (route.isActive) route.navigator?.removeRoute(route);
    }
    setState(() {});
  }

  // ---- the movable button

  OrbView _view(BoxConstraints box) {
    final mq = MediaQuery.of(context);
    final wide = mq.size.width >= 768;
    // keep clear of the status bar, and of the tab bar along the bottom on phones
    return OrbView(width: box.maxWidth, height: box.maxHeight, insetTop: mq.padding.top, insetBottom: mq.padding.bottom + (wide ? 0 : 64));
  }

  void _nudge(double dx, double dy) {
    final next = OrbPos((_pos.x + dx).clamp(0, 1).toDouble(), (_pos.y + dy).clamp(0, 1).toDouble());
    setState(() => _pos = next);
    saveOrb(next);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    // Keyboard and switch users cannot drag: the arrow keys nudge it, Enter opens it.
    const step = 0.04;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _nudge(-step, 0);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _nudge(step, 0);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _nudge(0, -step);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _nudge(0, step);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      _show();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return LayoutBuilder(builder: (context, box) {
      final view = _view(box);
      final at = orbOffset(_pos, view);
      return Stack(children: [
        Positioned.fill(child: widget.child),
        if (!keyboard && !_conversation.open)
          Positioned(
            left: at.left,
            top: at.top,
            child: Focus(
              focusNode: _orbFocus,
              onKeyEvent: _onKey,
              child: Semantics(
                button: true,
                label: 'Talk to Escanor. Drag to move this button.',
                onTap: _show,
                child: Listener(
                  onPointerDown: (e) => _drag = (x: e.position.dx, y: e.position.dy, moved: false),
                  onPointerMove: (e) {
                    final d = _drag;
                    if (d == null) return;
                    if (!d.moved && movedFar(e.position.dx - d.x, e.position.dy - d.y)) {
                      _drag = (x: d.x, y: d.y, moved: true);
                      setState(() => _dragging = true);
                      haptic();
                    }
                    if (_drag!.moved) {
                      final box = context.findRenderObject() as RenderBox?;
                      final local = box?.globalToLocal(e.position) ?? e.position;
                      setState(() => _pos = posFromPoint(local.dx, local.dy, view));
                    }
                  },
                  onPointerUp: (_) {
                    final d = _drag;
                    _drag = null;
                    setState(() => _dragging = false);
                    if (d == null) return;
                    if (d.moved) {
                      saveOrb(_pos);
                    } else {
                      _show();
                    }
                  },
                  onPointerCancel: (_) {
                    if (_drag?.moved == true) saveOrb(_pos);
                    _drag = null;
                    setState(() => _dragging = false);
                  },
                  child: _Orb(dragging: _dragging),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.dragging});
  final bool dragging;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedScale(
      scale: dragging ? 1.1 : 1,
      duration: const Duration(milliseconds: 150),
      child: Container(
        width: orbSize,
        height: orbSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF050505),
          border: Border.all(color: c.lineStrong),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: dragging ? 0.7 : 0.45), blurRadius: dragging ? 40 : 18, offset: Offset(0, dragging ? 18 : 8), spreadRadius: -8),
          ],
        ),
        child: const IgnorePointer(child: Logo(size: 38)),
      ),
    );
  }
}

const _label = <VoicePhase, String>{
  VoicePhase.idle: 'Tap the mic to talk',
  VoicePhase.listening: 'Listening…',
  VoicePhase.thinking: 'Working on it…',
  VoicePhase.speaking: 'Speaking',
};

/// Voice mode: the full screen where Escanor listens, works and answers.
class VoiceModeScreen extends StatefulWidget {
  const VoiceModeScreen({super.key, required this.conversation, required this.session});
  final VoiceConversation conversation;
  final VoiceSession session;
  @override
  State<VoiceModeScreen> createState() => _VoiceModeScreenState();
}

class _VoiceModeScreenState extends State<VoiceModeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  // The phone-control steps open under an answer that needs them; "Not now" hides them until the next answer.
  bool _setupClosed = false;
  Object? _lastReply;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.session, widget.conversation]),
      builder: (context, _) {
        final v = widget.session;
        if (!identical(v.reply, _lastReply)) {
          _lastReply = v.reply;
          _setupClosed = false;
        }
        return _build(context, v);
      },
    );
  }

  Widget _build(BuildContext context, VoiceSession v) {
    final c = context.c;
    final busy = v.phase != VoicePhase.idle;
    final reply = v.reply;
    final dev = deviceOrNull();
    final still = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(children: [
              const Logo(size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text('Escanor', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink))),
              IconButton(
                tooltip: 'Close voice',
                onPressed: widget.conversation.close,
                icon: Icon(Icons.close_rounded, size: 22, color: c.muted),
              ),
            ]),
          ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height * 0.55),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _Rings(phase: v.phase, anim: _anim, still: still),
                    const SizedBox(height: 20),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (v.phase == VoicePhase.thinking) ...[const Spinner(size: 22), const SizedBox(width: 8)],
                      Text(_label[v.phase]!, style: TextStyle(fontSize: 14, color: c.muted)),
                    ]),
                    if (v.heard.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text('“${v.heard}”', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, height: 1.3, color: c.ink)),
                    ],
                    if (reply != null) ...[
                      const SizedBox(height: 20),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 448, maxHeight: MediaQuery.sizeOf(context).height * 0.34),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: reply.ok ? c.surfaceCard : c.warning.withValues(alpha: 0.05),
                            border: Border.all(color: reply.ok ? c.hairline : c.warning.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(Radii.lg),
                          ),
                          child: SingleChildScrollView(
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Icon(reply.ok ? Icons.check_circle_rounded : Icons.error_rounded, size: 20, color: reply.ok ? c.success : c.warning),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(reply.say, style: TextStyle(fontSize: 14, height: 1.4, color: c.bodyStrong))),
                            ]),
                          ),
                        ),
                      ),
                    ],
                    if (reply?.needs == Needs.accessibility && !_setupClosed && dev != null) ...[
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 448),
                        child: Container(
                          decoration: BoxDecoration(color: c.surfaceCard, border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.lg)),
                          child: PhoneControlSetup(dev: dev, onDismiss: () => setState(() => _setupClosed = true)),
                        ),
                      ),
                    ],
                    if (v.heard.isEmpty && reply == null) ...[
                      const SizedBox(height: 20),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          'Try “open YouTube”, “set a timer for 5 minutes”, “call Mom”, “on my computer, show my containers”, or ask anything.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, height: 1.6, color: c.muted),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Semantics(
                button: true,
                label: busy ? 'Stop' : 'Talk',
                child: Material(
                  color: busy ? c.surfaceCard : c.primary,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      haptic();
                      widget.conversation.toggle();
                    },
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Icon(busy ? Icons.stop_rounded : Icons.mic_rounded, size: busy ? 30 : 32, color: busy ? c.ink : c.onPrimary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(busy ? 'Tap to stop' : 'Tap to talk', style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The mark in the middle, with what it is doing drawn around it: rings while listening, a turning arc while working, a glow
/// while speaking.
class _Rings extends StatelessWidget {
  const _Rings({required this.phase, required this.anim, required this.still});
  final VoicePhase phase;
  final Animation<double> anim;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final listening = phase == VoicePhase.listening;
    return SizedBox(
      width: 160,
      height: 160,
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final t = still ? 0.5 : anim.value;
          final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
          return Stack(alignment: Alignment.center, children: [
            if (listening) ...[
              Transform.scale(
                scale: 0.75 + 0.35 * t,
                child: Opacity(
                  opacity: (1 - t) * 0.8,
                  child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.primary.withValues(alpha: 0.3), width: 2))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Opacity(
                  opacity: 0.4 + 0.6 * pulse,
                  child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.primary.withValues(alpha: 0.4)))),
                ),
              ),
            ],
            if (phase == VoicePhase.thinking)
              Transform.rotate(
                angle: t * 2 * math.pi,
                child: SizedBox.expand(child: CustomPaint(painter: _ArcPainter(c.primary))),
              ),
            if (phase == VoicePhase.speaking)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Opacity(
                  opacity: 0.4 + 0.6 * pulse,
                  child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary.withValues(alpha: 0.1))),
                ),
              ),
            Container(
              width: 112,
              height: 112,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF050505),
                border: Border.all(color: listening ? c.primary.withValues(alpha: 0.6) : c.lineStrong),
                boxShadow: listening ? [BoxShadow(color: c.primary.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: -6)] : null,
              ),
              child: const Logo(size: 76),
            ),
          ]);
        },
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Offset.zero & size, -math.pi / 2, math.pi / 2, false, p);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}
