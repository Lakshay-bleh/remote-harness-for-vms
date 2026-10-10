/// A copy of the person's data: how it is written and named. Pure; saving and sharing it is in export_share.dart.
library;

import 'dart:convert';

/// The export as text, as the person receives it.
String exportText(Object? data) => const JsonEncoder.withIndent('  ').convert(data);

String _two(int n) => n.toString().padLeft(2, '0');

/// "escanor-my-data-2026-10-03.json" (the date in UTC, as the website names it).
String exportFileName([DateTime? now]) {
  final t = (now ?? DateTime.now()).toUtc();
  return 'escanor-my-data-${t.year}-${_two(t.month)}-${_two(t.day)}.json';
}

/// Roughly how big it is, for "12 KB", before the person decides to copy or share it.
String sizeLabel(String text) {
  final bytes = utf8.encode(text).length;
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
