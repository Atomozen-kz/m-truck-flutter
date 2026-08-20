import 'package:shared_preferences/shared_preferences.dart';

/// Хранилище Bearer-токена Sanctum.
///
/// Значение кэшируется в памяти: [ApiClient] читает токен перед каждым
/// запросом, а обращение к диску на горячем пути не нужно.
class TokenStore {
  TokenStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'auth.token';

  String? _cached;
  bool _loaded = false;

  Future<String?> read() async {
    if (!_loaded) {
      _cached = _prefs.getString(_key);
      _loaded = true;
    }
    return _cached;
  }

  Future<void> write(String token) async {
    _cached = token;
    _loaded = true;
    await _prefs.setString(_key, token);
  }

  Future<void> clear() async {
    _cached = null;
    _loaded = true;
    await _prefs.remove(_key);
  }
}
