import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/load.dart';
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'connections_api.dart';
import 'connections_logic.dart';

/// CONTRACT: the Connections tab. The services the person has connected, and every one they can add:
/// by signing in on the provider's page (in the browser) or by pasting a key.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

const _capsCache = CachePolicy('connections.capabilities', ttl: Duration(seconds: 20));
const _catalogCache = CachePolicy('connections.catalog', ttl: Duration(minutes: 10), maxAge: Duration(days: 7));

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late final Loader<Capabilities> _caps = Loader(
    () => api.capabilities(),
    every: const Duration(seconds: 20),
    cache: _capsCache,
    decode: (j) => Capabilities.fromJson(Map<String, dynamic>.from(j as Map)),
    encode: (c) => c.toJson(),
  );
  late final Loader<List<CatalogProvider>> _catalog = Loader(
    () => api.catalog(),
    cache: _catalogCache,
    decode: (j) => [for (final p in j as List) CatalogProvider.fromJson(Map<String, dynamic>.from(p as Map))],
    encode: (l) => [for (final p in l) p.toJson()],
  );

  final _query = TextEditingController();
  int _shown = connectionsPage;
  String? _notice;

  @override
  void dispose() {
    _caps.dispose();
    _catalog.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _disconnect(ConnectedIntegration c) async {
    final ok = await confirm(context,
        title: 'Disconnect ${c.name}?', message: 'Your assistant will no longer be able to use it.', ok: 'Disconnect', danger: true);
    if (!ok) return;
    try {
      await api.disconnect(c.providerId);
      if (!mounted) return;
      setState(() => _notice = '${c.name} disconnected.');
      dropCache(_capsCache.key);
      _caps.reload();
    } catch (e) {
      if (mounted) setState(() => _notice = errorText(e));
    }
  }

  Future<void> _connect(CatalogProvider p) async {
    final name = await showESheet<String>(context, title: 'Connect ${p.name}', builder: (_) => ConnectSheet(provider: p));
    if (name == null || !mounted) return;
    setState(() => _notice = '$name connected.');
    dropCache(_capsCache.key);
    _caps.reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.canvas,
      child: Column(children: [
        const ScreenHeader(title: 'Connections'),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([_caps, _catalog, _query]),
            builder: (context, _) {
              final connected = _caps.data?.integrations ?? const <ConnectedIntegration>[];
              final available = availableProviders(_catalog.data ?? const [], connected, _query.text);
              return RefreshIndicator(
                onRefresh: () async {
                  _caps.reload();
                  _catalog.reload();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    Text(
                      '${_caps.data?.summary ?? 'What your assistant can work with.'} Connect a service once and it works here, on the web and for your assistant.',
                      style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
                    ),
                    if (_notice != null) Padding(padding: const EdgeInsets.only(top: 12), child: Notice(_notice!)),
                    if (_caps.error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Notice(_caps.error!, tone: NoticeTone.error)),
                    if (connected.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _SectionTitle('Connected'),
                      _ListCard(children: [for (final i in connected) _ConnectedRow(item: i, onDisconnect: () => _disconnect(i))]),
                    ],
                    const SizedBox(height: 24),
                    _SectionTitle('Add a service'),
                    TextField(
                      controller: _query,
                      onChanged: (_) => setState(() => _shown = connectionsPage),
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      decoration: InputDecoration(
                        hintText: 'Search GitHub, Vercel, Sentry…',
                        prefixIcon: Icon(Icons.search_rounded, size: 20, color: c.mutedSoft),
                        suffixIcon: _query.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                                onPressed: () => setState(() {
                                  _query.clear();
                                  _shown = connectionsPage;
                                }),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_catalog.loading) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: Spinner())),
                    if (_catalog.error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Notice(_catalog.error!, tone: NoticeTone.error)),
                    if (!_catalog.loading || available.isNotEmpty)
                      _ListCard(children: [
                        for (final p in available.take(_shown)) _ProviderRow(provider: p, onTap: () => _connect(p)),
                        if (!_catalog.loading && available.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Text('Nothing matches.', style: TextStyle(fontSize: 14, color: c.muted)),
                          ),
                      ]),
                    if (available.length > _shown)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: EButton(
                          label: 'Show more',
                          kind: ButtonKind.quiet,
                          expand: true,
                          onPressed: () => setState(() => _shown += connectionsPage),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: context.c.ink)),
      );
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, thickness: 1, color: c.hairline));
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(Radii.lg)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }
}

class _ConnectedRow extends StatelessWidget {
  const _ConnectedRow({required this.item, required this.onDisconnect});
  final ConnectedIntegration item;
  final VoidCallback onDisconnect;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final status = connectedStatus(item);
    final tone = switch (status.tone) { StatusTone.warning => c.warning, StatusTone.success => c.success, StatusTone.muted => c.muted };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: c.ink)),
            const SizedBox(height: 2),
            Text(status.text, style: TextStyle(fontSize: 12, color: tone)),
          ]),
        ),
        TextButton(
          onPressed: () {
            haptic();
            onDisconnect();
          },
          child: Text('Disconnect', style: TextStyle(fontSize: 14, color: c.muted)),
        ),
      ]),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.provider, required this.onTap});
  final CatalogProvider provider;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: () {
        haptic();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(provider.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: c.ink)),
              if (provider.categoryLabel.isNotEmpty)
                Text(provider.categoryLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
          ),
          const SizedBox(width: 12),
          Text('Connect', style: TextStyle(fontSize: 14, color: c.primary)),
        ]),
      ),
    );
  }
}

