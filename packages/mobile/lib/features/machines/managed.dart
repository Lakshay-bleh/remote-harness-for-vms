import '../../core/api.dart';
import 'hub_api.dart';

/// Escanor's hosted hub (managed.ts). Signing in to Escanor gives the person a private tenant on it: the backend hands
/// the app the hub's address and a token that belongs to that person alone. The app keeps them where the self-hosted
/// flow keeps a hub login, so the Machines screen works the same either way, plus a flag, so signing out of Escanor
/// takes them away again.
class ManagedHub {
  const ManagedHub({
    required this.available,
    this.hubUrl,
    this.agentUrl,
    this.agentToken,
    this.appToken,
    this.installCommand,
    this.guideUrl,
  });

  final bool available;
  final String? hubUrl;

  /// wss://…/agent, what a VM's agent dials.
  final String? agentUrl;

  /// The secret a VM's agent authenticates with.
  final String? agentToken;
  final String? appToken;

  /// One line to run on a VM: installs the agent already pointed at this hub.
  final String? installCommand;
  final String? guideUrl;

  factory ManagedHub.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    String? s(String k) => m[k] is String && (m[k] as String).isNotEmpty ? m[k] as String : null;
    return ManagedHub(
      available: m['available'] == true,
      hubUrl: s('hub_url'),
      agentUrl: s('agent_url'),
      agentToken: s('agent_token'),
      appToken: s('app_token'),
      installCommand: s('install_command'),
      guideUrl: s('guide_url'),
    );
  }
}

extension ManagedHubApi on Api {
  /// The hosted hub: its address and this person's tokens for their VMs (created the first time).
  Future<ManagedHub> managedHub() async => ManagedHub.fromJson(await get('/agent/hub/managed'));
}

bool isManaged([HubCredentials creds = const HubCredentials()]) => creds.managed;

/// Point this app at the person's hosted tenant. Returns true when the token changed (it was rotated).
/// Throws when the hosted hub's address is not https (it is then not used).
bool applyManaged(ManagedHub hub, [HubCredentials creds = const HubCredentials()]) {
  final changed = creds.managed && creds.token != hub.appToken;
  creds.hubUrl = hub.hubUrl ?? '';
  creds.token = hub.appToken;
  creds.managed = true;
  return changed;
}

/// Forget the hosted tenant's credentials (Escanor sign-out). Returns true when there were any.
bool clearManaged([HubCredentials creds = const HubCredentials()]) {
  if (!creds.managed) return false;
  creds.token = null;
  creds.hubUrl = '';
  creds.managed = false;
  return true;
}
