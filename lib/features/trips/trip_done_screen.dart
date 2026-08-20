import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/api_client.dart';
import '../../data/models/models.dart';
import '../../data/repositories/marketplace_repository.dart';
import '../../widgets/primitives.dart';
import '../backload/backload_screen.dart';

/// S4 · Рейс завершён — итог и предложение обратной загрузки.
///
/// Момент сразу после выгрузки — единственный, когда водителя реально волнует
/// обратный груз: машина пустая и стоит в чужом городе.
class TripDoneScreen extends StatefulWidget {
  const TripDoneScreen({super.key, required this.shipment});

  final Shipment shipment;

  @override
  State<TripDoneScreen> createState() => _TripDoneScreenState();
}

class _TripDoneScreenState extends State<TripDoneScreen> {
  List<Order> _backload = const [];
  bool _isLoading = true;

  GeoPoint? get _origin => widget.shipment.order?.to;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBackload());
  }

  /// Ищем заявки, отправляющиеся из точки, где водитель сейчас стоит.
  Future<void> _loadBackload() async {
    final origin = _origin;
    if (origin == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final orders = await context.read<MarketplaceRepository>().feed(
            MarketplaceFilters(
              nearLat: origin.lat,
              nearLng: origin.lng,
              radiusKm: 60,
              sort: 'distance',
            ),
          );
      if (!mounted) return;
      setState(() {
        _backload = orders.take(3).toList();
        _isLoading = false;
      });
    } on ApiException {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openBackload() {
    final origin = _origin;
    if (origin == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => BackloadScreen(origin: origin, shipment: widget.shipment),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shipment = widget.shipment;
    final order = shipment.order;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.xxl, Gap.screen, 0),
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: AppColors.successSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      PhosphorIcons.check(PhosphorIconsStyle.bold),
                      size: 32,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: Gap.xl),
                  Text('Рейс завершён', style: AppText.displayLg),
                  const SizedBox(height: 6),
                  Text(
                    [
                      Fmt.direction(order?.from?.address, order?.to?.address),
                      Fmt.km(order?.distanceKm),
                      Fmt.duration(shipment.actualMinutes ?? order?.durationMin),
                    ].join(' · '),
                    style: AppText.bodyMd.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: Gap.xl),
                  Text('НАЧИСЛЕНО', style: AppText.label),
                  const SizedBox(height: Gap.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(Fmt.money(shipment.earning), style: AppText.price),
                  ),
                  const SizedBox(height: Gap.xl),
                  const HairLine(),
                  const SizedBox(height: Gap.xl),
                  _BackloadSection(
                    isLoading: _isLoading,
                    orders: _backload,
                    origin: _origin,
                  ),
                  const SizedBox(height: Gap.xxl),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                Gap.screen,
                Gap.md,
                Gap.screen,
                Gap.md + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                children: [
                  if (_backload.isNotEmpty)
                    PrimaryButton(
                      label: 'Смотреть заявки обратно',
                      height: Touch.cta,
                      onPressed: _openBackload,
                    ),
                  const SizedBox(height: Gap.sm),
                  SizedBox(
                    height: Touch.min,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                      child: Text(
                        _backload.isEmpty ? 'В ленту заявок' : 'Позже',
                        style: AppText.bodyLg.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackloadSection extends StatelessWidget {
  const _BackloadSection({
    required this.isLoading,
    required this.orders,
    required this.origin,
  });

  final bool isLoading;
  final List<Order> orders;
  final GeoPoint? origin;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Gap.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (orders.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Обратная загрузка', style: AppText.displayMd),
          const SizedBox(height: 6),
          Text(
            'Пока нет заявок из ${Fmt.shortPlace(origin?.address)}. '
            'Мы пришлём уведомление, как только появятся.',
            style: AppText.bodyMd.copyWith(fontSize: 15),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Обратная загрузка', style: AppText.displayMd),
        const SizedBox(height: 6),
        Text(
          '${orders.length} ${_plural(orders.length)} из '
          '${Fmt.shortPlace(origin?.address)}',
          style: AppText.bodyMd.copyWith(fontSize: 15),
        ),
        const SizedBox(height: Gap.lg),
        for (final (index, order) in orders.indexed) ...[
          if (index > 0) const SizedBox(height: Gap.betweenCards),
          _BackloadRow(order: order),
        ],
      ],
    );
  }

  static String _plural(int count) {
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'заявок';
    return switch (count % 10) {
      1 => 'заявка',
      2 || 3 || 4 => 'заявки',
      _ => 'заявок',
    };
  }
}

/// Компактная строка заявки: направление, цена и условия.
class _BackloadRow extends StatelessWidget {
  const _BackloadRow({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.bgSurface,
        border: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    Fmt.direction(order.from?.address, order.to?.address),
                    style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Text(
                  Fmt.money(order.displayPrice),
                  style: AppText.stat.copyWith(fontSize: 19),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${Fmt.km(order.distanceKm)} · ${Fmt.weight(order.weightKg)}'
              '${order.requiresRefrigeration ? ' · Рефрижератор' : ''}',
              style: AppText.bodyMd,
            ),
            const SizedBox(height: 2),
            Text(
              'Погрузка ${Fmt.pickupAt(order.pickupFrom)}',
              style: AppText.bodyMd.copyWith(fontSize: 13),
            ),
          ],
        ),
      );
}
