import 'package:shared_preferences/shared_preferences.dart';

/// Minimal key-value storage used by the app store.
abstract class Storage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// Keeps everything in memory. Used in tests and as a fallback.
class MemoryStorage implements Storage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

/// Persists to the platform's shared preferences. If the platform storage is
/// unavailable the data is kept in memory for the current session instead of
/// crashing the app.
class PrefsStorage implements Storage {
  SharedPreferences? _prefs;
  final MemoryStorage _fallback = MemoryStorage();
  bool _useFallback = false;

  Future<SharedPreferences?> _open() async {
    if (_useFallback) return null;
    try {
      return _prefs ??= await SharedPreferences.getInstance();
    } catch (_) {
      _useFallback = true;
      return null;
    }
  }

  @override
  Future<String?> read(String key) async {
    final prefs = await _open();
    if (prefs == null) return _fallback.read(key);
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await _open();
    if (prefs == null) return _fallback.write(key, value);
    await prefs.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    final prefs = await _open();
    if (prefs == null) return _fallback.remove(key);
    await prefs.remove(key);
  }
}
