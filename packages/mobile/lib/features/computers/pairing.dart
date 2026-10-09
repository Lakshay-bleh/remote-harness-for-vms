import 'dart:convert';

import 'protocol/client.dart';
import 'protocol/failure.dart';
import 'protocol/lan_pair.dart';
import 'protocol/protocol.dart';
import 'protocol/secure.dart';

/// What a person typed, pasted or scanned: the code, and (from a QR) which computer it belongs to and where it is on Wi-Fi.
class PairEntry {
  const PairEntry({required this.code, this.payload});
  final String code;
  final PairingPayload? payload;
}

/// Accepts a typed code (any case, dashes or spaces) or the QR's JSON. Anything else is not a pairing.
PairEntry? parseEntry(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('{')) {
    try {
      final v = jsonDecode(t);
      if (v is Map && v['v'] == 1 && v['code'] is String && v['lan'] is List) {
        final code = formatCode(parseCode(v['code'] as String));
        return PairEntry(
          code: code,
          payload: PairingPayload(
            code: code,
            machine: v['machine'] is String ? v['machine'] as String : 'My computer',
            lan: [
              for (final a in v['lan'] as List)
                if (a is String) a,
            ],
            agentId: v['agentId'] is String ? v['agentId'] as String : null,
          ),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
  try {
    return PairEntry(code: formatCode(parseCode(t)));
  } catch (_) {
    return null;
  }
}

/// `host:port` or null: the address of a computer on the local network. The port is optional, and a pasted `http://…/` is fine.
String? normalizeAddress(String text) => normalizeLanAddress(text);

/// Pair with a computer on the same Wi-Fi knowing only its address, with no code: the person approves on the computer after
/// checking that it shows the same confirmation number as this phone ([LanAskOptions.onConfirm] receives it).
Future<PairedComputer> pairOnWifi(String address, String deviceName, [LanAskOptions o = const LanAskOptions()]) => pairByAddress(address, deviceName, o);

enum PairMode { cloud, lan }

class PairOptions {
  const PairOptions({this.mode = PairMode.cloud, required this.cloud, this.lanAddress, this.env = const ClientEnv()});

  /// `cloud` (the default): the code alone, from anywhere. `lan`: straight to the computer over the same Wi-Fi.
  final PairMode mode;
  final CloudDirectory cloud;

  /// Local mode, when the code was typed rather than scanned.
  final String? lanAddress;
  final ClientEnv env;
}

/// The cloud could not be reached at all (as opposed to the computer saying no). Only then is the local network worth a try.
bool _cloudUnreachable(Object e) =>
    RegExp('could not reach|did not answer|offline|timed out|failed to fetch|network', caseSensitive: false).hasMatch(failureText(e));

Future<PairedComputer> pairComputer(PairEntry entry, String deviceName, PairOptions o) async {
  final p = entry.payload;
  Future<PairedComputer> local(List<String> addresses) =>
      pairWithPayload(PairingPayload(code: entry.code, machine: p?.machine ?? 'My computer', lan: addresses, agentId: p?.agentId), deviceName, o.env);

  if (o.mode == PairMode.lan) {
    final typed = o.lanAddress != null ? normalizeAddress(o.lanAddress!) : null;
    final addresses = (p?.lan.isNotEmpty ?? false) ? p!.lan : (typed != null ? [typed] : <String>[]);
    if (addresses.isEmpty) throw const ComputerError('Enter the address shown on your computer, like 192.168.1.20.');
    return local(addresses);
  }
  try {
    return await pairWithCode(entry.code, deviceName, o.cloud, agentId: p?.agentId, machine: p?.machine, lan: p?.lan);
  } catch (e) {
    // the QR also carries Wi-Fi addresses: use them if the internet route is down
    if ((p?.lan.isNotEmpty ?? false) && _cloudUnreachable(e)) return local(p!.lan);
    rethrow;
  }
}
