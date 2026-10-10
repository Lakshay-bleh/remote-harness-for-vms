import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/nav.dart';
import '../../core/prefs.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'copy_row.dart';
import 'hub_store.dart';
import 'hub_url.dart';
import 'protocol.dart';

/// On a self-hosted hub: hand Escanor this hub's address and a token, so Escanor installs its tools into every Claude
/// session on every machine here (EscanorConnect.tsx). The row shows whether it is installed.
class EscanorConnectRow extends StatefulWidget {
  const EscanorConnectRow({super.key});
  @override
  State<EscanorConnectRow> createState() => _EscanorConnectRowState();
}

class _EscanorConnectRowState extends State<EscanorConnectRow> {
  McpOverview? _overview;

  @override
  void initState() {
    super.initState();
    _refresh(); // the badge needs the state without opening the sheet
  }

  Future<void> _refresh() async {
    try {
      final o = await HubStore.instance.api.getMcpOverview();
      if (mounted) setState(() => _overview = o);
    } catch (_) {
      // an older hub has no /mcp-servers; the sheet still works for copying the details
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final installed = escanorInstalled(_overview);
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () async {
        haptic();
        await showESheet<void>(context, title: 'Connect to Escanor', builder: (_) => const EscanorConnectBody());
        _refresh();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: installed ? c.success : c.hairline)),
          const SizedBox(width: 10),
          Expanded(child: Text(installed ? 'Escanor connected' : 'Connect to Escanor', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.body))),
        ]),
      ),
    );
  }
}

class EscanorConnectBody extends ConsumerStatefulWidget {
  const EscanorConnectBody({super.key});
  @override
  ConsumerState<EscanorConnectBody> createState() => _EscanorConnectBodyState();
}

class _EscanorConnectBodyState extends ConsumerState<EscanorConnectBody> {
  McpOverview? _overview;
  bool _failed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Poll only while this is open: this is how the person sees Escanor land on their machines.
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final o = await HubStore.instance.api.getMcpOverview();
      if (mounted) {
        setState(() {
          _overview = o;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final overview = _overview;
    final installed = escanorInstalled(overview);
    final address = HubStore.instance.api.credentials.hubUrl;
    final signedIn = ref.watch(sessionProvider).status == SessionStatus.signedIn;
    final body = TextStyle(fontSize: 13, height: 1.45, color: c.body);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(
        'Escanor installs its tools into every Claude session on every machine here — running chats included — and turns them on. New machines get it automatically.',
        style: TextStyle(fontSize: 13, height: 1.45, color: c.muted),
      ),
      const SizedBox(height: 16),
      if (installed && overview != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.success.withValues(alpha: 0.1),
            border: Border.all(color: c.success.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Escanor is installed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.ink)),
            const SizedBox(height: 6),
            for (final vm in overview.vms)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: vm.connected ? c.success : c.hairline)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: vm.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                      TextSpan(text: '  ${escanorInstallLabel(vm)}', style: TextStyle(color: c.muted)),
                    ]), style: TextStyle(fontSize: 12.5, color: c.body)),
                  ),
                ]),
              ),
            if (overview.vms.isEmpty) Text('No machines have connected yet.', style: TextStyle(fontSize: 12.5, color: c.muted)),
          ]),
        )
      else
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('1. Copy your hub URL and generate a token below.', style: body),
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
            const TextSpan(text: '2. In Escanor, open '),
            TextSpan(text: 'Integrations → Claude cloud sessions', style: TextStyle(fontWeight: FontWeight.w500, color: c.ink)),
            const TextSpan(text: '.'),
          ]), style: body),
          const SizedBox(height: 4),
          Text("3. Paste them and press Connect. That's it.", style: body),
        ]),
      const SizedBox(height: 16),
      CopyRow(label: 'Hub URL', value: address),
      const SizedBox(height: 12),
      const _TokenSection(),
      if (isPrivateAddress(address)) ...[
        const SizedBox(height: 12),
        const Notice(
          'This address only works on your own network. Escanor connects to your hub from the internet, so put the hub behind a public https:// address (a reverse proxy, a tunnel, or the Cloudflare Worker hub) and use that URL.',
          tone: NoticeTone.warn,
        ),
      ],
      if (_failed && overview == null) ...[
        const SizedBox(height: 12),
        Text('Could not read the install status from this hub. If it is an older release, update it to let Escanor install.',
            style: TextStyle(fontSize: 12, color: c.muted)),
      ],
      const SizedBox(height: 12),
      Text(
        'A token gives full access to this hub. Only paste it into Escanor, which stores it encrypted and uses it solely to install and update the MCP. Revoke it here any time; signing out of this phone does not affect it.',
        style: TextStyle(fontSize: 12, height: 1.45, color: c.mutedSoft),
      ),
      const SizedBox(height: 16),
      EButton(
        label: 'Open Connections',
        expand: true,
        onPressed: () {
          Navigator.of(context).pop();
          // Inside the signed-in app this is the Connections tab; on its own (no Escanor sign-in) there is no tab to go to.
          if (signedIn) ref.read(navProvider.notifier).go(AppTab.connections);
        },
      ),
    ]);
  }
}

/// A dedicated token for Escanor rather than this phone's login: signing out here never breaks it, and it can be
/// revoked on its own. The value is shown once, when it is created.
class _TokenSection extends StatefulWidget {
  const _TokenSection();
  @override
  State<_TokenSection> createState() => _TokenSectionState();
}

class _TokenSectionState extends State<_TokenSection> {
  List<ApiTokenDto> _tokens = const [];
  ApiTokenDto? _created;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await HubStore.instance.api.listApiTokens();
      if (mounted) setState(() => _tokens = t);
    } catch (_) {
      // an older hub has no /tokens; the rest of the sheet still works
    }
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Escanor only installs and reads MCP servers, so it gets a token that can do exactly that.
      final t = await HubStore.instance.api.createApiToken('Escanor', scope: 'mcp');
      if (mounted) setState(() => _created = t);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().isEmpty ? 'Could not create a token' : e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(String id) async {
    try {
      await HubStore.instance.api.deleteApiToken(id);
      if (_created?.id == id && mounted) setState(() => _created = null);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().isEmpty ? 'Could not revoke the token' : e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final created = _created;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (created != null && created.token != null) ...[
        CopyRow(label: 'Hub token for Escanor (shown once)', value: created.token!, secret: true),
        const SizedBox(height: 6),
        Text('Copy it now. It is not shown again, but you can always generate another.', style: TextStyle(fontSize: 12, color: c.mutedSoft)),
      ] else
        EButton(label: _busy ? 'Generating…' : 'Generate a token for Escanor', kind: ButtonKind.quiet, expand: true, onPressed: _busy ? null : _generate),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 12.5, color: c.error))),
      if (_tokens.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final t in _tokens)
          Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: t.label),
                  TextSpan(text: ' · ${_date(t.createdAt)}', style: TextStyle(color: c.mutedSoft)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: c.body),
              ),
            ),
            TextButton(onPressed: () => _revoke(t.id), child: Text('Revoke', style: TextStyle(fontSize: 12.5, color: c.muted))),
          ]),
      ],
    ]);
  }

  String _date(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? '' : DateFormat.yMd().format(d.toLocal());
  }
}
