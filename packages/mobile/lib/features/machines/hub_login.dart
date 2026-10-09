import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/parts.dart' show pushPage;
import '../../ui/widgets.dart';
import '../settings/info_pages.dart' show LegalDocPage;
import 'hub_scope.dart';
import 'hub_store.dart';

/// Opens one of Escanor's notices (privacy, terms, support). The lead can point this at the app's own legal sheet;
/// by default the page opens on the website.
void Function(BuildContext context, String doc)? openLegalDoc;

/// Sign in to a hub you host yourself (Login.tsx). The same frame as the Escanor sign-in, so the two never feel
/// like different apps.
class HubLogin extends StatefulWidget {
  const HubLogin({super.key, this.onBack});

  /// "Back to Escanor", when this is the stand-alone hub.
  final VoidCallback? onBack;

  @override
  State<HubLogin> createState() => _HubLoginState();
}

class _HubLoginState extends State<HubLogin> {
  late final _hubUrl = TextEditingController(text: HubStore.instance.api.credentials.hubUrl);
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _hubUrl.addListener(() => setState(() {}));
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _hubUrl.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _password.text.isEmpty || _hubUrl.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = _hubUrl.text.trim();
      if (!RegExp(r'^https?://').hasMatch(url)) throw StateError('Hub URL must start with https://');
      final store = HubStore.instance;
      store.api.credentials.hubUrl = url; // throws when it is not https
      await store.login(_password.text);
    } catch (e) {
      final s = e is StateError ? e.message : e.toString();
      if (mounted) setState(() => _error = s.isEmpty ? 'Login failed' : s);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final embedded = HubScope.embeddedOf(context);
    final label = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.ink);
    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Your hub', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: c.ink)),
          const SizedBox(height: 6),
          Text('Sign in to the hub you run yourself.', style: TextStyle(fontSize: 14, height: 1.45, color: c.body)),
          const SizedBox(height: 24),
          Text('Hub URL', style: label),
          const SizedBox(height: 6),
          TextField(
            controller: _hubUrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.url],
            decoration: const InputDecoration(hintText: 'https://hub.example.com'),
          ),
          const SizedBox(height: 16),
          Text('Password', style: label),
          const SizedBox(height: 6),
          TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.go,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[const SizedBox(height: 16), Notice(_error!, tone: NoticeTone.error)],
          const SizedBox(height: 16),
          EButton(
            label: _busy ? 'Signing in…' : 'Sign in',
            expand: true,
            onPressed: _busy || _password.text.isEmpty || _hubUrl.text.isEmpty ? null : _submit,
          ),
          // Inside the signed-in app the notices live in Settings; only a stand-alone sign-in carries them.
          if (!embedded) const _LegalLinks(),
        ]),
      ),
    );
    return Material(
      color: c.canvas,
      child: Stack(children: [
        LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 64),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (widget.onBack != null) const SizedBox(height: 40),
                const Logo(size: 36),
                const SizedBox(height: 32),
                Center(child: form),
              ]),
            ),
          ),
        ),
        if (widget.onBack != null)
          Positioned(
            left: 8,
            top: 8,
            child: TextButton(onPressed: widget.onBack, child: Text('← Back to Escanor', style: TextStyle(fontSize: 14, color: c.muted))),
          ),
      ]),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  void _open(BuildContext context, String doc) {
    final hook = openLegalDoc;
    if (hook != null) return hook(context, doc);
    pushPage(context, LegalDocPage(docKey: doc));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final link = TextStyle(fontSize: 12, color: c.muted, decoration: TextDecoration.underline, decorationColor: c.muted);
    Widget a(String label, String doc) => InkWell(onTap: () => _open(context, doc), child: Text(label, style: link));
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 4, children: [a('Escanor privacy', 'privacy'), a('Terms', 'terms'), a('Support', 'support')]),
        const SizedBox(height: 8),
        Text('For a self-hosted hub, ask its operator about access, storage and deletion of your session data.',
            style: TextStyle(fontSize: 12, height: 1.45, color: c.muted)),
      ]),
    );
  }
}
