import 'computers/computer_api.dart' show startComputers;
import 'machines/hub_login.dart' show openLegalDoc;
import 'machines/machines_start.dart';
import 'push/push_service.dart';
import 'settings/info_pages.dart' show showLegalSheet;
import 'voice/start_voice.dart';

/// Work each feature needs before the first frame (Firebase, sign-out hooks, native channels).
Future<void> startFeatures() async {
  openLegalDoc = (context, doc) => showLegalSheet(context, start: doc);
  await startComputers();
  await startMachines();
  await startPush();
  await startVoice();
}
