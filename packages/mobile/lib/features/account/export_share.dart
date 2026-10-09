import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'data_export.dart';

enum ShareOutcome { shared, cancelled }

/// Hand text to the phone's share sheet as a file, so it can be saved to Files or Drive, mailed or sent to another app.
Future<ShareOutcome> shareExport(String text, {String? name, String title = 'My Escanor data', String mime = 'application/json'}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${name ?? exportFileName()}');
  await file.writeAsString(text, flush: true);
  final r = await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: mime)],
    title: title,
    subject: title,
  ));
  return r.status == ShareResultStatus.dismissed ? ShareOutcome.cancelled : ShareOutcome.shared;
}

Future<void> copyExport(String text) => Clipboard.setData(ClipboardData(text: text));
