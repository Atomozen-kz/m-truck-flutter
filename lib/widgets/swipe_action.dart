import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/tokens.dart';

/// Подтверждение действия свайпом.
///
/// В кабине трясёт, и обычная кнопка ловит случайные нажатия. Смена статуса
/// рейса необратима, поэтому она требует осознанного протаскивания ручки
/// шириной 72 dp через всю дорожку.
class SwipeAction extends StatefulWidget {
  const SwipeAction({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.icon,
    this.enabled = true,
    this.hint,
  });

  final String label;
  final Future<void> Function() onConfirmed;
  final IconData? icon;
  final bool enabled;

  /// Пояснение под дорожкой («Статус сохранится на телефоне…»).
  final String? hint;

  @override
  State<SwipeAction> createState() => _SwipeActionState();
}

class _SwipeActionState extends State<SwipeAction> {
  static const _trackHeight = Touch.swipe;
  static const _padding = 6.0;

  /// Порог, после которого свайп считается завершённым.
  static const _threshold = 0.82;

  /// Возврат ручки анимируется, само перетаскивание следует за пальцем.
  static const _settleDuration = Duration(milliseconds: 220);

  double _dragFraction = 0;
  bool _isBusy = false;
  bool _isDragging = false;

  Future<void> _confirm() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    HapticFeedback.heavyImpact();
    try {
      await widget.onConfirmed();
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _dragFraction = 0;
        });
      }
    }
  }

  void _settle() {
    final reached = _dragFraction >= _threshold;
    setState(() {
      _isDragging = false;
      _dragFraction = reached ? 1 : 0;
    });
    if (reached) _confirm();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final travel = constraints.maxWidth - _trackHeight - _padding * 2;
            final knobLeft = _padding + travel * _dragFraction;

            return Container(
              height: _trackHeight,
              decoration: BoxDecoration(
                color: widget.enabled ? AppColors.bgSurface2 : AppColors.bgSurface,
                borderRadius: Radii.cardAll,
              ),
              child: Stack(
                children: [
                  // Подпись гаснет по мере протаскивания ручки.
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(left: _trackHeight + Gap.lg, right: Gap.lg),
                      child: Row(
                        children: [
                          Expanded(
                            child: Opacity(
                              opacity: (1 - _dragFraction * 1.4).clamp(0.0, 1.0),
                              child: Text(
                                widget.label.toUpperCase(),
                                style: AppText.button.copyWith(
                                  color: widget.enabled
                                      ? AppColors.textSecondary
                                      : AppColors.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          Icon(
                            PhosphorIcons.caretDoubleRight(),
                            size: 20,
                            color: AppColors.textTertiary
                                .withValues(alpha: (1 - _dragFraction * 1.4).clamp(0.0, 1.0)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    // Под пальцем ручка идёт без задержки, отпущенная —
                    // плавно возвращается на место.
                    duration: _isDragging ? Duration.zero : _settleDuration,
                    curve: Curves.easeOutCubic,
                    left: knobLeft,
                    top: _padding,
                    child: GestureDetector(
                      onHorizontalDragUpdate: widget.enabled && !_isBusy
                          ? (details) => setState(() {
                                _isDragging = true;
                                _dragFraction =
                                    (_dragFraction + details.delta.dx / travel).clamp(0.0, 1.0);
                              })
                          : null,
                      onHorizontalDragEnd: widget.enabled && !_isBusy ? (_) => _settle() : null,
                      child: Container(
                        width: _trackHeight - _padding * 2,
                        height: _trackHeight - _padding * 2,
                        decoration: BoxDecoration(
                          color: widget.enabled ? AppColors.accent : AppColors.bgSurface2,
                          borderRadius: Radii.cardAll,
                        ),
                        child: _isBusy
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: AppColors.bgBase,
                                ),
                              )
                            : Icon(
                                widget.icon ?? PhosphorIcons.arrowRight(),
                                size: 26,
                                color: widget.enabled
                                    ? AppColors.bgBase
                                    : AppColors.textTertiary,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (widget.hint != null) ...[
          const SizedBox(height: Gap.sm),
          Text(widget.hint!, style: AppText.bodyMd.copyWith(fontSize: 13)),
        ],
      ],
    );
  }
}
