import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/load.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../settings/settings_widgets.dart' show shortDate;
import 'account_api.dart';
import 'security.dart';

/// An account waiting to be deleted is shown over everything, with the way to keep it.
///
/// Placed as a direct child of the shell's Stack. Nothing scheduled: [otherwise] (the Terms gate in the shell), else nothing. Reads
/// the deletion status once on start, again when the app comes back to the foreground, and after the deletion is cancelled.
class DeletionNotice extends ConsumerStatefulWidget {
  const DeletionNotice({super.key, this.otherwise});

  /// Shown when no deletion is scheduled (or while that is not known yet).
  final Widget? otherwise;
  @override
  ConsumerState<DeletionNotice> createState() => _DeletionNoticeState();
}

class _DeletionNoticeState extends ConsumerState<DeletionNotice> {
  final _status = Loader<DeletionStatus?>(() => fetchDeletionStatus().then<DeletionStatus?>((s) => s).catchError((_) => null));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  Future<void> _keep() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await cancelDeletion();
      _status.reload();
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, 'Could not cancel.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _status,
      builder: (context, _) {
        final s = _status.data;
        if (s == null || !s.scheduled) return widget.otherwise ?? const SizedBox.shrink();
        final c = context.c;
        final when = s.scheduledFor;
        final date = when == null ? '' : shortDate(when);
        return Positioned.fill(
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            label: 'Account scheduled for deletion',
            child: Material(
              color: c.canvas,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 384),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.warning_rounded, size: 40, color: c.warning),
                        const SizedBox(height: 16),
                        Text(
                          'Your account will be deleted ${when != null ? daysUntil(when) : 'soon'}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 24, height: 1.25, color: c.ink, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'You asked to delete it${date.isNotEmpty ? ', due on $date' : ''}. Until then you can keep it by cancelling the deletion.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, height: 1.5, color: c.body),
                        ),
                        if (_error != null) ...[const SizedBox(height: 16), Notice(_error!, tone: NoticeTone.error)],
                        const SizedBox(height: 16),
                        EButton(label: _busy ? 'Cancelling…' : 'Keep my account', expand: true, onPressed: _busy ? null : _keep),
                        const SizedBox(height: 12),
                        EButton(
                          label: 'Sign out',
                          kind: ButtonKind.quiet,
                          expand: true,
                          onPressed: () => ref.read(sessionProvider.notifier).signOut(),
                        ),
                      ]),
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
