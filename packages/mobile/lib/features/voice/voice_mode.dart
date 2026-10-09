import 'package:flutter/foundation.dart';

import 'device.dart';

/// CONTRACT (owned by the voice feature; keep these signatures).

/// Set by [VoiceHost] while the signed-in app is showing: opens voice mode and starts listening.
final ValueNotifier<VoidCallback?> voiceModeOpener = ValueNotifier<VoidCallback?>(null);

/// Open full-screen voice mode (a conversation by voice), e.g. from the composer's voice button.
void openVoiceMode() => voiceModeOpener.value?.call();

/// False where voice mode cannot run (no speech recognition on this phone).
bool get voiceModeAvailable => isAndroid || isIOS;
