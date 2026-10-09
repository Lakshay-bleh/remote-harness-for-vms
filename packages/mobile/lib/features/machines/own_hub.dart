import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'hub_app.dart';
import 'machines_start.dart';

/// CONTRACT: the Remote Harness on the person's own hub, used without an Escanor account.
class OwnHub extends StatelessWidget {
  const OwnHub({super.key, required this.onBack});
  final VoidCallback onBack;

  /// True when this phone only ever used its own hub (signed in to a hub, never to Escanor, and not Escanor's hosted
  /// hub). Someone like that keeps landing there.
  static bool startsHere() => ownHubStartsHere();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.c.canvas,
        body: SafeArea(child: HubApp(onBack: onBack)),
      );
}
