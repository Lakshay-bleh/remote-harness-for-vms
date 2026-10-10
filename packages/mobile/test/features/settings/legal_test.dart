import 'dart:convert';

import 'package:escanor/features/settings/info_pages.dart';
import 'package:escanor/features/settings/legal_content.dart';
import 'package:escanor/features/settings/legal_rich.dart';
import 'package:escanor/features/voice/control_consent.dart' as consent;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Every span inside the legal paragraphs on screen.
List<TextSpan> _spans(WidgetTester t) => [
      for (final w in t.widgetList<SelectableText>(find.byType(SelectableText)))
        for (final s in (w.textSpan!.children ?? const <InlineSpan>[])) s as TextSpan,
    ];

void main() {
  group('inline marks', () {
    test('a site path opens the same page inside the app', () {
      expect(parseLegalRich('Make a request on [Privacy requests](/privacy/requests), in Settings.'), const [
        RichPart('Make a request on '),
        RichPart('Privacy requests', doc: privacyRequestsDoc),
        RichPart(', in Settings.'),
      ]);
      expect(parseLegalRich('[Refunds](/refunds)'), const [RichPart('Refunds', doc: 'refunds')]);
    });
    test('a path the app has no page for is its label, never a link to the website', () {
      expect(parseLegalRich('read the [documentation](/docs) or [book a call](/book-a-call)'), const [
        RichPart('read the '),
        RichPart('documentation'),
        RichPart(' or '),
        RichPart('book a call'),
      ]);
    });
    test('an https link opens as it is', () {
      expect(parseLegalRich('[Razorpay](https://razorpay.com/privacy/)'), const [
        RichPart('Razorpay', href: 'https://razorpay.com/privacy/'),
      ]);
    });
    test('anything that is not https is its label, as plain text', () {
      expect(parseLegalRich('see [the notice](http://example.com) or [mail](mailto:a@b.c).'), const [
        RichPart('see '),
        RichPart('the notice'),
        RichPart(' or '),
        RichPart('mail'),
        RichPart('.'),
      ]);
    });
    test('bold', () {
      expect(parseLegalRich('**Account:** name and email'), const [
        RichPart('Account:', bold: true),
        RichPart(' name and email'),
      ]);
    });
    test('mixed text, and plain text untouched', () {
      expect(parseLegalRich('**Terminal sessions:** 90 days. **Commands:** see [Privacy policy](/privacy).'), const [
        RichPart('Terminal sessions:', bold: true),
        RichPart(' 90 days. '),
        RichPart('Commands:', bold: true),
        RichPart(' see '),
        RichPart('Privacy policy', doc: 'privacy'),
        RichPart('.'),
      ]);
      expect(parseLegalRich('No marks here, \$5 and it’s fine.'), const [RichPart('No marks here, \$5 and it’s fine.')]);
      expect(parseLegalRich(''), isEmpty);
    });
  });

  group('stored documents', () {
    test('every listed document has sections, each with paragraphs or items', () {
      expect(legalList, isNotEmpty);
      for (final d in legalList) {
        final doc = legalDocuments[d.key];
        expect(doc, isNotNull, reason: d.key);
        expect(doc!.title, isNotEmpty, reason: d.key);
        expect(doc.sections, isNotEmpty, reason: d.key);
        for (final s in doc.sections) {
          expect(s.paragraphs.isNotEmpty || s.items.isNotEmpty, true, reason: '${d.key}: ${s.heading}');
        }
      }
    });
    test('the policy version, and the phone-control consent refers to it', () async {
      expect(policyVersion, '2026-10-08');
      expect(policyDate, '8 October 2026');
      final backend = await setUpBackend({'POST /compliance/consents': (_) => {'ok': true}});
      await consent.recordPhoneControlConsent(true);
      final sent = jsonDecode(backend.calls.single.body) as Map<String, dynamic>;
      expect(sent['notice_version'], policyVersion);
    });
    test('every link in the documents is to the website or https', () {
      for (final doc in legalDocuments.values) {
        for (final s in doc.sections) {
          for (final text in [...s.paragraphs, ...s.items]) {
            for (final p in parseLegalRich(text)) {
              if (p.href != null) expect(p.href, startsWith('https://'));
              if (p.doc != null) expect(p.doc == privacyRequestsDoc || legalDocuments.containsKey(p.doc), true, reason: '${p.doc} in $text');
              expect(p.href?.contains('escanor.in'), isNot(true), reason: 'no link to the website: $text');
              expect(p.text.contains('**'), false, reason: text);
            }
          }
        }
      }
    });
  });

  testWidgets('A document shows its date, bold text, links and a bulleted list', (t) async {
    tallPhone(t);
    await setUpBackend();
    await t.pumpWidget(host(const Scaffold(body: SingleChildScrollView(child: LegalBody(docKey: 'privacy')))));
    await settle(t);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Last updated $policyDate'), findsOneWidget);
    expect(find.text('What we collect and why'), findsOneWidget);
    expect(find.text('•'), findsWidgets);

    final spans = _spans(t);
    final bold = spans.firstWhere((s) => s.text == 'Account:');
    expect(bold.style!.fontWeight, FontWeight.w600);
    final link = spans.firstWhere((s) => s.text == 'Privacy requests');
    expect(link.recognizer, isA<TapGestureRecognizer>());
    expect(link.style!.decoration, TextDecoration.underline);
    expect(spans.any((s) => s.text?.contains('[') ?? false), false);
  });

  testWidgets('An unknown document says so', (t) async {
    await setUpBackend();
    await t.pumpWidget(host(const Scaffold(body: LegalBody(docKey: 'about'))));
    await settle(t);
    expect(find.text('This document is not available.'), findsOneWidget);
  });
}
