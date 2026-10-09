import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/cache.dart';
import '../../core/storage.dart';
import 'chat_store.dart';
import 'computer_prefs.dart';
import 'protocol/client.dart';

/// The computers this phone is paired with. The device key in each is what authorises this phone, so it is kept in the Keychain /
/// Android Keystore ([Storage.setSecret]); the rest (name, addresses, when) is ordinary metadata in preferences.
const _listKey = 'escanor.computers.v1';
const _secretPrefix = 'escanor.computer.key.';

/// Fires whenever the list changes (paired, forgotten, cleared), so every screen showing it can follow.
final ValueNotifier<int> computersChanges = ValueNotifier<int>(0);

List<Map<String, dynamic>> _rawList() {
  try {
    final v = jsonDecode(Storage.instance.getString(_listKey) ?? '[]');
    return v is List
        ? [
            for (final e in v)
              if (e is Map) Map<String, dynamic>.from(e),
          ]
        : [];
  } catch (_) {
    return [];
  }
}

void _writeList(List<PairedComputer> list) {
  Storage.instance.setString(_listKey, jsonEncode([for (final c in list) c.toMetaJson()]));
  computersChanges.value++;
}

/// Every paired computer whose key is still held. One whose key is gone (a keystore that was reset) cannot be used, so it is left out.
List<PairedComputer> loadPairedComputers() {
  final out = <PairedComputer>[];
  for (final m in _rawList()) {
    final id = m['id'];
    if (id is! String) continue;
    final key = Storage.instance.secret('$_secretPrefix$id');
    if (key == null || key.isEmpty) continue;
    final c = PairedComputer.fromMetaJson(m, key);
    if (c != null) out.add(c);
  }
  return out;
}

/// Remember a newly paired computer (first in the list). Returns the new list.
List<PairedComputer> saveComputer(PairedComputer c) {
  Storage.instance.setSecret('$_secretPrefix${c.id}', c.key);
  final next = [c, ...loadPairedComputers().where((x) => x.id != c.id)];
  _writeList(next);
  return next;
}

/// Forget one computer here: its key, its name and route, its chats and what was cached for it.
List<PairedComputer> removeComputer(String id) {
  Storage.instance.setSecret('$_secretPrefix$id', null);
  forgetComputerPrefs(id);
  forgetChats(id);
  dropCache('computer:$id:');
  final next = loadPairedComputers().where((c) => c.id != id).toList();
  _writeList(next);
  return next;
}

/// Signing out of Escanor takes the paired computers with it: every device key, and what this phone remembered about them.
void clearPairedComputers() {
  for (final k in Storage.instance.secretKeys.where((k) => k.startsWith(_secretPrefix)).toList()) {
    Storage.instance.setSecret(k, null);
  }
  Storage.instance.remove(_listKey);
  forgetAllComputerPrefs();
  forgetAllChats();
  dropCache('computer:');
  computersChanges.value++;
}
