import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import '../data/models/models.dart';
import '../data/repositories/marketplace_repository.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';

/// Пресет фильтра — то, что нарисовано чипами над лентой.
class FilterChipSpec {
  const FilterChipSpec({required this.id, required this.label, required this.apply});

  final String id;
  final String label;
  final MarketplaceFilters Function(MarketplaceFilters current) apply;
}

/// Лента биржи: загрузка, фильтры и работа без сети.
class FeedController extends ChangeNotifier {
  FeedController({
    required MarketplaceRepository repository,
    required ConnectivityService connectivity,
    required LocationService location,
    required SyncService sync,
  })  : _repository = repository,
        _connectivity = connectivity,
        _location = location,
        _sync = sync;

  final MarketplaceRepository _repository;
  final ConnectivityService _connectivity;
  final LocationService _location;
  final SyncService _sync;

  List<Order> _orders = const [];
  MarketplaceFilters _filters = const MarketplaceFilters();
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _error;
  DateTime? _updatedAt;
  bool _isFromCache = false;
  final Set<String> _activeChips = {};

  List<Order> get orders => _orders;
  MarketplaceFilters get filters => _filters;
  bool get isLoading => _isLoading && _orders.isEmpty;
  bool get isRefreshing => _isRefreshing;
  String? get error => _error;

  /// Когда данные были получены — «обновлено 12 мин назад».
  DateTime? get updatedAt => _updatedAt;

  /// Показанные заявки взяты из кэша, а не с сервера.
  bool get isFromCache => _isFromCache;

  bool get hasActiveFilters => _activeChips.isNotEmpty;
  int get activeFilterCount => _activeChips.length;
  bool isChipActive(String id) => _activeChips.contains(id);

  /// Пресеты фильтров ленты. «Все» сбрасывает остальные.
  static const chips = <FilterChipSpec>[
    FilterChipSpec(id: 'near', label: 'Рядом', apply: _applyNear),
    FilterChipSpec(id: 'light', label: 'До 20 т', apply: _applyLight),
    FilterChipSpec(id: 'fridge', label: 'Рефрижератор', apply: _applyFridge),
  ];

  static MarketplaceFilters _applyNear(MarketplaceFilters f) => f.copyWith(radiusKm: 100.0);
  static MarketplaceFilters _applyLight(MarketplaceFilters f) => f.copyWith(maxWeightKg: 20000);
  static MarketplaceFilters _applyFridge(MarketplaceFilters f) =>
      f.copyWith(cargoType: 'скоропорт');

  /// Первая загрузка: сразу показываем кэш, затем идём в сеть.
  Future<void> load() async {
    final cached = _repository.cachedFeed();
    if (cached != null && _orders.isEmpty) {
      _orders = cached.value;
      _updatedAt = cached.savedAt;
      _isFromCache = true;
      notifyListeners();
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    _isLoading = _orders.isEmpty;
    _error = null;
    notifyListeners();

    try {
      _orders = await _repository.feed(await _withPosition(_filters));
      _updatedAt = DateTime.now();
      _isFromCache = false;
      _connectivity.reportSuccess();
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _connectivity.reportFailure();
        _fallBackToCache();
      } else {
        _error = e.message;
      }
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }

  void _fallBackToCache() {
    final cached = _repository.cachedFeed();
    if (cached == null) {
      if (_orders.isEmpty) _error = 'Нет сети и нет сохранённых заявок';
      return;
    }
    _orders = cached.value;
    _updatedAt = cached.savedAt;
    _isFromCache = true;
  }

  /// Фильтр «Рядом» требует координат — подставляем их перед запросом.
  Future<MarketplaceFilters> _withPosition(MarketplaceFilters filters) async {
    if (filters.radiusKm == null) return filters;
    final position = await _location.current();
    if (position == null) return filters;
    return filters.copyWith(nearLat: position.latitude, nearLng: position.longitude);
  }

  Future<void> toggleChip(String id) async {
    if (!_activeChips.remove(id)) _activeChips.add(id);
    _rebuildFilters();
    await refresh();
  }

  Future<void> clearFilters() async {
    if (_activeChips.isEmpty) return;
    _activeChips.clear();
    _rebuildFilters();
    await refresh();
  }

  void _rebuildFilters() {
    var next = const MarketplaceFilters();
    for (final chip in chips) {
      if (_activeChips.contains(chip.id)) next = chip.apply(next);
    }
    _filters = next;
    notifyListeners();
  }

  /// Отклик уже отправлен или ждёт отправки в очереди.
  bool hasBid(Order order) => order.myBid != null || _sync.hasPendingBid(order.id);

  /// Отклик лежит в очереди — карточка рисует состояние «Отклик в очереди».
  bool isBidQueued(Order order) => order.myBid == null && _sync.hasPendingBid(order.id);

  /// Локально помечает заявку как «отклик отправлен», не дожидаясь обновления.
  void markBidPlaced(int orderId, Bid bid) {
    _orders = [
      for (final order in _orders)
        if (order.id == orderId) order.copyWith(myBid: bid) else order,
    ];
    notifyListeners();
  }
}
