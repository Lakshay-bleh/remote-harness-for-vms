import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'cloud.dart';
import 'pairing.dart';
import 'protocol/client.dart';
import 'protocol/failure.dart';
import 'protocol/lan_pair.dart';
import 'qr_scan.dart';

/// What this phone calls itself on the computer's list of paired phones.
String phoneDeviceName() => Platform.isAndroid ? 'Android phone' : (Platform.isIOS ? 'iPhone' : 'Phone');

/// Pair with a computer. [onPaired] runs once it is paired (even if the sheet was closed meanwhile: a pairing that completes is
/// never lost); the sheet then closes itself.
Future<void> showPairSheet(BuildContext context, {required void Function(PairedComputer c) onPaired, CloudDirectory? cloud}) => showESheet<void>(
  context,
  title: 'Add your computer',
  builder: (_) => PairSheet(onPaired: onPaired, cloud: cloud),
);

enum _Way { code, scan, wifi }

/// By default with just the code it shows: that works from anywhere there is internet, with no address and no shared Wi-Fi.
/// Scanning its QR is the same thing without typing. Pairing over the local network is the quiet alternative.
class PairSheet extends StatefulWidget {
  const PairSheet({super.key, required this.onPaired, this.cloud});
  final void Function(PairedComputer c) onPaired;

  /// The signed-in app's own backend (tests give another).
  final CloudDirectory? cloud;

  @override
  State<PairSheet> createState() => _PairSheetState();
}

class _PairSheetState extends State<PairSheet> {
  _Way _way = _Way.code;
  final _code = TextEditingController();
  final _address = TextEditingController();
  bool _busy = false;

  /// While pairing on Wi-Fi: the number to compare with the one on the computer.
  String? _confirm;
  CancelToken? _cancel;
  String? _error;
  final _deviceName = phoneDeviceName();

