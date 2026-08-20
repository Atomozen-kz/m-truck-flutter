import '../api_client.dart';
import '../local/cache_store.dart';
import '../local/token_store.dart';
import '../models/models.dart';

/// Результат проверки телефона перед отправкой кода.
class PhoneCheck {
  const PhoneCheck({required this.exists, required this.codeSent});

  final bool exists;
  final bool codeSent;
}

/// Результат подтверждения кода.
class VerifyResult {
  const VerifyResult({required this.user, required this.isNew});

  final User user;
  final bool isNew;
}

/// Вход по телефону, профиль и регистрация водителя.
///
/// Пароля нет: `phone/check` «отправляет» код, `phone/verify` выдаёт токен
/// Sanctum, после чего новый водитель заполняет машину в `register-driver`.
class AuthRepository {
  AuthRepository({
    required ApiClient api,
    required TokenStore tokens,
    required CacheStore cache,
  })  : _api = api,
        _tokens = tokens,
        _cache = cache;

  final ApiClient _api;
  final TokenStore _tokens;
  final CacheStore _cache;

  Future<PhoneCheck> requestCode(String phone) async {
    final response = await _api.post('/api/auth/phone/check', body: {'phone': phone});
    final data = response.asMap;
    return PhoneCheck(
      exists: data['exists'] == true,
      codeSent: data['code_sent'] != false,
    );
  }

  /// Подтверждает код и сохраняет токен. Роль всегда `driver` — это мобилка.
  Future<VerifyResult> verifyCode({
    required String phone,
    required String code,
    String? name,
  }) async {
    final response = await _api.post('/api/auth/phone/verify', body: {
      'phone': phone,
      'code': code,
      'role': 'driver',
      if (name != null && name.isNotEmpty) 'name': name,
    });

    final data = response.asMap;
    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw ApiException('Сервер не вернул токен доступа');
    }
    await _tokens.write(token);

    final userJson = data['user'];
    if (userJson is! Map<String, dynamic>) {
      throw ApiException('Сервер не вернул профиль');
    }
    await _cache.write(CacheStore.keyUser, userJson);

    return VerifyResult(user: User.parse(userJson), isNew: data['is_new'] == true);
  }

  Future<User> me() async {
    final response = await _api.get('/api/auth/me');
    final data = response.asMap;
    await _cache.write(CacheStore.keyUser, data);
    return User.parse(data);
  }

  /// Профиль из кэша — чтобы приложение открывалось мгновенно и без сети.
  User? cachedUser() {
    final snapshot = _cache.readMap(CacheStore.keyUser);
    return snapshot == null ? null : User.parse(snapshot.value);
  }

  /// Регистрация водителя: машина и права уходят на модерацию.
  Future<User> registerDriver({
    required String name,
    required String licenseNo,
    required String plate,
    required String vehicleType,
    required int capacityKg,
    bool hasRefrigeration = false,
    String? licensePhotoPath,
  }) async {
    final response = await _api.multipart(
      '/api/auth/register-driver',
      fields: {
        'name': name,
        'license_no': licenseNo,
        'plate': plate,
        'vehicle_type': vehicleType,
        'capacity_kg': '$capacityKg',
        'has_refrigeration': hasRefrigeration ? '1' : '0',
      },
      files: {'license_photo': ?licensePhotoPath},
    );

    final data = response.asMap;
    final userJson = data['user'] is Map<String, dynamic> ? data['user'] : data;
    await _cache.write(CacheStore.keyUser, userJson);
    return User.parse(userJson as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await _api.post('/api/auth/logout');
    } on ApiException {
      // Даже если сервер недоступен, локальную сессию всё равно закрываем.
    }
    await _tokens.clear();
    await _cache.clearAll();
  }
}
