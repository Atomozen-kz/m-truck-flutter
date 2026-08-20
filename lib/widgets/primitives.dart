import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/tokens.dart';

/// Главная кнопка действия — янтарная, высотой 56, во всю ширину.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.height = Touch.min,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final double height;

  /// Кнопка по ширине текста, а не на всю карточку.
  ///
  /// В ленте таких кнопок столько же, сколько заявок: во всю ширину они
  /// сплошной янтарной лестницей перетягивают внимание с цен и адресов.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        height: height,
        width: compact ? null : double.infinity,
        child: Material(
          color: enabled ? AppColors.accent : AppColors.bgSurface2,
          borderRadius: Radii.cardAll,
          child: InkWell(
            onTap: enabled ? () {
              HapticFeedback.mediumImpact();
              onPressed!();
            } : null,
            borderRadius: Radii.cardAll,
            highlightColor: AppColors.accentPressed.withValues(alpha: 0.4),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? Gap.xl : 0),
              child: isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.bgBase,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(
                            icon,
                            size: 20,
                            color: enabled ? AppColors.bgBase : AppColors.textTertiary,
                          ),
                          const SizedBox(width: Gap.sm),
                        ],
                        Text(
                          label.toUpperCase(),
                          style: AppText.button.copyWith(
                            color: enabled ? AppColors.bgBase : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Вторичная кнопка — контурная, для действий второго плана.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Опасное действие («Отозвать отклик») — красный текст.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.textPrimary;
    return SizedBox(
      height: Touch.min,
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: Radii.cardAll,
        child: InkWell(
          onTap: onPressed,
          borderRadius: Radii.cardAll,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: Radii.cardAll,
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: color),
                    const SizedBox(width: Gap.sm),
                  ],
                  Text(label, style: AppText.bodyLg.copyWith(color: color)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Круглая кнопка-иконка с зоной нажатия 56×56.
class IconTapTarget extends StatelessWidget {
  const IconTapTarget({
    super.key,
    required this.icon,
    this.onPressed,
    this.color = AppColors.textSecondary,
    this.size = 24,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: Touch.min,
      height: Touch.min,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Карточка-поверхность: фон #151920, рамка #232A33, радиус 12.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.card),
    this.onTap,
    this.color = AppColors.bgSurface,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: color,
      borderRadius: Radii.cardAll,
      border: border ? Border.all(color: AppColors.borderSubtle) : null,
    );

    if (onTap == null) {
      return DecoratedBox(
        decoration: decoration,
        child: Padding(padding: padding, child: child),
      );
    }

    return Material(
      color: Colors.transparent,
      borderRadius: Radii.cardAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardAll,
        highlightColor: AppColors.bgSurface3.withValues(alpha: 0.6),
        child: Ink(
          decoration: decoration,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Чип фильтра высотой 48 с радиусом 100.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Крестик сброса на активном чипе.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.bgSurface2 : Colors.transparent,
      borderRadius: Radii.pillAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.pillAll,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: Radii.pillAll,
            border: Border.all(
              color: selected ? AppColors.borderDefault : AppColors.borderSubtle,
            ),
          ),
          child: Container(
            height: 48,
            padding: EdgeInsets.only(left: 18, right: onClear != null && selected ? 12 : 18),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppText.chip.copyWith(
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (onClear != null && selected) ...[
                  const SizedBox(width: Gap.sm),
                  GestureDetector(
                    onTap: onClear,
                    child: Icon(
                      PhosphorIcons.x(),
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Тройка показателей с вертикальными разделителями: «152 км | 3 ч 10 мин | 20 т».
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.items, this.padding});

  final List<({String value, String label})> items;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(
        horizontal: Gap.screen,
        vertical: Gap.lg,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, item) in items.indexed) ...[
              if (index > 0)
                const VerticalDivider(
                  width: Gap.xxl,
                  thickness: 1,
                  color: AppColors.borderSubtle,
                ),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(item.value, style: AppText.stat),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label.toUpperCase(),
                      style: AppText.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Пустое состояние: круглая иконка, заголовок, пояснение и действие.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: const BoxDecoration(
                color: AppColors.bgSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: AppColors.textTertiary),
            ),
            const SizedBox(height: Gap.xxl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.displayMd.copyWith(fontSize: 20),
            ),
            if (message != null) ...[
              const SizedBox(height: Gap.sm),
              Text(message!, textAlign: TextAlign.center, style: AppText.bodyMd),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Gap.xxl),
              SizedBox(
                width: 260,
                child: SecondaryButton(
                  label: actionLabel!,
                  icon: actionIcon,
                  onPressed: onAction,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Строка-разделитель на всю ширину экрана.
class HairLine extends StatelessWidget {
  const HairLine({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: indent,
        color: AppColors.borderSubtle,
      );
}

/// Небольшая метка-тег для характеристик груза: «20 т», «Тент».
class SpecTag extends StatelessWidget {
  const SpecTag(this.label, {super.key, this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.bgSurface2,
          borderRadius: Radii.pillAll,
          border: emphasized ? Border.all(color: AppColors.borderDefault) : null,
        ),
        child: Text(
          label,
          style: AppText.bodyMd.copyWith(
            fontSize: 13,
            color: emphasized ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      );
}
