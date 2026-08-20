import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/tokens.dart';

/// Почему действие недоступно.
///
/// Приложение водителя ходит в API платформы и не умеет ничего сверх того, что
/// API принимает. Пункт, за которым нет эндпоинта, честнее показать закрытым с
/// объяснением, чем прятать или притворяться, что он работает.
class LockedReason {
  const LockedReason({
    required this.title,
    required this.message,
    this.workaround,
  });

  /// Название функции — то же, что в строке списка.
  final String title;

  /// Что именно не работает и почему.
  final String message;

  /// Что водителю делать вместо этого.
  final String? workaround;

  /// Данные меняет диспетчер: у мобильного API нет ни одного метода записи в
  /// профиль, машину или документы.
  static const askDispatcher =
      'Пока меняется только через диспетчера — позвоните ему, и он поправит '
      'данные в системе.';
}

/// Показывает, почему пункт закрыт.
Future<void> showLockedSheet(BuildContext context, LockedReason reason) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(Gap.screen, Gap.xl, Gap.screen, Gap.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.bgSurface2,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      PhosphorIcons.lockSimple(PhosphorIconsStyle.fill),
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(child: Text(reason.title, style: AppText.displayMd)),
                ],
              ),
              const SizedBox(height: Gap.lg),
              Text(reason.message, style: AppText.bodyMd.copyWith(fontSize: 15)),
              if (reason.workaround != null) ...[
                const SizedBox(height: Gap.md),
                Text(
                  reason.workaround!,
                  style: AppText.bodyMd.copyWith(fontSize: 15),
                ),
              ],
            ],
          ),
        ),
      ),
    );

/// Строка настроек. Закрытая строка приглушена и помечена замком.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.locked,
  });

  final IconData icon;
  final String label;

  /// Текущее значение справа: «Русский», «Водитель», «Тент».
  final String? value;

  final VoidCallback? onTap;

  /// Заполнено — строка закрыта и по тапу объясняет почему.
  final LockedReason? locked;

  @override
  Widget build(BuildContext context) {
    final reason = locked;
    final muted = reason != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: reason != null ? () => showLockedSheet(context, reason) : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.screen, vertical: Gap.lg),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: muted ? AppColors.textTertiary : AppColors.textSecondary,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  label,
                  style: AppText.bodyLg.copyWith(
                    fontSize: 15,
                    color: muted ? AppColors.textSecondary : AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: Gap.sm),
                Flexible(
                  child: Text(
                    value!,
                    style: AppText.bodyMd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: Gap.sm),
              ],
              Icon(
                muted ? PhosphorIcons.lockSimple() : PhosphorIcons.caretRight(),
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
