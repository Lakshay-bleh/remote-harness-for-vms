import 'package:flutter/foundation.dart';

import '../../core/storage.dart';
import 'animals.dart';

/// Which animal this phone shows, and whether it makes its sound. Kept on the device (a companion is a taste, not an
/// account setting) and shared by every screen through two small notifiers, so picking one in Settings changes all of
/// them at once.
const String companionKey = 'escanor.companion.v1';
const String soundKey = 'escanor.companion.sound.v1';

/// Read a stored choice defensively: anything that is not one of the known animals is the default.
Animal parseCompanion(String? raw) => isAnimal(raw) ? Animal.values.byName(raw!) : defaultAnimal;

String? _read(String key) {
  try {
    return Storage.instance.getString(key);
  } catch (_) {
    return null; // storage not ready (tests): the defaults
  }
}

void _write(String key, String value) {
  try {
    Storage.instance.setString(key, value);
  } catch (_) {
    // not saved, but it still applies until the app is closed
  }
}

ValueNotifier<Animal>? _choice;
ValueNotifier<bool>? _sound;

/// The chosen animal. Listen to it (ValueListenableBuilder) to follow changes made in Settings.
ValueNotifier<Animal> get companionChoice => _choice ??= ValueNotifier(parseCompanion(_read(companionKey)));

/// The sound it makes when tapped: on by default, one switch per device.
ValueNotifier<bool> get companionSound => _sound ??= ValueNotifier(_read(soundKey) != 'off');

Animal getCompanion() => companionChoice.value;

void setCompanion(Animal animal) {
  companionChoice.value = animal;
  _write(companionKey, animal.name);
}

bool getCompanionSound() => companionSound.value;

void setCompanionSound(bool on) {
  companionSound.value = on;
  _write(soundKey, on ? 'on' : 'off');
}

/// For tests: forget what was read, so the next read comes from storage again.
@visibleForTesting
void resetCompanionForTest() {
  _choice = null;
  _sound = null;
}
