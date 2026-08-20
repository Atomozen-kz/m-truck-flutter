import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import '../data/local/outbox.dart';
import '../data/models/models.dart';
import '../data/repositories/marketplace_repository.dart';
import '../data/repositories/shipment_repository.dart';
import 'connectivity_service.dart';

/// Отправка отложенных действий, когда появляется сеть.
///
/// Экран обещает водителю: «Статус сохранится на телефоне и уйдёт, когда
/// появится сеть». Эта служба выполняет обещание — она разбирает очередь по
/// одному элементу, сохраняя порядок, и останавливается на первом сетевом сбое.
class SyncService extends ChangeNotifier {
  SyncService({
    required Outbox outbox,
    required ConnectivityService connectivity,
    required MarketplaceRepository marketplace,
    required ShipmentRepository shipments,
  })  : _outbox = outbox,
        _connectivity = connectivity,
        _marketplace = marketplace,
        _shipments = shipments {
    _connectivity.addListener(_onConnectivityChanged);
  }

  final Outbox _outbox;
  final ConnectivityService _connectivity;
  final MarketplaceRepository _marketplace;
  final ShipmentRepository _shipments;

  Timer? _retryTimer;
  bool _isFlushing = false;

  /// Сколько действий водителя (без GPS) ждут отправки.
  int get pendingActions => _outbox.pendingActions();

  /// Сколько GPS-точек лежит в буфере — цифра на бейдже в макете.
  int get bufferedPoints => _outbox.bufferedPoints();

  bool get hasPending => _outbox.read().isNotEmpty;

  bool get isFlushing => _isFlushing;

  /// Сообщает, что действие ушло в очередь, и пробует отправить сразу.
  Future<void> enqueue(OutboxKind kind, Map<String, dynamic> payload) async {
    await _outbox.add(kind, payload);
    notifyListeners();
    unawaited(flush());
  }

  bool hasPendingBid(int orderId) => _outbox.hasPendingBid(orderId);

  void _onConnectivityChanged() {
    if (_connectivity.isOnline) unawaited(flush());
  }

  /// Разбирает очередь. Безопасно вызывать сколько угодно раз.
  Future<void> flush() async {
    if (_isFlushing) return;
    final items = _outbox.read();
    if (items.isEmpty) return;

    _isFlushing = true;
    notifyListeners();

    try {
      for (final item in items) {
        final outcome = await _send(item);
        if (outcome == _Outcome.retryLater) {
          _scheduleRetry();
          break;
        }
        await _outbox.remove(item.id);
        notifyListeners();
      }
    } finally {
      _isFlushing = false;
      notifyListeners();
    }
  }

  Future<_Outcome> _send(OutboxItem item) async {
    try {
      switch (item.kind) {
        case OutboxKind.bid:
          await _marketplace.placeBid(
            orderId: item.payload['order_id'] as int,
            price: item.payload['price'] as int,
            vehicleId: item.payload['vehicle_id'] as int,
            etaMinutes: item.payload['eta_minutes'] as int?,
            comment: item.payload['comment'] as String?,
          );
        case OutboxKind.shipmentStatus:
          await _shipments.changeStatus(
            shipmentId: item.payload['shipment_id'] as int,
            status: ShipmentStatus.parse(item.payload['status'] as String?),
            lat: (item.payload['lat'] as num?)?.toDouble(),
            lng: (item.payload['lng'] as num?)?.toDouble(),
          );
        case OutboxKind.tracking:
          await _shipments.pushTracking(
            shipmentId: item.payload['shipment_id'] as int,
            points: (item.payload['points'] as List).cast<Map<String, dynamic>>(),
          );
        case OutboxKind.proof:
          await _shipments.submitProof(
            shipmentId: item.payload['shipment_id'] as int,
            photoPath: item.payload['photo_path'] as String?,
            code: item.payload['code'] as String?,
          );
      }
      _connectivity.reportSuccess();
      return _Outcome.done;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _connectivity.reportFailure();
        await _outbox.update(item.copyWith(
          attempts: item.attempts + 1,
          lastError: e.message,
        ));
        return _Outcome.retryLater;
      }

      // Сервер ответил отказом: повторять бессмысленно — заявку уже забрали,
      // статус уже проставлен или водитель не прошёл модерацию.
      if (item.attempts + 1 >= Outbox.maxAttempts || _isPermanent(e)) {
        return _Outcome.done;
      }
      await _outbox.update(item.copyWith(
        attempts: item.attempts + 1,
        lastError: e.message,
      ));
      return _Outcome.retryLater;
    }
  }

  bool _isPermanent(ApiException e) =>
      e.isForbidden || e.isConflict || e.statusCode == 404 || e.statusCode == 422;

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 30), () {
      if (_connectivity.isOnline) unawaited(flush());
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}

enum _Outcome { done, retryLater }
