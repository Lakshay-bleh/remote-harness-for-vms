import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../companion/dog_state.dart';
import 'activity_label.dart';
import 'activity_paging.dart';
import 'computer_chat.dart' show ComputerRequest;
import 'error_card.dart';
import 'protocol/failure.dart';
import 'protocol/protocol.dart';
import 'remote.dart';

class ActivityPage {
  ActivityPage(this.items, this.more);
  final List<ActivityItem> items;

  /// null: an older computer that sends everything at once.
  final bool? more;

  Map<String, dynamic> toJson() => {
    'items': [for (final a in items) a.toJson()],
    'more': more,
  };
  static ActivityPage fromJson(Object? j) {
    final m = j as Map;
    return ActivityPage([for (final a in m['items'] as List) ActivityItem.fromJson(Map<String, dynamic>.from(a as Map))], m['more'] as bool?);
  }
}

Future<ActivityPage> fetchActivityPage(ComputerRequest request, [String? before]) async {
  final m = firstOf(await request(ClientMsg.activity(limit: activityPage, before: before)), const {'activity', 'error'});
  if (m?['t'] == 'activity') {
    return ActivityPage([
      for (final a in (m!['items'] as List? ?? const []))
        if (a is Map) ActivityItem.fromJson(Map<String, dynamic>.from(a)),
    ], m['more'] is bool ? m['more'] as bool : null);
  }
  throw ComputerError(m?['t'] == 'error' ? '${m!['message']}' : 'The computer did not answer.');
}

/// What phones and the voice assistant did on this computer lately, newest first. Loads a page at a time: the next page is fetched
/// when the end of the list scrolls into view, so opening this tab is quick however much has happened.
class ActivityTab extends StatefulWidget {
  const ActivityTab({super.key, required this.computerId, required this.request, required this.online, this.visible = true});
  final String computerId;
  final ComputerRequest request;
  final bool online;
  final bool visible;
  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  late final Remote<ActivityPage> _first = Remote<ActivityPage>(
    computerId: widget.computerId,
    what: 'activity',
    run: () => fetchActivityPage(widget.request),
    ttl: const Duration(seconds: 10),
    every: const Duration(seconds: 20),
    decode: ActivityPage.fromJson,
    encode: (v) => v.toJson(),
    online: widget.online,
  )..enabled = widget.visible;

  List<ActivityItem> _items = [];
  bool? _serverMore;
  int _shown = activityPage;
  bool _loadingMore = false;
  String? _moreError;

  /// Once older pages are loaded, a refresh of the first page must not reset "more".
  bool _olderLoaded = false;
  ActivityPage? _seen;

  @override
  void initState() {
    super.initState();
    _absorb();
    _first.addListener(_absorb);
  }

  void _absorb() {
    final d = _first.data;
    if (d == null || identical(d, _seen)) return;
    _seen = d;
    setState(() {
      _items = mergeActivity(_items, d.items);
      if (!_olderLoaded) _serverMore = d.more;
    });
  }

  @override
  void didUpdateWidget(ActivityTab old) {
    super.didUpdateWidget(old);
    _first.run = () => fetchActivityPage(widget.request);
    _first.online = widget.online;
    _first.enabled = widget.visible;
  }

  @override
  void dispose() {
    _first.removeListener(_absorb);
    _first.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    final step = nextStep(_items.length, _shown, _serverMore);
    if (step == NextStep.reveal) {
      setState(() => _shown += activityPage);
      return;
    }
    if (step == NextStep.done || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await fetchActivityPage(widget.request, oldest(_items));
      if (!mounted) return;
      setState(() {
        _olderLoaded = true;
        _items = mergeActivity(_items, page.items);
        _serverMore = page.more;
        _shown += activityPage;
      });
    } catch (e) {
      if (mounted) setState(() => _moreError = failureText(e).isEmpty ? 'Could not load older activity.' : failureText(e));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _first, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final c = context.c;
    if (_first.data == null && _items.isEmpty) {
      if (_first.error != null && !_first.refreshing) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorCard(error: _first.error, onRetry: _first.reload),
        );
      }
      if (!widget.online) return const DogState(scene: 'sleep', title: 'Your computer is offline', text: 'Its activity will show here when it is back.');
      return const DogState(scene: 'dig', live: true, title: 'Digging up what happened…', text: 'Asking your computer for its recent activity.');
    }
    if (_items.isEmpty) {
      return const DogState(scene: 'dig', title: 'Nothing dug up yet', text: 'Things your phone and the assistant do on this computer show up here.');
    }

    final visible = _items.take(_shown).toList();
    final hasMore = _shown < _items.length || _serverMore == true;
    // The end of the list coming near the screen (the list builds it within its cache extent) asks for the next page.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: visible.length + 1,
      itemBuilder: (context, i) {
        if (i == visible.length) {
          return Column(
            children: [
              if (_loadingMore) const DogRunner(label: 'Fetching older activity…'),
              if (_moreError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('$_moreError ', style: TextStyle(fontSize: 13, color: c.muted)),
                      GestureDetector(
                        onTap: () {
                          setState(() => _moreError = null);
                          _more();
                        },
                        child: Text(
                          'Try again',
                          style: TextStyle(fontSize: 13, color: c.primary, decoration: TextDecoration.underline, decorationColor: c.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!hasMore && _items.length > activityPage)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('That is everything.', style: TextStyle(fontSize: 12, color: c.mutedSoft)),
                ),
              if (hasMore && !_loadingMore && _moreError == null) _AutoMore(key: ValueKey('${_items.length}/$_shown'), onVisible: _more),
            ],
          );
        }
        return _Row(a: visible[i], first: i == 0);
      },
    );
  }
}

/// Asks for more once it is built: the list builds it only when its end comes near the screen.
class _AutoMore extends StatefulWidget {
  const _AutoMore({super.key, required this.onVisible});
  final VoidCallback onVisible;
  @override
  State<_AutoMore> createState() => _AutoMoreState();
}

class _AutoMoreState extends State<_AutoMore> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? widget.onVisible() : null);
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 1);
}

class _Row extends StatelessWidget {
  const _Row({required this.a, required this.first});
  final ActivityItem a;
  final bool first;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ok = a.outcome == 'ok';
    final refused = a.outcome == 'forbidden' || a.outcome == 'denied';
    final caller = a.caller.replaceFirst(RegExp(r'^phone:'), 'From ').replaceFirst(RegExp(r'^voice$'), 'Voice assistant');
    return Container(
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              ok ? Icons.check_circle_rounded : (refused ? Icons.warning_rounded : Icons.cancel_rounded),
              size: 20,
              color: ok ? c.success : (refused ? c.warning : c.error),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activityLabel(a.capabilityId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: c.ink),
                ),
                Text(
                  '$caller · ${ago(a.at)}${ok ? '' : (refused ? ' · was not allowed' : ' · did not work')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
                if (a.message != null && !ok)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      a.message!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.35, color: c.body),
                    ),
                  ),
              ],
            ),
          ),
          if (a.risk != 'read')
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: a.risk == 'destructive' ? c.error.withValues(alpha: 0.1) : c.surfaceStrong,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(a.risk == 'destructive' ? 'Deletes' : 'Changes', style: TextStyle(fontSize: 11, color: a.risk == 'destructive' ? c.error : c.muted)),
            ),
        ],
      ),
    );
  }
}
