import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'email_auth_api.dart';

enum _Step { signin, signup, verify, forgot, reset }

const _meterLabel = ['', 'Weak', 'Fair', 'Good', 'Strong'];

/// Email and password in the app: sign in, create an account (a six-digit code mailed to the address proves it), reset a
/// forgotten password. [begin] binds this attempt to this app (PKCE) and returns the challenge; [onCode] gets the finished
/// sign-in's one-time code, which the session trades for tokens exactly as it does after Google.
class EmailAuth extends StatefulWidget {
  const EmailAuth({super.key, required this.begin, required this.onCode, this.onBusy, this.authApi});
  final String? Function() begin;
  final void Function(String code) onCode;
  final void Function(bool busy)? onBusy;

  /// For tests; defaults to Escanor's own server.
  final EmailAuthApi? authApi;

  @override
  State<EmailAuth> createState() => _EmailAuthState();
}

class _EmailAuthState extends State<EmailAuth> {
  late final EmailAuthApi _api = widget.authApi ?? EmailAuthApi(escanorApiBase());
  bool? _available;
  _Step _step = _Step.signin;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _code = '';
  bool _show = false;
  bool _busy = false;
  String? _error;
  String? _notice;
  int _wait = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
    _api.available().then((ok) {
      if (mounted) setState(() => _available = ok);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _setWait(int seconds) {
    _tick?.cancel();
    setState(() => _wait = seconds);
    if (seconds <= 0) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait <= 0) t.cancel();
    });
  }

  void _go(_Step to) => setState(() {
        _step = to;
        _error = null;
        _notice = null;
        _code = '';
      });

  void _setBusy(bool b) {
    setState(() => _busy = b);
    widget.onBusy?.call(b);
  }

  Future<void> _run(Future<void> Function() job) async {
    FocusManager.instance.primaryFocus?.unfocus();
    _setBusy(true);
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      await job();
    } on EmailAuthError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.code == 'cooldown' && e.retryAfter != null) _setWait(e.retryAfter!);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  AuthFlow _flow() => AuthFlow(redirectUri: mobileLoginRedirect, platform: 'mobile', challenge: widget.begin());

  void _sent(CodeSent result, [String? message]) {
    _setWait(result.resendAfter);
    setState(() => _notice = result.devCode != null ? 'Email is not configured on this server. Development code: ${result.devCode}' : message);
  }

  void _need(bool ok, String message, [String code = 'invalid']) {
    if (!ok) throw EmailAuthError(message, code, 400, null);
  }

  String get _mail => _email.text.trim();

  void _finished(Finished f) {
    TextInput.finishAutofillContext();
    widget.onCode(f.code);
  }

  Future<void> _submitSignIn() => _run(() async {
        _need(isEmail(_email.text), 'Enter a valid email address.');
        _finished(await _api.login(email: _mail, password: _password.text, flow: _flow()));
      });

  Future<void> _submitSignUp() => _run(() async {
        _need(isEmail(_email.text), 'Enter a valid email address.');
        final problem = passwordProblem(_password.text, _email.text);
        _need(problem == null, problem ?? '', 'weak_password');
        final result = await _api.register(email: _mail, password: _password.text, name: _name.text.trim(), flow: _flow());
        if (!mounted) return;
        setState(() => _step = _Step.verify);
        _sent(result);
      });

  Future<void> _submitVerify(String digits) => _run(() async {
        _finished(await _api.verify(email: _mail, code: digits));
      });

  Future<void> _submitForgot() => _run(() async {
        _need(isEmail(_email.text), 'Enter a valid email address.');
        final result = await _api.forgot(_mail);
        if (!mounted) return;
        setState(() => _step = _Step.reset);
        _sent(result);
      });

  Future<void> _submitReset() => _run(() async {
        final problem = passwordProblem(_password.text, _email.text);
        _need(problem == null, problem ?? '', 'weak_password');
        _need(_code.length == codeLength, 'Enter the six-digit code from the email.', 'bad_code');
        _finished(await _api.reset(email: _mail, code: _code, password: _password.text, flow: _flow()));
      });

  Future<void> _resend() => _run(() async {
        final r = _step == _Step.reset ? await _api.forgot(_mail) : await _api.resend(_mail);
        if (mounted) _sent(r, 'A new code is on its way.');
      });

  // ---------------------------------------------------------------------------- pieces

  Widget _labelled(String label, Widget child) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label, style: TextStyle(fontSize: 13, color: c.body))),
      child,
    ]);
  }

  InputDecoration _decoration(String hint, {Widget? suffix}) => InputDecoration(hintText: hint, suffixIcon: suffix);

  Widget _emailField({required TextInputAction action, VoidCallback? onDone}) => _labelled(
        'Email',
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: action,
          autofillHints: const [AutofillHints.email],
          onSubmitted: onDone == null ? null : (_) => onDone(),
          style: TextStyle(fontSize: 15, color: context.c.ink),
          decoration: _decoration('you@example.com'),
        ),
      );

  Widget _passwordField(String label, {required bool meter, required bool newPassword, required VoidCallback onDone}) {
    final c = context.c;
    final strength = passwordStrength(_password.text);
    final colors = [c.hairline, c.error, c.warning, c.primary.withValues(alpha: 0.7), c.primary];
    return _labelled(
      label,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _password,
          obscureText: !_show,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          autofillHints: [newPassword ? AutofillHints.newPassword : AutofillHints.password],
          onSubmitted: (_) => onDone(),
          style: TextStyle(fontSize: 15, color: c.ink),
          decoration: _decoration(
            meter ? 'At least 8 characters' : 'Your password',
            suffix: IconButton(
              tooltip: _show ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _show = !_show),
              icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: c.muted),
            ),
          ),
        ),
        if (meter && _password.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              label: _meterLabel[strength],
              child: Row(children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Row(children: [
                      for (var n = 1; n <= 4; n++) ...[
                        if (n > 1) const SizedBox(width: 4),
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            height: 4,
                            decoration: BoxDecoration(color: strength >= n ? colors[strength] : c.hairline, borderRadius: BorderRadius.circular(Radii.pill)),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: ExcludeSemantics(child: Text(_meterLabel[strength], textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: c.muted))),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  List<Widget> _banner() => [
        if (_error != null) Notice(_error!, tone: NoticeTone.error),
        if (_notice != null) Notice(_notice!),
      ];

  Widget _back(_Step to, String text) {
    final c = context.c;
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => _go(to),
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chevron_left_rounded, size: 18, color: c.muted),
            Text(text, style: TextStyle(fontSize: 13, color: c.muted)),
          ]),
        ),
      ),
    );
  }

  List<Widget> _spaced(List<Widget> items, [double gap = 12]) => [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(height: gap), items[i]],
      ];

  // ---------------------------------------------------------------------------- steps

  @override
  Widget build(BuildContext context) {
    if (_available == null) return const SizedBox(height: 160);
    return AutofillGroup(
      child: switch (_step) {
        _Step.verify || _Step.reset => _codeStep(),
        _Step.forgot => _forgotStep(),
        _ => _mainStep(),
      },
    );
  }

  Widget _codeStep() {
    final c = context.c;
    final resetting = _step == _Step.reset;
    final canSubmit = !_busy && _code.length == codeLength;
    void submit() {
      if (resetting) {
        _submitReset();
      } else if (_code.length == codeLength) {
        _submitVerify(_code);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: _spaced([
      _back(resetting ? _Step.forgot : _Step.signup, 'Back'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(Radii.md)),
          child: Icon(Icons.mail_outline_rounded, size: 20, color: c.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Check your email', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink)),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'We sent a six-digit code to '),
                TextSpan(text: _mail, style: TextStyle(fontWeight: FontWeight.w500, color: c.ink)),
                const TextSpan(text: '. It works for 10 minutes.'),
              ]),
              style: TextStyle(fontSize: 14, height: 1.5, color: c.body),
            ),
          ]),
        ),
      ]),
      ..._banner(),
      CodeBoxes(
        value: _code,
        disabled: _busy,
        onChange: (v) => setState(() => _code = v),
        onComplete: (digits) {
          if (!resetting) _submitVerify(digits);
        },
      ),
      if (resetting) _passwordField('New password', meter: true, newPassword: true, onDone: submit),
      EButton(
        label: _busy ? 'Please wait…' : (resetting ? 'Set password and sign in' : 'Verify and continue'),
        expand: true,
        onPressed: canSubmit ? submit : null,
      ),
      Center(
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Didn’t get it? Check spam, or '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: _busy || _wait > 0 ? null : _resend,
                child: Text(
                  _wait > 0 ? 'resend in ${_wait}s' : 'send a new code',
                  style: TextStyle(
                    fontSize: 13,
                    color: _busy || _wait > 0 ? c.muted : c.primary,
                    decoration: _busy || _wait > 0 ? TextDecoration.none : TextDecoration.underline,
                    decorationColor: c.primary,
                  ),
                ),
              ),
            ),
          ]),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: c.muted),
        ),
      ),
    ], 16));
  }

  Widget _forgotStep() {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: _spaced([
      _back(_Step.signin, 'Back to sign in'),
      Text('Reset your password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink)),
      Text('Enter your email and we’ll send a code to choose a new one.', style: TextStyle(fontSize: 14, height: 1.5, color: c.body)),
      ..._banner(),
      _emailField(action: TextInputAction.send, onDone: _submitForgot),
      EButton(label: _busy ? 'Sending…' : 'Send reset code', expand: true, onPressed: _busy ? null : _submitForgot),
    ]));
  }

  Widget _mainStep() {
    final c = context.c;
    // Without mail the server cannot send sign-up or reset codes, but signing in with a password needs no email at all.
    final mail = _available != false;
    final signingUp = mail && _step == _Step.signup;
    void submit() => signingUp ? _submitSignUp() : _submitSignIn();

    Widget tab(_Step t, String label) {
      final on = _step == t;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: Material(
            color: on ? c.primary : Colors.transparent,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _go(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: on ? c.onPrimary : c.muted)),
              ),
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: _spaced([
      if (mail)
        Semantics(
          label: 'Sign in or create an account',
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.pill)),
            child: Row(children: [tab(_Step.signin, 'Sign in'), tab(_Step.signup, 'Create account')]),
          ),
        ),
      ..._banner(),
      if (signingUp)
        _labelled(
          'Name',
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            style: TextStyle(fontSize: 15, color: c.ink),
            decoration: _decoration('Alex Rivera'),
          ),
        ),
      _emailField(action: TextInputAction.next),
      _passwordField('Password', meter: signingUp, newPassword: signingUp, onDone: submit),
      if (!signingUp && mail)
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => _go(_Step.forgot),
            child: Text('Forgot password?', style: TextStyle(fontSize: 12.5, color: c.muted)),
          ),
        ),
      EButton(label: _busy ? 'Please wait…' : (signingUp ? 'Create account' : 'Sign in'), expand: true, onPressed: _busy ? null : submit),
      if (!mail)
        Text('New here? Continue with Google. Creating an account with email is not available right now.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.5, color: c.muted)),
    ]));
  }
}

