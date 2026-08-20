import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/formatters.dart';
import '../core/theme/tokens.dart';
import '../data/models/models.dart';
import 'primitives.dart';
import 'route_rail.dart';
import 'status_badge.dart';

/// Состояние карточки заявки в ленте.
enum OrderCardState {
  /// Можно откликнуться.
  open,

  /// Отклик отправлен и ждёт ответа.
  bidSent,

  /// Отклик лежит в офлайн-очереди.
  bidQueued,

  /// Водитель на модерации — откликаться нельзя.
  blocked,
}

/// Карточка заявки: цена, маршрут, условия и действие.
///
/// Порядок продиктован тем, как водитель принимает решение: сначала деньги,
/// потом куда ехать, потом тоннаж и время, и только затем кнопка.
class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.state,
    this.onTap,
    this.onBid,
    this.badge,
  });

  final Order order;
  final OrderCardState state;
  final VoidCallback? onTap;
  final VoidCallback? onBid;

  /// Переопределение бейджа в правом верхнем углу.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      child: Column(
        // Карточка занимает ровно свою высоту — она живёт и в скролле ленты,
        // и в колонке экрана обратной загрузки.
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
                  child: Text(Fmt.money(order.displayPrice), style: AppText.price),
                ),
              ),
              const SizedBox(width: Gap.md),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: badge ?? _defaultBadge(),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          RouteRail(
            compact: true,
            stops: [
              RailStop(title: order.from?.address ?? '—'),
              RailStop(title: order.to?.address ?? '—'),
            ],
          ),
          const SizedBox(height: Gap.lg),
          Text(
            '${Fmt.km(order.distanceKm)} · ${Fmt.weight(order.weightKg)}',
            style: AppText.stat,
          ),
          const SizedBox(height: 6),
          Text(_conditions(), style: AppText.bodyMd),
          if (order.pickupDistanceKm != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(PhosphorIcons.mapPin(), size: 14, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  '${Fmt.km(order.pickupDistanceKm)} до погрузки',
                  style: AppText.bodyMd.copyWith(color: AppColors.accent, fontSize: 13),
                ),
              ],
            ),
          ],
          const SizedBox(height: Gap.lg),
          _action(),
        ],
      ),
    );
  }

  /// Бейдж нужен там, где есть что сказать про статус. Для обычной свежей
  /// заявки полезнее не слово «НОВАЯ», а возраст: он говорит, успел ли
  /// кто-то её разобрать.
  Widget _defaultBadge() => switch (state) {
        OrderCardState.bidSent => StatusBadge.bidSent(compact: true),
        OrderCardState.bidQueued => StatusBadge.queued(compact: true),
        _ when order.offeredToMe => StatusBadge.targeted(compact: true),
        _ => _PublishedAt(at: order.publishedAt),
      };

  /// «Тент · Погрузка сегодня 14:00»
  String _conditions() {
    final cargo = order.requiresRefrigeration
        ? 'Рефрижератор'
        : (order.cargoType.isEmpty ? 'Груз' : _capitalize(order.cargoType));
    final pickup = order.pickupFrom == null
        ? 'время погрузки уточняется'
        : 'погрузка ${Fmt.pickupAt(order.pickupFrom)}';
    return '$cargo · $pickup';
  }

  static String _capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  Widget _action() => switch (state) {
        OrderCardState.open => Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(
              label: 'Откликнуться',
              onPressed: onBid,
              compact: true,
              height: Touch.compact,
            ),
          ),
        OrderCardState.bidSent => _StatusStrip(
            icon: PhosphorIcons.clock(PhosphorIconsStyle.fill),
            label: 'Отклик отправлен · ${Fmt.money(order.myBid?.price)}',
            hint: 'Ждём ответа заказчика',
          ),
        OrderCardState.bidQueued => _StatusStrip(
            icon: PhosphorIcons.arrowClockwise(),
            label: 'Отклик в очереди',
            hint: 'Отправится автоматически, когда появится сеть',
          ),
        OrderCardState.blocked => const _StatusStrip(
            icon: null,
            label: 'Права на модерации',
            hint: 'Откликаться можно после проверки документов',
          ),
      };
}

/// Возраст заявки в правом верхнем углу карточки.
class _PublishedAt extends StatelessWidget {
  const _PublishedAt({required this.at});

  final DateTime? at;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.clock(), size: 13, color: AppColors.textTertiary),
          const SizedBox(width: 5),
          Text(
            Fmt.ago(at),
            style: AppText.caption,
            maxLines: 1,
          ),
        ],
      );
}

/// Полоса вместо кнопки, когда действие уже совершено или недоступно.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.icon, required this.label, this.hint});

  final IconData? icon;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: Touch.min,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: Radii.cardAll,
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.textTertiary),
                const SizedBox(width: Gap.sm),
              ],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: AppText.button.copyWith(color: AppColors.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: Gap.sm),
          Text(hint!, style: AppText.bodyMd.copyWith(fontSize: 13)),
        ],
      ],
    );
  }
}
