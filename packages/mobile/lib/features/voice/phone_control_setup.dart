import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../settings/info_pages.dart' show showLegalSheet;
import 'actions.dart';
import 'control_consent.dart';
import 'phone_control.dart';
import 'voice_prefs.dart';

/// What phone control can see and do, said in the app before Android is ever opened. Google Play calls this the prominent disclosure.
const _canDo = [
  'Go home or back, open recent apps, notifications or quick settings, lock the screen and take a screenshot',
  'Scroll, tap a button by its name, and type into the box you are in',
  'Read the words on your screen, only when you ask “what is on my screen”',
];

/// Switching on phone control, one step at a time and each one asked for: what it does and "I agree", then (for an app installed
/// from a file on Android 13+) allowing the restricted setting in App info, then switching Escanor on in Accessibility settings.
/// Android lets only the person do the last two; this says exactly where to tap and checks again when they come back.
class PhoneControlSetup extends StatefulWidget {
  const PhoneControlSetup({super.key, required this.dev, this.onStatus, this.onDismiss});
  final DevicePlugin dev;
  final void Function(ControlStatus s)? onStatus;
  final VoidCallback? onDismiss;

  @override
  State<PhoneControlSetup> createState() => _PhoneControlSetupState();
}

class _PhoneControlSetupState extends State<PhoneControlSetup> with WidgetsBindingObserver {
  ControlStatus? _status;

