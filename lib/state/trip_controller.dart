import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/api_client.dart';
import '../data/local/outbox.dart';
import '../data/models/models.dart';
import '../data/repositories/marketplace_repository.dart';
import '../data/repositories/shipment_repository.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';

/// Активный рейс, отклики водителя и история.
///
/// Здесь же живёт трекинг: пока рейс в работе, координаты копятся пачками и
/// уходят на сервер, а без сети — оседают в [Outbox] до появления связи.
class TripController extends ChangeNotifier {
  TripController({
    required ShipmentRepository shipments,
    required MarketplaceRepository marketplace,
    required LocationService location,
    required ConnectivityService connectivity,
    required SyncService sync,
    required Outbox outbox,
  })  : _shipments = shipments,
        _marketplace = marketplace,
        _location = location,
        _connectivity = connectivity,
        _sync = sync,
        _outbox = outbox;

  final ShipmentRepository _shipments;
  final MarketplaceRepository _marketplace;
  final LocationService _location;
  final ConnectivityService _connectivity;
  final SyncService _sync;
  final Outbox _outbox;

  /// Точки копим и отправляем пачкой — экономия батареи и трафика.
  static const _batchSize = 10;
  static const _batchInterval = Duration(minutes: 2);

  Shipment? _active;
  List<Bid> _bids = const [];
  List<Shipment> _history = const [];
  bool _isLoading = false;
  String? _error;

  final List<Map<String, dynamic>> _pendingPoints = [];
  Timer? _batchTimer;
  Position? _lastPosition;

  Shipment? get active => _active;
  List<Bid> get bids => _bids;
  List<Shipment> get history => _history;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Position? get lastPosition => _lastPosition;

  /// Отклики, ждущие ответа заказчика.
  List<Bid> get pendingBids =>
      _bids.where((b) => b.status == BidStatus.pending).toList(growable: false);

  /// Отклики, которым место во вкладке «Отклики».
  ///
  /// Принятый отклик уже превратился в рейс — держать его здесь значит
  /// показывать одну и ту же работу дважды.
  List<Bid> get openBids =>
      _bids.where((b) => b.status != BidStatus.accepted).toList(growable: false);

  /// Рейсы в работе, включая назначенные.
  List<Shipment> get liveShipments =>
      _history.where((s) => s.status.isLive).toList(growable: false);

  int get bufferedPointCount => _pendingPoints.length + _outbox.bufferedPoints();

  /// Загружает всё, что нужно вкладкам «Рейсы» и «История».
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    _restoreFromCache();
    await Future.wait([_loadActive(), _loadBids(), _loadHistory()]);

    _isLoading = false;
    notifyListeners();

