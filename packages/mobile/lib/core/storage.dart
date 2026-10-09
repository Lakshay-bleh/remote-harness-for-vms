import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the app keeps on the phone. Two stores, both loaded once at start so reads are synchronous:
/// - [prefs]: ordinary settings, caches and lists (SharedPreferences).
/// - secrets: sign-in tokens and device keys (Keychain / Android Keystore), mirrored in memory.
class Storage {
  Storage._(this.prefs, this._secure, this._secrets);

  final SharedPreferences prefs;
  final FlutterSecureStorage? _secure;
  final Map<String, String> _secrets;

  static Storage? _instance;
  static Storage get instance {
    final s = _instance;
    if (s == null) throw StateError('Storage.init() was not called');
    return s;
  }

  static Future<Storage> init() async {
    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage();
    Map<String, String> secrets;
    try {
      secrets = await secure.readAll();
    } catch (_) {
      secrets = {}; // a keystore that cannot be read (restored backup): start signed out rather than crash
    }
    return _instance = Storage._(prefs, secure, secrets);
  }

  /// For tests: everything in memory.
  static Future<Storage> initForTest({Map<String, Object> prefs = const {}, Map<String, String> secrets = const {}}) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    return _instance = Storage._(p, null, Map.of(secrets));
  }

  String? secret(String key) => _secrets[key];

  void setSecret(String key, String? value) {
    if (value == null) {
      _secrets.remove(key);
      _secure?.delete(key: key);
    } else {
      _secrets[key] = value;
      _secure?.write(key: key, value: value);
    }
  }

  Iterable<String> get secretKeys => _secrets.keys;

  String? getString(String key) => prefs.getString(key);
  Future<void> setString(String key, String? value) => value == null ? prefs.remove(key) : prefs.setString(key, value);
  Future<void> remove(String key) => prefs.remove(key);
}
