import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../services/connectivity_service.dart';
import '../../services/location_service.dart';
import '../../state/feed_controller.dart';
import '../../state/session_controller.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/order_card.dart';
import '../../widgets/orders_map.dart';
import '../../widgets/primitives.dart';
import 'order_screen.dart';
import 'orders_map_screen.dart';

/// S1 · Лента заявок — главный экран водителя.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FeedController>().load();
    });
  }

  Future<void> _openOrder(Order order, {bool autoBid = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderScreen(orderId: order.id, preloaded: order, autoBid: autoBid),
      ),
    );
    if (mounted) await context.read<FeedController>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedController>();
    final isOffline = context.watch<ConnectivityService>().isOffline;
    final canBid = context.select<SessionController, bool>((s) => s.canBid);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _Header(feed: feed, isOffline: isOffline),
          if (isOffline || feed.isFromCache) OfflineBanner.cachedFeed(feed.updatedAt),
          _FilterRow(feed: feed),
          Expanded(child: _body(feed, canBid)),
        ],
      ),
    );
  }

  Widget _body(FeedController feed, bool canBid) {
    if (feed.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (feed.orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: feed.refresh,
        color: AppColors.accent,
        backgroundColor: AppColors.bgSurface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
            _emptyState(feed),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: feed.refresh,
      color: AppColors.accent,
      backgroundColor: AppColors.bgSurface,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.xxl),
        // Первая строка списка — превью карты: скроллится вместе с лентой и
        // не отъедает высоту у карточек.
        itemCount: feed.orders.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: Gap.betweenCards),
        itemBuilder: (context, index) {
          if (index == 0) return _MapPreview(orders: feed.orders);
          final order = feed.orders[index - 1];
          return OrderCard(
            order: order,
            state: _cardState(feed, order, canBid),
            onTap: () => _openOrder(order),
            onBid: canBid ? () => _openOrder(order, autoBid: true) : null,
          );
        },
      ),
    );
  }

  OrderCardState _cardState(FeedController feed, Order order, bool canBid) {
    if (order.myBid != null) return OrderCardState.bidSent;
    if (feed.isBidQueued(order)) return OrderCardState.bidQueued;
    if (!canBid) return OrderCardState.blocked;
    return OrderCardState.open;
  }

  Widget _emptyState(FeedController feed) {
    if (feed.error != null && feed.orders.isEmpty) {
      return EmptyState(
        icon: PhosphorIcons.warningCircle(),
        title: 'Не удалось загрузить заявки',
        message: feed.error,
        actionLabel: 'Повторить',
        actionIcon: PhosphorIcons.arrowClockwise(),
        onAction: feed.refresh,
      );
    }

    if (feed.hasActiveFilters) {
      return EmptyState(
        icon: PhosphorIcons.package(),
        title: 'Пока нет заявок по вашим фильтрам',
        message: 'Проверяем новые заявки каждую минуту. '
            'Попробуйте расширить направление или тоннаж.',
        actionLabel: 'Сбросить фильтры',
        actionIcon: PhosphorIcons.arrowCounterClockwise(),
        onAction: feed.clearFilters,
      );
    }

    return EmptyState(
      icon: PhosphorIcons.package(),
      title: 'Пока нет открытых заявок',
      message: 'Новые заявки появляются в течение дня — потяните вниз, чтобы обновить.',
    );
  }
}

