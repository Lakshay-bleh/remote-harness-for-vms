/// Settings: the small rules behind the screens, kept apart so they can be tested.
library;

/// "api.escanor.in" from the full address.
String hostOf(String url) {
  final u = Uri.tryParse(url);
  return u == null || u.host.isEmpty ? url : (u.hasPort ? '${u.host}:${u.port}' : u.host);
}

/// The health check lives beside the API, not under it.
Uri healthUri(String apiBase) => Uri.parse('${apiBase.replaceAll(RegExp(r'/api/v1/?$'), '')}/health');

/// The result of "Test connection", in words.
String checkText({required bool ok, required int ms, required int status}) =>
    ok ? 'Reachable · $ms ms' : (status != 0 ? 'Error $status' : 'Cannot reach it');

/// What to paste when asking for help. Never contains passwords or tokens.
String debugInfo({
  required String version,
  required String platform,
  required String server,
  required bool signedIn,
  required int computers,
  required String screen,
  String? os,
  required DateTime now,
}) =>
    [
      'Escanor app $version',
      'Platform: $platform',
      'Server: $server',
      'Signed in: ${signedIn ? 'yes' : 'no'}',
      'Paired computers: $computers',
      'Screen: $screen',
      if (os != null) 'OS: $os',
      'Time: ${now.toUtc().toIso8601String()}',
    ].join('\n');

/// A name typed in a sheet: one line, spaces tidied.
String cleanName(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The profile name, or why it cannot be saved.
({String? name, String? problem}) checkProfileName(String text) {
  final next = cleanName(text);
  if (next.isEmpty) return (name: null, problem: 'Please enter a name.');
  if (next.length > 80) return (name: null, problem: 'A name can be up to 80 characters.');
  return (name: next, problem: null);
}

/// A key for another AI app, as listed.
class McpConnection {
  const McpConnection({
    required this.id,
    required this.name,
    this.tokenPrefix = '',
    this.createdAt = '',
    this.lastUsedAt,
    this.revokedAt,
    this.totalCalls = 0,
    this.managedBy,
  });
  final String id;
  final String name;
  final String tokenPrefix;
  final String createdAt;
  final String? lastUsedAt;
  final String? revokedAt;
  final int totalCalls;
  final String? managedBy;

  factory McpConnection.fromJson(Map<String, dynamic> j) => McpConnection(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        tokenPrefix: '${j['token_prefix'] ?? ''}',
        createdAt: '${j['created_at'] ?? ''}',
        lastUsedAt: j['last_used_at'] as String?,
        revokedAt: j['revoked_at'] as String?,
        totalCalls: (j['total_calls'] as num?)?.toInt() ?? 0,
        managedBy: j['managed_by'] as String?,
      );
}

/// The keys the person made for other AI apps: not revoked, and not ones Escanor manages itself.
List<McpConnection> appKeys(Iterable<McpConnection> all) =>
    all.where((c) => (c.revokedAt == null || c.revokedAt!.isEmpty) && (c.managedBy == null || c.managedBy!.isEmpty)).toList();

/// A freshly made key: shown once.
class McpInstall {
  const McpInstall({required this.endpoint, required this.token, this.cliCommand = '', this.tokenId});
  final String endpoint;
  final String token;
  final String cliCommand;
  final String? tokenId;
  factory McpInstall.fromJson(Map<String, dynamic> j) => McpInstall(
        endpoint: '${j['endpoint'] ?? ''}',
        token: '${j['token'] ?? ''}',
        cliCommand: '${j['cli_command'] ?? ''}',
        tokenId: j['token_id'] as String?,
      );
}

/// What Escanor may tell this person about. The same switches as on the website.
class NotificationPrefs {
  const NotificationPrefs({
    this.pushEnabled = true,
    this.emergencyAlerts = true,
    this.serverDown = true,
    this.deploymentApprovals = true,
    this.teamPings = true,
    this.checks = true,
    this.machineChats = true,
  });
  final bool pushEnabled;
  final bool emergencyAlerts;
  final bool serverDown;
  final bool deploymentApprovals;
  final bool teamPings;
  final bool checks;
  final bool machineChats;

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) => NotificationPrefs(
        pushEnabled: j['push_enabled'] != false,
        emergencyAlerts: j['emergency_alerts'] != false,
        serverDown: j['server_down'] != false,
        deploymentApprovals: j['deployment_approvals'] != false,
        teamPings: j['team_pings'] != false,
        checks: j['checks'] != false,
        machineChats: j['machine_chats'] != false,
      );

  Map<String, dynamic> toJson() => {
        'push_enabled': pushEnabled,
        'emergency_alerts': emergencyAlerts,
        'server_down': serverDown,
        'deployment_approvals': deploymentApprovals,
        'team_pings': teamPings,
        'checks': checks,
        'machine_chats': machineChats,
      };

  bool operator [](String key) => toJson()[key] == true;

  NotificationPrefs merge(Map<String, bool> patch) => NotificationPrefs.fromJson({...toJson(), ...patch});
}

const notificationKinds = [
  (key: 'emergency_alerts', label: 'Emergency alerts', sub: 'Something serious needs you right now'),
  (key: 'server_down', label: 'Machine or server down', sub: 'A computer or server stopped responding'),
  (key: 'deployment_approvals', label: 'Approvals needed', sub: 'The assistant wants your OK before it deploys or changes something'),
  (key: 'team_pings', label: 'Team messages', sub: 'A teammate sent you a note'),
  (key: 'checks', label: 'Automatic checks', sub: 'A deployment failed or a tool stopped syncing'),
  (key: 'machine_chats', label: 'Claude on your machines', sub: 'Claude needs your OK to continue, or finished a task'),
];
