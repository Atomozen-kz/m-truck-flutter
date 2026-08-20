import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/tokens.dart';

/// Крупная цифровая клавиатура на весь низ экрана.
///
/// Системную клавиатуру в перчатке не нажать: клавиши здесь высотой 60 dp и
/// живут в нижней трети экрана, до которой дотягивается большой палец.
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onLongBackspace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// Долгое нажатие на стрелку стирает всё поле.
  final VoidCallback? onLongBackspace;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.sm,
        Gap.sm,
        Gap.sm,
        Gap.sm + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _rows)
            _KeyRow(children: [for (final digit in row) _digitKey(digit)]),
          _KeyRow(
            children: [
              // Пустая клетка держит ноль по центру, как на телефонной клавиатуре.
              const SizedBox(height: _Key.height),
              _digitKey('0'),
              _Key(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onBackspace();
                },
                onLongPress: onLongBackspace,
                child: Icon(
                  PhosphorIcons.backspace(),
                  size: 26,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _digitKey(String digit) => _Key(
        onTap: () {
          HapticFeedback.selectionClick();
          onDigit(digit);
        },
        child: Text(
          digit,
          style: AppText.displayMd.copyWith(
            fontWeight: FontWeight.w500,
            fontFeatures: AppText.tabularFigures,
          ),
        ),
      );
}

/// Ряд из трёх клавиш равной ширины.
class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Row(
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0) const SizedBox(width: Gap.sm),
              Expanded(child: child),
            ],
          ],
        ),
      );
}

class _Key extends StatelessWidget {
  const _Key({required this.child, required this.onTap, this.onLongPress});

  static const height = 60.0;

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.bgSurface,
        borderRadius: Radii.cardAll,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: Radii.cardAll,
          highlightColor: AppColors.bgSurface3,
          child: SizedBox(height: height, child: Center(child: child)),
        ),
      );
}
