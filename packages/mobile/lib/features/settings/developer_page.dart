import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/load.dart';
import '../../core/nav.dart';
import '../../core/prefs.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../ui/parts.dart';
import '../../ui/widgets.dart';
import '../account/help_page.dart';
import '../account/money.dart';
import '../assistant/chat_meta_store.dart' show chatMetaProvider;
import '../computers/computer_api.dart';
import 'settings_api.dart';
import 'settings_logic.dart';
import 'settings_widgets.dart';

const _mcpCache = CachePolicy('mcp-connections', ttl: Duration(minutes: 1), maxAge: Duration(days: 7));

/// The debug details for this phone, as text to paste when asking for help.
String debugInfoFor(BuildContext context, WidgetRef ref) => debugInfo(
      version: appVersion.value,
      platform: platformLabel(),
      server: api.base,
      signedIn: ref.read(sessionProvider).user != null,
      computers: loadComputers().length,
      screen: screenText(context),
      os: osVersion(),
      now: DateTime.now(),
    );

/// Start the app again from the top, as a reload of the page did on the web: every screen is rebuilt and the account is read
/// again. Nothing stored is lost.
void reloadApp(WidgetRef ref) {
  for (final k in tabNavigatorKeys.values) {
    k.currentState?.popUntil((r) => r.isFirst);
  }
  ref.invalidate(prefsProvider);
  ref.invalidate(navProvider);
  ref.invalidate(sessionProvider);
}

enum _CheckState { idle, running, done }

/// For people who build on Escanor: where the app connects, whether it can reach it, keys for other AI apps, and what to send when
/// asking for help.
class DeveloperPage extends ConsumerStatefulWidget {
  const DeveloperPage({super.key});
  @override
  ConsumerState<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends ConsumerState<DeveloperPage> {
  final _mcp = Loader<List<dynamic>>(fetchMcpConnections, cache: _mcpCache);
  final _copied = CopiedFlag();
  _CheckState _check = _CheckState.idle;
  ({bool ok, int ms, int status})? _result;
  bool _creating = false;
  String? _keyError;

  @override
  void dispose() {
    _mcp.dispose();
    _copied.dispose();
    super.dispose();
  }

  Future<void> _runCheck() async {
    setState(() => _check = _CheckState.running);
    final r = await ping();
    if (mounted) {
      setState(() {
        _result = r;
        _check = _CheckState.done;
      });
    }
  }

  Future<void> _createKey() async {
    setState(() {
      _creating = true;
      _keyError = null;
    });
    try {
      final install = await createMcpInstall('Mobile ${DateFormat.yMd().format(DateTime.now())}');
      _mcp.reload();
      if (mounted) await showNewKey(context, install);
    } catch (e) {
      if (mounted) setState(() => _keyError = errorText(e, 'Could not create a key.'));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _resetData() async {
    await showConfirmSheet(
      context,
      title: 'Reset app data?',
      body: 'This phone forgets its preferences, pinned and renamed chats, and every computer paired with it. Nothing changes on the '
          'computers themselves, and you can pair them again.',
      action: 'Reset',
      onConfirm: () async {
        ref.read(prefsProvider.notifier).reset();
        ref.read(chatMetaProvider.notifier).reset();
        clearComputers();
      },
    ).then((done) {
      if (done) reloadApp(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final base = api.base;
    return ListenableBuilder(
      listenable: Listenable.merge([_mcp, _copied, appVersion]),
      builder: (context, _) {
        final apps = appKeys([for (final j in (_mcp.data ?? const [])) if (j is Map) McpConnection.fromJson(Map<String, dynamic>.from(j))]);
        final r = _result;
        return SettingsPage(title: 'Developer', subtitle: 'For building on Escanor and asking for help', children: [
          Group(
            title: 'Connection',
            footer: 'The app always talks to Escanor’s own server. Test checks that it answers; it does not need you to be signed in.',
            children: [
              SRow(icon: Icons.public_rounded, label: 'Server', value: hostOf(base)),
              SRow(
                icon: Icons.power_outlined,
                label: 'Test connection',
                onTap: _runCheck,
                chevron: false,
                disabled: _check == _CheckState.running,
                right: _check == _CheckState.running
                    ? const Spinner(size: 22)
                    : (_check == _CheckState.done && r != null
                        ? Text(checkText(ok: r.ok, ms: r.ms, status: r.status), style: TextStyle(fontSize: 14, color: r.ok ? c.success : c.error))
                        : null),
              ),
            ],
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('Keys for other AI apps'),
            const Footnote('Give Claude, Cursor or another AI app access to your connected services. Each gets its own key. Tap a key to rename it, '
                'replace it or delete it.'),
            const SizedBox(height: 8),
            if (_keyError != null) ...[Notice(_keyError!, tone: NoticeTone.error), const SizedBox(height: 8)],
            RowsCard(children: [
              if (_mcp.loading && _mcp.data == null)
                const BlockSpinner(padding: 16)
              else if (_mcp.error != null && _mcp.data == null)
                CardText(_mcp.error!, error: true)
              else if (apps.isEmpty)
                const CardText('No keys yet.')
              else
                for (final k in apps)
                  SRow(
                    icon: Icons.key_rounded,
                    label: k.name,
                    sub: '${k.tokenPrefix.isNotEmpty ? '${k.tokenPrefix}… · ' : ''}${groupThousands(k.totalCalls)} calls',
                    value: k.lastUsedAt != null ? 'used ${ago(k.lastUsedAt)}' : 'not used yet',
                    onTap: () => showESheet<void>(context, title: 'Key', builder: (_) => _KeySheet(connection: k, onChanged: _mcp.reload)),
                  ),
              SRow(icon: Icons.key_rounded, label: _creating ? 'Creating…' : 'Create a key', onTap: _createKey, disabled: _creating),
            ]),
          ]),
          Group(title: 'Help and diagnostics', footer: 'The debug details contain no passwords or tokens.', children: [
            SRow(
              icon: Icons.copy_rounded,
              label: 'Copy debug info',
              value: _copied.value == 'debug' ? 'Copied' : null,
              chevron: false,
              onTap: () => _copied.copy('debug', debugInfoFor(context, ref)),
            ),
            SRow(icon: Icons.bug_report_outlined, label: 'Report a problem', onTap: () => pushPage(context, const HelpPage())),
            SRow(icon: Icons.refresh_rounded, label: 'Reload the app', chevron: false, onTap: () => reloadApp(ref)),
          ]),
          Group(
            title: 'This phone',
            footer: 'Removes saved preferences, pinned and renamed chats and the computers paired with this phone. You stay signed in.',
            children: [SRow(icon: Icons.delete_outline_rounded, label: 'Reset app data', danger: true, onTap: _resetData)],
          ),
          Footnote('Version ${appVersion.value}', center: true, soft: true),
        ]);
      },
    );
  }
}

/// A new key, shown once with a way to copy it.
Future<void> showNewKey(BuildContext context, McpInstall install) =>
    showESheet<void>(context, title: 'Your new key', builder: (_) => _NewKeySheet(install: install));

class _NewKeySheet extends StatefulWidget {
  const _NewKeySheet({required this.install});
  final McpInstall install;
  @override
  State<_NewKeySheet> createState() => _NewKeySheetState();
}

class _NewKeySheetState extends State<_NewKeySheet> {
  final _copied = CopiedFlag();
  @override
  void dispose() {
    _copied.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: _copied,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Notice('Copy it now. It is shown only once.', tone: NoticeTone.warn),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.code, borderRadius: BorderRadius.circular(Radii.md)),
          child: SelectableText(widget.install.token, style: TextStyle(fontFamily: monoFamily, fontSize: 12, color: c.onCode)),
        ),
        const SizedBox(height: 12),
        EButton(label: _copied.value == 'key' ? 'Copied' : 'Copy key', expand: true, onPressed: () => _copied.copy('key', widget.install.token)),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Address: '),
            TextSpan(text: widget.install.endpoint, style: const TextStyle(fontFamily: monoFamily)),
          ]),
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
      ]),
    );
  }
}

