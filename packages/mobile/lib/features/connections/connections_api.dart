import '../../core/api.dart';
import 'connections_logic.dart';

/// The Escanor endpoints the Connections tab uses (the same backend the website uses, so the same truth).
extension ConnectionsApi on Api {
  /// What the assistant can work with right now, including the services already connected.
  Future<Capabilities> capabilities() async =>
      Capabilities.fromJson(Map<String, dynamic>.from(await get('/ai/capabilities') as Map));

  /// Every service Escanor can connect to.
  Future<List<CatalogProvider>> catalog() async {
    final r = await get('/integrations/catalog') as Map;
    final list = r['providers'];
    if (list is! List) return const [];
    return [for (final p in list) if (p is Map) CatalogProvider.fromJson(Map<String, dynamic>.from(p))];
  }

  /// Connect with an API key / token and any extra credential fields.
  Future<void> connectWithKey(String providerId, {String? accessToken, Map<String, String>? credentials}) async {
    await post('/auth/integrations/${enc(providerId)}/connect', {
      'access_token': ?accessToken,
      'credentials': ?credentials,
    });
  }

  /// The provider's consent page, to open in the browser.
  Future<String> integrationAuthorizeUrl(String providerId) async {
    final r = await get('/auth/integrations/${enc(providerId)}/authorize?platform=mobile') as Map;
    return '${r['authorization_url'] ?? ''}';
  }

  Future<void> disconnect(String providerId) async {
    await delete('/auth/integrations/${enc(providerId)}');
  }
}
