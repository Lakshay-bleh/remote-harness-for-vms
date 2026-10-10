import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/api.dart';
import 'core/native_licences.dart';
import 'core/storage.dart';
import 'features/startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerNativeLicences();
  await Storage.init();
  api = Api();
  await startFeatures();
  runApp(const ProviderScope(child: EscanorApp()));
}