/// Six boxes drawn over one real text field, so fast typing, pasting and the keyboard's one-time-code suggestion all work.
class CodeBoxes extends StatefulWidget {
  const CodeBoxes({super.key, required this.value, required this.onChange, required this.onComplete, this.disabled = false});
  final String value;
  final void Function(String next) onChange;
  final void Function(String code) onComplete;
  final bool disabled;

  @override
  State<CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<CodeBoxes> {
  late final _input = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant CodeBoxes old) {
    super.didUpdateWidget(old);
    if (widget.value != _input.text) {
      _input.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(String next) {
    final clean = digitsOnly(next);
    if (clean != next) _input.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
    final before = widget.value;
    widget.onChange(clean);
    if (clean.length == codeLength && clean != before) widget.onComplete(clean);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final value = widget.value;
    final cursor = value.length < codeLength ? value.length : codeLength - 1;
    return Semantics(
      label: 'Six digit verification code',
      child: Stack(children: [
        Opacity(
          opacity: widget.disabled ? 0.5 : 1,
          child: Row(children: [
            for (var i = 0; i < codeLength; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.canvas,
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(
                      color: _focus.hasFocus && i == cursor ? c.primary : (i < value.length ? c.primary.withValues(alpha: 0.5) : c.hairline),
                      width: _focus.hasFocus && i == cursor ? 2 : 1,
                    ),
                  ),
                  child: Text(i < value.length ? value[i] : '', style: TextStyle(fontFamily: monoFamily, fontSize: 24, color: c.ink)),
                ),
              ),
            ],
          ]),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _input,
              focusNode: _focus,
              autofocus: true,
              enabled: !widget.disabled,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: codeLength * 2,
              showCursor: false,
              enableInteractiveSelection: false,
              onChanged: _set,
              decoration: const InputDecoration(counterText: '', border: InputBorder.none, filled: false, contentPadding: EdgeInsets.zero),
            ),
          ),
        ),
      ]),
    );
  }
}
