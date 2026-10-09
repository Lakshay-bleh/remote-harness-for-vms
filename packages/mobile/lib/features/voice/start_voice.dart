import 'device.dart';
import 'voice_prefs.dart';

/// Before the first frame: listen to the native side (so "Hey Escanor" and escanor://voice are not missed while the app starts)
/// and read the voice prefs.
Future<void> startVoice() async {
  if (isAndroid || isIOS) ChannelDevice.instance; // registers the channel's handler
  getVoicePrefs();
}