/// Превью карты над лентой: где лежат грузы, одним взглядом.
///
/// Превью намеренно без жестов — иначе оно съедало бы прокрутку ленты. Тап и
/// кнопка разворота ведут на полноэкранную карту, где жесты работают.
class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.orders});

  final List<Order> orders;

  void _open(BuildContext context, {int? initialId}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrdersMapScreen(orders: orders, initialId: initialId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.betweenCards),
        child: ClipRRect(
          borderRadius: Radii.cardAll,
          child: GestureDetector(
            onTap: () => _open(context),
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                OrdersMapView(
                  orders: orders,
                  height: 150,
                  onLocate: context.read<LocationService>().currentLatLng,
                ),
                Positioned(
                  left: Gap.md,
                  top: Gap.md,
                  child: _ExpandButton(onTap: () => _open(context)),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ExpandButton extends StatelessWidget {
  const _ExpandButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.bgSurface2.withValues(alpha: 0.92),
        borderRadius: Radii.cardAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.cardAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIcons.arrowsOut(),
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'НА КАРТЕ',
                  style: AppText.label.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.feed, required this.isOffline});

  final FeedController feed;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.sm, Gap.sm, Gap.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Заявки', style: AppText.displayLg),
                const SizedBox(height: 2),
                Text(_subtitle(), style: AppText.bodySm),
              ],
            ),
          ),
          if (feed.isRefreshing)
            const SizedBox(
              width: Touch.min,
              height: Touch.min,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            )
          else
            IconTapTarget(
              icon: PhosphorIcons.slidersHorizontal(),
              tooltip: 'Фильтры',
              onPressed: () => _showFilters(context),
            ),
        ],
      ),
    );
  }

  String _subtitle() {
    final count = feed.orders.length;
    final word = _plural(count, 'заявка', 'заявки', 'заявок');
    final parts = <String>[
      '$count $word${feed.isFromCache ? ' из кэша' : ''}',
      if (feed.hasActiveFilters)
        '${feed.activeFilterCount} '
            '${_plural(feed.activeFilterCount, 'фильтр', 'фильтра', 'фильтров')}',
      _updated(),
    ];
    return parts.join(' · ');
  }

  String _updated() {
    final at = feed.updatedAt;
    if (at == null) return 'ещё не обновлялось';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'обновлено только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    return '${diff.inDays} дн назад';
  }

  /// Русские числительные: 1 заявка, 2 заявки, 5 заявок.
  static String _plural(int count, String one, String few, String many) {
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return many;
    return switch (count % 10) {
      1 => one,
      2 || 3 || 4 => few,
      _ => many,
    };
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      builder: (sheetContext) => _FilterSheet(feed: feed),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.feed});

  final FeedController feed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48 + Gap.lg,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.lg),
        children: [
          FilterPill(
            label: 'Все',
            selected: !feed.hasActiveFilters,
            onTap: feed.clearFilters,
          ),
          for (final chip in FeedController.chips) ...[
            const SizedBox(width: Gap.sm),
            FilterPill(
              label: chip.label,
              selected: feed.isChipActive(chip.id),
              onTap: () => feed.toggleChip(chip.id),
              onClear: () => feed.toggleChip(chip.id),
            ),
          ],
        ],
      ),
    );
  }
}

/// Лист фильтров — тот же набор пресетов, что и чипы, но с пояснениями.
class _FilterSheet extends StatelessWidget {
  const _FilterSheet({required this.feed});

  final FeedController feed;

  static const _descriptions = {
    'near': 'Заявки в радиусе 100 км от вашего положения',
    'light': 'Груз до 20 тонн',
    'fridge': 'Только скоропортящийся груз — нужен рефрижератор',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Gap.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Фильтры', style: AppText.displayMd)),
                IconTapTarget(
                  icon: PhosphorIcons.x(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            for (final chip in FeedController.chips)
              ListenableBuilder(
                listenable: feed,
                builder: (context, _) => _FilterRowTile(
                  label: chip.label,
                  description: _descriptions[chip.id] ?? '',
                  selected: feed.isChipActive(chip.id),
                  onTap: () => feed.toggleChip(chip.id),
                ),
              ),
            const SizedBox(height: Gap.lg),
            SecondaryButton(
              label: 'Сбросить всё',
              icon: PhosphorIcons.arrowCounterClockwise(),
              onPressed: () {
                feed.clearFilters();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRowTile extends StatelessWidget {
  const _FilterRowTile({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppText.bodyLg),
                    const SizedBox(height: 2),
                    Text(description, style: AppText.bodyMd.copyWith(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: Gap.lg),
              Icon(
                selected
                    ? PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)
                    : PhosphorIcons.circle(),
                size: 26,
                color: selected ? AppColors.accent : AppColors.borderDefault,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
