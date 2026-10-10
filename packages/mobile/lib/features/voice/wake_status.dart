/// "Hey Escanor": what the native side says about it, and what the settings screen makes of that. Pure.
library;

class WakeStatus {
  const WakeStatus({
    required this.running,
    required this.modelReady,
    required this.downloading,
    required this.micAllowed,
    this.opensDirectly,
    this.fullScreenDeclared,
    this.fullScreenAllowed,
  });
  final bool running;
  final bool modelReady;
  final bool downloading;
  final bool micAllowed;

  /// Phone control is on, and with it Android lets the app open itself from another app or the home screen.
  final bool? opensDirectly;

  /// This build can use full-screen notifications at all (the normal download leaves them out).
  final bool? fullScreenDeclared;

  /// "Full-screen notifications" (Android 14+): lets the notification take over a locked or idle screen.
  final bool? fullScreenAllowed;

  factory WakeStatus.fromJson(Object? raw) {
    final j = raw is Map ? raw : const {};
    bool? opt(String k) => j[k] is bool ? j[k] as bool : null;
    return WakeStatus(
      running: j['running'] == true,
      modelReady: j['modelReady'] == true,
      downloading: j['downloading'] == true,
      micAllowed: j['micAllowed'] == true,
      opensDirectly: opt('opensDirectly'),
      fullScreenDeclared: opt('fullScreenDeclared'),
      fullScreenAllowed: opt('fullScreenAllowed'),
    );
  }

  WakeStatus copyWith({bool? running, bool? modelReady, bool? micAllowed, bool? opensDirectly, bool? fullScreenDeclared, bool? fullScreenAllowed}) =>
      WakeStatus(
        running: running ?? this.running,
        modelReady: modelReady ?? this.modelReady,
        downloading: downloading,
        micAllowed: micAllowed ?? this.micAllowed,
        opensDirectly: opensDirectly ?? this.opensDirectly,
        fullScreenDeclared: fullScreenDeclared ?? this.fullScreenDeclared,
        fullScreenAllowed: fullScreenAllowed ?? this.fullScreenAllowed,
      );
}

/// How "Hey Escanor" gets the app on screen when it is heard outside the app, in a sentence, and what could be switched on to improve
/// it. Escanor never draws over other apps (payment apps refuse to run next to one that can), so outside the app it is a notification
/// unless phone control is on.
({String line, bool best, bool canAllowFullScreen}) outsideApp(WakeStatus? s) {
  final canAllowFullScreen = s?.fullScreenDeclared == true && s?.fullScreenAllowed == false;
  if (s?.opensDirectly == true) return (line: 'Escanor opens straight away, from any app or the home screen.', best: true, canAllowFullScreen: false);
  return (
    line: canAllowFullScreen
        ? 'Escanor shows a “Hey! I’m listening” notification: tap it. Allow “Full-screen notifications” so it also shows on a locked screen.'
        : 'Escanor shows a “Hey! I’m listening” notification: tap it. With phone control on, it opens straight away.',
    best: false,
    canAllowFullScreen: canAllowFullScreen,
  );
}

/// What the person sees while turning "Hey Escanor" on, in order: a sentence for each thing that can be in the way.
enum WakeStep { unsupported, download, microphone, ready, listening }

WakeStep wakeStep(WakeStatus? s, {required bool native}) {
  if (!native || s == null) return WakeStep.unsupported;
  if (s.running) return WakeStep.listening;
  if (!s.modelReady) return WakeStep.download;
  if (!s.micAllowed) return WakeStep.microphone;
  return WakeStep.ready;
}
