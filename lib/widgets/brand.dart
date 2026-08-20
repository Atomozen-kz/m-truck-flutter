import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// Логотип приложения.
///
/// Исходник — квадрат с непрозрачной подложкой [AppColors.bgSurface], поэтому
/// рисуем его плиткой со скруглением карточки: так он читается как элемент
/// системы, а не как случайный прямоугольник поверх фона экрана.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64});

  /// Сторона квадратной плитки.
  final double size;

  static const _asset = 'assets/brand/logo.png';

  /// В исходнике вокруг марки широкие пустые поля — на плитке 64 dp она из-за
  /// них выглядит крошечной. Подложка совпадает с [AppColors.bgSurface], так
  /// что лишнее поле можно просто срезать зумом: шва не видно.
  static const _trim = 1.25;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: Radii.cardAll,
        child: SizedBox(
          width: size,
          height: size,
          child: Transform.scale(
            scale: _trim,
            child: Image.asset(
              _asset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'Mangystau Truck',
              // Если ассет не подхватился, экран входа не должен превращаться
              // в красный прямоугольник ошибки — оставляем пустую плитку.
              errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.bgSurface),
            ),
          ),
        ),
      );
}

/// Шапка экранов входа: логотип, название и роль.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.subtitle = 'Кабинет перевозчика'});

  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const AppLogo(),
          const SizedBox(width: Gap.lg),
          // Гибкая колонка: название не должно выталкивать себя за экран при
          // крупном системном шрифте или на узком телефоне.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('Mangystau Truck', style: AppText.displayMd),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppText.bodyMd.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      );
}
