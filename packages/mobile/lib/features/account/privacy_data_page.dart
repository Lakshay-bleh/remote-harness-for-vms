import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/load.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../settings/legal_content.dart' show policyVersion;
import '../settings/settings_widgets.dart';
import 'account_api.dart';
import 'data_export.dart';
import 'export_share.dart';
import 'privacy.dart';

/// Your choices, a copy of your data, and requests about it, all inside the app. [initialType] opens a new request of that kind
/// straight away (Help > Report a problem opens a complaint).
class PrivacyDataPage extends StatefulWidget {
  const PrivacyDataPage({super.key, this.initialType});
  final String? initialType;
  @override
  State<PrivacyDataPage> createState() => _PrivacyDataPageState();
}

class _PrivacyDataPageState extends State<PrivacyDataPage> {
  final _consents = Loader<List<dynamic>>(fetchConsents);
  final _requests = Loader<List<dynamic>>(fetchPrivacyRequests);
  String? _saving;
  ({bool error, String text})? _notice;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final start = widget.initialType;
    if (start != null) WidgetsBinding.instance.addPostFrameCallback((_) => _compose(start));
  }

  @override
  void dispose() {
    _consents.dispose();
    _requests.dispose();
    super.dispose();
  }

  Future<void> _toggle(String purpose, bool grant) async {
    setState(() {
      _saving = purpose;
      _notice = null;
    });
    try {
      await recordConsent(purpose, grant, policyVersion);
      _consents.reload();
    } catch (e) {
      if (mounted) setState(() => _notice = (error: true, text: errorText(e, 'Could not save that choice.')));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  Future<void> _prepare() async {
    setState(() {
      _exporting = true;
      _notice = null;
    });
    try {
      final json = await exportMyData();
      final scope = json['scope'];
      if (mounted) {
        showESheet<void>(context, title: 'Your data', builder: (_) => _DataSheet(text: exportText(json), scope: scope is String ? scope : null));
      }
    } catch (e) {
      if (mounted) setState(() => _notice = (error: true, text: errorText(e, 'Could not get your data.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _compose(String type) async {
    final sent = await showESheet<bool>(context, title: 'New request', builder: (_) => _NewRequest(start: type));
    if (sent == true) _requests.reload();
  }

  Future<void> _open(PrivacyRequest r) async {
    var full = r;
    try {
      full = PrivacyRequest.fromJson(await fetchPrivacyRequest(r.id));
    } catch (_) {}
    if (!mounted) return;
    showESheet<void>(context, title: r.reference, builder: (_) => _RequestSheet(r: full));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_consents, _requests]),
      builder: (context, _) {
        final c = context.c;
        final granted = <String, bool>{
          for (final j in _consents.data ?? const []) if (j is Map) '${j['purpose']}': j['granted'] == true,
        };
        final requests = [for (final j in _requests.data ?? const []) if (j is Map) PrivacyRequest.fromJson(Map<String, dynamic>.from(j))];
        return SettingsPage(title: 'Privacy and your data', children: [
          if (_notice != null) Notice(_notice!.text, tone: _notice!.error ? NoticeTone.error : NoticeTone.info),
          Group(
            title: 'Your choices',
            footer: 'None of these is needed to use Escanor, and each takes effect when you change it.',
            children: _consents.loading && _consents.data == null
                ? const [BlockSpinner(padding: 16)]
                : _consents.error != null && _consents.data == null
                    ? const [CardText('Could not load your choices.', error: true)]
                    : [
                        for (final k in optionalConsents)
                          SwitchRow(
                            label: k.label,
                            sub: k.description,
                            on: granted[k.purpose] == true,
                            disabled: _saving != null,
                            onChanged: (v) => _toggle(k.purpose, v),
                          ),
                      ],
          ),
          Group(
            title: 'A copy of your data',
            footer: 'Your account records as a JSON file: profile, workspaces, your choices and requests. It never contains passwords or access '
                'tokens.',
            children: [
              SRow(
                icon: Icons.description_outlined,
                label: _exporting ? 'Getting it…' : 'Get my data',
                sub: 'Prepares the file so you can copy or save it',
                chevron: false,
                disabled: _exporting,
                onTap: _prepare,
              ),
            ],
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle(
              'Your requests',
              trailing: InkWell(
                onTap: () => _compose('access'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 16, color: c.primary),
                    const SizedBox(width: 2),
                    Text('New request', style: TextStyle(fontSize: 13, color: c.primary)),
                  ]),
                ),
              ),
            ),
            RowsCard(children: [
              if (_requests.loading && _requests.data == null)
                const BlockSpinner(padding: 16)
              else if (_requests.error != null && _requests.data == null)
                CardText(_requests.error!, error: true)
              else if (requests.isEmpty)
                const CardText('No requests yet. Ask to correct your data, withdraw a consent, or make a complaint, and track it here.')
              else
                for (final r in requests)
                  SRow(
                    icon: Icons.verified_user_outlined,
                    label: r.subject,
                    sub: '${r.reference} · ${requestTypeLabel(r.requestType)}${isFinished(r.status) ? '' : ' · ${describeDue(r.nextDue)}'}',
                    value: statusLabel(r.status),
                    onTap: () => _open(r),
                  ),
            ]),
          ]),
        ]);
      },
    );
  }
}

class _DataSheet extends StatefulWidget {
  const _DataSheet({required this.text, this.scope});
  final String text;
  final String? scope;
  @override
  State<_DataSheet> createState() => _DataSheetState();
}

class _DataSheetState extends State<_DataSheet> {
  String? _state;
  bool _busy = false;

