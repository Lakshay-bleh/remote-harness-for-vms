import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The app's colours, the same palettes as the website and the old app (styles.css). Read them in any
/// widget with `context.c` (e.g. `context.c.ink`).

enum ThemeChoice { system, dark, light, black }

enum ThemeName { dark, light, black }

enum AccentName { gold, coral, teal, violet, blue, rose }

const themeChoices = <(ThemeChoice, String, String)>[
  (ThemeChoice.system, 'Match my phone', 'Light by day, dark by night, following your phone’s setting'),
  (ThemeChoice.dark, 'Dark', 'Easy on the eyes'),
  (ThemeChoice.light, 'Light', 'Bright and warm'),
  (ThemeChoice.black, 'Pure black', 'Saves battery on OLED screens'),
];

/// Accent colours: `dark` tone for dark themes, `light` tone for the light theme.
const accents = <AccentName, ({String label, Color dark, Color light})>{
  AccentName.gold: (label: 'Gold', dark: Color.fromARGB(255, 242, 167, 59), light: Color.fromARGB(255, 217, 138, 18)),
  AccentName.coral: (label: 'Coral', dark: Color.fromARGB(255, 240, 112, 88), light: Color.fromARGB(255, 214, 84, 58)),
  AccentName.teal: (label: 'Teal', dark: Color.fromARGB(255, 64, 188, 160), light: Color.fromARGB(255, 24, 140, 118)),
  AccentName.violet: (label: 'Violet', dark: Color.fromARGB(255, 150, 132, 255), light: Color.fromARGB(255, 104, 82, 224)),
  AccentName.blue: (label: 'Blue', dark: Color.fromARGB(255, 88, 156, 255), light: Color.fromARGB(255, 36, 104, 224)),
  AccentName.rose: (label: 'Rose', dark: Color.fromARGB(255, 240, 108, 156), light: Color.fromARGB(255, 208, 62, 118)),
};

ThemeName resolveTheme(ThemeChoice choice, bool systemDark) => switch (choice) {
      ThemeChoice.system => systemDark ? ThemeName.dark : ThemeName.light,
      ThemeChoice.dark => ThemeName.dark,
      ThemeChoice.light => ThemeName.light,
      ThemeChoice.black => ThemeName.black,
    };

