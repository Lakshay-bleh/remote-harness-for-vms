import 'package:flutter/widgets.dart';

import 'managed.dart';

/// How the hub screens are shown: inside the signed-in app (embedded, on the Machines tab) or on their own, and
/// whether the hub is Escanor's hosted one ([managed], null on a self-hosted hub).
class HubScope extends InheritedWidget {
  const HubScope({super.key, required this.embedded, this.managed, required super.child});
  final bool embedded;
  final ManagedHub? managed;

  static HubScope? _of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HubScope>();

  /// The signed-in person's hosted hub, when the screen is showing it.
  static ManagedHub? managedOf(BuildContext context) => _of(context)?.managed;
  static bool embeddedOf(BuildContext context) => _of(context)?.embedded ?? false;

  @override
  bool updateShouldNotify(HubScope oldWidget) => embedded != oldWidget.embedded || managed != oldWidget.managed;
}
