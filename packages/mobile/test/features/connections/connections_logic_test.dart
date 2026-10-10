import 'package:escanor/features/connections/connections_logic.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogProvider p(String id, {String name = '', String category = '', bool connected = false, String via = 'oauth', bool oauth = true, List<String> fields = const []}) =>
    CatalogProvider(id: id, name: name.isEmpty ? id : name, categoryLabel: category, connected: connected, connectVia: via, oauthAvailable: oauth, credentialFields: fields);

void main() {
  test('reads the catalog defensively', () {
    final c = CatalogProvider.fromJson({
      'id': 'github',
      'name': 'GitHub',
      'description': 'Code',
      'category_label': 'Source control',
      'connected': false,
      'connect_via': 'api_key',
      'can_connect': true,
      'oauth_available': false,
      'credential_fields': ['org_name', 3],
      'token_label': 'Personal access token',
      'help_url': 'https://github.com/settings/tokens',
    });
    expect((c.name, c.categoryLabel, c.viaKey, c.viaOauth, c.tokenLabel), ('GitHub', 'Source control', true, false, 'Personal access token'));
    expect(c.credentialFields, ['org_name', '3']);
    expect(CatalogProvider.fromJson(c.toJson()).helpUrl, c.helpUrl);
    expect(CatalogProvider.fromJson({}).credentialFields, isEmpty);
  });

  test('how each service connects', () {
    expect(p('a', via: 'oauth').viaOauth, isTrue);
    expect(p('a', via: 'oauth', oauth: false).viaOauth, isFalse);
    expect(p('a', via: 'credentials').viaKey, isTrue);
    expect(p('a', via: 'local_agent').viaLocalAgent, isTrue);
  });

  test('capabilities and what the person has connected', () {
    final caps = Capabilities.fromJson({
      'summary': 'You have 2 services.',
      'integrations': [
        {'provider_id': 'github', 'name': 'GitHub', 'available_to_assistant': true, 'needs_reconnect': false},
        {'provider_id': 'sentry', 'name': 'Sentry', 'available_to_assistant': null},
        'junk',
      ],
    });
    expect(caps.summary, 'You have 2 services.');
    expect(caps.integrations.length, 2);
    expect(caps.integrations[1].availableToAssistant, isNull);
    expect(Capabilities.fromJson(caps.toJson()).integrations.first.providerId, 'github');
    expect(Capabilities.fromJson({'summary': ''}).summary, isNull);
  });

  test('the line under a connected service', () {
    const base = ConnectedIntegration(providerId: 'x', name: 'X');
    expect(connectedStatus(const ConnectedIntegration(providerId: 'x', name: 'X', needsReconnect: true, availableToAssistant: true)).text, 'Needs reconnecting');
    expect(connectedStatus(const ConnectedIntegration(providerId: 'x', name: 'X', availableToAssistant: true)).tone, StatusTone.success);
    expect(connectedStatus(const ConnectedIntegration(providerId: 'x', name: 'X', availableToAssistant: false)).text, 'Connected, no assistant tools for it yet');
    expect(connectedStatus(base).text, 'Connected');
  });

  test('what can still be added, and searching it by name or category', () {
    final catalog = [p('github', name: 'GitHub', category: 'Source control'), p('vercel', name: 'Vercel', category: 'Hosting'), p('done', connected: true), p('sentry', name: 'Sentry', category: 'Observability')];
    const connected = [ConnectedIntegration(providerId: 'sentry', name: 'Sentry')];
    expect(availableProviders(catalog, connected, '').map((x) => x.id), ['github', 'vercel']);
    expect(availableProviders(catalog, connected, ' HOST ').map((x) => x.id), ['vercel']);
    expect(availableProviders(catalog, connected, 'git').map((x) => x.id), ['github']);
    expect(availableProviders(catalog, connected, 'zzz'), isEmpty);
  });

  test('field labels', () {
    expect(fieldLabel('client_secret'), 'Client secret');
    expect(fieldLabel('org'), 'Org');
    expect(fieldLabel(''), '');
  });

  test('the key form needs a token or one of the fields, and sends only what was typed', () {
    final prov = p('x', via: 'credentials', fields: ['account_id']);
    expect(canSubmitKey(prov, '  ', {}), isFalse);
    expect(canSubmitKey(prov, '', {'account_id': ' '}), isFalse);
    expect(canSubmitKey(prov, '', {'account_id': '42'}), isTrue);
    expect(canSubmitKey(prov, 'tok', {}), isTrue);
    expect(keyBody(' tok ', {}), (accessToken: 'tok', credentials: null));
    final b = keyBody('', {'a': 'b'});
    expect(b.accessToken, isNull);
    expect(b.credentials, {'a': 'b'});
  });

  test('only https pages open outside the app', () {
    expect(isSafeExternalUrl('https://github.com/login/oauth'), isTrue);
    expect(isSafeExternalUrl('http://x'), isFalse);
    expect(isSafeExternalUrl('javascript:alert(1)'), isFalse);
  });
}
