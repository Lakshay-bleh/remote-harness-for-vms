import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../companion/dog_state.dart';
import 'computer_chat.dart' show ComputerRequest;
import 'error_card.dart';
import 'permissions.dart';
import 'protocol/failure.dart';
import 'protocol/protocol.dart';
import 'remote.dart';

Future<List<PermissionGroup>> fetchGroups(ComputerRequest request) async {
  final m = firstOf(await request(ClientMsg.groups()), const {'groups', 'error'});
  if (m?['t'] == 'groups') {
    return [
      for (final g in (m!['items'] as List? ?? const []))
        if (g is Map) PermissionGroup.fromJson(Map<String, dynamic>.from(g)),
    ];
  }
  throw ComputerError(m?['t'] == 'error' ? '${m!['message']}' : 'The computer did not answer.');
}

/// What this phone may do on the computer. Switched-off kinds can be requested from here, but only the person at the computer can
/// allow them: the computer shows a question, and the phone has no way to answer it.
class PermissionsTab extends StatefulWidget {
  const PermissionsTab({super.key, required this.computerId, required this.request, required this.online, this.visible = true});
  final String computerId;
  final ComputerRequest request;
  final bool online;
  final bool visible;
  @override
  State<PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends State<PermissionsTab> {
  final Map<String, String> _notes = {};
  String? _busy;
  Timer? _watch;
  Timer? _watchEnd;

  // What was shown last time appears at once; the list is checked again in the background (it rarely changes).
  late final Remote<List<PermissionGroup>> _list = Remote<List<PermissionGroup>>(
    computerId: widget.computerId,
    what: 'groups',
    run: () => fetchGroups(widget.request),
    ttl: const Duration(seconds: 60),
    decode: (j) => [for (final g in j as List) PermissionGroup.fromJson(Map<String, dynamic>.from(g as Map))],
    encode: (v) => [for (final g in v) g.toJson()],
    online: widget.online,
  )..enabled = widget.visible;

  @override
  void didUpdateWidget(PermissionsTab old) {
    super.didUpdateWidget(old);
    _list.run = () => fetchGroups(widget.request);
    _list.online = widget.online;
    _list.enabled = widget.visible;
    if (!widget.online) _stopWatching();
  }

  @override
  void dispose() {
    _stopWatching();
    _list.dispose();
    super.dispose();
  }

  /// After asking, look again every few seconds: the list changes the moment the person says yes on the computer.
  void _startWatching() {
    _stopWatching();
    _watch = Timer.periodic(const Duration(seconds: 4), (_) => widget.online ? _list.reload() : null);
    _watchEnd = Timer(const Duration(minutes: 2), _stopWatching);
  }

  void _stopWatching() {
    _watch?.cancel();
    _watchEnd?.cancel();
    _watch = null;
  }

  Future<void> _ask(PermissionGroup g) async {
    setState(() => _busy = g.id);
    try {
      final m = firstOf(await widget.request(ClientMsg.requestGroup(g.id)), const {'group_request', 'error'});
      final status = m?['t'] == 'group_request' ? groupRequestStatusOf(m!['status']) : null;
      setState(() => _notes[g.id] = status != null ? describeGroupRequest(status, g.label) : (m?['t'] == 'error' ? '${m!['message']}' : 'No answer.'));
      if (status == GroupRequestStatus.asked) _startWatching();
    } catch (e) {
      if (mounted) setState(() => _notes[g.id] = failureText(e).isEmpty ? 'That did not work.' : failureText(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _list, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final c = context.c;
    final groups = _list.data;
    if (groups == null) {
      if (_list.error != null && !_list.refreshing) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorCard(error: _list.error, onRetry: _list.reload),
        );
      }
      if (!widget.online) return const DogState(scene: 'sleep', title: 'Your computer is offline', text: 'Its permissions will show here when it is back.');
      return const DogState(scene: 'sniff', live: true, title: 'Sniffing out the permissions…', text: 'Asking your computer what this phone may do.');
    }
    final off = groups.where((g) => !g.enabled).length;
    final sorted = sortGroups(groups);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'What this phone is allowed to do on your computer. '
          '${off > 0 ? '$off kind${off == 1 ? ' is' : 's are'} switched off. Ask to switch one on and approve it on the computer.' : 'Everything is allowed.'}'
          ' Change these any time on the computer in Escanor Desktop → Settings → Permissions.',
          style: TextStyle(fontSize: 13, height: 1.5, color: c.muted),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: c.surfaceCard,
            border: Border.all(color: c.hairline),
            borderRadius: BorderRadius.circular(Radii.xl),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, g) in sorted.indexed) ...[
                if (i > 0) Divider(height: 1, color: c.hairline),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: g.enabled ? c.success.withValues(alpha: 0.1) : c.canvas,
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                            child: Icon(g.enabled ? Icons.check_circle_rounded : Icons.lock_outline_rounded, size: 18, color: g.enabled ? c.success : c.muted),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(g.label, style: TextStyle(fontSize: 15, color: c.ink)),
                                Text(g.about, style: TextStyle(fontSize: 12, height: 1.35, color: c.muted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (g.enabled)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('Allowed', style: TextStyle(fontSize: 12, color: c.success)),
                            )
                          else
                            EButton(
                              label: _busy == g.id ? 'Asking…' : 'Ask to allow',
                              kind: ButtonKind.quiet,
                              onPressed: _busy == g.id || !widget.online ? null : () => _ask(g),
                            ),
                        ],
                      ),
                      if (_notes[g.id] != null && !g.enabled) Padding(padding: const EdgeInsets.only(top: 8), child: Notice(_notes[g.id]!)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
