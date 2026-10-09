import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/load.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../settings/settings_widgets.dart';
import 'account_api.dart';
import 'delete_account_page.dart';
import 'export_share.dart';
import 'security.dart';

/// Asks for a code from the authenticator app (or a backup code) and hands back what to send. [onSubmit] closes the sheet itself
/// (or opens the next step); an error it throws is shown here.
Future<void> showCodeSheet(BuildContext context,
        {required String title, required String body, required String action, required Future<void> Function(String code, NavigatorState sheet) onSubmit}) =>
    showESheet<void>(context, title: title, builder: (_) => CodeForm(body: body, action: action, onSubmit: onSubmit));

class CodeForm extends StatefulWidget {
  const CodeForm({super.key, required this.body, required this.action, required this.onSubmit});
  final String body;
  final String action;
  final Future<void> Function(String code, NavigatorState sheet) onSubmit;
  @override
  State<CodeForm> createState() => _CodeFormState();
}

class _CodeFormState extends State<CodeForm> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = parseCodeInput(_text.text);
    if (code == null) return setState(() => _error = 'Enter the 6 digits from your authenticator app, or a backup code like ABCD-EFGH.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(code, Navigator.of(context));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, 'That did not work.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(widget.body, style: TextStyle(fontSize: 14, color: c.body)),
      if (_error != null) ...[const SizedBox(height: 12), Notice(_error!, tone: NoticeTone.error)],
      const SizedBox(height: 12),
      LabeledField(
        label: 'Code',
        controller: _text,
        hint: '123 456',
        mono: true,
        autofocus: true,
        autocorrect: false,
        capitalization: TextCapitalization.characters,
        autofillHints: const [AutofillHints.oneTimeCode],
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 12),
      EButton(label: _busy ? 'Checking…' : widget.action, expand: true, onPressed: _busy || _text.text.trim().isEmpty ? null : _submit),
    ]);
  }
}

/// The backup codes, shown once.
Future<void> showBackupCodes(BuildContext context, List<String> codes) =>
    showESheet<void>(context, title: 'Your backup codes', builder: (_) => _BackupCodes(codes: codes));

class _BackupCodes extends StatefulWidget {
  const _BackupCodes({required this.codes});
  final List<String> codes;
  @override
  State<_BackupCodes> createState() => _BackupCodesState();
}

class _BackupCodesState extends State<_BackupCodes> {
  String? _note;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = backupCodesText(widget.codes);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Notice('Save these now. They are shown once. Each one signs you through once if you lose your phone.', tone: NoticeTone.warn),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.code, borderRadius: BorderRadius.circular(Radii.md)),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 5,
          children: [for (final code in widget.codes) SelectableText(code, style: TextStyle(fontFamily: monoFamily, fontSize: 15, color: c.onCode))],
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: EButton(
            label: 'Copy',
            icon: Icons.copy_rounded,
            kind: ButtonKind.quiet,
            expand: true,
            onPressed: () async {
              final ok = await copyText(text);
              if (mounted) setState(() => _note = ok ? 'Copied.' : 'Could not copy.');
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: EButton(
            label: 'Save or send',
            kind: ButtonKind.quiet,
            expand: true,
            onPressed: () async {
              try {
                await shareExport(text, name: 'escanor-backup-codes.txt', title: 'Escanor backup codes', mime: 'text/plain');
              } catch (_) {
                if (mounted) setState(() => _note = 'Could not share.');
              }
            },
          ),
        ),
      ]),
      if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!, style: TextStyle(fontSize: 12, color: c.muted))),
      const SizedBox(height: 12),
      EButton(label: 'I have saved them', expand: true, onPressed: () => Navigator.of(context).pop()),
    ]);
  }
}

/// Turning two-step verification on: scan the code or type the key, then confirm a code. [onEnabled] gets the backup codes.
class _Setup extends StatefulWidget {
  const _Setup({required this.onEnabled});
  final void Function(List<String> codes) onEnabled;
  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  ({String secret, String otpauthUri})? _setup;
  String? _error;
  bool _copied = false;
  bool _verify = false;

