import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licences of what the app bundles outside Dart packages: native Android and iOS libraries and the fonts.
///
/// Flutter's licence page lists every Dart package and the Flutter engine by itself; these come from Gradle, CocoaPods
/// and assets, so they are added here. Licence names and links are the ones each library's own package (its Maven POM
/// or licence file) declares. When a native dependency is added or changed, add or update its entry.
@visibleForTesting
final List<NativeLicence> nativeLicences = [
  const NativeLicence(
    ['Vosk speech recognition (com.alphacephei:vosk-android 0.3.75)'],
    'Copyright Alpha Cephei Inc. Licensed under the Apache License, Version 2.0. Used on Android for "Hey Escanor".\n\n'
    'The English model "vosk-model-small-en-us-0.15" is downloaded from alphacephei.com when "Hey Escanor" is first '
    'switched on, and is also distributed under the Apache License, Version 2.0.',
    asset: 'assets/licenses/apache-2.0.txt',
  ),
  const NativeLicence(
    ['Java Native Access (net.java.dev.jna:jna 5.19.1)'],
    'Used on Android by Vosk. JNA is dual-licensed: Apache License 2.0 OR GNU LGPL 2.1 or later, at the user\'s choice. '
    'Escanor uses it under the Apache License, Version 2.0. Both licence texts follow.',
    asset: 'assets/licenses/jna-notice.txt',
    extraAssets: ['assets/licenses/apache-2.0.txt', 'assets/licenses/lgpl-2.1.txt'],
  ),
  const NativeLicence(
    ['Firebase SDKs (Firebase Cloud Messaging, Firebase Core)'],
    'Copyright Google LLC. Licensed under the Apache License, Version 2.0. Used for app notifications.',
    asset: 'assets/licenses/apache-2.0.txt',
  ),
  const NativeLicence(
    ['Google Play services (base, basement, cloud messaging)'],
    'Copyright Google LLC. Provided under the Android Software Development Kit License: '
    'https://developer.android.com/studio/terms.html',
  ),
  const NativeLicence(
    ['Google ML Kit barcode scanning'],
    'Copyright Google LLC. Provided under the ML Kit Terms of Service: https://developers.google.com/ml-kit/terms. '
    'Used to scan the pairing code shown by Escanor Desktop.',
  ),
  const NativeLicence(
    ['Razorpay Checkout SDK (com.razorpay:checkout)'],
    'Copyright Razorpay Software Private Limited. Proprietary; used under Razorpay\'s terms: https://razorpay.com/terms/. '
    'Used for payments.',
  ),
  const NativeLicence(
    ['Gellix typeface'],
    'The Gellix typeface by Gerillass is a commercial font, not open source.',
  ),
];

class NativeLicence {
  const NativeLicence(this.packages, this.notice, {this.asset, this.extraAssets = const []});
  final List<String> packages;
  final String notice;

  /// A licence text shipped as an asset, shown after [notice].
  final String? asset;
  final List<String> extraAssets;
}

/// Adds [nativeLicences] to Flutter's [LicenseRegistry], so "Open-source licences" lists them. Call once at start-up.
void registerNativeLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final licence in nativeLicences) {
      final texts = [licence.notice];
      for (final path in [?licence.asset, ...licence.extraAssets]) {
        texts.add(await rootBundle.loadString(path));
      }
      yield LicenseEntryWithLineBreaks(licence.packages, texts.join('\n\n'));
    }
  });
}
