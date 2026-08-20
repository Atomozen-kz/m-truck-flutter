import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../services/connectivity_service.dart';
import '../../services/sync_service.dart';
import '../../state/trip_controller.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/primitives.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/step_trail.dart';
import '../marketplace/order_screen.dart';
import 'active_trip_screen.dart';

/// S5 · Мои рейсы — отклики и назначенные рейсы.
///
/// Когда рейс активен, он вытесняет список целиком: за рулём водителю нужен
/// один экран, а не вкладки.
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TripController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final trips = context.watch<TripController>();
    final active = trips.active;

    // Активный рейс — самостоятельный экран поверх вкладки.
    if (active != null && active.status.isLive) {
      return ActiveTripScreen(shipment: active);
    }

    final isOffline = context.watch<ConnectivityService>().isOffline;
    final sync = context.watch<SyncService>();

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.sm, Gap.screen, Gap.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Мои рейсы', style: AppText.displayLg),
            ),
          ),
          if (isOffline)
            OfflineBanner.queuedActions(sync.pendingActions)
          else if (trips.error != null)
            _ErrorNotice(message: trips.error!, onRetry: trips.refresh),
          _Tabs(
            selected: _tab,
            bidCount: trips.openBids.length,
            shipmentCount: trips.liveShipments.length,
            onSelect: (index) => setState(() => _tab = index),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: trips.refresh,
              color: AppColors.accent,
              backgroundColor: AppColors.bgSurface,
              child: _tab == 0
                  ? _ShipmentsList(trips: trips)
                  : _BidsList(trips: trips),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.selected,
    required this.bidCount,
    required this.shipmentCount,
    required this.onSelect,
  });

  final int selected;
  final int bidCount;
  final int shipmentCount;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.screen),
      child: Row(
        children: [
          _Tab(
            label: 'Рейсы',
            count: shipmentCount,
            selected: selected == 0,
            onTap: () => onSelect(0),
          ),
          const SizedBox(width: Gap.xxl),
          _Tab(
            label: 'Отклики',
            count: bidCount,
            selected: selected == 1,
            onTap: () => onSelect(1),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Text(
              '$label · $count',
              style: AppText.bodyLg.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.textPrimary : AppColors.textTertiary,
                fontFeatures: AppText.tabularFigures,
              ),
            ),
          ),
          Container(
            height: 2,
            width: 64,
            color: selected ? AppColors.accent : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

class _BidsList extends StatelessWidget {
  const _BidsList({required this.trips});

  final TripController trips;

  @override
  Widget build(BuildContext context) {
    final bids = trips.openBids;

    if (bids.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.1),
          EmptyState(
            icon: PhosphorIcons.paperPlaneTilt(),
            title: 'Пока нет откликов',
            message: 'Найдите заявку на бирже и предложите свою цену. '
                'Принятый отклик переедет во вкладку «Рейсы».',
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.lg, Gap.screen, Gap.xxl),
      itemCount: bids.length,
      separatorBuilder: (_, _) => const SizedBox(height: Gap.betweenCards),
      itemBuilder: (context, index) => _BidCard(bid: bids[index]),
    );
  }
}

class _BidCard extends StatelessWidget {
  const _BidCard({required this.bid});

  final Bid bid;

  @override
  Widget build(BuildContext context) {
    final order = bid.order;
    final isAccepted = bid.status == BidStatus.accepted;

    return SurfaceCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OrderScreen(orderId: bid.orderId, preloaded: order),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge.forBid(bid, compact: true),
              const Spacer(),
              Text(Fmt.ago(bid.createdAt), style: AppText.caption),
            ],
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  Fmt.direction(order?.from?.address, order?.to?.address),
                  style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAccepted)
                Icon(PhosphorIcons.caretRight(), size: 20, color: AppColors.textTertiary),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.money(bid.price), style: AppText.stat.copyWith(fontSize: 24)),
              const Spacer(),
              if (order?.priceOffer != null && order!.priceOffer != bid.price)
                Text(
                  bid.status == BidStatus.rejected
                      ? 'ушёл за ${Fmt.money(order.priceFinal ?? order.priceOffer)}'
                      : 'заказчик просил ${Fmt.money(order.priceOffer)}',
                  style: AppText.bodyMd.copyWith(fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_details(order), style: AppText.bodyMd.copyWith(fontSize: 13)),
          const SizedBox(height: Gap.lg),
          StepTrail.forBid(bid),
        ],
      ),
    );
  }

  String _details(Order? order) {
    if (bid.status == BidStatus.rejected) return 'Заказчик выбрал другого перевозчика';
    return [
      if (order?.distanceKm != null) Fmt.km(order!.distanceKm),
      if (order != null) Fmt.weight(order.weightKg),
      if (bid.etaAt != null) 'подача ${Fmt.pickupAt(bid.etaAt)}',
    ].join(' · ');
  }
}

class _ShipmentsList extends StatelessWidget {
  const _ShipmentsList({required this.trips});

  final TripController trips;

  @override
  Widget build(BuildContext context) {
    final shipments = trips.liveShipments;

    if (shipments.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.1),
          EmptyState(
            icon: PhosphorIcons.truck(),
            title: 'Нет назначенных рейсов',
            message: 'Как только заказчик примет отклик, рейс появится здесь.',
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.lg, Gap.screen, Gap.xxl),
      itemCount: shipments.length,
      separatorBuilder: (_, _) => const SizedBox(height: Gap.betweenCards),
      itemBuilder: (context, index) {
        final shipment = shipments[index];
        return SurfaceCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(body: ActiveTripScreen(shipment: shipment)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusBadge.forShipment(shipment.status, compact: true),
                  const Spacer(),
                  Text('Рейс №${shipment.id}', style: AppText.caption),
                ],
              ),
              const SizedBox(height: Gap.md),
              Text(
                Fmt.direction(
                  shipment.order?.from?.address,
                  shipment.order?.to?.address,
                ),
                style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(Fmt.money(shipment.earning), style: AppText.stat.copyWith(fontSize: 24)),
              const SizedBox(height: 6),
              Text(
                '${Fmt.km(shipment.order?.distanceKm)} · '
                '${Fmt.weight(shipment.order?.weightKg)}',
                style: AppText.bodyMd.copyWith(fontSize: 13),
              ),
              const SizedBox(height: Gap.lg),
              StepTrail.forShipment(shipment.status),
            ],
          ),
        );
      },
    );
  }
}

/// Полоса с ошибкой загрузки: сбой сервера не должен растворяться в тишине.
class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.md),
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: Radii.cardAll,
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIcons.warningCircle(PhosphorIconsStyle.fill),
              size: 22,
              color: AppColors.danger,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(message, style: AppText.bodyMd.copyWith(fontSize: 13)),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Повторить',
                style: AppText.bodyMd.copyWith(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}
