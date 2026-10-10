import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/load.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import 'hub_app.dart';
import 'hub_state.dart';
import 'hub_store.dart';
import 'machines_home.dart';
import 'machines_start.dart';
import 'managed.dart';

/// CONTRACT: the Machines tab for someone signed in to Escanor (ManagedMachines.tsx). The hub address and their token
/// come from Escanor (created for them the first time), so there is no hub to deploy and no password to type. When
/// this Escanor has no hosted hub, the person's own hub is shown instead.
class MachinesScreen extends ConsumerStatefulWidget {
  const MachinesScreen({super.key});

  @override
  ConsumerState<MachinesScreen> createState() => _MachinesScreenState();
}

class _MachinesScreenState extends ConsumerState<MachinesScreen> {
  final store = HubStore.instance;

  // Never cached: it carries the person's hub token.
  late final Loader<ManagedHub> _hub = Loader(() => api.managedHub());
  StreamSubscription<void>? _unauthorized;
  ManagedHub? _applied;
  bool _ready = false;
  String? _applyError;

  @override
  void initState() {
    super.initState();
    _hub.addListener(_onHub);
    // The hub refused our token (it was rotated elsewhere): ask Escanor for the current one.
    _unauthorized = store.managedUnauthorized.listen((_) => _hub.reload());
    _onHub();
  }

  @override
  void dispose() {
    _unauthorized?.cancel();
    _hub.removeListener(_onHub);
    _hub.dispose();
    super.dispose();
  }

  void _onHub() {
    final hub = _hub.data;
    if (hub != null && hub.available && !identical(hub, _applied)) {
      _applied = hub;
      final creds = store.api.credentials;
      final prevHub = creds.hubUrl;
      final prevToken = creds.token;
      try {
        applyManaged(hub, creds);
        _applyError = null;
      } catch (e) {
        _applyError = errorText(e);
        if (mounted) setState(() {});
        return;
      }
      if (store.state.authed && prevHub != creds.hubUrl) {
        // Another hub entirely: nothing of the last one may stay on screen.
        store.dispatch(const SetAuthed(false));
        store.dispatch(const SetAuthed(true));
      } else if (store.state.authed && prevToken != creds.token) {
        // A rotated token means the open connection is dead; starting it over is the simplest way to be sure.
        unawaited(store.restart());
      } else {
        store.dispatch(const SetAuthed(true));
      }
      _ready = true;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionProvider, (prev, next) {
      if (next.status == SessionStatus.signedOut) machinesSignedOut();
    });
    final c = context.c;
    final hub = _hub.data;
    // The Servers half of the Machines tab has the tab's header; Add comes from the server list once there is a hub.
    final half = MachinesHalf.of(context);
    if (hub != null && !hub.available) {
      MachinesHalf.offerAdd(context, null);
      return const HubApp(embedded: true);
    }
    final error = _applyError ?? (hub == null ? _hub.error : null);
    if (error != null) {
      MachinesHalf.offerAdd(context, null);
      return Material(
        color: c.canvas,
        child: Column(children: [
          if (!half) const ScreenHeader(title: 'Servers'),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Notice(error, tone: NoticeTone.error),
                  const SizedBox(height: 12),
                  EButton(
                    label: 'Try again',
                    kind: ButtonKind.quiet,
                    onPressed: () {
                      _applied = null;
                      setState(() => _applyError = null);
                      _hub.reload();
                    },
                  ),
                ]),
              ),
            ),
          ),
        ]),
      );
    }
    if (!_ready || hub == null) {
      MachinesHalf.offerAdd(context, null);
      return Material(
        color: c.canvas,
        child: Column(children: [if (!half) const ScreenHeader(title: 'Servers'), const Expanded(child: Center(child: Spinner()))]),
      );
    }
    return HubApp(embedded: true, managed: hub);
  }
}
