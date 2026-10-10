/// CONTRACT (owned by the computers feature; keep these signatures, add freely).
/// What other features (voice, settings) need from the paired computers.
library;

import 'dart:math';

import '../../core/session.dart';
import 'cloud.dart';
import 'computer_prefs.dart';
import 'errors.dart';
import 'protocol/client.dart';
import 'protocol/failure.dart';
import 'protocol/protocol.dart';
import 'storage.dart';

export 'errors.dart' show Explained, FixWhere, explainComputerFailure, spokenProblem;
export 'protocol/client.dart' show PairedComputer;
export 'storage.dart' show computersChanges;

/// The computers paired with this phone (newest first).
List<PairedComputer> loadComputers() => loadPairedComputers();

/// Forget every paired computer (sign-out, Developer > reset): device keys, names, routes, chats and caches.
void clearComputers() => clearPairedComputers();

final _rand = Random();
String _id() => List.generate(8, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[_rand.nextInt(36)]).join();

/// Say one sentence to a paired computer and wait for its reply. Throws the failure as it is.
///
/// Connects the way the person chose for that computer (Wi-Fi, cloud or automatic), asks, and hangs up.
Future<String> chatWithComputer(PairedComputer computer, String text) => chatWithComputerUsing(computer, text);

/// [chatWithComputer] with the cloud route and connection given (tests).
Future<String> chatWithComputerUsing(PairedComputer c, String text, {RelayTransport? relay, ClientEnv env = const ClientEnv()}) async {
  final routed = applyRoute(c, getComputerPrefs(c.id).route);
  final client = ComputerClient(
    routed.computer,
    ClientEnv(
      client: env.client,
      socket: env.socket,
      lanTimeout: env.lanTimeout,
      now: env.now,
      relay: routed.cloud ? (relay ?? env.relay ?? apiRelay()) : null,
    ),
  );
  try {
    await client.connect();
    final out = await client.request(ClientMsg.chat(_id(), text), timeout: const Duration(seconds: 60));
    final m = firstOf(out, const {'reply', 'error'});
    if (m == null) return '';
    if (m['t'] == 'error') throw ComputerError('${m['message'] ?? ''}');
    return '${m['reply'] ?? ''}';
  } finally {
    client.close();
  }
}

/// A failure from talking to a computer, in words a person can act on: one sentence saying what is wrong and where to fix it
/// (this app or the computer), as the voice assistant says it. For the full explanation (title, where, steps, and whether the
/// phone can ask the computer to allow it) use [explainComputerFailure].
String explainFailure(Object error) => spokenProblem(error);

/// The reply is really "that is switched off for phones": a problem with a fix, not an answer.
bool isSwitchedOffReply(String said) => explainComputerFailure(said).askGroupLabel != null;

/// Work before the first frame: paired computers (their device keys, names and chats) leave with the person who signs out.
Future<void> startComputers() async {
  signOutHooks.add(() async => clearComputers());
}
