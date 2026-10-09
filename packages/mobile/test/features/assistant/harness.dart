import 'package:escanor/core/theme.dart';
import 'package:flutter/material.dart';

/// A screen inside the app's theme, for widget tests.
Widget themed(Widget child) => MaterialApp(
      theme: buildTheme(EscanorColors.of(ThemeName.dark, AccentName.gold), reduceMotion: true),
      home: Scaffold(body: child),
    );
