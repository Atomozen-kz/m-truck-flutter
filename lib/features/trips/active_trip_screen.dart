import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/api_client.dart';
import '../../data/models/models.dart';
import '../../services/connectivity_service.dart';
import '../../services/location_service.dart';
import '../../services/sync_service.dart';
import '../../state/trip_controller.dart';
import '../../widgets/navigator_sheet.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/primitives.dart';
import '../../widgets/route_map.dart';
import '../../widgets/route_rail.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/swipe_action.dart';
import 'finish_trip_screen.dart';

/// S3 · Активный рейс — экран, который водитель видит всю дорогу.
///
/// Верх занимает карта, середина — цифры «сколько осталось», низ — единственное
/// действие. Всё, что можно нажать, лежит в нижней трети экрана.
class ActiveTripScreen extends StatelessWidget {
  const ActiveTripScreen({super.key, required this.shipment});

  final Shipment shipment;

  @override
  Widget build(BuildContext context) {
    final trips = context.watch<TripController>();
    final sync = context.watch<SyncService>();
    final isOffline = context.watch<ConnectivityService>().isOffline;
    final order = shipment.order;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _Header(shipment: shipment),
          if (isOffline)
            OfflineBanner.queuedActions(sync.pendingActions),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _Map(shipment: shipment, trips: trips),
                _Remaining(shipment: shipment, trips: trips),
                const HairLine(),
                Padding(
                  padding: const EdgeInsets.all(Gap.screen),
                  child: RouteRail(stops: _stops()),
                ),
                if (order?.shipper != null) ...[
                  const HairLine(),
                  _Contacts(shipment: shipment),
                ],
                const SizedBox(height: Gap.md),
              ],
            ),
          ),
          _ActionBar(shipment: shipment, isOffline: isOffline),
        ],
      ),
    );
  }

  /// Точки маршрута с состоянием, выведенным из статуса рейса.
  List<RailStop> _stops() {
    final order = shipment.order;
    final loaded = shipment.status != ShipmentStatus.assigned;

    return [
      RailStop(
        title: order?.from?.address ?? '—',
        subtitle: loaded
            ? 'Загружено · ${Fmt.time(shipment.pickedUpAt)}'
            : 'Погрузка: ${Fmt.window(order?.pickupFrom, order?.pickupTo)}',
        state: loaded ? RailStopState.done : RailStopState.current,
        marker: loaded ? null : 'А',
      ),
      RailStop(
        title: order?.to?.address ?? '—',
        subtitle: shipment.status == ShipmentStatus.delivered
            ? 'Выгружено · ${Fmt.time(shipment.deliveredAt)}'
            : 'Выгрузка · ожидается ${Fmt.time(_eta(shipment))}',
        state: loaded ? RailStopState.current : RailStopState.upcoming,
        marker: loaded ? null : 'Б',
      ),
    ];
  }

  /// Ожидаемое время прибытия от текущего момента.
  static DateTime? _eta(Shipment shipment) {
    final minutes = shipment.order?.durationMin;
    if (minutes == null) return null;
    final start = shipment.pickedUpAt ?? shipment.assignedAt ?? DateTime.now();
    return start.add(Duration(minutes: minutes));
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.shipment});

  final Shipment shipment;

  @override
  Widget build(BuildContext context) {
    final order = shipment.order;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.sm, Gap.screen, Gap.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Рейс №${shipment.id}', style: AppText.displayMd),
                const SizedBox(height: 1),
                Text(
                  [
                    if (order != null && order.cargoType.isNotEmpty) order.cargoType,
                    if (order != null) Fmt.weight(order.weightKg),
                    Fmt.money(shipment.earning),
                  ].join(' · '),
                  style: AppText.bodySm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.md),
          StatusBadge.forShipment(shipment.status, compact: true),
        ],
      ),
    );
  }
}

class _Map extends StatelessWidget {
  const _Map({required this.shipment, required this.trips});

  final Shipment shipment;
  final TripController trips;

  @override
  Widget build(BuildContext context) {
    final position = trips.lastPosition;
    final driver = position == null
        ? null
        : (lat: position.latitude, lng: position.longitude);

    return Stack(
      children: [
        RouteMapView(
          route: shipment.mapRoute,
          height: 260,
          progress: _progress(),
          driver: driver,
          from: shipment.order?.from,
          to: shipment.order?.to,
          title: 'Рейс №${shipment.id}',
          onLocate: context.read<LocationService>().currentLatLng,
        ),
        Positioned(
          right: Gap.screen,
          bottom: Gap.screen,
          child: GpsPill(
            isTracking: trips.isTracking,
            bufferedPoints: trips.bufferedPointCount,
          ),
        ),
      ],
    );
  }

