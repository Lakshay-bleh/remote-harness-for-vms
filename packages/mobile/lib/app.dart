import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/prefs.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/welcome_screen.dart';
import 'features/machines/own_hub.dart';
import 'shell/shell.dart';
import 'ui/widgets.dart';

/// Links the app was opened with, for features other than sign-in (computer pairing links, push targets).
final StreamController<Uri> appLinks = StreamController<Uri>.broadcast();

class EscanorApp extends ConsumerStatefulWidget {
  const EscanorApp({super.key});
  @override
  ConsumerState<EscanorApp> createState() => _EscanorAppState();
}

class _EscanorAppState extends ConsumerState<EscanorApp> with WidgetsBindingObserver {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      final links = AppLinks();
      _links = links.uriLinkStream.listen(_onLink, onError: (_) {});
    } catch (_) {
      // no platform (tests)
    }
  }

  void _onLink(Uri uri) {
    if (!ref.read(sessionProvider.notifier).handleLink(uri)) appLinks.add(uri);
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void dispose() {
    _links?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final systemDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final themeName = resolveTheme(prefs.theme, systemDark);
    final colors = EscanorColors.of(themeName, prefs.accent);
    SystemChrome.setSystemUIOverlayStyle(
      (colors.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: colors.surfaceSoft),
    );
    return MaterialApp(
      title: 'Escanor',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(colors, reduceMotion: prefs.reduceMotion),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1) * prefs.textScale),
            disableAnimations: prefs.reduceMotion || mq.disableAnimations,
          ),
          child: child!,
        );
      },
      home: const Root(),
    );
  }
}

/// Signed out: the welcome screen (or the person's own hub). Signed in: the app.
class Root extends ConsumerStatefulWidget {
  const Root({super.key});
  @override
  ConsumerState<Root> createState() => _RootState();
}

class _RootState extends ConsumerState<Root> {
  /// Someone who only ever used their own hub keeps landing there.
  late bool _ownHub = OwnHub.startsHere();

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (_ownHub) return OwnHub(onBack: () => setState(() => _ownHub = false));
    return switch (session.status) {
      SessionStatus.loading => Scaffold(
          body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [Logo(), SizedBox(height: 16), Spinner()])),
        ),
      SessionStatus.signedOut => WelcomeScreen(onAdvanced: () => setState(() => _ownHub = true)),
      SessionStatus.signedIn => const Shell(),
    };
  }
}
