import '../api_client.dart';
import '../local/cache_store.dart';
import '../models/models.dart';

/// Фильтры ленты биржи. Пустой набор означает «Все».
class MarketplaceFilters {
  const MarketplaceFilters({
    this.cargoType,
    this.maxWeightKg,
    this.nearLat,
    this.nearLng,
    this.radiusKm,
    this.sort = 'new',
  });

  final String? cargoType;
  final int? maxWeightKg;
  final double? nearLat;
  final double? nearLng;
  final double? radiusKm;
  final String sort;

  bool get isEmpty => cargoType == null && maxWeightKg == null && radiusKm == null;

  MarketplaceFilters copyWith({
    Object? cargoType = _keep,
    Object? maxWeightKg = _keep,
    Object? radiusKm = _keep,
    double? nearLat,
    double? nearLng,
    String? sort,
  }) =>
      MarketplaceFilters(
        cargoType: identical(cargoType, _keep) ? this.cargoType : cargoType as String?,
        maxWeightKg: identical(maxWeightKg, _keep) ? this.maxWeightKg : maxWeightKg as int?,
        radiusKm: identical(radiusKm, _keep) ? this.radiusKm : radiusKm as double?,
        nearLat: nearLat ?? this.nearLat,
        nearLng: nearLng ?? this.nearLng,
        sort: sort ?? this.sort,
      );

  static const _keep = Object();

  Map<String, dynamic> toQuery() => {
        'cargo_type': cargoType,
        'max_weight': maxWeightKg,
        'near_lat': nearLat,
        'near_lng': nearLng,
        'radius_km': radiusKm,
        'sort': sort,
      };
}

/// Лента заявок, карточка заявки и отклики водителя.
class MarketplaceRepository {
  MarketplaceRepository({required ApiClient api, required CacheStore cache})
      : _api = api,
        _cache = cache;

  final ApiClient _api;
  final CacheStore _cache;

  /// Лента биржи. Успешный ответ кладём в кэш — он же покажется без сети.
  Future<List<Order>> feed(MarketplaceFilters filters) async {
    final response = await _api.get('/api/marketplace/orders', query: filters.toQuery());
    final raw = response.asList;
    // Кэшируем только неотфильтрованную ленту, иначе офлайн покажет обрезок.
    if (filters.isEmpty) await _cache.write(CacheStore.keyMarketplace, raw);
    return raw.map(Order.parse).toList();
  }

  CachedSnapshot<List<Order>>? cachedFeed() {
    final snapshot = _cache.readList(CacheStore.keyMarketplace);
    if (snapshot == null) return null;
    return CachedSnapshot(
      value: snapshot.value.map(Order.parse).toList(),
      savedAt: snapshot.savedAt,
    );
  }

  Future<Order> order(int orderId) async {
    final response = await _api.get('/api/marketplace/orders/$orderId');
    return Order.parse(response.asMap);
  }

  /// Отклик на заявку. Требует статус водителя `approved` — иначе прилетит 403.
  Future<Bid> placeBid({
    required int orderId,
    required int price,
    required int vehicleId,
    int? etaMinutes,
    String? comment,
  }) async {
    final response = await _api.post('/api/orders/$orderId/bids', body: {
      'price': price,
      'vehicle_id': vehicleId,
      'eta_minutes': ?etaMinutes,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    return Bid.parse(response.asMap);
  }

  Future<List<Bid>> myBids() async {
    final response = await _api.get('/api/my/bids');
    final raw = response.asList;
    await _attachOrders(raw);
    await _cache.write(CacheStore.keyMyBids, raw);
    return raw.map(Bid.parse).toList();
  }

  /// Подставляет заявку в каждый отклик.
  ///
  /// `/api/my/bids` отдаёт отклик без вложенной заявки, поэтому в списке
  /// «Отклики» нечем показать «Актау → Жанаозен» и тоннаж. Сначала ищем заявку
  /// в кэше ленты — она там почти всегда есть, ведь отклик оттуда и сделан, —
  /// и только за остальными идём в сеть.
  Future<void> _attachOrders(List<Map<String, dynamic>> bids) async {
    final missing = bids
        .where((b) => b['order'] is! Map || (b['order'] as Map).isEmpty)
        .toList(growable: false);
    if (missing.isEmpty) return;

    final feed = <String, Map<String, dynamic>>{
      for (final order in _cache.readList(CacheStore.keyMarketplace)?.value ?? const [])
        '${order['id']}': order,
    };

    final unresolved = <int>{};
    for (final bid in missing) {
      final id = bid['order_id'];
      final cached = feed['$id'];
      if (cached != null) {
        bid['order'] = cached;
      } else if (id is int) {
        unresolved.add(id);
      }
    }
    if (unresolved.isEmpty) return;

    // Откликов у водителя единицы — параллельная догрузка обходится дёшево.
    final fetched = await Future.wait(unresolved.map(_tryFetchOrder));
    final byId = <String, Map<String, dynamic>>{
      for (final order in fetched.nonNulls) '${order['id']}': order,
    };
    for (final bid in missing) {
      final order = byId['${bid['order_id']}'];
      if (order != null) bid['order'] = order;
    }
  }

  /// Заявку могли снять с публикации — тогда отклик просто останется без неё.
  Future<Map<String, dynamic>?> _tryFetchOrder(int orderId) async {
    try {
      final response = await _api.get('/api/marketplace/orders/$orderId');
      final data = response.asMap;
      return data.isEmpty ? null : data;
    } on ApiException {
      return null;
    }
  }

  CachedSnapshot<List<Bid>>? cachedBids() {
    final snapshot = _cache.readList(CacheStore.keyMyBids);
    if (snapshot == null) return null;
    return CachedSnapshot(
      value: snapshot.value.map(Bid.parse).toList(),
      savedAt: snapshot.savedAt,
    );
  }
}
