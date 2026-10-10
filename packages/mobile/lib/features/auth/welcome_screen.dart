import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'auth_shell.dart';
import 'email_auth.dart';

/// The email-only sign-in exists for developing against a local backend: only a debug build that points at another API shows
/// it (the production backend refuses it, as it must: it signs in as any address without a password).
const _devApi = String.fromEnvironment('ESCANOR_API');
bool get showDevLogin => kDebugMode && _devApi.isNotEmpty;

/// Signed out: sign in with email or Google, or go to your own Remote Harness hub.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, required this.onAdvanced});
  final VoidCallback onAdvanced;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _emailBusy = false;
  final _devEmail = TextEditingController();
  String? _devError;
  bool _devBusy = false;

  @override
  void dispose() {
    _devEmail.dispose();
    super.dispose();
  }

  Future<void> _dev() async {
    setState(() {
      _devError = null;
      _devBusy = true;
    });
    try {
      await ref.read(sessionProvider.notifier).devLogin(_devEmail.text.trim());
    } catch (e) {
      if (mounted) setState(() => _devError = errorText(e, 'Dev sign-in failed.'));
    } finally {
      if (mounted) setState(() => _devBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final session = ref.watch(sessionProvider);
    final notifier = ref.read(sessionProvider.notifier);
    final busy = session.busy;

    return AuthShell(
      title: 'Welcome to Escanor',
      subtitle: 'Sign in once. Your assistant, its machine and your hub are set up for you.',
      footer: TextButton(
        onPressed: widget.onAdvanced,
        child: Text('I run my own Remote Harness hub', style: TextStyle(fontSize: 13, color: c.muted)),
      ),
      children: [
        if (session.error != null) Notice(session.error!, tone: NoticeTone.error),
        EmailAuth(
          begin: notifier.beginEmailSignIn,
          onCode: notifier.finishSignIn,
          onBusy: (b) {
            if (mounted && b != _emailBusy) setState(() => _emailBusy = b);
          },
        ),
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Divider(height: 1, color: c.hairline)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(fontSize: 12, color: c.muted))),
              Expanded(child: Divider(height: 1, color: c.hairline)),
            ]),
          ),
        ),
        _GoogleButton(busy: busy, onPressed: busy || _emailBusy ? null : notifier.signInWithGoogle),
        if (showDevLogin)
          Row(children: [
            Expanded(
              child: TextField(
                controller: _devEmail,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                onSubmitted: (_) => _dev(),
                style: TextStyle(fontSize: 14, color: c.ink),
                decoration: const InputDecoration(hintText: 'dev email'),
              ),
            ),
            const SizedBox(width: 8),
            EButton(label: 'Dev', busy: _devBusy, onPressed: _dev),
          ]),
        if (showDevLogin && _devError != null) Notice(_devError!, tone: NoticeTone.error),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: c.lineStrong)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (!busy) ...[const GoogleIcon(), const SizedBox(width: 10)],
              Text(busy ? 'Opening Google…' : 'Continue with Google', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.ink)),
            ]),
          ),
        ),
      ),
    );
  }
}
