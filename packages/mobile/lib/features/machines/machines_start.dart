import '../../core/api.dart' show Tokens;
import '../../core/session.dart';
import '../../core/storage.dart';
import 'hub_api.dart';
import 'hub_state.dart';
import 'hub_store.dart';
import 'managed.dart';

/// Is the person signed in to Escanor on this phone?
bool hasEscanorSession() {
  try {
    return Tokens(Storage.instance).hasSession;
  } catch (_) {
    return false;
  }
}

/// Signing out of Escanor takes the hosted hub's credentials, and the last person's chats, with it (App.tsx).
/// A self-hosted hub's login is the person's own and stays.
void machinesSignedOut() {
  try {
    if (!clearManaged()) return;
  } catch (_) {
    return;
  }
  if (HubStore.created) {
    HubStore.instance.socket.stop();
    HubStore.instance.dispatch(const SetAuthed(false));
  }
}

/// Before the first frame: register the sign-out hook, and drop hosted-hub credentials left from an Escanor session
/// that ended while the app was closed.
Future<void> startMachines() async {
  signOutHooks.add(() async => machinesSignedOut());
  if (!hasEscanorSession()) machinesSignedOut();
}

/// This phone has its own hub's login, no Escanor session and no hosted hub: it opens on that hub (Root in App.tsx).
bool ownHubStartsHere([HubCredentials creds = const HubCredentials()]) {
  try {
    if (hasEscanorSession()) return false;
    machinesSignedOut(); // hosted-hub credentials are never shown without an Escanor sign-in
    return creds.signedIn && !creds.managed;
  } catch (_) {
    return false;
  }
}
