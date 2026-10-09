import 'package:mobile_scanner/mobile_scanner.dart';

/// The port of nativeScan.ts: what went wrong in the scanner, in the three ways the caller cares about, and the first code read.
enum ScanFailure { cancelled, unavailable, failed, denied }

/// What went wrong in the scanner. [ScanFailure.denied] is camera permission refused (the photo option still works).
ScanFailure classifyScanError(Object? e) {
  if (e is MobileScannerException) {
    switch (e.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return ScanFailure.denied;
      case MobileScannerErrorCode.unsupported:
        return ScanFailure.unavailable;
      default:
        break;
    }
    final details = '${e.errorDetails?.message ?? ''} ${e.errorDetails?.code ?? ''}';
    return _byText(details);
  }
  return _byText(e is String ? e : (e is Exception || e is Error ? '$e' : ''));
}

ScanFailure _byText(String text) {
  final m = text.toLowerCase();
  if (m.contains('cancel')) return ScanFailure.cancelled;
  if (RegExp('permission|denied|not allowed').hasMatch(m)) return ScanFailure.denied;
  if (RegExp('not available|not implemented|not installed|modulenot|play services|unavailable|unsupported').hasMatch(m)) return ScanFailure.unavailable;
  return ScanFailure.failed;
}

/// The first readable value among what the scanner read, ignoring empty ones.
String? firstQr(Iterable<String?>? values) {
  if (values == null) return null;
  for (final v in values) {
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

/// The first QR value in one capture.
String? firstQrOf(BarcodeCapture? capture) => firstQr(capture?.barcodes.map((b) => b.rawValue));

/// Why the camera is not running, in words, for a scanner failure.
String cameraProblemText(Object? e) => switch (classifyScanError(e)) {
  ScanFailure.denied => 'Camera access was not allowed. You can allow it in the phone’s settings for Escanor.',
  ScanFailure.unavailable => 'This phone cannot use the camera here.',
  _ => 'The camera could not start.',
};