  @override
  void initState() {
    super.initState();
    twoFactorSetup().then((s) {
      if (mounted) setState(() => _setup = s);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = errorText(e, 'Could not start the setup.'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = _setup;
    if (_verify && s != null) {
      return CodeForm(
        body: 'Enter the 6 digits your authenticator app shows for Escanor now.',
        action: 'Turn on',
        onSubmit: (code, sheet) async {
          final codes = await twoFactorEnable(code);
          sheet.pop();
          widget.onEnabled(codes);
        },
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (_error != null) Notice(_error!, tone: NoticeTone.error),
      if (s == null && _error == null) const BlockSpinner(),
      if (s != null) ...[
        Text(
          '1. Open an authenticator app (Google Authenticator, Microsoft Authenticator, 1Password, Aegis…).\n2. Add an account: scan this code, or type the key.',
          style: TextStyle(fontSize: 14, height: 1.5, color: c.body),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Radii.lg)),
            child: Semantics(
              label: 'Setup QR code',
              image: true,
              child: QrImageView(
                data: s.otpauthUri,
                size: 208,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                padding: const EdgeInsets.all(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        EButton(
          label: 'Open in my authenticator app',
          kind: ButtonKind.quiet,
          expand: true,
          onPressed: () async {
            var opened = false;
            try {
              opened = await launchUrl(Uri.parse(s.otpauthUri), mode: LaunchMode.externalApplication);
            } catch (_) {}
            if (!opened && context.mounted) toast(context, 'No authenticator app on this phone opens setup links. Scan the code or type the key.');
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.surfaceCard, borderRadius: BorderRadius.circular(Radii.md)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Setup key', style: TextStyle(fontSize: 12, color: c.muted)),
            SelectableText(groupKey(s.secret), style: TextStyle(fontFamily: monoFamily, fontSize: 14, color: c.ink)),
            GestureDetector(
              onTap: () async {
                if (await copyText(s.secret) && mounted) setState(() => _copied = true);
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_copied ? 'Copied' : 'Copy key', style: TextStyle(fontSize: 12, color: c.primary)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        EButton(label: 'I added it: enter the code', expand: true, onPressed: () => setState(() => _verify = true)),
      ],
    ]);
  }
}

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});
  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  final _status = Loader<TwoFactorStatus>(fetchTwoFactor);

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  void _setup() {
    showESheet<void>(context, title: 'Turn on two-step verification', builder: (_) => _Setup(onEnabled: (codes) {
      _status.reload();
      if (mounted) showBackupCodes(context, codes);
    }));
  }

  void _disable() => showCodeSheet(
        context,
        title: 'Turn off two-step verification',
        body: 'Enter a code from your authenticator app, or a backup code, to turn it off.',
        action: 'Turn off',
        onSubmit: (code, sheet) async {
          await twoFactorDisable(code);
          sheet.pop();
          _status.reload();
        },
      );

  void _codes() => showCodeSheet(
        context,
        title: 'New backup codes',
        body: 'Enter a code from your authenticator app. You get 8 new backup codes and the old ones stop working.',
        action: 'Get new codes',
        onSubmit: (code, sheet) async {
          final codes = await twoFactorBackupCodes(code);
          sheet.pop();
          _status.reload();
          if (mounted) showBackupCodes(context, codes);
        },
      );

  Future<void> _delete() async {
    await pushPage(context, const DeleteAccountPage());
    _status.reload(); // they may have turned two-step verification on from there
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _status,
      builder: (context, _) {
        final s = _status.data;
        return SettingsPage(title: 'Security', subtitle: 'Two-step verification and your account', children: [
          if (_status.error != null && s == null) Notice(_status.error!, tone: NoticeTone.error),
          if (_status.loading && s == null) const BlockSpinner(padding: 32),
          if (s != null)
            Group(
              title: 'Two-step verification',
              footer: s.enabled
                  ? 'A code from your authenticator app is needed to delete your account and to change these settings.'
                  : 'Adds a code from an authenticator app as a second check. It is required to delete your account.',
              children: s.enabled
                  ? [
                      SRow(icon: Icons.verified_user_outlined, label: 'On', sub: s.enrolledAt != null ? 'Since ${shortDate(s.enrolledAt)}' : null),
                      SRow(
                        icon: Icons.key_rounded,
                        label: 'Backup codes',
                        value: '${s.backupCodesLeft} left',
                        sub: 'Get a fresh set (the old ones stop working)',
                        onTap: _codes,
                      ),
                      SRow(icon: Icons.smartphone_rounded, label: 'Turn off', danger: true, onTap: _disable),
                    ]
                  : [SRow(icon: Icons.verified_user_outlined, label: 'Turn on', sub: 'Authenticator app', onTap: _setup)],
            ),
          Group(
            title: 'Danger zone',
            footer: 'Deleting your account is scheduled for 7 days, and you can cancel in that time.',
            children: [SRow(icon: Icons.delete_outline_rounded, label: 'Delete account', danger: true, onTap: _delete)],
          ),
        ]);
      },
    );
  }
}
