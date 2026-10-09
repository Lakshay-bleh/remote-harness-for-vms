import 'package:flutter/foundation.dart';

/// How many things are loading right now, anywhere in the app. The companion runs while this is above
/// zero, so the whole app has one honest "working on it" signal. Count a load with [trackBusy].
final ValueNotifier<int> busyCount = ValueNotifier<int>(0);

void Function() beginBusy() {
  busyCount.value += 1;
  var done = false;
  return () {
    if (done) return;
    done = true;
    busyCount.value = busyCount.value > 0 ? busyCount.value - 1 : 0;
  };
}

/// Counts [work] as busy until it settles, and hands its result (or error) through untouched.
Future<T> trackBusy<T>(Future<T> work) {
  final end = beginBusy();
  return work.whenComplete(end);
}
