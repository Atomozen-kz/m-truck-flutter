import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import '../data/local/token_store.dart';
import '../data/models/models.dart';
import '../data/repositories/auth_repository.dart';
import '../services/connectivity_service.dart';

/// Стадия сессии, определяющая корневой экран приложения.
enum SessionStage {
  /// Читаем сохранённый токен.
  loading,

  /// Токена нет — вход по телефону.
  signedOut,

  /// Токен есть, но профиль водителя не заполнен.
  needsDriverProfile,

  /// Права на модерации — откликаться пока нельзя.
  pendingModeration,

  /// Полный доступ.
  ready,
}

/// Текущий пользователь и его путь от телефона до одобренного профиля.
class SessionController extends ChangeNotifier {
  SessionController({
    required AuthRepository auth,
    required TokenStore tokens,
    required ConnectivityService connectivity,
  })  : _auth = auth,
        _tokens = tokens,
        _connectivity = connectivity;

  final AuthRepository _auth;
  final TokenStore _tokens;
  final ConnectivityService _connectivity;

  SessionStage _stage = SessionStage.loading;
  User? _user;
  String? _pendingPhone;

  SessionStage get stage => _stage;
  User? get user => _user;

  /// Телефон, на который «отправлен» код — показывается на экране ввода кода.
  String? get pendingPhone => _pendingPhone;

  bool get isSignedIn => _user != null;

  /// Водитель прошёл модерацию и может отправлять отклики.
  bool get canBid => _user?.canBid ?? false;

  /// Восстанавливает сессию при старте. Без сети опирается на кэш профиля.
  Future<void> restore() async {
    final token = await _tokens.read();
    if (token == null) {
      _setStage(SessionStage.signedOut);
      return;
    }

    final cached = _auth.cachedUser();
    if (cached != null) _applyUser(cached);

    try {
      _applyUser(await _auth.me());
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await signOut();
        return;
      }
      if (e.isNetwork) _connectivity.reportFailure();
      // Иначе живём на кэше: без сети водитель всё равно должен видеть рейс.
      if (cached == null) _setStage(SessionStage.signedOut);
    }
  }

  Future<PhoneCheck> requestCode(String phoneDigits) async {
    final result = await _auth.requestCode(phoneDigits);
    _pendingPhone = phoneDigits;
    notifyListeners();
    return result;
  }

  /// Подтверждает код и переводит сессию в следующую стадию.
  Future<void> verifyCode(String code, {String? name}) async {
    final phone = _pendingPhone;
    if (phone == null) {
      throw ApiException('Сначала запросите код');
    }
    final result = await _auth.verifyCode(phone: phone, code: code, name: name);
    _applyUser(result.user);
  }

  Future<void> registerDriver({
    required String name,
    required String licenseNo,
    required String plate,
    required String vehicleType,
    required int capacityKg,
    bool hasRefrigeration = false,
    String? licensePhotoPath,
  }) async {
    await _auth.registerDriver(
      name: name,
      licenseNo: licenseNo,
      plate: plate,
      vehicleType: vehicleType,
      capacityKg: capacityKg,
      hasRefrigeration: hasRefrigeration,
      licensePhotoPath: licensePhotoPath,
    );
    // register-driver отдаёт профиль без связей — перечитываем целиком.
    await refresh();
  }

  /// Перечитывает профиль. Молча переживает отсутствие сети.
  Future<void> refresh() async {
    try {
      _applyUser(await _auth.me());
    } on ApiException catch (e) {
      if (e.isUnauthorized) await signOut();
      if (e.isNetwork) _connectivity.reportFailure();
    }
  }

  Future<void> signOut() async {
    await _auth.logout();
    _user = null;
    _pendingPhone = null;
    _setStage(SessionStage.signedOut);
  }

  void _applyUser(User user) {
    _user = user;
    _setStage(switch (user.driver?.status) {
      null => SessionStage.needsDriverProfile,
      DriverStatus.approved => SessionStage.ready,
      DriverStatus.pending => SessionStage.pendingModeration,
      DriverStatus.rejected => SessionStage.needsDriverProfile,
    });
  }

  void _setStage(SessionStage stage) {
    _stage = stage;
    notifyListeners();
  }
}
