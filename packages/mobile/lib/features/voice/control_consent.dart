import '../../core/api.dart';
import '../../core/storage.dart';
import '../settings/legal_content.dart' show policyVersion; // the privacy notice the consent refers to
import 'voice_prefs.dart';

const _pending = 'escanor.controlConsent.pending';

/// The ledger knows web, android and desktop; phone control only exists on Android.
String _source() => 'android';

/// The consent ledger: POST /compliance/consents (purpose phone_control).
Future<Object?> recordPhoneControlConsent(bool grant) => api.post('/compliance/consents', {
      'purpose': 'phone_control',
      'action': grant ? 'grant' : 'withdraw',
      'notice_version': policyVersion,
      'source': _source(),
    });

/// Send the latest phone-control choice to the consent ledger. A choice that could not be sent waits here for the next try.
Future<void> _send(bool grant, Future<Object?> Function(bool grant) record) async {
  try {
    await record(grant);
    await Storage.instance.remove(_pending);
  } catch (_) {
    try {
      await Storage.instance.setString(_pending, grant ? 'grant' : 'withdraw');
    } catch (_) {
      // kept for this visit only
    }
  }
}

/// The person agreed to (or took back) phone control: remember it on the phone at once, and in their account's consent ledger.
Future<void> setControlConsent(bool grant, [Future<Object?> Function(bool grant) record = recordPhoneControlConsent]) {
  setVoicePrefs((p) => p.copyWith(controlConsent: grant));
  return _send(grant, record);
}

/// Send a choice that could not be sent before (offline, signed out). Does nothing when none is waiting.
Future<void> flushControlConsent([Future<Object?> Function(bool grant) record = recordPhoneControlConsent]) async {
  String? pending;
  try {
    pending = Storage.instance.getString(_pending);
  } catch (_) {
    return;
  }
  if (pending == 'grant' || pending == 'withdraw') await _send(pending == 'grant', record);
}

/// Is a choice waiting to be sent? (For tests.)
bool controlConsentPending() {
  try {
    return Storage.instance.getString(_pending) != null;
  } catch (_) {
    return false;
  }
}
