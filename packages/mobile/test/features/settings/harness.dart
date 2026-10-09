import 'dart:convert';

import 'package:escanor/core/api.dart';
import 'package:escanor/core/cache.dart';
import 'package:escanor/core/storage.dart';
import 'package:escanor/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fake Escanor backend for widget tests: answers by "METHOD /path" (query ignored), and records every request.
class FakeBackend {
  FakeBackend(this.routes);
  final Map<String, Object? Function(http.Request req)> routes;
  final List<http.Request> calls = [];

  static Map<String, Object? Function(http.Request)> base() => {
        'GET /auth/session': (_) => {
              'user': {'id': 'u1', 'email': 'ada@example.com', 'name': 'Ada Lovelace'}
            },
        'GET /ai/usage': (_) => {
              'messages_today': 12,
              'message_limit': 50,
              'today': {'tokens': 4200},
              'month': {'requests': 30, 'input_tokens': 120000, 'output_tokens': 9000, 'cost_usd': 1.234},
              'cost_is_estimate': true,
            },
        'GET /billing/subscription': (_) => {'plan_id': 'pro', 'plan_name': 'Pro', 'status': 'active'},
        'GET /account/deletion': (_) => {'scheduled': false, 'two_factor_enabled': false, 'grace_days': 7},
      };

  Future<http.Response> handle(http.Request req) async {
    calls.add(req);
    final path = req.url.path.replaceFirst('/api/v1', '');
    final h = routes['${req.method} $path'];
    if (h == null) return http.Response(jsonEncode({'detail': 'Not found'}), 404);
    final body = h(req);
    if (body is http.Response) return body;
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
  }

  int count(String methodPath) => calls.where((r) => '${r.method} ${r.url.path.replaceFirst('/api/v1', '')}' == methodPath).length;
}

/// Storage in memory, signed in, and [api] pointed at [backend].
Future<FakeBackend> setUpBackend([Map<String, Object? Function(http.Request)> extra = const {}]) async {
  await Storage.initForTest(secrets: {'escanor_access': 'access-1', 'escanor_refresh': 'refresh-1'});
  clearCache(); // nothing remembered from another test
  final backend = FakeBackend({...FakeBackend.base(), ...extra});
  api = Api(client: MockClient(backend.handle), tokens: Tokens(Storage.instance), base: 'https://test.escanor/api/v1');
  return backend;
}

/// A page inside the app's theme, with Riverpod and a navigator.
Widget host(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: buildTheme(EscanorColors.of(ThemeName.dark, AccentName.gold), reduceMotion: true),
        home: child,
      ),
    );

/// Let loads finish without waiting for endless animations (the companion runs while loading).
Future<void> settle(WidgetTester t, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// A tall phone, so long settings pages lay out without scrolling.
void tallPhone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 4000);
  t.view.devicePixelRatio = 2.5;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}
