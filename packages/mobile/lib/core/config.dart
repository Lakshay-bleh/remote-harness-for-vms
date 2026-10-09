/// Where the Escanor backend is. Always Escanor's own server; only a development build
/// (`--dart-define=ESCANOR_API=http://10.0.2.2:8100/api/v1`) points elsewhere.
const String _defaultApi = 'https://api.escanor.in/api/v1';
const String _builtApi = String.fromEnvironment('ESCANOR_API');

String escanorApiBase() => (_builtApi.isNotEmpty ? _builtApi : _defaultApi).replaceAll(RegExp(r'/+$'), '');

/// The scheme this app owns; escanor.in/auth/mobile/login hands the login code to it.
const String appScheme = 'escanor';
const String mobileLoginRedirect = 'https://www.escanor.in/auth/mobile/login';
const String websiteBase = 'https://www.escanor.in';

/// Application id on Android and bundle id on iOS.
const String appId = 'com.escanorlabs.escanor';
