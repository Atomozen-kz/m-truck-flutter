import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/tokens.dart';
import '../data/models/models.dart';

/// Пилюля статуса: цвет, иконка и текст одновременно.
///
/// Экран засвечен солнцем, водитель может быть дальтоником — одного цвета
/// недостаточно, поэтому иконка и подпись обязательны.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
    this.compact = false,
  });

  /// «Новая заявка» — заявка доступна для отклика.
  factory StatusBadge.newOrder({bool compact = false}) => StatusBadge(
        label: 'НОВАЯ',
        icon: PhosphorIcons.circle(PhosphorIconsStyle.fill),
        color: AppColors.info,
        background: AppColors.infoSoft,
        compact: compact,
      );

  /// Заявка адресована лично этому водителю.
  factory StatusBadge.targeted({bool compact = false}) => StatusBadge(
        label: 'ВАМ ЛИЧНО',
        icon: PhosphorIcons.userFocus(),
        color: AppColors.accent,
        background: AppColors.accentSoft,
        compact: compact,
      );

  /// Обратная загрузка — попутный рейс из точки выгрузки.
  factory StatusBadge.backload({bool compact = false}) => StatusBadge(
        label: 'ПОПУТНО',
        icon: PhosphorIcons.arrowsClockwise(),
        color: AppColors.info,
        background: AppColors.infoSoft,
        compact: compact,
      );

  /// Отклик отправлен, ждём ответа заказчика.
  factory StatusBadge.bidSent({bool compact = false}) => StatusBadge(
        label: 'ОТКЛИК ОТПРАВЛЕН',
        icon: PhosphorIcons.clock(PhosphorIconsStyle.fill),
        color: AppColors.accent,
        background: AppColors.accentSoft,
        compact: compact,
      );

  /// Отклик лежит в офлайн-очереди.
  factory StatusBadge.queued({bool compact = false}) => StatusBadge(
        label: 'В ОЧЕРЕДИ',
        icon: PhosphorIcons.clockCounterClockwise(),
        color: AppColors.accent,
        background: AppColors.accentSoft,
        compact: compact,
      );

  /// Отклик принят, рейс назначен.
  factory StatusBadge.assigned({String? label, bool compact = false}) => StatusBadge(
        label: label ?? 'РЕЙС НАЗНАЧЕН',
        icon: PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
        color: AppColors.success,
        background: AppColors.successSoft,
        compact: compact,
      );

  /// Рейс выполняется, GPS активен.
  factory StatusBadge.inTransit({bool compact = false}) => StatusBadge(
        label: 'В ПУТИ',
        icon: PhosphorIcons.play(PhosphorIconsStyle.fill),
        color: AppColors.accent,
        background: AppColors.accentSoft,
        compact: compact,
      );

  /// Груз выгружен, оплата начислена.
  factory StatusBadge.completed({bool compact = false}) => StatusBadge(
        label: 'ЗАВЕРШЁН',
        icon: PhosphorIcons.checks(),
        color: AppColors.neutral,
        background: AppColors.neutralSoft,
        compact: compact,
      );

  /// Заказчик выбрал другого перевозчика.
  factory StatusBadge.rejected({bool compact = false}) => StatusBadge(
        label: 'ОТКЛОНЁН',
        icon: PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
        color: AppColors.danger,
        background: AppColors.dangerSoft,
        compact: compact,
      );

  /// Деньги за рейс пришли.
  factory StatusBadge.paid({bool compact = false}) => StatusBadge(
        label: 'ВЫПЛАЧЕНО',
        icon: PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
        color: AppColors.success,
        background: AppColors.successSoft,
        compact: compact,
      );

  /// Рейс сдан, деньги ещё не пришли.
  factory StatusBadge.awaitingPayout({bool compact = false}) => StatusBadge(
        label: 'ОЖИДАЕТ',
        icon: PhosphorIcons.hourglass(PhosphorIconsStyle.fill),
        color: AppColors.accent,
        background: AppColors.accentSoft,
        compact: compact,
      );

  /// Бейдж по статусу выплаты — используется на экране «Выплаты».
  factory StatusBadge.forPayout(PayoutStatus status, {bool compact = false}) =>
      switch (status) {
        PayoutStatus.paid => StatusBadge.paid(compact: compact),
        PayoutStatus.pending => StatusBadge.awaitingPayout(compact: compact),
      };

  /// Бейдж по статусу отклика — используется в списке «Мои отклики».
  factory StatusBadge.forBid(Bid bid, {bool compact = false}) => switch (bid.status) {
        BidStatus.pending => StatusBadge(
            label: 'ЖДЁТ ОТВЕТА',
            icon: PhosphorIcons.clock(PhosphorIconsStyle.fill),
            color: AppColors.accent,
            background: AppColors.accentSoft,
            compact: compact,
          ),
        BidStatus.accepted => StatusBadge.assigned(compact: compact),
        BidStatus.rejected => StatusBadge.rejected(compact: compact),
      };

  /// Бейдж по статусу рейса.
  factory StatusBadge.forShipment(ShipmentStatus status, {bool compact = false}) =>
      switch (status) {
        ShipmentStatus.assigned => StatusBadge.assigned(compact: compact),
        ShipmentStatus.pickedUp => StatusBadge(
            label: 'ЗАГРУЖЕН',
            icon: PhosphorIcons.package(PhosphorIconsStyle.fill),
            color: AppColors.accent,
            background: AppColors.accentSoft,
            compact: compact,
          ),
        ShipmentStatus.inTransit => StatusBadge.inTransit(compact: compact),
        ShipmentStatus.delivered ||
        ShipmentStatus.closed =>
          StatusBadge.completed(compact: compact),
      };

  final String label;
  final IconData icon;
  final Color color;
  final Color background;

  /// Уменьшенный вариант для плотных списков.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 10.0 : 12.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(color: background, borderRadius: Radii.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 6),
          Text(label, style: AppText.label.copyWith(color: color)),
        ],
      ),
    );
  }
}
