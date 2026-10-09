import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'qr.dart';
import 'scan.dart';

/// A photo is shrunk to this before the slower attempts for poor light: faster, and a QR this size is still crisp.
const _photoSide = 1280;

/// Scans a QR code with the camera (mobile_scanner: the phone's own camera with autofocus, read by ML Kit / Vision), and also from
/// a photo of it. If the camera cannot start (permission refused, none present) it says so, and the photo option still works.
class QrScan extends StatefulWidget {
  const QrScan({super.key, required this.onCode});
  final void Function(String text) onCode;

  @override
  State<QrScan> createState() => _QrScanState();
}

class _QrScanState extends State<QrScan> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.normal);
  String? _note;

  /// Why the camera is not running, if it is not. The photo option below still works, so the scanner stays open and says so.
  String? _cameraProblem;
  double _zoom = 0;
  bool _done = false;
  bool _reading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _found(String text) {
    if (_done || !mounted) return;
    _done = true;
    widget.onCode(text);
  }

  Future<String?> _analyze(String path) async {
    try {
      return firstQrOf(await _controller.analyzeImage(path, formats: const [BarcodeFormat.qrCode]));
    } catch (_) {
      return null;
    }
  }

  Future<void> _fromPhoto() async {
    setState(() => _note = null);
    XFile? file;
    try {
      file = await ImagePicker().pickImage(source: ImageSource.gallery);
    } catch (_) {
      setState(() => _note = 'That photo could not be read.');
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _reading = true);
    try {
      final text = await _analyze(file.path) ?? await _hardRead(await file.readAsBytes());
      if (!mounted) return;
      if (text != null) {
        _found(text);
      } else {
        setState(() => _note = 'No QR code found in that photo. Try a sharper, closer one.');
      }
    } catch (_) {
      if (mounted) setState(() => _note = 'That photo could not be read.');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// The photo again, helped for poor conditions (contrast stretched, judged area by area, the middle on its own).
  Future<String?> _hardRead(Uint8List bytes) async {
    final img = await _decodeRgba(bytes);
    if (img == null) return null;
    final dir = await getTemporaryDirectory();
    for (final (i, v) in hardVariants(img).indexed) {
      final png = await _encodePng(v);
      if (png == null) continue;
      final f = File('${dir.path}/escanor-qr-$i-${DateTime.now().microsecondsSinceEpoch}.png');
      try {
        await f.writeAsBytes(png, flush: true);
        final text = await _analyze(f.path);
        if (text != null) return text;
      } finally {
        if (f.existsSync()) f.deleteSync();
      }
    }
    return null;
  }

  static Future<Rgba?> _decodeRgba(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final scale = min(1.0, _photoSide / max(desc.width, desc.height));
    final codec = await desc.instantiateCodec(targetWidth: max(1, (desc.width * scale).round()), targetHeight: max(1, (desc.height * scale).round()));
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final out = data == null ? null : Rgba(data.buffer.asUint8List(), frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    desc.dispose();
    buffer.dispose();
    return out;
  }

  static Future<Uint8List?> _encodePng(Rgba v) {
    final done = Completer<Uint8List?>();
    ui.decodeImageFromPixels(v.data, v.width, v.height, ui.PixelFormat.rgba8888, (image) async {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      done.complete(png?.buffer.asUint8List());
    });
    return done.future;
  }

  Future<void> _changeZoom(double v) async {
    setState(() => _zoom = v);
    try {
      await _controller.setZoomScale(v);
    } catch (_) {
      // not adjustable on this camera
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } catch (_) {
      if (mounted) setState(() => _note = 'This phone would not turn the light on.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_cameraProblem != null)
          Notice('$_cameraProblem You can still scan from a photo of the code, or type the code.', tone: NoticeTone.warn)
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.lg),
            child: AspectRatio(
              aspectRatio: 1,
              child: ColoredBox(
                color: Colors.black,
                child: MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    final text = firstQrOf(capture);
                    if (text != null) _found(text);
                  },
                  errorBuilder: (context, error) {
                    final problem = cameraProblemText(error);
                    if (_cameraProblem != problem) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() => _cameraProblem = problem) : null);
                    }
                    return const SizedBox.shrink();
                  },
                  placeholderBuilder: (context) => const Center(
                    child: Padding(padding: EdgeInsets.all(12), child: Notice('Starting the camera…')),
                  ),
                  overlayBuilder: (context, constraints) => IgnorePointer(
                    child: Stack(
                      children: [
                        // a frame to aim with, the rest dimmed
                        Positioned.fill(child: CustomPaint(painter: _AimPainter(c.primary.withValues(alpha: 0.8)))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_cameraProblem == null)
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, s, _) {
              final torchOk = s.isRunning && s.torchState != TorchState.unavailable;
              if (!s.isRunning) return const SizedBox(height: 0);
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    if (torchOk)
                      Semantics(
                        label: 'Light',
                        toggled: s.torchState == TorchState.on,
                        button: true,
                        child: Material(
                          color: s.torchState == TorchState.on ? c.primary : Colors.transparent,
                          shape: CircleBorder(side: BorderSide(color: s.torchState == TorchState.on ? c.primary : c.lineStrong)),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _toggleTorch,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(Icons.flashlight_on_rounded, size: 20, color: s.torchState == TorchState.on ? c.onPrimary : c.ink),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Semantics(
                        label: 'Zoom',
                        child: Slider(value: _zoom, min: 0, max: 1, onChanged: _changeZoom),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        if (_cameraProblem == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Hold the phone steady about 20–30 cm from the computer’s screen, and raise that screen’s brightness. Use the light or zoom if the room is dark or the code looks small.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.4, color: c.muted),
            ),
          ),
        if (_note != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Notice(_note!, tone: NoticeTone.warn),
          ),
        const SizedBox(height: 12),
        EButton(
          label: _reading ? 'Reading the photo…' : 'Choose a photo of the code',
          icon: Icons.image_outlined,
          kind: ButtonKind.quiet,
          expand: true,
          busy: _reading,
          onPressed: _fromPhoto,
        ),
      ],
    );
  }
}

class _AimPainter extends CustomPainter {
  _AimPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.shortestSide * 0.18;
    final box = RRect.fromRectAndRadius(Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset), const Radius.circular(16));
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(box);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawRRect(
      box,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_AimPainter old) => old.color != color;
}