    if (_active?.status.isLive ?? false) await startTracking();
  }

  void _restoreFromCache() {
    _active ??= _shipments.cachedCurrent()?.value;
    if (_bids.isEmpty) _bids = _marketplace.cachedBids()?.value ?? const [];
    if (_history.isEmpty) _history = _shipments.cachedHistory()?.value ?? const [];
  }

  Future<void> refresh() => load();

  Future<void> _loadActive() async {
    try {
      _active = await _shipments.current();
      _error = null;
      _connectivity.reportSuccess();
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _connectivity.reportFailure();
        _active ??= _shipments.cachedCurrent()?.value;
      } else {
        _error = e.message;
      }
    }
  }

  Future<void> _loadBids() async {
    try {
      _bids = await _marketplace.myBids();
    } on ApiException catch (e) {
      if (e.isNetwork) _bids = _marketplace.cachedBids()?.value ?? _bids;
    }
  }

  Future<void> _loadHistory() async {
    try {
      _history = await _shipments.list();
      // Кэшируем полный список — на вкладке «История» он же и показывается.
    } on ApiException catch (e) {
      if (e.isNetwork) _history = _shipments.cachedHistory()?.value ?? _history;
    }
  }

  // --- Смена статуса -------------------------------------------------------

  /// Переводит рейс на следующий шаг.
  ///
  /// Без сети статус применяется локально и уходит в очередь: водителю важно
  /// видеть результат свайпа сразу, даже в степи между Актау и Бейнеу.
  Future<void> advanceStatus(ShipmentStatus target) async {
    final shipment = _active;
    if (shipment == null) return;

    final position = _lastPosition;
    try {
      _active = await _shipments.changeStatus(
        shipmentId: shipment.id,
        status: target,
        lat: position?.latitude,
        lng: position?.longitude,
      );
      _connectivity.reportSuccess();
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;

      _connectivity.reportFailure();
      await _sync.enqueue(OutboxKind.shipmentStatus, {
        'shipment_id': shipment.id,
        'status': target.wire,
        if (position != null) 'lat': position.latitude,
        if (position != null) 'lng': position.longitude,
      });
      final now = DateTime.now();
      // Кэш обязателен: без него следующий запуск покажет старый шаг рейса.
      _active = await _shipments.cacheLocalStatus(
            shipmentId: shipment.id,
            status: target,
            at: now,
          ) ??
          _localAdvance(shipment, target, now);
    }

    if (_active?.status.isFinished ?? false) await stopTracking();
    notifyListeners();
  }

  /// Локальный сдвиг статуса, пока запрос ждёт сеть.
  Shipment _localAdvance(Shipment shipment, ShipmentStatus target, DateTime now) {
    return Shipment(
      id: shipment.id,
      orderId: shipment.orderId,
      status: target,
      trackToken: shipment.trackToken,
      routeGeometry: shipment.routeGeometry,
      assignedAt: shipment.assignedAt,
      pickedUpAt: target == ShipmentStatus.pickedUp ? now : shipment.pickedUpAt,
      deliveredAt: target == ShipmentStatus.delivered ? now : shipment.deliveredAt,
      order: shipment.order,
      vehicle: shipment.vehicle,
    );
  }

  /// Подтверждение доставки: фото накладной и код получателя.
  Future<void> submitProof({String? photoPath, String? code}) async {
    final shipment = _active;
    if (shipment == null) return;
    try {
      await _shipments.submitProof(shipmentId: shipment.id, photoPath: photoPath, code: code);
      _connectivity.reportSuccess();
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      _connectivity.reportFailure();
      await _sync.enqueue(OutboxKind.proof, {
        'shipment_id': shipment.id,
        'photo_path': ?photoPath,
        'code': ?code,
      });
    }
  }

  /// Закрывает завершённый рейс на экране — водитель возвращается в ленту.
  Future<void> clearActive() async {
    await stopTracking();
    // Иначе завершённый рейс воскреснет из кэша при следующем запуске.
    await _shipments.forgetCurrent();
    _active = null;
    notifyListeners();
    unawaited(load());
  }

  // --- Трекинг -------------------------------------------------------------

  Future<bool> startTracking() async {
    if (_location.isTracking) return true;
    final started = await _location.startTracking(_onPosition);
    if (started) {
      _batchTimer ??= Timer.periodic(_batchInterval, (_) => unawaited(_flushPoints()));
    }
    notifyListeners();
    return started;
  }

  Future<void> stopTracking() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    await _location.stopTracking();
    await _flushPoints();
    notifyListeners();
  }

  bool get isTracking => _location.isTracking;

  void _onPosition(Position position) {
    _lastPosition = position;
    _pendingPoints.add({
      'lat': position.latitude,
      'lng': position.longitude,
      'speed': position.speed,
      'heading': position.heading,
      'recorded_at': position.timestamp.toUtc().toIso8601String(),
    });
    notifyListeners();
    if (_pendingPoints.length >= _batchSize) unawaited(_flushPoints());
  }

  /// Отправляет накопленные точки; при сбое — откладывает их в очередь.
  Future<void> _flushPoints() async {
    final shipment = _active;
    if (shipment == null || _pendingPoints.isEmpty) return;

    final batch = List<Map<String, dynamic>>.from(_pendingPoints);
    _pendingPoints.clear();

    try {
      await _shipments.pushTracking(shipmentId: shipment.id, points: batch);
      _connectivity.reportSuccess();
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _connectivity.reportFailure();
        await _sync.enqueue(OutboxKind.tracking, {
          'shipment_id': shipment.id,
          'points': batch,
        });
      }
      // Отказ сервера по треку не критичен — рейс продолжается.
    }
    notifyListeners();
  }

  // --- Заработок -----------------------------------------------------------

  /// Завершённые рейсы за период — источник цифр на экране «История».
  List<Shipment> completedBetween(DateTime from, DateTime to) => _history
      .where((s) => s.status.isFinished)
      .where((s) {
        final at = s.deliveredAt;
        return at != null && !at.isBefore(from) && at.isBefore(to);
      })
      .toList(growable: false);

  @override
  void dispose() {
    _batchTimer?.cancel();
    unawaited(_location.stopTracking());
    super.dispose();
  }
}