double _channel(int v) {
  final s = v / 255;
  return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG relative luminance, 0..1.
double luminanceOf(Color c) =>
    0.2126 * _channel((c.r * 255).round()) + 0.7152 * _channel((c.g * 255).round()) + 0.0722 * _channel((c.b * 255).round());

/// Text on top of an accent: near-black on light accents, white on dark ones.
Color onAccent(Color c) {
  const dark = Color.fromARGB(255, 24, 14, 2);
  const white = Color(0xFFFFFFFF);
  double contrast(double a, double b) => (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
  final l = luminanceOf(c);
  return contrast(l, luminanceOf(dark)) >= contrast(l, luminanceOf(white)) ? dark : white;
}

Color _darker(Color c, [double by = 0.07]) => Color.fromARGB(
    255, ((c.r * 255) * (1 - by)).round(), ((c.g * 255) * (1 - by)).round(), ((c.b * 255) * (1 - by)).round());

Color _rgb(int r, int g, int b) => Color.fromARGB(255, r, g, b);

@immutable
class EscanorColors extends ThemeExtension<EscanorColors> {
  const EscanorColors({
    required this.primary,
    required this.primaryActive,
    required this.primaryDisabled,
    required this.onPrimary,
    required this.ink,
    required this.body,
    required this.bodyStrong,
    required this.muted,
    required this.mutedSoft,
    required this.hairline,
    required this.hairlineSoft,
    required this.lineStrong,
    required this.canvas,
    required this.surfaceSoft,
    required this.surfaceCard,
    required this.surfaceStrong,
    required this.code,
    required this.codeElevated,
    required this.field,
    required this.onCode,
    required this.onCodeSoft,
    required this.permission,
    required this.teal,
    required this.amber,
    required this.success,
    required this.warning,
    required this.error,
    required this.inlineCode,
    required this.brightness,
  });

  final Color primary, primaryActive, primaryDisabled, onPrimary;
  final Color ink, body, bodyStrong, muted, mutedSoft;
  final Color hairline, hairlineSoft, lineStrong;
  final Color canvas, surfaceSoft, surfaceCard, surfaceStrong;

  /// Code windows and tool output stay dark in every theme.
  final Color code, codeElevated, field, onCode, onCodeSoft;
  final Color permission, teal, amber, success, warning, error, inlineCode;
  final Brightness brightness;

  static EscanorColors of(ThemeName theme, AccentName accent) {
    final a = theme == ThemeName.light ? accents[accent]!.light : accents[accent]!.dark;
    final base = switch (theme) { ThemeName.dark => _dark, ThemeName.black => _black, ThemeName.light => _light };
    return base.copyWith(primary: a, primaryActive: _darker(a), onPrimary: onAccent(a));
  }

  static final _dark = EscanorColors(
    primary: _rgb(242, 167, 59),
    primaryActive: _rgb(227, 154, 44),
    primaryDisabled: _rgb(62, 60, 55),
    onPrimary: _rgb(24, 14, 2),
    ink: _rgb(243, 241, 236),
    body: _rgb(190, 178, 177),
    bodyStrong: _rgb(226, 223, 216),
    muted: _rgb(152, 148, 139),
    mutedSoft: _rgb(126, 123, 115),
    hairline: _rgb(36, 35, 32),
    hairlineSoft: _rgb(24, 24, 22),
    lineStrong: _rgb(62, 60, 55),
    canvas: _rgb(5, 5, 5),
    surfaceSoft: _rgb(9, 9, 8),
    surfaceCard: _rgb(21, 21, 19),
    surfaceStrong: _rgb(31, 30, 27),
    code: _rgb(8, 8, 7),
    codeElevated: _rgb(21, 21, 19),
    field: _rgb(12, 12, 11),
    onCode: _rgb(243, 241, 236),
    onCodeSoft: _rgb(152, 148, 139),
    permission: _rgb(139, 147, 255),
    teal: _rgb(93, 184, 166),
    amber: _rgb(232, 165, 90),
    success: _rgb(93, 184, 114),
    warning: _rgb(224, 176, 64),
    error: _rgb(239, 107, 98),
    inlineCode: _rgb(255, 216, 142),
    brightness: Brightness.dark,
  );

  static final _black = _dark.copyWith(
    primaryDisabled: _rgb(44, 44, 42),
    hairline: _rgb(30, 30, 29),
    hairlineSoft: _rgb(18, 18, 17),
    lineStrong: _rgb(52, 52, 50),
    canvas: _rgb(0, 0, 0),
    surfaceSoft: _rgb(4, 4, 4),
    surfaceCard: _rgb(14, 14, 13),
    surfaceStrong: _rgb(24, 24, 23),
    code: _rgb(10, 10, 9),
    field: _rgb(6, 6, 6),
  );

  static final _light = _dark.copyWith(
    primaryDisabled: _rgb(214, 208, 196),
    ink: _rgb(28, 26, 22),
    body: _rgb(78, 72, 64),
    bodyStrong: _rgb(40, 37, 32),
    muted: _rgb(108, 102, 92),
    mutedSoft: _rgb(140, 134, 123),
    hairline: _rgb(229, 223, 212),
    hairlineSoft: _rgb(238, 233, 224),
    lineStrong: _rgb(205, 197, 183),
    canvas: _rgb(250, 248, 244),
    surfaceSoft: _rgb(244, 241, 235),
    surfaceCard: _rgb(255, 255, 255),
    surfaceStrong: _rgb(236, 231, 221),
    field: _rgb(255, 255, 255),
    permission: _rgb(84, 92, 220),
    teal: _rgb(28, 130, 112),
    amber: _rgb(184, 116, 20),
    success: _rgb(34, 128, 58),
    warning: _rgb(168, 116, 10),
    error: _rgb(205, 50, 42),
    inlineCode: _rgb(150, 84, 6),
    brightness: Brightness.light,
  );

  @override
  EscanorColors copyWith({
    Color? primary,
    Color? primaryActive,
    Color? primaryDisabled,
    Color? onPrimary,
    Color? ink,
    Color? body,
    Color? bodyStrong,
    Color? muted,
    Color? mutedSoft,
    Color? hairline,
    Color? hairlineSoft,
    Color? lineStrong,
    Color? canvas,
    Color? surfaceSoft,
    Color? surfaceCard,
    Color? surfaceStrong,
    Color? code,
    Color? codeElevated,
    Color? field,
    Color? onCode,
    Color? onCodeSoft,
    Color? permission,
    Color? teal,
    Color? amber,
    Color? success,
    Color? warning,
    Color? error,
    Color? inlineCode,
    Brightness? brightness,
  }) =>
      EscanorColors(
        primary: primary ?? this.primary,
        primaryActive: primaryActive ?? this.primaryActive,
        primaryDisabled: primaryDisabled ?? this.primaryDisabled,
        onPrimary: onPrimary ?? this.onPrimary,
        ink: ink ?? this.ink,
        body: body ?? this.body,
        bodyStrong: bodyStrong ?? this.bodyStrong,
        muted: muted ?? this.muted,
        mutedSoft: mutedSoft ?? this.mutedSoft,
        hairline: hairline ?? this.hairline,
        hairlineSoft: hairlineSoft ?? this.hairlineSoft,
        lineStrong: lineStrong ?? this.lineStrong,
        canvas: canvas ?? this.canvas,
        surfaceSoft: surfaceSoft ?? this.surfaceSoft,
        surfaceCard: surfaceCard ?? this.surfaceCard,
        surfaceStrong: surfaceStrong ?? this.surfaceStrong,
        code: code ?? this.code,
        codeElevated: codeElevated ?? this.codeElevated,
        field: field ?? this.field,
        onCode: onCode ?? this.onCode,
        onCodeSoft: onCodeSoft ?? this.onCodeSoft,
        permission: permission ?? this.permission,
        teal: teal ?? this.teal,
        amber: amber ?? this.amber,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        error: error ?? this.error,
        inlineCode: inlineCode ?? this.inlineCode,
        brightness: brightness ?? this.brightness,
      );

  @override
  EscanorColors lerp(ThemeExtension<EscanorColors>? other, double t) {
    if (other is! EscanorColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return EscanorColors(
      primary: l(primary, other.primary),
      primaryActive: l(primaryActive, other.primaryActive),
      primaryDisabled: l(primaryDisabled, other.primaryDisabled),
      onPrimary: l(onPrimary, other.onPrimary),
      ink: l(ink, other.ink),
      body: l(body, other.body),
      bodyStrong: l(bodyStrong, other.bodyStrong),
      muted: l(muted, other.muted),
      mutedSoft: l(mutedSoft, other.mutedSoft),
      hairline: l(hairline, other.hairline),
      hairlineSoft: l(hairlineSoft, other.hairlineSoft),
      lineStrong: l(lineStrong, other.lineStrong),
      canvas: l(canvas, other.canvas),
      surfaceSoft: l(surfaceSoft, other.surfaceSoft),
      surfaceCard: l(surfaceCard, other.surfaceCard),
      surfaceStrong: l(surfaceStrong, other.surfaceStrong),
      code: l(code, other.code),
      codeElevated: l(codeElevated, other.codeElevated),
      field: l(field, other.field),
      onCode: l(onCode, other.onCode),
      onCodeSoft: l(onCodeSoft, other.onCodeSoft),
      permission: l(permission, other.permission),
      teal: l(teal, other.teal),
      amber: l(amber, other.amber),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      error: l(error, other.error),
      inlineCode: l(inlineCode, other.inlineCode),
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}

extension EscanorThemeX on BuildContext {
  EscanorColors get c => Theme.of(this).extension<EscanorColors>()!;
}

const fontFamily = 'Gellix';
const monoFamily = 'monospace';

/// Corner radii, as on the website.
abstract final class Radii {
  static const xs = 4.0, sm = 6.0, md = 8.0, lg = 12.0, xl = 16.0, pill = 999.0;
}

ThemeData buildTheme(EscanorColors c, {required bool reduceMotion}) {
  final scheme = ColorScheme(
    brightness: c.brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.teal,
    onSecondary: c.onPrimary,
    error: c.error,
    onError: const Color(0xFFFFFFFF),
    surface: c.canvas,
    onSurface: c.ink,
    surfaceContainerHighest: c.surfaceCard,
    surfaceContainerHigh: c.surfaceCard,
    surfaceContainer: c.surfaceSoft,
    surfaceContainerLow: c.surfaceSoft,
    outline: c.lineStrong,
    outlineVariant: c.hairline,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    dividerColor: c.hairline,
    splashFactory: reduceMotion ? NoSplash.splashFactory : InkSparkle.splashFactory,
    pageTransitionsTheme: reduceMotion
        ? const PageTransitionsTheme(builders: {
            TargetPlatform.android: _NoTransition(),
            TargetPlatform.iOS: _NoTransition(),
          })
        : const PageTransitionsTheme(builders: {
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          }),
    extensions: [c],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink, fontFamily: fontFamily),
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: c.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.field,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(color: c.mutedSoft),
      labelStyle: TextStyle(color: c.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.lg), borderSide: BorderSide(color: c.lineStrong)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.lg), borderSide: BorderSide(color: c.lineStrong)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.lg), borderSide: BorderSide(color: c.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.lg), borderSide: BorderSide(color: c.error)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.canvas,
      modalBackgroundColor: c.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      showDragHandle: true,
      dragHandleColor: c.lineStrong,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl), side: BorderSide(color: c.hairline)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surfaceStrong,
      contentTextStyle: TextStyle(color: c.ink, fontFamily: fontFamily),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onPrimary : c.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : c.surfaceStrong),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.primary, selectionColor: c.primary.withValues(alpha: 0.3), selectionHandleColor: c.primary),
  );
}

class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) => child;
}
