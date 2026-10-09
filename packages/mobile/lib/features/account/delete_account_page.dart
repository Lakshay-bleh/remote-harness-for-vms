import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/load.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../settings/settings_widgets.dart';
import 'account_api.dart';
import 'security.dart';

/// Delete the account: confirmed with the account email (and a code when two-step verification is on), scheduled for a week so it
/// can be taken back.
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});
  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  final _status = Loader<DeletionStatus>(fetchDeletionStatus);
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _status.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final needsCode = _status.data?.twoFactorEnabled == true;
    final parsed = parseCodeInput(_code.text);
    if (needsCode && parsed == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await requestDeletion(needsCode ? parsed : null, _email.text.trim());
      if (!mounted) return;
      setState(() => _busy = false);
      await _scheduled(done);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, 'That did not work. Nothing was changed.');
          _busy = false;
        });
      }
    }
  }

  /// Done: say when, then sign out (the server already signed this account out everywhere).
  Future<void> _scheduled(DeletionStatus done) async {
    final session = ref.read(sessionProvider.notifier);
    final when = done.scheduledFor == null ? null : DateTime.tryParse(done.scheduledFor!);
    await showESheet<void>(context, title: 'Deletion scheduled', builder: (ctx) {
      final c = ctx.c;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('Your account will be deleted ${when != null ? 'on ${shortDate(done.scheduledFor)}' : 'in 7 days'}. You have been signed out everywhere.',
            style: TextStyle(fontSize: 14, height: 1.5, color: c.body)),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Changed your mind? Sign in again before then and choose to keep your account. Reference: '),
            TextSpan(text: done.reference ?? '', style: TextStyle(fontFamily: monoFamily, color: c.ink, fontWeight: FontWeight.w600)),
          ]),
          style: TextStyle(fontSize: 14, height: 1.5, color: c.body),
        ),
        const SizedBox(height: 16),
        EButton(label: 'OK', expand: true, onPressed: () => Navigator.of(ctx).pop()),
      ]);
    });
    await session.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user;
    return ListenableBuilder(
      listenable: _status,
      builder: (context, _) {
        final c = context.c;
        final s = _status.data;
        final needsCode = s?.twoFactorEnabled == true;
        final ready = emailConfirmed(_email.text, user?.email) && (!needsCode || parseCodeInput(_code.text) != null);
        return SettingsPage(title: 'Delete account', children: [
          if (_status.loading && s == null) const BlockSpinner(padding: 32),
          if (_status.error != null && s == null) Notice(_status.error!, tone: NoticeTone.error),
          if (s != null && s.scheduled)
            Notice(
              'Your account is already scheduled for deletion ${s.scheduledFor != null ? daysUntil(s.scheduledFor!) : ''}. You can cancel it when you open the app.',
              tone: NoticeTone.warn,
            ),
          if (s != null && !s.scheduled) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.error.withValues(alpha: 0.05),
                border: Border.all(color: c.error.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.warning_rounded, size: 20, color: c.error),
                  const SizedBox(width: 8),
                  Text('What happens', style: TextStyle(fontSize: 18, color: c.error, fontWeight: FontWeight.w500)),
                ]),
                for (final f in deletionFacts)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('• $f', style: TextStyle(fontSize: 13.5, height: 1.5, color: c.bodyStrong)),
                  ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_error != null) ...[Notice(_error!, tone: NoticeTone.error), const SizedBox(height: 12)],
              LabeledField(
                label: 'Type your email to confirm (${user?.email ?? ''})',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (ready && !_busy) _submit();
                },
              ),
              if (needsCode) ...[
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Code from your authenticator app (or a backup code)',
                  controller: _code,
                  hint: '123 456',
                  mono: true,
                  autocorrect: false,
                  capitalization: TextCapitalization.characters,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (ready && !_busy) _submit();
                  },
                ),
              ],
              const SizedBox(height: 12),
              EButton(
                label: _busy ? 'Scheduling…' : 'Delete my account',
                kind: ButtonKind.danger,
                expand: true,
                onPressed: ready && !_busy ? _submit : null,
              ),
            ]),
          ],
        ]);
      },
    );
  }
}