  Future<void> _run(Future<String> Function() what) async {
    setState(() => _busy = true);
    try {
      final r = await what();
      if (mounted) setState(() => _state = r.isEmpty ? null : r);
    } catch (e) {
      if (mounted) setState(() => _state = errorText(e, 'That did not work.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('Ready: ${sizeLabel(widget.text)}. Save it as a file, or copy it.', style: TextStyle(fontSize: 14, color: c.body)),
      const SizedBox(height: 12),
      EButton(
        label: 'Save or send as a file',
        icon: Icons.ios_share_rounded,
        expand: true,
        onPressed: _busy ? null : () => _run(() async => (await shareExport(widget.text)) == ShareOutcome.cancelled ? '' : 'Done.'),
      ),
      const SizedBox(height: 8),
      EButton(
        label: 'Copy to the clipboard',
        icon: Icons.copy_rounded,
        kind: ButtonKind.quiet,
        expand: true,
        onPressed: _busy
            ? null
            : () => _run(() async {
                  await copyExport(widget.text);
                  return 'Copied to the clipboard.';
                }),
      ),
      if (_state != null) ...[const SizedBox(height: 12), Notice(_state!)],
      if (widget.scope != null) ...[
        const SizedBox(height: 12),
        Text(widget.scope!, style: TextStyle(fontSize: 12, height: 1.5, color: c.muted)),
      ],
    ]);
  }
}

class _NewRequest extends StatefulWidget {
  const _NewRequest({required this.start});
  final String start;
  @override
  State<_NewRequest> createState() => _NewRequestState();
}

class _NewRequestState extends State<_NewRequest> {
  late String _type = widget.start;
  final _subject = TextEditingController();
  final _details = TextEditingController();
  bool _busy = false;
  String? _error;
  PrivacyRequest? _sent;

  @override
  void dispose() {
    _subject.dispose();
    _details.dispose();
    super.dispose();
  }

  String? get _problem => requestProblem(subject: _subject.text, details: _details.text);

  Future<void> _send() async {
    final problem = _problem;
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await openPrivacyRequest(type: _type, subject: _subject.text.trim(), details: _details.text.trim());
      if (mounted) setState(() => _sent = PrivacyRequest.fromJson(r));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e, 'Could not send that. Try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickType() async {
    final v = await showChoiceSheet<String>(context,
        title: 'What is this about?', options: [for (final t in requestTypes) Choice(t.value, t.label, t.hint)], value: _type);
    if (v != null && mounted) setState(() => _type = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sent = _sent;
    if (sent != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('Request received', style: TextStyle(fontSize: 17, color: c.ink, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Your reference is '),
            TextSpan(text: sent.reference, style: TextStyle(fontFamily: monoFamily, color: c.ink, fontWeight: FontWeight.w600)),
            TextSpan(
                text: '. A person looks at it; it is acknowledged ${describeDue(sent.acknowledgeBy)} and answered ${describeDue(sent.resolveBy)}. '
                    'You can follow it under Your requests.'),
          ]),
          style: TextStyle(fontSize: 14, height: 1.5, color: c.body),
        ),
        const SizedBox(height: 16),
        EButton(label: 'Done', expand: true, onPressed: () => Navigator.of(context).pop(true)),
      ]);
    }
    String hint = '';
    String label = _type;
    for (final t in requestTypes) {
      if (t.value == _type) {
        hint = t.hint;
        label = t.label;
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (_error != null) ...[Notice(_error!, tone: NoticeTone.error), const SizedBox(height: 12)],
      Material(
        color: c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: c.lineStrong)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _pickType,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('What is this about?', style: TextStyle(fontSize: 12, color: c.muted)),
                  Text(label, style: TextStyle(fontSize: 15, color: c.ink)),
                ]),
              ),
              Icon(Icons.expand_more_rounded, color: c.mutedSoft),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(hint, style: TextStyle(fontSize: 12, color: c.muted)),
      const SizedBox(height: 12),
      LabeledField(label: 'Title', controller: _subject, hint: 'A few words', maxLength: 200, onChanged: (_) => setState(() {})),
      const SizedBox(height: 12),
      LabeledField(label: 'Details (optional)', controller: _details, maxLines: 4, maxLength: 5000, onChanged: (_) => setState(() {})),
      const SizedBox(height: 8),
      Text('Do not include passwords, card numbers or access tokens.', style: TextStyle(fontSize: 12, color: c.muted)),
      const SizedBox(height: 12),
      EButton(label: _busy ? 'Sending…' : 'Send request', expand: true, onPressed: _busy || _problem != null ? null : _send),
    ]);
  }
}

class _RequestSheet extends StatelessWidget {
  const _RequestSheet({required this.r});
  final PrivacyRequest r;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(r.subject, style: TextStyle(fontSize: 14, color: c.ink)),
      const SizedBox(height: 8),
      Text('${requestTypeLabel(r.requestType)} · ${statusLabel(r.status)}${isFinished(r.status) ? '' : ', ${describeDue(r.nextDue)}'}',
          style: TextStyle(fontSize: 14, color: c.muted)),
      if (r.resolutionNote != null && r.resolutionNote!.isNotEmpty) ...[const SizedBox(height: 12), Notice(r.resolutionNote!)],
      if (r.events.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: c.hairline))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final e in r.events)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: statusLabel(e.toStatus), style: TextStyle(color: c.ink)),
                    TextSpan(text: ' · ${dateTime(e.createdAt)}', style: TextStyle(color: c.muted)),
                  ]), style: const TextStyle(fontSize: 13)),
                  if (e.note != null && e.note!.isNotEmpty) Text(e.note!, style: TextStyle(fontSize: 13, color: c.body)),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }
}