  /// Which of the restricted-setting steps the person has done (Android does not say when it has been allowed).
  int _done = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A choice made while offline or signed out reaches the consent ledger the next time this opens.
    flushControlConsent();
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The person leaves for Android's settings to switch something on: look again when they come back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    ControlStatus s;
    try {
      s = await widget.dev.controlStatus();
    } catch (_) {
      s = const ControlStatus(enabled: false, available: true);
    }
    if (!mounted) return;
    setState(() => _status = s);
    widget.onStatus?.call(s);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VoicePrefs>(
      valueListenable: voicePrefs,
      builder: (context, _, _) => _body(context, controlStep(_status, getVoicePrefs().controlConsent)),
    );
  }

  Widget _body(BuildContext context, ControlStep step) {
    final c = context.c;
    final text = TextStyle(fontSize: 13, height: 1.55, color: c.body);
    final small = TextStyle(fontSize: 12, height: 1.55, color: c.muted);
    final bold = TextStyle(fontWeight: FontWeight.w600, color: c.ink);
    Widget pad(List<Widget> children) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 10), children[i]],
          ]),
        );
    Widget link(String label, VoidCallback onTap, {TextStyle? style}) => InkWell(
          onTap: onTap,
          child: Text(label, style: (style ?? text).copyWith(color: c.ink, decoration: TextDecoration.underline, decorationColor: c.ink)),
        );
    Widget list(List<InlineSpan> Function(int i) item, int n, {bool numbered = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < n; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 20, child: Text(numbered ? '${i + 1}.' : '•', style: text)),
                  Expanded(child: Text.rich(TextSpan(style: text, children: item(i)))),
                ]),
              ),
          ],
        );
    final withdraw = Center(
      child: TextButton(
        onPressed: () => setControlConsent(false),
        child: Text('I changed my mind', style: small.copyWith(decoration: TextDecoration.underline, decorationColor: c.muted)),
      ),
    );

    switch (step) {
      case ControlStep.checking:
        return const Padding(padding: EdgeInsets.all(12), child: Center(child: Spinner(size: 32)));
      case ControlStep.on:
        return pad([
          Text.rich(TextSpan(style: text, children: [
            const TextSpan(
                text:
                    'Phone control is on. Payment and banking apps do not run while it is, so Escanor switches it off when you open one. You can switch it off yourself here, or turn off '),
            TextSpan(text: 'Escanor', style: bold),
            const TextSpan(text: ' in Accessibility settings.'),
          ])),
          EButton(
            label: 'Switch phone control off',
            kind: ButtonKind.quiet,
            expand: true,
            onPressed: () async {
              try {
                await widget.dev.controlTurnOff();
              } catch (_) {
                // an older build without it: the Accessibility settings button below still works
              }
              await _refresh();
            },
          ),
          EButton(label: 'Open Accessibility settings', kind: ButtonKind.quiet, expand: true, onPressed: () => widget.dev.openControlSettings()),
        ]);
      case ControlStep.notInBuild:
        return pad([
          Text.rich(TextSpan(style: text, children: [
            const TextSpan(
                text: 'This download of Escanor leaves phone control out, because Android’s Play Protect blocks downloaded apps that include it. To use it, install the '),
            TextSpan(text: '“with phone control”', style: bold),
            const TextSpan(text: ' APK from the Escanor release page.'),
          ])),
        ]);
      case ControlStep.disclosure:
        return pad([
          Text('Escanor uses Android’s Accessibility service to do these things for you:', style: text.copyWith(color: c.ink, fontWeight: FontWeight.w500)),
          list((i) => [TextSpan(text: _canDo[i])], _canDo.length),
          Text(
            'It acts only when you ask, by voice or in the app, and never on its own. To find a button or read the screen, it looks at the words on the screen at that moment. That text stays on this phone: it is shown and read aloud to you, and not stored or sent to Escanor’s servers. Escanor does not use it for ads or anything else.',
            style: text,
          ),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('You can switch it off any time in Android’s Accessibility settings. Your choice is recorded in your account. More in the ', style: text),
            link('privacy policy', () => showLegalSheet(context, start: 'privacy')),
            Text('.', style: text),
          ]),
          Row(children: [
            Expanded(child: EButton(label: 'I agree', expand: true, onPressed: () => setControlConsent(true))),
            if (widget.onDismiss != null) ...[
              const SizedBox(width: 8),
              Expanded(child: EButton(label: 'Not now', kind: ButtonKind.quiet, expand: true, onPressed: widget.onDismiss)),
            ],
          ]),
        ]);
      case ControlStep.restricted:
        return pad([
          Text(
            'Escanor was installed from a downloaded file, so Android greys its switch out (“Controlled by restricted setting”) until you lift that. Only you can do it. First lift the restriction, then switch Escanor on:',
            style: text,
          ),
          list(
            (i) => i == 0
                ? [
                    const TextSpan(text: 'Open Escanor’s App info, tap '),
                    TextSpan(text: '⋮', style: bold),
                    const TextSpan(text: ' at the top right, then '),
                    TextSpan(text: 'Allow restricted settings', style: bold),
                    const TextSpan(text: ', and confirm with your PIN or fingerprint.'),
                  ]
                : [
                    const TextSpan(text: 'Open Accessibility settings, tap '),
                    TextSpan(text: 'Escanor', style: bold),
                    const TextSpan(text: ' and switch it on.'),
                  ],
            2,
            numbered: true,
          ),
          EButton(
            label: '1. Allow restricted settings in App info',
            kind: _done == 0 ? ButtonKind.primary : ButtonKind.quiet,
            expand: true,
            onPressed: () {
              setState(() => _done = _done > 1 ? _done : 1);
              widget.dev.openAppInfo();
            },
          ),
          EButton(
            label: '2. Switch Escanor on in Accessibility',
            kind: _done >= 1 ? ButtonKind.primary : ButtonKind.quiet,
            expand: true,
            onPressed: () => widget.dev.openControlSettings(),
          ),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text.rich(TextSpan(style: small, children: [
              const TextSpan(text: 'No '),
              TextSpan(text: 'Allow restricted settings', style: bold),
              const TextSpan(
                  text:
                      ' under ⋮? Android only shows it after you have tried once: tap Escanor in Accessibility settings, close the “denied” message, then repeat step 1. '),
            ])),
            link('Open Accessibility settings', () => widget.dev.openControlSettings(), style: small),
          ]),
          withdraw,
        ]);
      case ControlStep.turnOn:
        return pad([
          Text.rich(TextSpan(style: text, children: [
            const TextSpan(text: 'In the next screen, find '),
            TextSpan(text: 'Escanor', style: bold),
            const TextSpan(text: ', tap it and switch it on. Android then shows its own warning, which it shows for every app that can press buttons for you.'),
          ])),
          EButton(label: 'Open Accessibility settings', expand: true, onPressed: () => widget.dev.openControlSettings()),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Greyed out, “Controlled by restricted setting”? Lift it first: open ', style: small),
            link('Escanor’s App info', () => widget.dev.openAppInfo(), style: small),
            Text(', tap ⋮ at the top right, then Allow restricted settings.', style: small),
          ]),
          withdraw,
        ]);
    }
  }
}
