import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../companion/dog_state.dart';
import 'computer_chat.dart' show ComputerRequest;
import 'error_card.dart';
import 'protocol/client.dart';
import 'protocol/failure.dart';
import 'protocol/protocol.dart';
import 'remote.dart';

String _gb(num n) => '${(n / pow(1024, 3)).toStringAsFixed(1)} GB';
final _rand = Random();
String _uid() => List.generate(8, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[_rand.nextInt(36)]).join();

num _n(Object? v) => v is num ? v : 0;
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

/// One reading: the computer's `system.stats` and its busiest programs, as JSON (so it is remembered as it came).
class Reading {
  Reading(this.stats, this.procs);
  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> procs;
  Map<String, dynamic> toJson() => {'stats': stats, 'procs': procs};
  static Reading fromJson(Object? j) {
    final m = _m(j);
    if (m['stats'] is! Map) throw const FormatException('no stats');
    return Reading(_m(m['stats']), [for (final p in (m['procs'] is List ? m['procs'] as List : const [])) _m(p)]);
  }
}

/// Ask for both at the same moment, so over the cloud they travel together.
Future<Reading> readResources(ComputerRequest request) async {
  final both = await Future.wait([
    request(ClientMsg.call(_uid(), 'system.stats')),
    request(ClientMsg.call(_uid(), 'system.processes', {'limit': 6})),
  ]);
  final sr = firstOf(both[0], const {'result'});
  final pr = firstOf(both[1], const {'result'});
  if (sr == null || sr['ok'] != true) {
    throw ComputerError(sr != null ? '${_m(sr['error'])['message'] ?? 'The computer could not read itself.'}' : 'No answer.');
  }
  final procs = pr != null && pr['ok'] == true && pr['result'] is List ? [for (final p in pr['result'] as List) _m(p)] : <Map<String, dynamic>>[];
  return Reading(_m(sr['result']), procs);
}

/// CPU, memory, storage and the busiest programs. Shows the last reading at once, then keeps it fresh: quickly over Wi-Fi, gently
/// over the cloud.
class ResourcesTab extends StatefulWidget {
  const ResourcesTab({super.key, required this.computerId, required this.request, required this.online, required this.route, this.visible = true});
  final String computerId;
  final ComputerRequest request;
  final bool online;
  final ComputerRoute? route;
  final bool visible;
  @override
  State<ResourcesTab> createState() => _ResourcesTabState();
}

class _ResourcesTabState extends State<ResourcesTab> {
  late final Remote<Reading> _r = Remote<Reading>(
    computerId: widget.computerId,
    what: 'stats',
    run: () => readResources(widget.request),
    ttl: const Duration(seconds: 3),
    every: _every,
    deadline: const Duration(seconds: 25),
    decode: Reading.fromJson,
    encode: (v) => v.toJson(),
    online: widget.online,
  )..enabled = widget.visible;

  Duration get _every => widget.route == ComputerRoute.lan ? const Duration(seconds: 3) : const Duration(seconds: 9);

  @override
  void didUpdateWidget(ResourcesTab old) {
    super.didUpdateWidget(old);
    _r.run = () => readResources(widget.request);
    _r.every = _every;
    _r.online = widget.online;
    _r.enabled = widget.visible;
  }

  @override
  void dispose() {
    _r.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _r, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final c = context.c;
    final data = _r.data;
    if (data == null) {
      if (_r.error != null && !_r.refreshing) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorCard(error: _r.error, onRetry: _r.reload),
        );
      }
      if (!widget.online) return const DogState(scene: 'sleep', title: 'Your computer is offline', text: 'Its numbers will show here when it is back.');
      return const DogState(scene: 'run', live: true, title: 'Reading your computer…', text: 'Fetching its CPU, memory and storage.');
    }
    final s = data.stats;
    final cpu = _m(s['cpu']);
    final mem = _m(s['mem']);
    final disks = s['disks'] is List ? [for (final d in s['disks'] as List) _m(d)] : <Map<String, dynamic>>[];
    final battery = s['battery'] is Map ? _m(s['battery']) : null;
    final temp = s['tempC'] is num ? s['tempC'] as num : null;
    final memPct = _n(mem['total']) > 0 ? _n(mem['used']) / _n(mem['total']) * 100 : 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _Panel(
          label: 'CPU',
          value: '${_n(cpu['load']).toStringAsFixed(0)}%',
          meter: _n(cpu['load']).toDouble(),
          footer: '${cpu['model'] ?? ''} · ${cpu['cores'] ?? '?'} threads${temp != null && temp != 0 ? ' · ${temp.toStringAsFixed(0)}°C' : ''}',
        ),
        const SizedBox(height: 16),
        _Panel(label: 'Memory', value: '${_gb(_n(mem['used']))} of ${_gb(_n(mem['total']))}', meter: memPct.toDouble()),
        if (disks.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Panel(
            label: 'Storage',
            value: '${_gb(_n(disks.first['used']))} of ${_gb(_n(disks.first['size']))}',
            meter: _n(disks.first['usePercent']).toDouble(),
          ),
        ],
        if (battery != null) ...[
          const SizedBox(height: 16),
          Text('Battery ${_n(battery['percent']).round()}%${battery['charging'] == true ? ', charging' : ''}', style: TextStyle(fontSize: 14, color: c.body)),
        ],
        if (data.procs.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: c.surfaceCard,
              border: Border.all(color: c.hairline),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'BUSIEST PROGRAMS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.6, color: c.muted),
                  ),
                ),
                for (final (i, p) in data.procs.indexed) ...[
                  if (i > 0) Divider(height: 1, color: c.hairline),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${p['name'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: c.ink),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_n(p['cpu']).toStringAsFixed(1)}% · ${(_n(p['memBytes']) / pow(1024, 2)).toStringAsFixed(0)} MB',
                          style: TextStyle(fontSize: 14, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (_r.stale)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Showing the last reading while it updates…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: c.mutedSoft),
            ),
          ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.label, required this.value, required this.meter, this.footer});
  final String label;
  final String value;
  final double meter;
  final String? footer;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final v = meter.clamp(0, 100).toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceCard,
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 14, color: c.body)),
              ),
              Text(
                value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.ink),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            value: '${v.round()}%',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: v / 100),
                duration: const Duration(milliseconds: 500),
                builder: (_, t, _) =>
                    LinearProgressIndicator(value: t, minHeight: 8, backgroundColor: c.canvas, color: v > 90 ? c.error : (v > 75 ? c.permission : c.primary)),
              ),
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(
              footer!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }
}
