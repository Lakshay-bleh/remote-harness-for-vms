import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';

/// Both sign-in screens (Escanor and your own hub) share this frame: the form, and the eclipse beside it on wide screens.
/// With [embedded] (inside the signed-in app, e.g. the hub's own sign-in on the Machines tab) it fills the space it is given
/// instead of the whole screen.
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.title, required this.subtitle, required this.children, this.footer, this.embedded = false});
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? footer;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final wide = MediaQuery.sizeOf(context).width >= 1024;

    final content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        header: true,
        child: Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: c.ink)),
      ),
      const SizedBox(height: 6),
      Text(subtitle, style: TextStyle(fontSize: 14, height: 1.5, color: c.body)),
      const SizedBox(height: 24),
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        children[i],
      ],
    ]);

    // The logo at the top, the form in the middle of what is left, the footer at the bottom; it all scrolls when the
    // keyboard leaves too little room.
    final form = LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: (box.maxHeight - 64).clamp(0, double.infinity)),
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Logo(size: 36),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(padding: const EdgeInsets.only(top: 24, bottom: 40), child: content),
              ),
            ),
            footer != null ? Center(child: footer!) : const SizedBox.shrink(),
          ]),
        ),
      ),
    );

    final body = wide
        ? Row(children: [
            Expanded(flex: 100, child: form),
            const Expanded(flex: 105, child: _Eclipse()),
          ])
        : form;

    if (embedded) return ColoredBox(color: c.canvas, child: body);
    return Scaffold(backgroundColor: c.canvas, body: SafeArea(child: body));
  }
}

class _Eclipse extends StatelessWidget {
  const _Eclipse();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.canvas, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.hairline)),
          child: Stack(fit: StackFit.expand, children: [
            Image.asset('assets/images/login-eclipse.webp', fit: BoxFit.cover, alignment: const Alignment(0, -0.64)),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [c.canvas, c.canvas.withValues(alpha: 0.3), c.canvas.withValues(alpha: 0)],
                ),
              ),
            ),
            Positioned(
              left: 40,
              right: 40,
              bottom: 40,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 384),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('When production breaks, Escanor goes to work.',
                      style: TextStyle(fontSize: 30, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: c.ink)),
                  const SizedBox(height: 12),
                  Text('Connect your stack and your agents. Escanor watches, fixes and verifies, even when you are not looking.',
                      style: TextStyle(fontSize: 14, color: c.body)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The Google "G", drawn in its own four colours.
class GoogleIcon extends StatelessWidget {
  const GoogleIcon({super.key, this.size = 17});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: CustomPaint(size: Size.square(size), painter: const _GooglePainter()));
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  // The four paths of the mark, on a 24 x 24 grid (escanor/ui.tsx).
  static Path _blue() => Path()
    ..moveTo(21.6, 12.23)
    ..cubicTo(21.6, 11.52, 21.54, 10.83, 21.42, 10.18)
    ..lineTo(12, 10.18)
    ..lineTo(12, 14.06)
    ..lineTo(17.38, 14.06)
    ..cubicTo(17.15, 15.31, 16.44, 16.38, 15.38, 17.08)
    ..lineTo(15.38, 19.58)
    ..lineTo(18.62, 19.58)
    ..cubicTo(20.51, 17.84, 21.6, 15.28, 21.6, 12.23)
    ..close();

  static Path _green() => Path()
    ..moveTo(12, 22)
    ..cubicTo(14.7, 22, 16.96, 21.1, 18.62, 19.58)
    ..lineTo(15.38, 17.08)
    ..cubicTo(14.48, 17.68, 13.34, 18.04, 12, 18.04)
    ..cubicTo(9.4, 18.04, 7.2, 16.28, 6.41, 13.93)
    ..lineTo(3.06, 13.93)
    ..lineTo(3.06, 16.51)
    ..cubicTo(4.71, 19.78, 8.09, 22, 12, 22)
    ..close();

  static Path _yellow() => Path()
    ..moveTo(6.41, 13.93)
    ..cubicTo(6.01, 12.68, 6.01, 11.33, 6.41, 10.08)
    ..lineTo(6.41, 7.5)
    ..lineTo(3.06, 7.5)
    ..cubicTo(1.65, 10.33, 1.65, 13.67, 3.06, 16.5)
    ..lineTo(6.41, 13.93)
    ..close();

  static Path _red() => Path()
    ..moveTo(12, 5.98)
    ..cubicTo(13.47, 5.98, 14.79, 6.48, 15.83, 7.48)
    ..lineTo(18.7, 4.61)
    ..cubicTo(16.95, 2.99, 14.7, 2, 12, 2)
    ..cubicTo(8.09, 2, 4.71, 4.22, 3.06, 7.5)
    ..lineTo(6.41, 10.08)
    ..cubicTo(7.2, 7.74, 9.4, 5.98, 12, 5.98)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()..isAntiAlias = true;
    canvas.drawPath(_blue(), p..color = const Color(0xFF4285F4));
    canvas.drawPath(_green(), p..color = const Color(0xFF34A853));
    canvas.drawPath(_yellow(), p..color = const Color(0xFFFBBC05));
    canvas.drawPath(_red(), p..color = const Color(0xFFEA4335));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
