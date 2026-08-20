import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/tokens.dart';

/// Плашка «Нет сети» с объяснением, что происходит с данными.
///
/// Водителю важно не «ошибка сети», а ответ на два вопроса: что он сейчас
/// видит и что случится с тем, что он уже нажал.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.title,
    required this.message,
    this.pendingCount,
  });

  /// Вариант для ленты: показаны сохранённые заявки.
  factory OfflineBanner.cachedFeed(DateTime? updatedAt) => OfflineBanner(
        title: 'Нет сети',
        message: updatedAt == null
            ? 'Показаны сохранённые заявки'
            : 'Показаны заявки из кэша · обновлено ${_ago(updatedAt)}',
      );

  /// Вариант для рейса: действия уйдут сами.
  factory OfflineBanner.queuedActions(int pending) => OfflineBanner(
        title: 'Нет сети',
        message: 'Статусы отправятся автоматически',
        pendingCount: pending > 0 ? pending : null,
      );

  final String title;
  final String message;

  /// Счётчик отложенных действий в янтарном кружке справа.
  final int? pendingCount;

  static String _ago(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    return '${diff.inDays} дн назад';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.md),
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: Radii.cardAll,
      ),
      child: Row(
        children: [
          Icon(PhosphorIcons.wifiSlash(), size: 24, color: AppColors.accent),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.bodyLg.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(message, style: AppText.bodyMd.copyWith(fontSize: 13)),
              ],
            ),
          ),
          if (pendingCount != null) ...[
            const SizedBox(width: Gap.md),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$pendingCount',
                style: AppText.bodyMd.copyWith(
                  color: AppColors.bgBase,
                  fontWeight: FontWeight.w600,
                  fontFeatures: AppText.tabularFigures,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Небольшой индикатор поверх карты: «GPS активен» / «42 GPS-точки в буфере».
class GpsPill extends StatelessWidget {
  const GpsPill({super.key, required this.isTracking, this.bufferedPoints = 0});

  final bool isTracking;
  final int bufferedPoints;

  @override
  Widget build(BuildContext context) {
    final buffered = bufferedPoints > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: buffered ? AppColors.accentSoft : AppColors.bgSurface2.withValues(alpha: 0.92),
        borderRadius: Radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            buffered
                ? PhosphorIcons.clock(PhosphorIconsStyle.fill)
                : PhosphorIcons.circle(PhosphorIconsStyle.fill),
            size: buffered ? 14 : 10,
            color: buffered
                ? AppColors.accent
                : (isTracking ? AppColors.success : AppColors.textTertiary),
          ),
          const SizedBox(width: Gap.sm),
          Text(
            buffered
                ? '$bufferedPoints GPS-точки в буфере'
                : (isTracking ? 'GPS активен' : 'GPS выключен'),
            style: AppText.bodyMd.copyWith(
              fontSize: 13,
              color: buffered ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
