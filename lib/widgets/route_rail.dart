import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/tokens.dart';

/// Состояние точки маршрута.
enum RailStopState {
  /// Ещё не пройдена — полый кружок.
  upcoming,

  /// Текущая — заполненный кружок.
  current,

  /// Пройдена — галочка.
  done,
}

/// Одна точка маршрута: заголовок, подпись и состояние.
class RailStop {
  const RailStop({
    required this.title,
    this.subtitle,
    this.state = RailStopState.upcoming,
    this.marker,
    this.subtitleColor,
  });

  final String title;
  final String? subtitle;
  final RailStopState state;

  /// Буква в кружке («А», «Б») либо иконка машины — как в макете.
  final String? marker;

  /// Позволяет подсветить подпись янтарным («Загружено 13:40 · ожидает отправки»).
  final Color? subtitleColor;
}

/// Вертикальный рельс точек А→Б с соединительной линией.
///
/// Компактный вариант (карточка ленты) рисует маленькие кружки без букв;
/// развёрнутый (карточка заявки, активный рейс) — кружки 28 dp с маркерами.
class RouteRail extends StatelessWidget {
  const RouteRail({
    super.key,
    required this.stops,
    this.compact = false,
    this.titleStyle,
  });

  final List<RailStop> stops;
  final bool compact;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompact();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, stop) in stops.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Marker(stop: stop, isLast: index == stops.length - 1),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: index == stops.length - 1 ? 0 : Gap.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.title,
                          style: titleStyle ?? AppText.titleLg,
                        ),
                        if (stop.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            stop.subtitle!,
                            style: AppText.bodyMd.copyWith(color: stop.subtitleColor),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Компактный рельс карточки: точка — линия 24 — точка.
  Widget _buildCompact() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.textTertiary, width: 2),
                ),
              ),
              Container(width: 2, height: 24, color: AppColors.borderDefault),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, stop) in stops.take(2).indexed) ...[
                if (index > 0) const SizedBox(height: 14),
                Text(
                  stop.title,
                  style: titleStyle ?? AppText.titleLg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.stop, required this.isLast});

  final RailStop stop;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final (background, border, foreground) = switch (stop.state) {
      RailStopState.done => (AppColors.successSoft, AppColors.success, AppColors.success),
      RailStopState.current => (AppColors.accentSoft, AppColors.accent, AppColors.accent),
      RailStopState.upcoming => (
          AppColors.bgSurface2,
          AppColors.borderDefault,
          AppColors.textSecondary,
        ),
    };

    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(color: border),
          ),
          child: switch (stop.state) {
            RailStopState.done => Icon(PhosphorIcons.check(PhosphorIconsStyle.bold),
                size: 14, color: foreground),
            RailStopState.current when stop.marker == null =>
              Icon(PhosphorIcons.truck(PhosphorIconsStyle.fill), size: 15, color: foreground),
            _ => Text(
                stop.marker ?? '•',
                style: AppText.label.copyWith(color: foreground, letterSpacing: 0),
              ),
          },
        ),
        if (!isLast)
          Expanded(
            child: Container(width: 2, color: AppColors.borderSubtle),
          ),
      ],
    );
  }
}
