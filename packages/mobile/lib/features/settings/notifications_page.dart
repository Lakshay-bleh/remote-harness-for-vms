import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/load.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../push/push_service.dart';
import 'settings_api.dart';
import 'settings_logic.dart';
import 'settings_widgets.dart';

const _icons = {
  'emergency_alerts': Icons.report_outlined,
  'server_down': Icons.bolt_rounded,
  'deployment_approvals': Icons.rocket_launch_outlined,
  'team_pings': Icons.groups_outlined,
  'checks': Icons.radar_rounded,
};

const _prefsCache = CachePolicy('notification-prefs', ttl: Duration(minutes: 5), maxAge: Duration(days: 30));

/// What Escanor may tell this person about. The switches are saved on their account, so the website and this app always agree.
/// Delivery to the phone itself needs push to be set up in the app build; until it is, this says so instead of implying otherwise.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _loaded = Loader<Map<String, dynamic>>(fetchNotificationPrefs, cache: _prefsCache);
  NotificationPrefs? _prefs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loaded.addListener(_sync);
    _sync();
  }

  void _sync() {
    final d = _loaded.data;
    if (d != null && mounted) setState(() => _prefs = NotificationPrefs.fromJson(d));
  }

  @override
  void dispose() {
    _loaded.removeListener(_sync);
    _loaded.dispose();
    super.dispose();
  }

  // Each switch saves straight away; if the save fails the switch goes back and says why.
  Future<void> _set(Map<String, bool> patch) async {
    final before = _prefs;
    if (before == null) return;
    setState(() {
      _prefs = before.merge(patch);
      _error = null;
    });
    try {
      final saved = await setNotificationPrefs(patch);
      writeCache(_prefsCache.key, saved.toJson());
      if (mounted) setState(() => _prefs = saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _prefs = before;
          _error = errorText(e, 'Could not save that.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _loaded,
      builder: (context, _) {
        final p = _prefs;
        return SettingsPage(title: 'Notifications', children: [
          if (_loaded.error != null && p == null) Notice(_loaded.error!, tone: NoticeTone.error),
          if (_error != null) Notice(_error!, tone: NoticeTone.error),
          const ThisPhone(),
          if (_loaded.loading && p == null)
            const BlockSpinner(padding: 40)
          else if (p != null) ...[
            Group(
              footer: 'Turning this off silences everything below. Your choices are saved to your Escanor account and shared with the website.',
              children: [
                SwitchRow(
                  icon: Icons.notifications_active_outlined,
                  label: 'Notifications',
                  sub: 'The master switch',
                  on: p.pushEnabled,
                  onChanged: (v) => _set({'push_enabled': v}),
                ),
              ],
            ),
            Group(title: 'Tell me about', children: [
              for (final k in notificationKinds)
                SwitchRow(
                  icon: _icons[k.key],
                  label: k.label,
                  sub: k.sub,
                  on: p.pushEnabled && p[k.key],
                  disabled: !p.pushEnabled,
                  onChanged: (v) => _set({k.key: v}),
                ),
            ]),
          ],
        ]);
      },
    );
  }
}

/// Whether this phone can receive alerts, and the buttons to turn them on and to check they arrive.
class ThisPhone extends StatefulWidget {
  const ThisPhone({super.key});
  @override
  State<ThisPhone> createState() => _ThisPhoneState();
}

class _ThisPhoneState extends State<ThisPhone> {
  final _server = Loader<({bool configured, int devices})?>(
    () => fetchPushStatus().then<({bool configured, int devices})?>((v) => v).catchError((_) => null),
  );
  PushState? _state;
  ChannelState? _channel;
  bool _busy = false;
  ({bool ok, String text})? _result;

  @override
  void initState() {
    super.initState();
    pushState().then((s) {
      if (!mounted) return;
      setState(() => _state = s);
      _checkChannel();
    });
  }

  // Android can silence the Alerts channel behind the app's back, and then "On" would be a lie. Ask it every time this opens.
  void _checkChannel() {
    if (_state != PushState.on) return;
    alertChannelState().then((c) {
      if (mounted) setState(() => _channel = c);
    });
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  Future<void> _turnOn() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final s = await enablePush();
    if (!mounted) return;
    setState(() {
      _state = s;
      _busy = false;
    });
    _server.reload();
    _checkChannel();
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final delivered = await sendTestPush();
      _result = delivered > 0
          ? (ok: true, text: 'Sent. It should arrive in a few seconds.')
          : (ok: false, text: 'Nothing was delivered. Try turning notifications off and on again.');
    } catch (e) {
      _result = (ok: false, text: errorText(e, 'Could not send the test.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _server,
      builder: (context, _) {
        final c = context.c;
        final state = _state;
        final server = _server.data;
        final phoneSettings = phoneSettingsName();
        if (state == null || (_server.loading && server == null)) return const SizedBox.shrink();
        if (state == PushState.unsupported) {
          return const Notice('Alerts on a phone need the Escanor Android app. Your choices below are saved to your account either way.');
        }
        if (state == PushState.unavailable) {
          return const Notice('This version of the app was built without Firebase, so it cannot receive notifications. Install the latest release.',
              tone: NoticeTone.warn);
        }
        if (server != null && !server.configured) {
          return const Notice('This Escanor server is not set up to send push notifications yet, so nothing can reach your phone. Your choices below '
              'are saved and will apply once it is.');
        }

        final footer = state == PushState.on && _channel == ChannelState.ok
            ? (phoneSettings == 'iPhone Settings'
                ? 'If a test still does not show, check iPhone Settings: Notifications, Escanor.'
                : 'If a test still does not show when the app is closed, check Android Settings: Battery, Escanor, Unrestricted; and Apps, Escanor, Notifications.')
            : state == PushState.denied
                ? (phoneSettings == 'iPhone Settings'
                    ? 'Notifications are blocked for Escanor. Allow them in iPhone Settings, under Notifications, Escanor.'
                    : 'Notifications are blocked for Escanor. Allow them in Android Settings, under Apps, Escanor, Notifications.')
                : null;

        final ch = _channel;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Group(title: 'On this phone', footer: footer, children: [
            if (state == PushState.on) ...[
              SRow(
                icon: Icons.smartphone_rounded,
                label: 'Notifications on this phone',
                right: Text('On', style: TextStyle(fontSize: 14, color: c.success)),
              ),
              if (ch != null && ch != ChannelState.ok)
                SRow(
                  icon: Icons.report_outlined,
                  label: ch == ChannelState.blocked
                      ? 'The Alerts channel is switched off'
                      : ch == ChannelState.quiet
                          ? 'Alerts are set to silent'
                          : 'The Alerts channel is not set up',
                  sub: ch == ChannelState.missing
                      ? 'Turn notifications off and on again, or reopen the app.'
                      : 'In Android Settings: Apps, Escanor, Notifications, Alerts. Turn it on and set it to make sound or pop up.',
                ),
              SRow(icon: Icons.send_outlined, label: 'Send a test notification', onTap: _test, disabled: _busy, chevron: false),
            ] else if (state == PushState.denied)
              SRow(
                icon: Icons.smartphone_rounded,
                label: 'Notifications are blocked',
                right: Text('Blocked', style: TextStyle(fontSize: 14, color: c.error)),
              )
            else
              SRow(
                icon: Icons.smartphone_rounded,
                label: 'Turn on notifications',
                sub: phoneSettings == 'iPhone Settings' ? 'Your iPhone will ask for your permission' : 'Android will ask for your permission',
                onTap: _turnOn,
                disabled: _busy,
              ),
          ]),
          if (_result != null) ...[const SizedBox(height: 12), Notice(_result!.text, tone: _result!.ok ? NoticeTone.info : NoticeTone.warn)],
        ]);
      },
    );
  }
}