  /// Доля пройденного пути. Пока нет фикса GPS — оцениваем по статусу.
  double _progress() {
    final route = shipment.mapRoute;
    final position = trips.lastPosition;
    if (route == null || route.isEmpty || position == null) {
      return switch (shipment.status) {
        ShipmentStatus.assigned => 0.04,
        ShipmentStatus.pickedUp => 0.12,
        ShipmentStatus.inTransit => 0.55,
        _ => 1,
      };
    }

    // Ищем ближайшую точку маршрута к машине и берём её долю в ломаной.
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (final (index, point) in route.points.indexed) {
      final distance = LocationService.distanceKm(
        position.latitude,
        position.longitude,
        point.lat,
        point.lng,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    return (bestIndex / math.max(route.points.length - 1, 1)).clamp(0.02, 1.0);
  }
}

class _Remaining extends StatelessWidget {
  const _Remaining({required this.shipment, required this.trips});

  final Shipment shipment;
  final TripController trips;

  @override
  Widget build(BuildContext context) {
    final eta = ActiveTripScreen._eta(shipment);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.xl, Gap.screen, Gap.xl),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _BigStat(
                value: Fmt.km(_remainingKm()),
                label: 'осталось',
              ),
            ),
            const VerticalDivider(
              width: Gap.xxl,
              thickness: 1,
              color: AppColors.borderSubtle,
            ),
            Expanded(
              flex: 3,
              child: _BigStat(
                value: Fmt.duration(_remainingMinutes()),
                label: eta == null
                    ? 'до прибытия'
                    : 'до прибытия · ${Fmt.time(eta)}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Остаток по прямой до точки выгрузки.
  ///
  /// Пока GPS не дал фикс, честнее показать полную дистанцию заявки, чем
  /// выдумывать пройденный путь.
  double? _remainingKm() {
    final to = shipment.order?.to;
    final position = trips.lastPosition;
    if (to == null || position == null) return shipment.order?.distanceKm;
    return LocationService.distanceKm(
      position.latitude,
      position.longitude,
      to.lat,
      to.lng,
    );
  }

  int? _remainingMinutes() {
    final total = shipment.order?.durationMin;
    final totalKm = shipment.order?.distanceKm;
    final remaining = _remainingKm();
    if (total == null || totalKm == null || remaining == null || totalKm <= 0) {
      return total;
    }
    return (total * (remaining / totalKm)).round().clamp(0, total);
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.price.copyWith(fontSize: 34),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: AppText.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
}

class _Contacts extends StatelessWidget {
  const _Contacts({required this.shipment});

  final Shipment shipment;

  Future<void> _call(BuildContext context) async {
    final phone = shipment.order?.shipper?.phone;
    if (phone == null) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  @override
  Widget build(BuildContext context) {
    final to = shipment.order?.to;
    return Padding(
      padding: const EdgeInsets.all(Gap.screen),
      child: Row(
        children: [
          Expanded(
            child: SecondaryButton(
              label: 'Заказчик',
              icon: PhosphorIcons.phone(PhosphorIconsStyle.fill),
              onPressed: () => _call(context),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: to == null
                ? const SizedBox.shrink()
                : NavigateButton(lat: to.lat, lng: to.lng),
          ),
        ],
      ),
    );
  }
}

/// Нижняя панель со свайпом — единственное действие экрана.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.shipment, required this.isOffline});

  final Shipment shipment;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final next = shipment.status.next;

    return Container(
      padding: EdgeInsets.fromLTRB(
        Gap.screen,
        Gap.md,
        Gap.screen,
        Gap.md + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgBase,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: next == null
          ? PrimaryButton(
              label: 'Завершить рейс',
              height: Touch.cta,
              onPressed: () => _openFinish(context),
            )
          : SwipeAction(
              label: _label(next),
              icon: _icon(next),
              hint: isOffline
                  ? 'Статус сохранится на телефоне и уйдёт, когда появится сеть'
                  : null,
              onConfirmed: () => _advance(context, next),
            ),
    );
  }

  static String _label(ShipmentStatus next) => switch (next) {
        ShipmentStatus.pickedUp => 'Смахните: загрузился',
        ShipmentStatus.inTransit => 'Смахните: выехал',
        ShipmentStatus.delivered => 'Смахните: прибыл',
        _ => 'Смахните',
      };

  static IconData _icon(ShipmentStatus next) => switch (next) {
        ShipmentStatus.pickedUp => PhosphorIcons.package(PhosphorIconsStyle.fill),
        ShipmentStatus.inTransit => PhosphorIcons.arrowRight(),
        ShipmentStatus.delivered => PhosphorIcons.flagCheckered(),
        _ => PhosphorIcons.arrowRight(),
      };

  Future<void> _advance(BuildContext context, ShipmentStatus next) async {
    final trips = context.read<TripController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await trips.advanceStatus(next);
      // Прибытие ведёт сразу на экран завершения — это один непрерывный шаг.
      if (next == ShipmentStatus.delivered && context.mounted) {
        await _openFinish(context);
      }
    } on ApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openFinish(BuildContext context) async {
    final trips = context.read<TripController>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FinishTripScreen(shipment: trips.active ?? shipment),
      ),
    );
  }
}
