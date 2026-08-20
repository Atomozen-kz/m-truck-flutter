import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Снимок данных с отметкой времени — то, что показываем при «Нет сети».
class CachedSnapshot<T> {
  const CachedSnapshot({required this.value, required this.savedAt});

  final T value;
  final DateTime savedAt;
}

/// Кэш ответов API на диске.
///
/// Лента заявок, активный рейс и справочник посёлков переживают перезапуск и
/// потерю связи: экран рисует их с пометкой «обновлено N мин назад».
class CacheStore {
  CacheStore(this._prefs);

  final SharedPreferences _prefs;

  static const keyMarketplace = 'cache.marketplace';
  static const keyMyBids = 'cache.my_bids';
  static const keyShipments = 'cache.shipments';
  static const keyCurrentShipment = 'cache.current_shipment';
  static const keyPayouts = 'cache.payouts';
  static const keyUser = 'cache.user';

  /// Сохраняет произвольный JSON-совместимый список или объект.
  Future<void> write(String key, Object? payload) async {
    if (payload == null) {
      await _prefs.remove(key);
      return;
    }
    await _prefs.setString(
      key,
      jsonEncode({'at': DateTime.now().toIso8601String(), 'payload': payload}),
    );
  }

  CachedSnapshot<List<Map<String, dynamic>>>? readList(String key) {
    final envelope = _read(key);
    if (envelope == null) return null;
    final payload = envelope.value;
    if (payload is! List) return null;
    return CachedSnapshot(
      value: payload.whereType<Map<String, dynamic>>().toList(growable: false),
      savedAt: envelope.savedAt,
    );
  }

  CachedSnapshot<Map<String, dynamic>>? readMap(String key) {
    final envelope = _read(key);
    if (envelope == null) return null;
    final payload = envelope.value;
    if (payload is! Map<String, dynamic>) return null;
    return CachedSnapshot(value: payload, savedAt: envelope.savedAt);
  }

  CachedSnapshot<dynamic>? _read(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final savedAt = DateTime.tryParse(decoded['at'] as String? ?? '');
      if (savedAt == null) return null;
      return CachedSnapshot(value: decoded['payload'], savedAt: savedAt);
    } on FormatException {
      return null;
    }
  }

  Future<void> clearAll() async {
    for (final key in const [
      keyMarketplace,
      keyMyBids,
      keyShipments,
      keyCurrentShipment,
      keyPayouts,
      keyUser,
    ]) {
      await _prefs.remove(key);
    }
  }
}
