import 'package:flutter/material.dart';

import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import 'actions.dart';
import 'device.dart';
import 'phone_control_setup.dart';
import 'voice_prefs.dart';
import 'wake_status.dart';

/// CONTRACT (owned by the voice feature). Settings > Voice and phone control.
///
/// Everything about talking to Escanor and letting it use the phone: "Hey Escanor", calling, and controlling the phone (home, back,
/// scrolling, tapping). Each permission is explained here, in plain words, before Android asks for it, and each can be switched off.
class VoiceSettingsPage extends StatefulWidget {
  const VoiceSettingsPage({super.key});
  @override
  State<VoiceSettingsPage> createState() => _VoiceSettingsPageState();
}

class _VoiceSettingsPageState extends State<VoiceSettingsPage> with WidgetsBindingObserver {
  final DevicePlugin? _dev = deviceOrNull();
  ControlStatus? _control;
  ({bool granted, bool? available})? _call;
  WakeStatus? _status;
  int? _progress;
  String? _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    final dev = _dev;
    if (dev == null) return;
    ({bool granted, bool? available}) call;
    try {
      call = await dev.callStatus();
    } catch (_) {
      call = (granted: false, available: null);
    }
    final status = await ChannelDevice.instance.wakeStatus();
    if (!mounted) return;
    setState(() {
      _call = call;
      _status = status;
    });
  }

  WakeStep _step(WakeStatus? s) => wakeStep(s, native: isAndroid);

  Future<void> _turnWakeOn() async {
    final wake = ChannelDevice.instance;
    setState(() {
      _note = null;
      _busy = true;
    });
    void note(String n) {
      if (mounted) setState(() => _note = n);
    }

    try {
      var s = _status;
      if (_step(s) == WakeStep.download) {
        setState(() => _progress = 0);
        final r = await wake.wakeDownloadModel((p) {
          if (mounted) setState(() => _progress = p);
        });
        if (mounted) setState(() => _progress = null);
        if (!r.ok) return note(r.message ?? 'Could not download the voice model.');
        s = await wake.wakeStatus();
        if (mounted) setState(() => _status = s);
      }
      if (_step(s) == WakeStep.microphone) {
        // Android asks the first time voice is used; if it was refused, only Android's settings can change it.
        return note('Escanor needs the microphone for this. Open Android Settings, then Apps, Escanor, Permissions, and allow Microphone. Then switch this on again.');
      }
      final r = await wake.wakeStart();
      if (!r.ok) return note(r.message ?? 'Could not start listening.');
      setVoicePrefs((p) => p.copyWith(wakeWord: true));
      final now = await wake.wakeStatus();
      if (mounted) setState(() => _status = now);
    } catch (_) {
      note('Could not start listening.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnWakeOff() async {
    final wake = ChannelDevice.instance;
    try {
      await wake.wakeStop();
    } catch (_) {}
    setVoicePrefs((p) => p.copyWith(wakeWord: false));
    final s = await wake.wakeStatus();
    if (mounted) setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VoicePrefs>(
      valueListenable: voicePrefs,
      builder: (context, _, _) => _page(context, getVoicePrefs()),
    );
  }

  Widget _page(BuildContext context, VoicePrefs prefs) {
    final dev = _dev;
    final step = _step(_status);
    final outside = outsideApp(_status);
    final ios = isIOS;
    final android = isAndroid;
    final wake = ChannelDevice.instance;
    return SettingsPage(
      title: 'Voice and phone control',
      subtitle: 'Talk to Escanor and let it use your phone',
      children: [
        if (dev == null) const Notice('These work in the Escanor phone app. You can look at what each one does here.'),
        if (ios)
          const Notice(
              'iOS does not let an app listen for “Hey Escanor” in the background or press buttons in other apps, so those two are Android only. Talking to Escanor with the microphone button, calling, torch and opening websites work here.'),
        if (!ios)
          Group(
            title: 'Hey Escanor',
            footer:
                'Escanor listens for the two words on this phone only, using a small voice model. Nothing is recorded or sent anywhere. A notification shows while it is listening, and it uses a little battery. Switch it off any time.',
            children: [
              SwitchRow(
                icon: Icons.graphic_eq_rounded,
                label: 'Say “Hey Escanor”',
                on: prefs.wakeWord && step == WakeStep.listening,
                disabled: dev == null || _busy,
                onChanged: (v) => v ? _turnWakeOn() : _turnWakeOff(),
              ),
              if (step == WakeStep.download)
                const SRow(icon: Icons.download_rounded, label: 'One-time download', sub: 'About 40 MB of voice model, fetched over a secure connection when you switch this on.'),
              if (_progress != null) SRow(label: 'Downloading… $_progress%', right: const Spinner(size: 24)),
              if (step == WakeStep.microphone)
                const SRow(icon: Icons.mic_rounded, label: 'Microphone needed', sub: 'Allow it in Android Settings, Apps, Escanor, Permissions.'),
              if (step == WakeStep.listening) const SRow(label: 'Listening now', sub: 'Say “Hey Escanor” and then what you want.'),
            ],
          ),
        if (android && (step == WakeStep.listening || step == WakeStep.ready))
          Group(
            title: 'From other apps and the home screen',
            footer: 'Android does not let an app open itself from the background. Escanor never draws over other apps, so payment and banking apps keep working.',
            children: [
              SRow(icon: Icons.open_in_new_rounded, label: 'Open Escanor when it hears you', sub: outside.line),
              if (outside.canAllowFullScreen)
                SRow(label: 'Full-screen notifications', value: 'Not allowed', sub: 'Lets the notification take over a locked or idle screen.', onTap: () => wake.wakeOpenFullScreenSettings()),
              SRow(
                label: 'Try it',
                sub: 'Tap, then press Home or open another app. In six seconds Escanor acts as though you had said it.',
                onTap: () => wake.wakeTest().then((_) {
                  if (mounted) setState(() => _note = 'Press Home now. Escanor will open in a few seconds.');
                }),
              ),
            ],
          ),
        if (_note != null) Notice(_note!, tone: NoticeTone.warn),
        if (!ios)
          Group(
            title: 'Control your phone',
            footer:
                'Escanor asks before each step. Android requires you to switch this on yourself, in its Accessibility settings. Payment and banking apps do not run while it is on, so Escanor switches it off by itself when you open one and leaves a notification to switch it back on.',
            children: [
              SRow(
                icon: Icons.touch_app_rounded,
                label: 'Phone control',
                sub: _control?.enabled == true ? 'Try: “go home”, “scroll down”, “tap Send”.' : 'Go home or back, scroll, tap and type when you ask.',
                value: dev != null && _control == null ? null : (_control?.enabled == true ? 'On' : 'Off'),
                right: dev != null && _control == null ? const Spinner(size: 24) : null,
              ),
              if (dev != null) PhoneControlSetup(dev: dev, onStatus: (s) => setState(() => _control = s)),
            ],
          ),
        // The normal download has no call permission: calls always open the dialer there.
        if (!ios && _call?.available == false)
          const Group(
            title: 'Calling',
            footer:
                '“Call Mom” opens the dialer with the number filled in, and you press call. Escanor does not ask for the Phone permission in this download, so it installs without warnings.',
            children: [SRow(icon: Icons.call_rounded, label: 'Calls open the dialer', chevron: false)],
          ),
        if (!ios && _call?.available != false)
          Group(
            title: 'Calling',
            footer:
                'With this on, “call Mom” rings straight away. Off, Escanor opens the dialer with the number filled in and you press call. Android asks for the Phone permission the first time.',
            children: [
              SwitchRow(icon: Icons.call_rounded, label: 'Call directly', on: prefs.directCalls, onChanged: (v) => setVoicePrefs((p) => p.copyWith(directCalls: v))),
              SRow(
                icon: Icons.verified_user_rounded,
                label: 'Phone permission',
                value: _call == null ? null : (_call!.granted ? 'Allowed' : 'Not allowed'),
                right: _call == null ? const Spinner(size: 24) : null,
                sub: _call != null && !_call!.granted ? 'Tap to allow Escanor to place calls.' : null,
                chevron: false,
                onTap: _call != null && !_call!.granted && dev != null ? () => dev.requestCallPermission().then((_) => _refresh()) : null,
              ),
            ],
          ),
      ],
    );
  }
}