/// One key for another AI app: rename it, replace it with a fresh one (the old stops working), or delete it.
class _KeySheet extends StatefulWidget {
  const _KeySheet({required this.connection, required this.onChanged});
  final McpConnection connection;
  final VoidCallback onChanged;
  @override
  State<_KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends State<_KeySheet> {
  late final _name = TextEditingController(text: widget.connection.name);
  String? _busy;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _clean => cleanName(_name.text);

  Future<void> _run(String what, Future<void> Function() job) async {
    setState(() {
      _busy = what;
      _error = null;
    });
    try {
      await job();
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, 'That did not work. Try again.');
          _busy = null;
        });
      }
    }
  }

  void _save() {
    final k = widget.connection;
    if (_clean.isEmpty || _clean == k.name) return;
    _run('save', () async {
      await renameMcp(k.id, _clean);
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _rotate() async {
    final k = widget.connection;
    final ok = await confirm(context,
        title: 'Replace this key?',
        message: 'You get a new key to copy now. The old one stops working immediately, so any app using it needs the new one.',
        ok: 'Replace',
        danger: true);
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    final outer = nav.context;
    await _run('rotate', () async {
      final fresh = await rotateMcp(k.id);
      nav.pop();
      if (outer.mounted) await showNewKey(outer, fresh);
    });
  }

  Future<void> _delete() async {
    final k = widget.connection;
    final ok = await confirm(context,
        title: 'Delete this key?',
        message: 'Apps using ${k.name} lose access to your connected services straight away. This cannot be undone, but you can always create a new key.',
        ok: 'Delete',
        danger: true);
    if (!ok || !mounted) return;
    await _run('delete', () async {
      await revokeMcp(k.id);
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final k = widget.connection;
    final canSave = _clean.isNotEmpty && _clean != k.name && _busy == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (_error != null) ...[Notice(_error!, tone: NoticeTone.error), const SizedBox(height: 12)],
      LabeledField(label: 'Name', controller: _name, maxLength: 60, onChanged: (_) => setState(() {}), onSubmitted: (_) => _save()),
      const SizedBox(height: 8),
      EButton(label: _busy == 'save' ? 'Saving…' : 'Save name', expand: true, onPressed: canSave ? _save : null),
      const SizedBox(height: 12),
      Text.rich(
        TextSpan(children: [
          if (k.tokenPrefix.isNotEmpty) ...[
            const TextSpan(text: 'Starts with '),
            TextSpan(text: '${k.tokenPrefix}…', style: const TextStyle(fontFamily: monoFamily)),
            const TextSpan(text: ' · '),
          ],
          TextSpan(
              text: 'created ${ago(k.createdAt)}${k.lastUsedAt != null ? ', last used ${ago(k.lastUsedAt)}' : ', not used yet'}. '
                  'The key itself is never shown again.'),
        ]),
        style: TextStyle(fontSize: 12, color: c.muted),
      ),
      const SizedBox(height: 12),
      Divider(height: 1, color: c.hairline),
      const SizedBox(height: 12),
      EButton(label: _busy == 'rotate' ? 'Working…' : 'Replace with a new key', kind: ButtonKind.quiet, expand: true, onPressed: _busy == null ? _rotate : null),
      const SizedBox(height: 8),
      EButton(label: _busy == 'delete' ? 'Working…' : 'Delete this key', kind: ButtonKind.danger, expand: true, onPressed: _busy == null ? _delete : null),
    ]);
  }
}
