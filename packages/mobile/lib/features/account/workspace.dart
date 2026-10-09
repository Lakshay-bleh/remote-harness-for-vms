/// Workspace and team presentation, pure so it can be tested.
library;

const regions = [
  (value: 'auto', label: 'Automatic'),
  (value: 'us-east', label: 'US East'),
  (value: 'us-west', label: 'US West'),
  (value: 'eu-west', label: 'Europe West'),
  (value: 'ap-south', label: 'India and South Asia'),
  (value: 'ap-southeast', label: 'Southeast Asia'),
];

const environments = [
  (value: 'production', label: 'Production'),
  (value: 'staging', label: 'Staging'),
  (value: 'development', label: 'Development'),
];

String _label(List<({String value, String label})> list, String v) {
  for (final o in list) {
    if (o.value == v) return o.label;
  }
  return v;
}

String regionLabel(String v) => _label(regions, v);
String environmentLabel(String v) => _label(environments, v);

/// A workspace name as the server will accept it: one line, 1 to 80 characters. Null when it is not usable.
String? cleanWorkspaceName(String text) {
  final name = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return name.isNotEmpty && name.length <= 80 ? name : null;
}

/// "workspace.settings_updated" -> "Workspace settings updated"; unknown shapes stay readable.
String describeAction(String action) {
  final words = action.replaceAll(RegExp(r'[._]+'), ' ').trim();
  return words.isNotEmpty ? words[0].toUpperCase() + words.substring(1) : 'Activity';
}

String roleLabel(String role) => role == 'owner' ? 'Owner' : (role == 'admin' ? 'Admin' : 'Member');

const activityPage = 25;
const activityMax = 500; // what the server will return

/// The part of an action before the first dot: "billing.plan_changed" is "billing".
String actionGroup(String action) {
  final first = action.split('.').first;
  return (first.isEmpty ? 'other' : first).toLowerCase();
}

class AuditLine {
  const AuditLine({this.id, this.createdAt = '', this.actorEmail, required this.action, this.target = '', this.status = '', this.detail = ''});
  final String? id;
  final String createdAt;
  final String? actorEmail;
  final String action;
  final String target;
  final String status;
  final String detail;
  factory AuditLine.fromJson(Map<String, dynamic> j) => AuditLine(
        id: j['id'] as String?,
        createdAt: '${j['created_at'] ?? ''}',
        actorEmail: j['actor_email'] as String?,
        action: '${j['action'] ?? ''}',
        target: '${j['target'] ?? ''}',
        status: '${j['status'] ?? ''}',
        detail: '${j['detail'] ?? ''}',
      );
}

/// The kinds of activity present in a list, most frequent first, for the filter chips.
List<({String value, String label, int count})> activityGroups(Iterable<AuditLine> lines) {
  final counts = <String, int>{};
  for (final l in lines) {
    final g = actionGroup(l.action);
    counts[g] = (counts[g] ?? 0) + 1;
  }
  final list = counts.entries.toList()..sort((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
  return [for (final e in list) (value: e.key, label: describeAction(e.key), count: e.value)];
}

/// Lines of one kind (or all), whose action, person, target or detail contains the text.
List<AuditLine> filterActivity(Iterable<AuditLine> lines, {String? group, String query = ''}) {
  final q = query.trim().toLowerCase();
  return lines
      .where((l) =>
          (group == null || actionGroup(l.action) == group) &&
          (q.isEmpty || [describeAction(l.action), l.actorEmail, l.target, l.detail].any((f) => (f ?? '').toLowerCase().contains(q))))
      .toList();
}

/// Whether asking for more could return more: the last answer filled the request and the server's ceiling is not reached.
bool canLoadMore(int received, int asked) => received >= asked && asked < activityMax;
int nextActivityLimit(int asked) => asked + activityPage * 2 > activityMax ? activityMax : asked + activityPage * 2;

class WorkspaceSettings {
  const WorkspaceSettings({
    this.organizationName = '',
    required this.workspaceName,
    this.defaultRegion = 'auto',
    this.environment = 'production',
    this.sessionTimeout = '',
    this.twoFactorEnabled = false,
    this.connectedDevices = 0,
  });
  final String organizationName;
  final String workspaceName;
  final String defaultRegion;
  final String environment;
  final String sessionTimeout;
  final bool twoFactorEnabled;
  final int connectedDevices;
  factory WorkspaceSettings.fromJson(Map<String, dynamic> j) => WorkspaceSettings(
        organizationName: '${j['organization_name'] ?? ''}',
        workspaceName: '${j['workspace_name'] ?? ''}',
        defaultRegion: '${j['default_region'] ?? 'auto'}',
        environment: '${j['environment'] ?? 'production'}',
        sessionTimeout: '${j['session_timeout'] ?? ''}',
        twoFactorEnabled: j['two_factor_enabled'] == true,
        connectedDevices: (j['connected_devices'] as num?)?.toInt() ?? 0,
      );
}

class OrgMember {
  const OrgMember({required this.userId, required this.email, this.name = '', this.role = 'member', this.joinedAt});
  final String userId;
  final String email;
  final String name;
  final String role;
  final String? joinedAt;
  factory OrgMember.fromJson(Map<String, dynamic> j) => OrgMember(
        userId: '${j['user_id'] ?? ''}',
        email: '${j['email'] ?? ''}',
        name: '${j['name'] ?? ''}',
        role: '${j['role'] ?? 'member'}',
        joinedAt: j['joined_at'] as String?,
      );
}

class Organization {
  const Organization({required this.yourRole, required this.members});
  final String yourRole;
  final List<OrgMember> members;
  factory Organization.fromJson(Map<String, dynamic> j) => Organization(
        yourRole: '${j['your_role'] ?? 'member'}',
        members: j['members'] is List ? [for (final m in (j['members'] as List).whereType<Map>()) OrgMember.fromJson(Map<String, dynamic>.from(m))] : const [],
      );
}
