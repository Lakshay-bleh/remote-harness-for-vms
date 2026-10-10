/// Two-step verification and deleting an account: the rules the screens follow, kept where they can be tested.
library;

/// A code as typed: six digits (spaces are fine), or a backup code like ABCD-EFGH. Returns what to send, or null if it is neither.
String? parseCodeInput(String text) {
  final digits = text.replaceAll(RegExp(r'\s+'), '');
  if (RegExp(r'^\d{6}$').hasMatch(digits)) return digits;
  final backup = text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return RegExp(r'^[A-Z2-9]{8}$').hasMatch(backup) ? '${backup.substring(0, 4)}-${backup.substring(4)}' : null;
}

/// Typing the account email is the "are you sure": exact, but not fussy about case or stray spaces.
bool emailConfirmed(String typed, String? email) =>
    email != null && email.isNotEmpty && typed.trim().toLowerCase() == email.trim().toLowerCase();

/// "in 6 days", "in 5 hours", "now": how long until the date, for "your account will be deleted …".
String daysUntil(String iso, {DateTime? now}) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final diff = t.difference(now ?? DateTime.now()).inMilliseconds;
  if (diff <= 0) return 'now';
  final days = diff ~/ 86400000;
  if (days >= 1) return 'in $days day${days == 1 ? '' : 's'}';
  final h = diff ~/ 3600000;
  final hours = h < 1 ? 1 : h;
  return 'in $hours hour${hours == 1 ? '' : 's'}';
}

/// The setup key in groups of four, easier to type: "ABCD EFGH IJKL".
String groupKey(String secret) {
  final parts = <String>[];
  for (var i = 0; i < secret.length; i += 4) {
    parts.add(secret.substring(i, i + 4 > secret.length ? secret.length : i + 4));
  }
  return parts.join(' ');
}

/// The backup codes as a text file the person keeps.
String backupCodesText(List<String> codes) => 'Escanor backup codes (each works once)\n\n${codes.join('\n')}\n';

/// What the server does, said before they confirm: shown as the list on the delete screen.
const deletionFacts = [
  'You are signed out everywhere and every key you made stops working straight away.',
  'Any paid plan stops renewing now. After 7 days your account and everything in it is deleted: connected services, chats, machines and keys.',
  'If you sign in during those 7 days you can cancel the deletion.',
  'A few records are kept because the law asks for them: your name, email and sign-up date for 180 days, payment records, and your consent and request history without your contact details.',
];

class TwoFactorStatus {
  const TwoFactorStatus({required this.enabled, this.enrolledAt, this.backupCodesLeft = 0});
  final bool enabled;
  final String? enrolledAt;
  final int backupCodesLeft;
  factory TwoFactorStatus.fromJson(Map<String, dynamic> j) => TwoFactorStatus(
        enabled: j['enabled'] == true,
        enrolledAt: j['enrolled_at'] as String?,
        backupCodesLeft: (j['backup_codes_left'] as num?)?.toInt() ?? 0,
      );
}

class DeletionStatus {
  const DeletionStatus({required this.scheduled, this.requestedAt, this.scheduledFor, this.graceDays = 7, this.twoFactorEnabled = false, this.reference});
  final bool scheduled;
  final String? requestedAt;
  final String? scheduledFor;
  final int graceDays;
  final bool twoFactorEnabled;
  final String? reference;
  factory DeletionStatus.fromJson(Map<String, dynamic> j) => DeletionStatus(
        scheduled: j['scheduled'] == true,
        requestedAt: j['requested_at'] as String?,
        scheduledFor: j['scheduled_for'] as String?,
        graceDays: (j['grace_days'] as num?)?.toInt() ?? 7,
        twoFactorEnabled: j['two_factor_enabled'] == true,
        reference: j['reference'] as String?,
      );
}
