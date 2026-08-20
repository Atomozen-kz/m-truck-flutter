import '../api_client.dart';
import '../local/cache_store.dart';
import '../models/models.dart';

/// Рейсы водителя, смена статусов и передача GPS-трека.
class ShipmentRepository {
  ShipmentRepository({required ApiClient api, required CacheStore cache})
      : _api = api,
        _cache = cache;

  final ApiClient _api;
  final CacheStore _cache;

  /// Активный рейс. Сервер отдаёт `null`, когда водитель свободен.
  Future<Shipment?> current() async {
    final response = await _api.get('/api/driver/current-shipment');
    final data = response.data;
    if (data is! Map<String, dynamic> || data.isEmpty) {
      await _cache.write(CacheStore.keyCurrentShipment, null);
      return null;
    }
    await _cache.write(CacheStore.keyCurrentShipment, data);
    return Shipment.parse(data);
  }

  CachedSnapshot<Shipment>? cachedCurrent() {
    final snapshot = _cache.readMap(CacheStore.keyCurrentShipment);
    if (snapshot == null) return null;
    return CachedSnapshot(value: Shipment.parse(snapshot.value), savedAt: snapshot.savedAt);
  }

  /// [status] — `active` или `history`; без него сервер отдаёт все рейсы.
  Future<List<Shipment>> list({String? status}) async {
    final response = await _api.get(
      '/api/my/shipments',
      query: {'status': ?status},
    );
    final raw = response.asList;
    if (status == 'history') await _cache.write(CacheStore.keyShipments, raw);
    return raw.map(Shipment.parse).toList();
  }

  CachedSnapshot<List<Shipment>>? cachedHistory() {
    final snapshot = _cache.readList(CacheStore.keyShipments);
    if (snapshot == null) return null;
    return CachedSnapshot(
      value: snapshot.value.map(Shipment.parse).toList(),
      savedAt: snapshot.savedAt,
    );
  }

  /// Смена статуса: picked_up → in_transit → delivered.
  ///
  /// Ответ сервера иногда приходит без вложенной заявки — накладываем его на
  /// кэш, чтобы активный рейс не потерял адреса, цену и заказчика.
  Future<Shipment> changeStatus({
    required int shipmentId,
    required ShipmentStatus status,
    double? lat,
    double? lng,
  }) async {
    final response = await _api.post('/api/shipments/$shipmentId/status', body: {
      'status': status.wire,
      'lat': ?lat,
      'lng': ?lng,
    });
    final merged = _patchCurrent(shipmentId, {
      'status': status.wire,
      ...response.asMap,
    });
    if (merged == null) return Shipment.parse(response.asMap);
    await _cache.write(CacheStore.keyCurrentShipment, merged);
    return Shipment.parse(merged);
  }

  /// Записывает в кэш статус, проставленный без сети.
  ///
  /// Свайп «загрузился» в степи должен пережить перезапуск приложения: сам
  /// запрос лежит в очереди, но водитель обязан видеть свой рейс на том шаге,
  /// на котором он его оставил. Возвращает `null`, если активного рейса с этим
  /// id в кэше нет — тогда патчить нечего.
  Future<Shipment?> cacheLocalStatus({
    required int shipmentId,
    required ShipmentStatus status,
    DateTime? at,
  }) async {
    final stamp = (at ?? DateTime.now()).toIso8601String();
    final merged = _patchCurrent(shipmentId, {
      'status': status.wire,
      if (status == ShipmentStatus.pickedUp) 'picked_up_at': stamp,
      if (status == ShipmentStatus.delivered) 'delivered_at': stamp,
    }, requireCached: true);
    if (merged == null) return null;
    await _cache.write(CacheStore.keyCurrentShipment, merged);
    return Shipment.parse(merged);
  }

  /// Забывает активный рейс — водитель закрыл завершённый рейс на экране.
  Future<void> forgetCurrent() => _cache.write(CacheStore.keyCurrentShipment, null);

  /// Накладывает [patch] на кэш активного рейса.
  ///
  /// `null` означает «этот кэш не про наш рейс»: в очереди мог задержаться
  /// статус прошлого рейса, и затирать им текущий нельзя.
  Map<String, dynamic>? _patchCurrent(
    int shipmentId,
    Map<String, dynamic> patch, {
    bool requireCached = false,
  }) {
    final cached = _cache.readMap(CacheStore.keyCurrentShipment)?.value;
    if (cached == null) return requireCached ? null : {'id': shipmentId, ...patch};
    if ('${cached['id']}' != '$shipmentId') return null;
    return {...cached, ...patch};
  }

  /// Подтверждение доставки: фото накладной и/или код от получателя.
  Future<void> submitProof({
    required int shipmentId,
    String? photoPath,
    String? code,
  }) async {
    await _api.multipart(
      '/api/shipments/$shipmentId/proof',
      fields: {if (code != null && code.isNotEmpty) 'code': code},
      files: {'photo': ?photoPath},
    );
  }

  /// Пачка GPS-точек, до 200 за раз.
  Future<int> pushTracking({
    required int shipmentId,
    required List<Map<String, dynamic>> points,
  }) async {
    if (points.isEmpty) return 0;
    final response = await _api.post('/api/tracking/batch', body: {
      'shipment_id': shipmentId,
      'points': points.take(200).toList(),
    });
    return (response.asMap['accepted'] as num?)?.toInt() ?? points.length;
  }

  Future<TrackPayload> track(int shipmentId) async {
    final response = await _api.get('/api/shipments/$shipmentId/track');
    return TrackPayload.parse(response.asMap);
  }
}
