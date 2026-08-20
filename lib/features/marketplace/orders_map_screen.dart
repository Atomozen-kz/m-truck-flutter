import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../services/location_service.dart';
import '../../widgets/orders_map.dart';
import '../../widgets/primitives.dart';
import '../../widgets/route_rail.dart';
import 'order_screen.dart';

/// S1a · Карта заявок — та же лента, но видно, где что лежит.
///
/// Метка показывает цену: по ней водитель и выбирает. Тап по метке рисует путь
/// заявки и открывает карточку снизу с дистанцией и адресами.
class OrdersMapScreen extends StatefulWidget {
  const OrdersMapScreen({super.key, required this.orders, this.initialId});

  final List<Order> orders;

  /// С какой заявки открыться — например, той, что была под пальцем в ленте.
  final int? initialId;

  @override
  State<OrdersMapScreen> createState() => _OrdersMapScreenState();
}

class _OrdersMapScreenState extends State<OrdersMapScreen> {
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialId;
  }

  Order? get _selected {
    for (final order in widget.orders) {
      if (order.id == _selectedId) return order;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final withPoint = widget.orders.where((o) => o.from != null).length;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.screen, Gap.sm),
              child: Row(
                children: [
                  IconTapTarget(
                    icon: PhosphorIcons.arrowLeft(),
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Назад',
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(width: Gap.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Заявки на карте', style: AppText.displayMd),
                        const SizedBox(height: 1),
                        Text(
                          '${Fmt.orders(withPoint)} с точкой погрузки',
                          style: AppText.bodySm,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: OrdersMapView(
              orders: widget.orders,
              height: double.infinity,
              interactive: true,
              selectedId: _selectedId,
              onSelect: (order) => setState(() => _selectedId = order.id),
              onLocate: context.read<LocationService>().currentLatLng,
            ),
          ),
          if (selected == null)
            const _Hint()
          else
            _SelectedCard(
              order: selected,
              onClose: () => setState(() => _selectedId = null),
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          Gap.screen,
          Gap.lg,
          Gap.screen,
          Gap.lg + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: const BoxDecoration(
          color: AppColors.bgBase,
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: Row(
          children: [
            Icon(PhosphorIcons.handTap(), size: 20, color: AppColors.textTertiary),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                'Нажмите на цену, чтобы увидеть путь заявки',
                style: AppText.bodyMd.copyWith(fontSize: 14),
              ),
            ),
          ],
        ),
      );
}

/// Карточка выбранной заявки под картой.
class _SelectedCard extends StatelessWidget {
  const _SelectedCard({required this.order, required this.onClose});

  final Order order;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          Gap.screen,
          Gap.lg,
          Gap.screen,
          Gap.md + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: const BoxDecoration(
          color: AppColors.bgBase,
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Fmt.money(order.displayPrice),
                      style: AppText.price.copyWith(fontSize: 28),
                    ),
                  ),
                ),
                IconTapTarget(
                  icon: PhosphorIcons.x(),
                  onPressed: onClose,
                  tooltip: 'Снять выделение',
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            RouteRail(
              compact: true,
              stops: [
                RailStop(title: order.from?.address ?? '—'),
                RailStop(title: order.to?.address ?? '—'),
              ],
            ),
            const SizedBox(height: Gap.md),
            Text(
              [
                Fmt.km(order.distanceKm),
                Fmt.duration(order.durationMin),
                Fmt.weight(order.weightKg),
                if (order.pickupDistanceKm != null)
                  '${Fmt.km(order.pickupDistanceKm)} до погрузки',
              ].join(' · '),
              style: AppText.bodyMd.copyWith(fontSize: 13),
            ),
            const SizedBox(height: Gap.lg),
            PrimaryButton(
              label: 'Открыть заявку',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OrderScreen(orderId: order.id, preloaded: order),
                ),
              ),
            ),
          ],
        ),
      );
}
