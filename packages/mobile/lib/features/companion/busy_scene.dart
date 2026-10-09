import 'sprites.dart' show Scene;

/// Which scene the companion plays: working beats everything, then sleep, then the sit-and-sniff routine.
/// (The shared busy count itself is `busyCount` in lib/core/busy.dart.)
Scene buddyScene({required bool busy, required bool asleep, required bool sniffing}) =>
    busy ? Scene.run : asleep ? Scene.sleep : sniffing ? Scene.sniff : Scene.sit;
