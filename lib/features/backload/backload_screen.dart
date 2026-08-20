import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/api_client.dart';
import '../../data/models/models.dart';
import '../../data/repositories/marketplace_repository.dart';
import '../../services/sync_service.dart';
import '../../state/session_controller.dart';
import '../../widgets/order_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/status_badge.dart';
import '../marketplace/order_screen.dart';

/// S8 · Обратная загрузка — заявки из точки, где водитель только что выгрузился.
class BackloadScreen extends StatefulWidget {
  const BackloadScreen({super.key, required this.origin, this.shipment});

  /// Точка, из которой ищем груз.
  final GeoPoint origin;

  /// Завершённый рейс — показывается в шапке для контекста.
  final Shipment? shipment;

  @override
  State<BackloadScreen> createState() => _BackloadScreenState();
}

class _BackloadScreenState extends State<BackloadScreen> {
  /// Пресеты направления обратного пути.
  static const _radiusKm = 60.0;

  List<Order> _orders = const [];
  bool _isLoading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final orders = await context.read<MarketplaceRepository>().feed(
            MarketplaceFilters(
              nearLat: widget.origin.lat,
              nearLng: widget.origin.lng,
              radiusKm: _radiusKm,
              sort: 'distance',
            ),
          );
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

  /// Куда водитель хочет вернуться — обычно домой, в точку старта рейса.
  String? get _homeCity {
    final from = widget.shipment?.order?.from?.address;
    return from == null ? null : Fmt.shortPlace(from);
  }

  List<Order> get _visible {
    final home = _homeCity;
    return switch (_filter) {
      'home' when home != null => _orders
          .where((o) => Fmt.shortPlace(o.to?.address).toLowerCase() == home.toLowerCase())
          .toList(),
      'today' => _orders.where((o) {
          final at = o.pickupFrom;
          if (at == null) return false;
          final now = DateTime.now();
          return at.toLocal().day == now.day && at.toLocal().month == now.month;
        }).toList(),
      _ => _orders,
    };
  }

  Future<void> _openOrder(Order order, {bool autoBid = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderScreen(orderId: order.id, preloaded: order, autoBid: autoBid),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final canBid = context.select<SessionController, bool>((s) => s.canBid);
    final sync = context.watch<SyncService>();
    final visible = _visible;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(count: _orders.length),
            _OriginCard(origin: widget.origin, shipment: widget.shipment),
            _Filters(
              selected: _filter,
              homeCity: _homeCity,
              counts: _counts(),
              onSelect: (value) => setState(() => _filter = value),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? _empty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.accent,
                          backgroundColor: AppColors.bgSurface,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                              Gap.screen,
                              0,
                              Gap.screen,
                              Gap.xxl,
                            ),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: Gap.betweenCards),
                            itemBuilder: (context, index) {
                              final order = visible[index];
                              return OrderCard(
                                order: order,
                                badge: StatusBadge.backload(compact: true),
                                state: _cardState(order, canBid, sync),
                                onTap: () => _openOrder(order),
                                onBid: canBid
                                    ? () => _openOrder(order, autoBid: true)
                                    : null,
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, int> _counts() {
    final home = _homeCity;
    return {
      'all': _orders.length,
      if (home != null)
        'home': _orders
            .where((o) => Fmt.shortPlace(o.to?.address).toLowerCase() == home.toLowerCase())
            .length,
    };
  }

  OrderCardState _cardState(Order order, bool canBid, SyncService sync) {
    if (order.myBid != null) return OrderCardState.bidSent;
    if (sync.hasPendingBid(order.id)) return OrderCardState.bidQueued;
    if (!canBid) return OrderCardState.blocked;
    return OrderCardState.open;
  }

  Widget _empty() => EmptyState(
        icon: PhosphorIcons.arrowsClockwise(),
        title: _error == null
            ? 'Нет попутных заявок'
            : 'Не удалось загрузить заявки',
        message: _error ??
            'Из ${Fmt.shortPlace(widget.origin.address)} пока не грузят. '
                'Пришлём уведомление, когда появится заявка.',
        actionLabel: 'Обновить',
        actionIcon: PhosphorIcons.arrowClockwise(),
        onAction: _load,
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.screen, Gap.md),
        child: Row(
          children: [
            IconTapTarget(
              icon: PhosphorIcons.arrowLeft(),
              color: AppColors.textPrimary,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Обратная загрузка', style: AppText.displayMd),
                  const SizedBox(height: 1),
                  Text(
                    'Чтобы не гнать машину пустой',
                    style: AppText.bodySm,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Плашка «откуда ищем» — контекст, без которого список непонятен.
class _OriginCard extends StatelessWidget {
  const _OriginCard({required this.origin, this.shipment});

  final GeoPoint origin;
  final Shipment? shipment;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.lg),
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: Radii.cardAll,
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIcons.mapPin(PhosphorIconsStyle.fill),
              size: 22,
              color: AppColors.accent,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Из ${Fmt.shortPlace(origin.address)}',
                    style: AppText.bodyLg.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    shipment == null
                        ? origin.address
                        : 'Рейс №${shipment!.id} · выгрузка '
                            '${Fmt.pickupAt(shipment!.deliveredAt)}',
                    style: AppText.bodyMd.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.selected,
    required this.homeCity,
    required this.counts,
    required this.onSelect,
  });

  final String selected;
  final String? homeCity;
  final Map<String, int> counts;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48 + Gap.lg,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.lg),
          children: [
            FilterPill(
              label: 'Все · ${counts['all'] ?? 0}',
              selected: selected == 'all',
              onTap: () => onSelect('all'),
            ),
            if (homeCity != null) ...[
              const SizedBox(width: Gap.sm),
              FilterPill(
                label: 'В $homeCity · ${counts['home'] ?? 0}',
                selected: selected == 'home',
                onTap: () => onSelect('home'),
              ),
            ],
            const SizedBox(width: Gap.sm),
            FilterPill(
              label: 'Сегодня',
              selected: selected == 'today',
              onTap: () => onSelect('today'),
            ),
          ],
        ),
      );
}
