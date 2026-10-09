import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import 'billing.dart';
import 'security.dart';

/// The account endpoints: plan and billing, privacy, workspace and team, two-step verification and deletion. The same ones the
/// website uses.

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

// -- plan and billing

Future<List<dynamic>> fetchBillingPlans() async => List<dynamic>.from(_map(await api.get('/billing/plans', auth: false))['plans'] as List? ?? const []);
Future<Map<String, dynamic>> fetchBillingSubscription() async => _map(await api.get('/billing/subscription'));
Future<List<dynamic>> fetchInvoices() async => List<dynamic>.from(_map(await api.get('/billing/invoices'))['invoices'] as List? ?? const []);

Future<Map<String, dynamic>> billingCheckout(String planId, Cycle cycle) async =>
    _map(await api.post('/billing/checkout', {'plan_id': planId, 'cycle': cycle.name}));

Future<Map<String, dynamic>> billingChangePlan(String planId) async => _map(await api.post('/billing/change-plan', {'plan_id': planId}));

/// After Razorpay says it is paid: Escanor checks the signature before it changes the plan.
Future<Map<String, dynamic>> billingVerify({required String paymentId, required String subscriptionId, required String signature}) async =>
    _map(await api.post('/billing/verify', {
      'razorpay_payment_id': paymentId,
      'razorpay_subscription_id': subscriptionId,
      'razorpay_signature': signature,
    }));

Future<void> billingCancel() => api.post('/billing/cancel');

// -- privacy

Future<List<dynamic>> fetchConsents() async => List<dynamic>.from(await api.get('/compliance/consents') as List);

Future<void> recordConsent(String purpose, bool grant, String noticeVersion) => api.post('/compliance/consents', {
      'purpose': purpose,
      'action': grant ? 'grant' : 'withdraw',
      'notice_version': noticeVersion,
      'source': 'android',
    });

Future<List<dynamic>> fetchPrivacyRequests() async => List<dynamic>.from(await api.get('/compliance/requests') as List);
Future<Map<String, dynamic>> fetchPrivacyRequest(String id) async => _map(await api.get('/compliance/requests/${enc(id)}'));
Future<Map<String, dynamic>> openPrivacyRequest({required String type, required String subject, required String details}) async =>
    _map(await api.post('/compliance/requests', {'request_type': type, 'subject': subject, 'details': details}));

Future<Map<String, dynamic>> exportMyData() async => _map(await api.get('/compliance/me/export'));

// -- workspace and team

Future<Map<String, dynamic>> fetchWorkspaceSettings() async => _map(await api.get('/workspace/settings'));
Future<void> updateWorkspaceSettings(Map<String, String> patch) => api.patch('/workspace/settings', patch);

/// The team, or null when this person may not see it (the server answers 404 to non-admins).
Future<Map<String, dynamic>?> fetchOrganization() async {
  try {
    return _map(await api.get('/admin/organization'));
  } on ApiError catch (e) {
    if (e.status == 404) return null;
    rethrow;
  }
}

Future<void> setMemberRole(String userId, String role) => api.patch('/admin/organization/members/${enc(userId)}', {'role': role});

Future<List<dynamic>> fetchAuditLogs(int limit) async => List<dynamic>.from(_map(await api.get('/audit-logs?limit=$limit'))['logs'] as List? ?? const []);

// -- two-step verification and deleting the account

Future<TwoFactorStatus> fetchTwoFactor() async => TwoFactorStatus.fromJson(_map(await api.get('/security/2fa')));
Future<({String secret, String otpauthUri})> twoFactorSetup() async {
  final r = _map(await api.post('/security/2fa/setup'));
  return (secret: '${r['secret'] ?? ''}', otpauthUri: '${r['otpauth_uri'] ?? ''}');
}

List<String> _codes(Map<String, dynamic> r) => [for (final c in (r['backup_codes'] as List? ?? const [])) '$c'];

Future<List<String>> twoFactorEnable(String code) async => _codes(_map(await api.post('/security/2fa/enable', {'code': code})));
Future<void> twoFactorDisable(String code) => api.post('/security/2fa/disable', {'code': code});
Future<List<String>> twoFactorBackupCodes(String code) async => _codes(_map(await api.post('/security/2fa/backup-codes', {'code': code})));

Future<DeletionStatus> fetchDeletionStatus() async => DeletionStatus.fromJson(_map(await api.get('/account/deletion')));
/// [code] only when two-step verification is on; without it the account email alone confirms.
Future<DeletionStatus> requestDeletion(String? code, String confirmEmail) async =>
    DeletionStatus.fromJson(_map(await api.post('/account/deletion', {'code': code ?? '', 'confirm_email': confirmEmail})));
Future<DeletionStatus> cancelDeletion() async => DeletionStatus.fromJson(_map(await api.post('/account/deletion/cancel')));

// -- links

/// The website, already signed in: a one-minute link, so a page there opens without a second sign-in.
Future<String> webHandoff(String next) async => '${_map(await api.post('/auth/handoff', {'next': next}))['url']}';

/// Open a page of the website signed in (e.g. `/dashboard/settings/billing`).
Future<void> openWebHandoff(String next) async {
  final url = await webHandoff(next);
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
    throw StateError('Could not open the website.');
  }
}

/// A link from the server (an invoice, a payment page): opened in a browser view inside the app.
Future<void> openLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) throw StateError('That link cannot be opened.');
  if (!await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) throw StateError('Could not open the link.');
  }
}
