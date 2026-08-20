import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/tokens.dart';
import '../data/models/models.dart';

/// Шаг сделки от отклика до сдачи груза.
enum DeliveryStep {
  bid('Отклик'),
  accepted('Принят'),
  pickup('Погрузка'),
  transit('В пути'),
  delivered('Сдан');

  const DeliveryStep(this.label);

  final String label;

  /// Где находится отклик: дальше шага «Принят» он сам по себе не уезжает.
  static DeliveryStep? forBid(BidStatus status) => switch (status) {
        BidStatus.pending => DeliveryStep.bid,
        BidStatus.accepted => DeliveryStep.accepted,
        BidStatus.rejected => null,
      };

  /// Где находится рейс.
  static DeliveryStep forShipment(ShipmentStatus status) => switch (status) {
        ShipmentStatus.assigned => DeliveryStep.accepted,
        ShipmentStatus.pickedUp => DeliveryStep.pickup,
        ShipmentStatus.inTransit => DeliveryStep.transit,
        ShipmentStatus.delivered || ShipmentStatus.closed => DeliveryStep.delivered,
      };
}

/// Полоса шагов сделки: от отклика до сдачи груза получателю.
///
/// Один бейдж статуса отвечает на вопрос «что сейчас», но не на вопрос
/// «сколько ещё осталось». Полоса показывает весь путь целиком, поэтому
/// отправленный отклик перестаёт выглядеть застрявшим.
class StepTrail extends StatelessWidget {
  const StepTrail({super.key, required this.current, this.rejected = false});

  /// Текущий шаг. `null` вместе с [rejected] означает «сделка не состоялась».
  final DeliveryStep? current;

  /// Заказчик выбрал другого перевозчика — путь оборвался на первом шаге.
  final bool rejected;

  factory StepTrail.forBid(Bid bid, {Key? key}) => StepTrail(
        key: key,
        current: DeliveryStep.forBid(bid.status),
        rejected: bid.status == BidStatus.rejected,
      );

  factory StepTrail.forShipment(ShipmentStatus status, {Key? key}) => StepTrail(
        key: key,
        current: DeliveryStep.forShipment(status),
      );

  @override
  Widget build(BuildContext context) {
    if (rejected) return const _RejectedTrail();

    final activeIndex = current?.index ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in DeliveryStep.values)
          Expanded(
            child: _Step(
              step: step,
              state: switch (step.index.compareTo(activeIndex)) {
                < 0 => _StepState.done,
                0 => _StepState.current,
                _ => _StepState.upcoming,
              },
              isFirst: step.index == 0,
              isLast: step.index == DeliveryStep.values.length - 1,
            ),
          ),
      ],
    );
  }
}

enum _StepState { done, current, upcoming }

class _Step extends StatelessWidget {
  const _Step({
    required this.step,
    required this.state,
    required this.isFirst,
    required this.isLast,
  });

  final DeliveryStep step;
  final _StepState state;
  final bool isFirst;
  final bool isLast;

  static const _dot = 14.0;

  @override
  Widget build(BuildContext context) {
    final reached = state != _StepState.upcoming;
    final color = reached ? AppColors.accent : AppColors.borderDefault;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _dot,
          child: Row(
            children: [
              // Соединители половинной ширины: линия идёт от центра к центру,
              // а у крайних шагов внешняя половина остаётся пустой.
              Expanded(child: _Connector(visible: !isFirst, done: reached)),
              _Dot(state: state, color: color),
              Expanded(
                child: _Connector(
                  visible: !isLast,
                  done: state == _StepState.done,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          step.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.bodyMd.copyWith(
            fontSize: 11,
            height: 1.2,
            color: switch (state) {
              _StepState.current => AppColors.textPrimary,
              _StepState.done => AppColors.textSecondary,
              _StepState.upcoming => AppColors.textTertiary,
            },
            fontWeight:
                state == _StepState.current ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state, required this.color});

  final _StepState state;
  final Color color;

  @override
  Widget build(BuildContext context) => switch (state) {
        // Пройденный шаг — залитый кружок с галочкой: цвета мало, когда экран
        // засвечен солнцем.
        _StepState.done => Container(
            width: _Step._dot,
            height: _Step._dot,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(PhosphorIcons.check(PhosphorIconsStyle.bold),
                size: 9, color: AppColors.bgBase),
          ),
        _StepState.current => Container(
            width: _Step._dot,
            height: _Step._dot,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accentSoft, width: 3),
            ),
          ),
        _StepState.upcoming => Container(
            width: _Step._dot - 4,
            height: _Step._dot - 4,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppColors.bgSurface2,
              shape: BoxShape.circle,
              border: Border.all(color: color),
            ),
          ),
      };
}

class _Connector extends StatelessWidget {
  const _Connector({required this.visible, required this.done});

  final bool visible;
  final bool done;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          height: 2,
          color: !visible
              ? Colors.transparent
              : done
                  ? AppColors.accent
                  : AppColors.borderSubtle,
        ),
      );
}

class _RejectedTrail extends StatelessWidget {
  const _RejectedTrail();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(
            PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              'Сделка не состоялась — заказчик выбрал другого перевозчика',
              style: AppText.bodyMd.copyWith(fontSize: 12),
              maxLines: 2,
            ),
          ),
        ],
      );
}
