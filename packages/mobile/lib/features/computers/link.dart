import 'dart:math';

import 'protocol/client.dart';
import 'protocol/failure.dart';

/// When a computer that was "offline" should be tried again, and when a failed request should count as offline at all. Pure, so it
/// is tested without a phone: the two things that made a computer that was in fact on look offline were a single failed request
/// flipping the screen, and nothing ever trying again afterwards.

/// Milliseconds to wait before retry number [attempt] (1, 2, 3, …): quick at first, then a calm 30 s.
int retryDelayMs(int attempt) => min(30000, 3000 * pow(2, max(0, attempt - 1)).toInt());

/// A request that fails once is a hiccup (a slow poll, a changing network); two in a row means the computer is not answering.
const offlineAfterFailures = 2;

bool shouldShowOffline(int consecutiveFailures) => consecutiveFailures >= offlineAfterFailures;

/// What to tell the person when the computer could not be reached, in words that point at the likely cause.
String offlineMessage(Object? reason, ComputerRoute? route) {
  final text = reason == null ? '' : failureText(reason);
  if (RegExp('session|sign in', caseSensitive: false).hasMatch(text)) return text;
  if (route == ComputerRoute.cloud || RegExp('did not answer|offline|online', caseSensitive: false).hasMatch(text)) {
    return 'Your computer did not answer. Check that Escanor Desktop is open and signed in, with “Away from home” on. This page keeps trying.';
  }
  return text.isNotEmpty ? text : 'Could not reach this computer. This page keeps trying.';
}
