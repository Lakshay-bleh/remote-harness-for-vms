/// The Connections tab's logic, with no Flutter in it so it can be tested on its own.
library;

/// How many services the "Add a service" list shows before "Show more".
const connectionsPage = 30;

class CatalogProvider {
  const CatalogProvider({
    required this.id,
    required this.name,
    this.description = '',
    this.categoryLabel = '',
    this.connected = false,
    this.connectVia = '',
    this.canConnect = false,
    this.oauthAvailable = false,
    this.credentialFields = const [],
    this.tokenLabel = '',
    this.helpUrl = '',
  });

  final String id;
  final String name;
  final String description;
  final String categoryLabel;
  final bool connected;

  /// oauth | api_key | credentials | local_agent (or something newer this app does not know).
  final String connectVia;
  final bool canConnect;
  final bool oauthAvailable;
  final List<String> credentialFields;
  final String tokenLabel;
  final String helpUrl;

  factory CatalogProvider.fromJson(Map<String, dynamic> j) => CatalogProvider(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        description: '${j['description'] ?? ''}',
        categoryLabel: '${j['category_label'] ?? ''}',
        connected: j['connected'] == true,
        connectVia: '${j['connect_via'] ?? ''}',
        canConnect: j['can_connect'] == true,
        oauthAvailable: j['oauth_available'] == true,
        credentialFields: [for (final f in (j['credential_fields'] is List ? j['credential_fields'] as List : const [])) '$f'],
        tokenLabel: '${j['token_label'] ?? ''}',
        helpUrl: '${j['help_url'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category_label': categoryLabel,
        'connected': connected,
        'connect_via': connectVia,
        'can_connect': canConnect,
        'oauth_available': oauthAvailable,
        'credential_fields': credentialFields,
        'token_label': tokenLabel,
        'help_url': helpUrl,
      };

  /// Connected by pasting a key (and maybe a few more fields).
  bool get viaKey => connectVia == 'api_key' || connectVia == 'credentials';

  /// Connected through the provider's own consent page.
  bool get viaOauth => connectVia == 'oauth' && oauthAvailable;

  /// Connected through a machine the person pairs (set up on the web).
  bool get viaLocalAgent => connectVia == 'local_agent';
}

class ConnectedIntegration {
  const ConnectedIntegration({required this.providerId, required this.name, this.availableToAssistant, this.needsReconnect = false});
  final String providerId;
  final String name;

  /// true: the assistant will see it; false: connected but it has no tools for it yet; null: could not check.
  final bool? availableToAssistant;
  final bool needsReconnect;

  factory ConnectedIntegration.fromJson(Map<String, dynamic> j) => ConnectedIntegration(
        providerId: '${j['provider_id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        availableToAssistant: j['available_to_assistant'] is bool ? j['available_to_assistant'] as bool : null,
        needsReconnect: j['needs_reconnect'] == true,
      );

  Map<String, dynamic> toJson() => {
        'provider_id': providerId,
        'name': name,
        'available_to_assistant': availableToAssistant,
        'needs_reconnect': needsReconnect,
      };
}

class Capabilities {
  const Capabilities({this.integrations = const [], this.summary});
  final List<ConnectedIntegration> integrations;
  final String? summary;

  factory Capabilities.fromJson(Map<String, dynamic> j) => Capabilities(
        integrations: [
          for (final i in (j['integrations'] is List ? j['integrations'] as List : const []))
            if (i is Map) ConnectedIntegration.fromJson(Map<String, dynamic>.from(i)),
        ],
        summary: j['summary'] is String && (j['summary'] as String).isNotEmpty ? j['summary'] as String : null,
      );

  Map<String, dynamic> toJson() => {'integrations': [for (final i in integrations) i.toJson()], 'summary': summary};
}

/// `client_secret` -> `Client secret`.
String fieldLabel(String f) {
  final s = f.replaceAll('_', ' ');
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// The services that can still be added: not connected yet, and matching the search by name or category.
List<CatalogProvider> availableProviders(List<CatalogProvider> catalog, List<ConnectedIntegration> connected, String query) {
  final ids = {for (final c in connected) c.providerId};
  final q = query.trim().toLowerCase();
  return catalog
      .where((p) =>
          !ids.contains(p.id) &&
          !p.connected &&
          (q.isEmpty || p.name.toLowerCase().contains(q) || p.categoryLabel.toLowerCase().contains(q)))
      .toList();
}

enum StatusTone { warning, success, muted }

/// The line under a connected service.
({String text, StatusTone tone}) connectedStatus(ConnectedIntegration c) {
  if (c.needsReconnect) return (text: 'Needs reconnecting', tone: StatusTone.warning);
  if (c.availableToAssistant == true) return (text: 'Your assistant can use this', tone: StatusTone.success);
  if (c.availableToAssistant == false) return (text: 'Connected, no assistant tools for it yet', tone: StatusTone.muted);
  return (text: 'Connected', tone: StatusTone.muted);
}

/// Is there anything to send? A token, or at least one of the extra fields.
bool canSubmitKey(CatalogProvider p, String token, Map<String, String> fields) =>
    token.trim().isNotEmpty || p.credentialFields.any((f) => (fields[f] ?? '').trim().isNotEmpty);

/// What the key form sends: the token when there is one, the fields when any were typed.
({String? accessToken, Map<String, String>? credentials}) keyBody(String token, Map<String, String> fields) => (
      accessToken: token.trim().isEmpty ? null : token.trim(),
      credentials: fields.isEmpty ? null : Map.of(fields),
    );

/// How long to keep watching for a browser connection to land before giving up.
const oauthWaitLimit = Duration(seconds: 120);
const oauthPollEvery = Duration(seconds: 2);

/// Only https pages are ever opened outside the app.
bool isSafeExternalUrl(String url) => RegExp(r'^https://', caseSensitive: false).hasMatch(url);
