import 'package:escanor/features/push/push_host.dart';
import 'package:escanor/features/push/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../settings/harness.dart';

void main() {
  testWidgets('without Firebase the host just shows the app', (t) async {
    await setUpBackend();
    expect(firebaseReady, false);
    expect(await pushState(), PushState.unsupported); // not a phone here
    await t.pumpWidget(host(const PushHost(child: Scaffold(body: Text('the app')))));
    await settle(t);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('the banner shows the title and body and goes where it points', (t) async {
    var tapped = 0;
    await setUpBackend();
    await t.pumpWidget(host(Scaffold(body: PushBanner(title: 'Approval needed', body: 'Deploy to production?', onTap: () => tapped++))));
    expect(find.text('Approval needed'), findsOneWidget);
    expect(find.text('Deploy to production?'), findsOneWidget);
    await t.tap(find.text('Approval needed'));
    expect(tapped, 1);
  });
}
