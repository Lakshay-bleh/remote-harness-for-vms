import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/load.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../settings/info_pages.dart' show showLegalSheet;
import '../settings/legal_content.dart' show policyVersion;
import 'account_api.dart';
import 'policy.dart';

/// The rules, in short: shown with the Terms and once every three months.
const policyRules = [
  'Use Escanor only on systems and content you are allowed to use, and follow the Acceptable use policy.',
  'If you break the rules or the law, we may remove content and suspend or close your account.',
  'You are responsible under the law for what you store, share or create, including with the AI features.',
  'We report offences to the authorities where the law requires it.',
];

/// Terms and Privacy acceptance at the current version, and the reminder of the rules every three months. Fails open: when the
/// consents cannot be read, nothing is shown. Placed as a direct child of the shell's Stack (shown when no deletion is scheduled).
class PolicyGate extends StatefulWidget {
  const PolicyGate({super.key});
  @override
  State<PolicyGate> createState() => _PolicyGateState();
}

class _PolicyGateState extends State<PolicyGate> {
  final _consents = Loader<List<ConsentState>?>(
    () => fetchConsents().then<List<ConsentState>?>((l) => [for (final j in l) ConsentState.fromJson(j)]).catchError((_) => null),
  );
  late final _terms = TapGestureRecognizer()..onTap = () => showLegalSheet(context, start: 'terms');
  late final _privacy = TapGestureRecognizer()..onTap = () => showLegalSheet(context, start: 'privacy');
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _consents.dispose();
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  Future<void> _record(List<String> purposes) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final p in purposes) {
        await recordConsent(p, true, policyVersion);
      }
      _consents.reload();
    } catch (_) {
      if (mounted) setState(() => _error = 'We could not save that. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _consents,
      builder: (context, _) {
        final states = _consents.data;
        if (states == null) return const SizedBox.shrink();
        final mustAccept = needsAcceptance(states, policyVersion);
        if (!mustAccept && !needsRulesNotice(states)) return const SizedBox.shrink();
        final c = context.c;
        final title = mustAccept ? 'Terms and privacy' : 'A reminder of our rules';
        final body = TextStyle(fontSize: 14, height: 1.5, color: c.body);
        final link = TextStyle(decoration: TextDecoration.underline, decorationColor: c.body);
        return Positioned.fill(
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            label: title,
            child: Material(
              color: Colors.black.withValues(alpha: 0.5),
              child: SafeArea(
                child: Align(
                  alignment: MediaQuery.sizeOf(context).width >= 640 ? Alignment.center : Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 448, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
                      child: Container(
                        decoration: BoxDecoration(
                          color: c.surfaceCard,
                          border: Border.all(color: c.hairline),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                            Text(title, style: TextStyle(fontSize: 20, color: c.ink, fontWeight: FontWeight.w500)),
                            if (mustAccept) ...[
                              const SizedBox(height: 16),
                              Text.rich(
                                TextSpan(style: body, children: [
                                  const TextSpan(text: 'Please read the '),
                                  TextSpan(text: 'Terms of service', style: link, recognizer: _terms),
                                  const TextSpan(text: ' and the '),
                                  TextSpan(text: 'Privacy policy', style: link, recognizer: _privacy),
                                  const TextSpan(text: '. In short:'),
                                ]),
                              ),
                            ],
                            const SizedBox(height: 12),
                            for (final r in policyRules)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('• $r', style: TextStyle(fontSize: 14, height: 1.5, color: c.bodyStrong)),
                              ),
                            if (mustAccept) ...[
                              const SizedBox(height: 10),
                              InkWell(
                                onTap: () => setState(() => _agreed = !_agreed),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: _agreed,
                                      onChanged: (v) => setState(() => _agreed = v ?? false),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text('I am 18 or older, and I agree to the Terms of service and the Privacy policy.',
                                        style: TextStyle(fontSize: 14, height: 1.5, color: c.ink)),
                                  ),
                                ]),
                              ),
                            ],
                            if (_error != null) ...[const SizedBox(height: 16), Notice(_error!, tone: NoticeTone.error)],
                            const SizedBox(height: 16),
                            EButton(
                              label: mustAccept ? 'Agree and continue' : 'Got it',
                              expand: true,
                              onPressed: _busy || (mustAccept && !_agreed)
                                  ? null
                                  : () => _record(mustAccept ? const ['terms', 'privacy_notice', 'rules_notice'] : const ['rules_notice']),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