/// Connecting one service. Pops with the service's name once it is connected.
class ConnectSheet extends StatefulWidget {
  const ConnectSheet({super.key, required this.provider});
  final CatalogProvider provider;
  @override
  State<ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<ConnectSheet> with WidgetsBindingObserver {
  final _token = TextEditingController();
  final Map<String, TextEditingController> _fields = {};
  String? _error;
  bool _busy = false;
  bool _waiting = false;
  Timer? _poll;
  DateTime? _started;
  bool _done = false;

  CatalogProvider get p => widget.provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final f in p.credentialFields) {
      _fields[f] = TextEditingController()..addListener(() => setState(() {}));
    }
    _token.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _token.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Back from the browser: look at once rather than waiting for the next tick.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waiting) _check();
  }

  void _connected() {
    if (_done || !mounted) return;
    _done = true;
    _poll?.cancel();
    Navigator.of(context).pop(p.name);
  }

  Map<String, String> get _typed => {
        for (final e in _fields.entries)
          if (e.value.text.isNotEmpty) e.key: e.value.text,
      };

  /// After the browser step the backend records the connection on its own; watch for it.
  Future<void> _check() async {
    try {
      final now = await api.capabilities();
      if (now.integrations.any((i) => i.providerId == p.id)) {
        _connected();
        return;
      }
    } catch (_) {
      // keep waiting
    }
    final started = _started;
    if (mounted && _waiting && started != null && DateTime.now().difference(started) > oauthWaitLimit) {
      _poll?.cancel();
      setState(() {
        _waiting = false;
        _error = 'That took too long. Try again.';
      });
    }
  }

  Future<void> _submitKey() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = keyBody(_token.text, _typed);
      await api.connectWithKey(p.id, accessToken: body.accessToken, credentials: body.credentials);
      _connected();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not connect.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startOauth() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await api.integrationAuthorizeUrl(p.id);
      if (!isSafeExternalUrl(url)) throw StateError('Could not start.');
      setState(() {
        _waiting = true;
        _started = DateTime.now();
      });
      _poll?.cancel();
      _poll = Timer.periodic(oauthPollEvery, (_) => _check());
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('Could not open the browser.');
    } catch (e) {
      _poll?.cancel();
      if (mounted) {
        setState(() {
          _waiting = false;
          _error = errorText(e, 'Could not start.');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final children = <Widget>[
      if (p.description.isNotEmpty) Text(p.description, style: TextStyle(fontSize: 14, height: 1.45, color: c.body)),
      if (_error != null) Notice(_error!, tone: NoticeTone.error),
      if (p.viaLocalAgent) Notice('${p.name} connects through a machine you pair. Set it up from Local Hub in Escanor on the web.'),
      if (p.viaOauth) ...[
        EButton(
          label: _waiting ? 'Waiting for you to finish…' : 'Continue with ${p.name}',
          expand: true,
          busy: _busy,
          onPressed: _busy || _waiting ? null : _startOauth,
        ),
        if (_waiting)
          Row(children: [
            const Spinner(size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text('Finish in the browser, then come back here.', style: TextStyle(fontSize: 12, color: c.muted))),
          ]),
      ],
      if (p.viaKey) ...[
        _Labeled(
          label: p.tokenLabel.isEmpty ? 'API key' : p.tokenLabel,
          child: TextField(
            controller: _token,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [],
            textInputAction: p.credentialFields.isEmpty ? TextInputAction.done : TextInputAction.next,
            onSubmitted: (_) {
              if (p.credentialFields.isEmpty && !_busy && canSubmitKey(p, _token.text, _typed)) _submitKey();
            },
          ),
        ),
        for (final f in p.credentialFields)
          _Labeled(
            label: fieldLabel(f),
            child: TextField(controller: _fields[f], autocorrect: false, enableSuggestions: false),
          ),
        if (p.helpUrl.isNotEmpty && isSafeExternalUrl(p.helpUrl))
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => launchUrl(Uri.parse(p.helpUrl), mode: LaunchMode.externalApplication),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('Where do I find this?',
                    style: TextStyle(fontSize: 12, color: c.primary, decoration: TextDecoration.underline, decorationColor: c.primary)),
              ),
            ),
          ),
        EButton(
          label: _busy ? 'Connecting…' : 'Connect',
          expand: true,
          onPressed: _busy || !canSubmitKey(p, _token.text, _typed) ? null : _submitKey,
        ),
      ],
      if (!p.viaKey && !p.viaOauth && !p.viaLocalAgent) Notice('${p.name} can’t be connected from here yet.'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
    ]);
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: TextStyle(fontSize: 14, color: context.c.body)),
        const SizedBox(height: 4),
        child,
      ]);
}
