import 'package:flutter/foundation.dart';

/// Ticks whenever the plan changes anywhere in the app (paid, switched, cancelled), so every screen that shows the plan or its
/// limits reloads instead of showing the old one (the web app's announcePlanChange / useOnPlanChange).
final planChanges = ValueNotifier<int>(0);

/// Tell every screen that shows the plan or its limits that it changed.
void announcePlanChange() => planChanges.value++;
