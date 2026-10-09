/// Privacy choices and requests, as the app shows them. The wording and rules follow the website's Privacy panel, so a person sees
/// the same thing in both.
library;

/// Separate, optional consents. None is bundled into another or needed to use the service.
const optionalConsents = [
  (purpose: 'marketing', label: 'Product news and offers', description: 'Occasional emails about new features and offers. Not needed to use Escanor.'),
  (purpose: 'product_updates', label: 'Product update notices', description: 'Notices about changes to the product that are not required service messages.'),
  (purpose: 'analytics', label: 'Usage analytics', description: 'Allow measuring how features are used so they can be improved. Not needed to use Escanor.'),
  (
    purpose: 'ai_improvement',
    label: 'Use my content to improve AI features',
    description: 'Allow prompts and results to be used to evaluate and improve AI features. Off unless you turn it on.'
  ),
];

const requestTypes = [
  (value: 'access', label: 'Get a copy of my data', hint: 'You can also copy it straight from here.'),
  (value: 'correction', label: 'Correct my data', hint: 'Something about you is wrong.'),
  (value: 'consent_withdrawal', label: 'Withdraw a consent', hint: 'Or switch it off above, which takes effect at once.'),
  (value: 'nomination', label: 'Nominate someone to act for me', hint: 'Someone who may act if you cannot.'),
  (value: 'grievance', label: 'Make a complaint or report a problem', hint: 'It is tracked and answered within the legal deadline.'),
  (value: 'erasure', label: 'Delete my data (without deleting the account)', hint: 'To delete the whole account, use Delete account in Security.'),
];

String requestTypeLabel(String value) {
  for (final t in requestTypes) {
    if (t.value == value) return t.label;
  }
  return value;
}

const _statusLabels = {
  'received': 'Received',
  'acknowledged': 'Acknowledged',
  'in_progress': 'In progress',
  'escalated': 'Escalated',
  'fulfilled': 'Completed',
  'rejected': 'Declined',
};
String statusLabel(String status) => _statusLabels[status] ?? status;
bool isFinished(String status) => status == 'fulfilled' || status == 'rejected';

const _hour = 3600000;
const _day = 24 * _hour;
String _plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';

/// "due in 2 days", "due in 5 hours", "overdue by 1 day".
String describeDue(String iso, {DateTime? now}) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final diff = t.difference(now ?? DateTime.now()).inMilliseconds;
  final abs = diff.abs();
  final text = abs >= _day ? _plural(abs ~/ _day, 'day') : _plural(abs ~/ _hour < 1 ? 1 : abs ~/ _hour, 'hour');
  return diff >= 0 ? 'due in $text' : 'overdue by $text';
}

/// The first thing wrong with a request, in words, or null. The limits are the server's (subject 3 to 200 characters, details up
/// to 5000).
String? requestProblem({required String subject, required String details}) {
  final s = subject.trim();
  if (s.length < 3) return 'Give it a short title (at least 3 characters).';
  if (s.length > 200) return 'Make the title shorter (200 characters at most).';
  if (details.length > 5000) return 'The details are too long (5,000 characters at most).';
  return null;
}

class RequestEvent {
  const RequestEvent({this.fromStatus, required this.toStatus, this.note, required this.createdAt});
  final String? fromStatus;
  final String toStatus;
  final String? note;
  final String createdAt;
}

class PrivacyRequest {
  const PrivacyRequest({
    required this.id,
    required this.reference,
    required this.requestType,
    required this.status,
    required this.subject,
    this.receivedAt = '',
    this.acknowledgeBy = '',
    this.resolveBy = '',
    this.resolutionNote,
    this.events = const [],
  });
  final String id;
  final String reference;
  final String requestType;
  final String status;
  final String subject;
  final String receivedAt;
  final String acknowledgeBy;
  final String resolveBy;
  final String? resolutionNote;
  final List<RequestEvent> events;

  /// The deadline that matters now: acknowledging a new request, then resolving it.
  String get nextDue => status == 'received' ? acknowledgeBy : resolveBy;

  factory PrivacyRequest.fromJson(Map<String, dynamic> j) => PrivacyRequest(
        id: '${j['id'] ?? ''}',
        reference: '${j['reference'] ?? ''}',
        requestType: '${j['request_type'] ?? ''}',
        status: '${j['status'] ?? ''}',
        subject: '${j['subject'] ?? ''}',
        receivedAt: '${j['received_at'] ?? ''}',
        acknowledgeBy: '${j['acknowledge_by'] ?? ''}',
        resolveBy: '${j['resolve_by'] ?? ''}',
        resolutionNote: j['resolution_note'] as String?,
        events: j['events'] is List
            ? [
                for (final e in (j['events'] as List).whereType<Map>())
                  RequestEvent(
                    fromStatus: e['from_status'] as String?,
                    toStatus: '${e['to_status'] ?? ''}',
                    note: e['note'] as String?,
                    createdAt: '${e['created_at'] ?? ''}',
                  ),
              ]
            : const [],
      );
}