  CloudDirectory get _cloud => widget.cloud ?? ApiCloudDirectory();

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    _address.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cancel?.cancel(); // the person left: stop waiting on the computer
    _code.dispose();
    _address.dispose();
    super.dispose();
  }

  void _done(PairedComputer paired) {
    haptic();
    widget.onPaired(paired);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _pair(PairEntry entry, PairMode mode, [String? lanAddress]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final paired = await pairComputer(entry, _deviceName, PairOptions(mode: mode, cloud: _cloud, lanAddress: lanAddress));
      _done(paired);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ComputerError || e is Exception ? failureText(e) : 'Pairing did not work.';
        _busy = false;
        if (_way == _Way.scan) _way = _Way.code; // after a failed scan, land on the typing form with the error visible
      });
    }
  }

  void _scanned(String text) {
    final entry = parseEntry(text);
    setState(() => _way = _Way.code); // out of the scan screen first: pairing then shows its own progress
    if (entry != null) {
      _pair(entry, PairMode.cloud);
    } else {
      setState(() => _error = 'That is not an Escanor pairing code.');
    }
  }

  void _submit() {
    final entry = parseEntry(_code.text);
    if (entry == null) {
      setState(() => _error = 'That is not a valid pairing code. It looks like ABCD-EFGH-IJKL-… (letters and the digits 2 to 7).');
      return;
    }
    _pair(entry, PairMode.cloud);
  }

  /// Same Wi-Fi: only the address. The computer asks its owner to approve, so no code is typed.
  Future<void> _pairWifi() async {
    final cancel = _cancel = CancelToken();
    setState(() {
      _busy = true;
      _error = null;
      _confirm = null;
    });
    try {
      final paired = await pairOnWifi(
        _address.text,
        _deviceName,
        LanAskOptions(cancel: cancel, onConfirm: (n) => mounted ? setState(() => _confirm = n) : null),
      );
      _done(paired);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = cancel.cancelled ? null : failureText(e);
        _busy = false;
        _confirm = null;
      });
    }
  }

  void _cancelWifi() {
    _cancel?.cancel();
    setState(() {
      _busy = false;
      _confirm = null;
    });
  }

  void _go(_Way w) => setState(() {
    _error = null;
    _way = w;
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final body = TextStyle(fontSize: 14, height: 1.45, color: c.body);
    final bold = body.copyWith(fontWeight: FontWeight.w600, color: c.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            style: body,
            children: [
              const TextSpan(text: 'On your computer, open '),
              TextSpan(text: 'Escanor Desktop', style: bold),
              const TextSpan(text: ', go to '),
              TextSpan(text: 'Phone', style: bold),
              const TextSpan(text: ' and choose '),
              TextSpan(text: 'Pair a phone', style: bold),
              const TextSpan(text: '. Then enter the code it shows. Both devices need to be signed in to the same Escanor account.'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[Notice(_error!, tone: NoticeTone.error), const SizedBox(height: 12)],
        if (_busy)
          _way == _Way.wifi ? _wifiWaiting(c) : _progress(c, 'Finding your computer and pairing…')
        else if (_way == _Way.scan) ...[
          QrScan(onCode: _scanned),
          const SizedBox(height: 8),
          EButton(label: 'Type the code instead', kind: ButtonKind.quiet, expand: true, onPressed: () => _go(_Way.code)),
        ] else
          _form(c),
      ],
    );
  }

  Widget _progress(EscanorColors c, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Row(
      children: [
        const Spinner(size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 14, color: c.muted)),
        ),
      ],
    ),
  );

  Widget _wifiWaiting(EscanorColors c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_confirm != null) ...[
          Text(
            'On your computer, Escanor Desktop is asking you to approve this phone. Approve it only if it shows this number:',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.45, color: c.body),
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _confirm!,
              style: TextStyle(fontFamily: monoFamily, fontSize: 36, fontWeight: FontWeight.w600, letterSpacing: 6, color: c.ink),
            ),
          ),
        ] else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spinner(size: 32),
              const SizedBox(width: 12),
              Text('Reaching your computer…', style: TextStyle(fontSize: 14, color: c.muted)),
            ],
          ),
        const SizedBox(height: 12),
        Text('Waiting for you to approve it on the computer…', style: TextStyle(fontSize: 12, color: c.muted)),
        const SizedBox(height: 12),
        EButton(label: 'Cancel', kind: ButtonKind.quiet, expand: true, onPressed: _cancelWifi),
      ],
    ),
  );

  Widget _form(EscanorColors c) {
    final wifi = _way == _Way.wifi;
    final field = TextStyle(fontFamily: monoFamily, fontSize: 15, color: c.ink);
    final canSubmit = wifi ? _address.text.trim().isNotEmpty : _code.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(wifi ? 'Computer address' : 'Pairing code', style: TextStyle(fontSize: 14, color: c.body)),
        const SizedBox(height: 4),
        if (wifi) ...[
          TextField(
            key: const ValueKey('address'),
            controller: _address,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => canSubmit ? _pairWifi() : null,
            decoration: const InputDecoration(hintText: '192.168.1.20'),
            style: field,
          ),
          const SizedBox(height: 4),
          Text(
            'Shown on the Phone screen of Escanor Desktop, with “On this network” switched on. Your phone must be on the same Wi-Fi. No code is needed: you approve the request on the computer.',
            style: TextStyle(fontSize: 12, height: 1.4, color: c.muted),
          ),
        ] else
          TextField(
            key: const ValueKey('code'),
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword, // no suggestions, no learning: this is a one-time secret
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => canSubmit ? _submit() : null,
            decoration: const InputDecoration(hintText: 'ABCD-EFGH-IJKL-…'),
            style: field,
          ),
        const SizedBox(height: 12),
        EButton(label: wifi ? 'Ask to pair' : 'Pair', expand: true, onPressed: canSubmit ? (wifi ? _pairWifi : _submit) : null),
        const SizedBox(height: 8),
        if (!wifi)
          EButton(label: 'Scan the QR code instead', icon: Icons.photo_camera_outlined, kind: ButtonKind.quiet, expand: true, onPressed: () => _go(_Way.scan)),
        Center(
          child: TextButton.icon(
            onPressed: () => _go(wifi ? _Way.code : _Way.wifi),
            icon: wifi ? const SizedBox.shrink() : Icon(Icons.wifi_rounded, size: 16, color: c.muted),
            label: Text(
              wifi ? 'Back to pairing from anywhere' : 'On the same Wi-Fi? Pair with just its address',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
        ),
      ],
    );
  }
}
