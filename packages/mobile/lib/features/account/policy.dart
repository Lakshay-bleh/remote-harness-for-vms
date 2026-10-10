/// Terms and Privacy acceptance at the current policy version, and the reminder of the rules every three months (the web app's
/// account/policy.ts). Pure, so the rules are tested.
library;

/// One consent record from GET /compliance/consents.
class ConsentState {
  const ConsentState({required this.purpose, required this.granted, required this.noticeVersion, required this.recordedAt});
  final String purpose;
  final bool granted;
  final String noticeVersion;

  /// ISO 8601.
  final String recordedAt;

  factory ConsentState.fromJson(Object? json) {
    final j = json is Map ? json : const {};
    String str(Object? v) => v is String ? v : (v == null ? '' : '$v');
    return ConsentState(purpose: str(j['purpose']), granted: j['granted'] == true, noticeVersion: str(j['notice_version']), recordedAt: str(j['recorded_at']));
  }
}

/// Both must be on record, granted, at the current version.
const acceptancePurposes = ['terms', 'privacy_notice'];
const rulesNoticeEvery = Duration(days: 90);

/// True until both acceptance records exist at the current policy version or a newer one. Versions are dates (YYYY-MM-DD), so
/// they order as strings. A newer one counts because the website, the desktop app and this app write the same records: if only
/// the exact version counted, two apps on different versions would each ask again after the other had recorded its own.
bool needsAcceptance(List<ConsentState> states, String version) => acceptancePurposes.any((purpose) {
      final found = states.where((s) => s.purpose == purpose).firstOrNull;
      return found == null || !found.granted || found.noticeVersion.compareTo(version) < 0;
    });

/// The IT Rules ask that people are reminded of the rules at least every three months.
bool needsRulesNotice(List<ConsentState> states, [DateTime? now]) {
  final found = states.where((s) => s.purpose == 'rules_notice').firstOrNull;
  if (found == null) return true;
  final at = DateTime.tryParse(found.recordedAt);
  if (at == null) return true;
  return (now ?? DateTime.now()).difference(at) > rulesNoticeEvery;
}
