/// Where the person is in switching on phone control, one step at a time, each asked for and none skipped. Pure.
library;

import 'actions.dart';

/// - notInBuild: this download leaves phone control out (see the "with phone control" APK)
/// - disclosure: say in the app what it can see and do, and wait for "I agree" (Google Play requires this before Accessibility)
/// - restricted: Android 13+ greys the switch out for apps installed from a file until the person allows it in App info
/// - turnOn: send them to Accessibility settings to switch Escanor on themselves
/// - on: done
enum ControlStep { checking, notInBuild, disclosure, restricted, turnOn, on }

ControlStep controlStep(ControlStatus? status, bool consented) {
  if (status == null) return ControlStep.checking;
  if (status.enabled) return ControlStep.on;
  if (status.available == false) return ControlStep.notInBuild;
  if (!consented) return ControlStep.disclosure;
  if (status.restricted == true) return ControlStep.restricted;
  return ControlStep.turnOn;
}
