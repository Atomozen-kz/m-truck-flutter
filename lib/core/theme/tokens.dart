import 'package:flutter/widgets.dart';

/// Дизайн-токены Mangystau Truck · приложение водителя.
///
/// Источник — канвас Brilliant «Driver / Design Tokens». Тёмная тема здесь
/// основная, а не опция: ночные рейсы, засветка солнцем, экономия батареи.
/// Единственный акцент — янтарный; иерархия строится размером и пространством.
abstract final class AppColors {
  // Поверхности
  static const bgBase = Color(0xFF0C0E11); // фон экрана
  static const bgSurface = Color(0xFF151920); // карточки
  static const bgSurface2 = Color(0xFF1E242D); // вложенное
  static const bgSurface3 = Color(0xFF2A313C); // pressed

  // Границы
  static const borderSubtle = Color(0xFF232A33); // разделители
  static const borderDefault = Color(0xFF39424F); // рамки

  // Текст
  static const textPrimary = Color(0xFFF7F9FB); // цены
  static const textSecondary = Color(0xFF98A2B0); // адреса
  static const textTertiary = Color(0xFF6B7684); // подписи

  // Акцент
  static const accent = Color(0xFFF59E0B); // CTA, деньги
  static const accentPressed = Color(0xFFD97F06);
  static const accentSoft = Color(0xFF3A2A08); // фон бейджа

  // Семантика статусов: цвет + фон бейджа
  static const info = Color(0xFF60A5FA);
  static const infoSoft = Color(0xFF122036);
  static const success = Color(0xFF4ADE80);
  static const successSoft = Color(0xFF0F2A18);
  static const danger = Color(0xFFF87171);
  static const dangerSoft = Color(0xFF33161A);
  static const neutral = textSecondary;
  static const neutralSoft = bgSurface2;
}

/// Шкала отступов — сетка 8pt с шагами 4 и 20.
///
/// Отступ экрана 16 · паддинг карточки 16 · зазор между карточками 12.
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  static const screen = 16.0;
  static const card = 16.0;
  static const betweenCards = 12.0;
}

/// Радиусы. Выше 16 для прямоугольных блоков не поднимаемся, теней нет —
/// глубина передаётся уровнями поверхности.
abstract final class Radii {
  static const card = Radius.circular(12);
  static const sheet = Radius.circular(16);
  static const pill = Radius.circular(100);

  static const cardAll = BorderRadius.all(card);
  static const sheetAll = BorderRadius.all(sheet);
  static const pillAll = BorderRadius.all(pill);
  static const sheetTop = BorderRadius.vertical(top: sheet);
}

/// Минимальные размеры зон нажатия. Водитель в перчатке, кабина трясётся —
/// ключевые действия живут в нижней трети экрана.
abstract final class Touch {
  static const min = 56.0;

  /// Кнопка второго плана внутри карточки: в ленте их столько же, сколько
  /// заявок, и на 56 они забивают собой цену и адреса. 48 всё ещё уверенно
  /// больше пальца (Material и HIG просят от 44).
  static const compact = 48.0;

  static const cta = 64.0;
  static const swipe = 72.0;
}

/// Типографика Inter. `tnum` обязателен на ценах, километрах, тоннах и
/// времени — цифры не должны прыгать при обновлении.
abstract final class AppText {
  static const _tnum = [FontFeature.tabularFigures()];

  /// 32/40 · 700 · tnum — цена рейса.
  static const price = TextStyle(
    fontFamily: 'Inter',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: AppColors.textPrimary,
    fontFeatures: _tnum,
  );

  /// 28/36 · 600 — заголовок экрана.
  static const displayLg = TextStyle(
    fontFamily: 'Inter',
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  /// 22/30 · 600 — заголовок секции.
  static const displayMd = TextStyle(
    fontFamily: 'Inter',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  /// 20/28 · 600 · tnum — «152 км · 20 т · 1 ч 20 мин».
  static const stat = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
    fontFeatures: _tnum,
  );

  /// 18/26 · 600 — адрес точки маршрута.
  static const titleLg = TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  /// 16/24 · 400.
  static const bodyLg = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  /// 16 · 600 — надпись на CTA.
  static const button = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.bgBase,
  );

  /// 15 · 400/600 — текст чипа.
  static const chip = TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.2,
    color: AppColors.textSecondary,
  );

  /// 14/20 · 400 — вторичная строка карточки.
  static const bodyMd = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  /// 13/18 · 400 — подпись под заголовком.
  static const bodySm = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textTertiary,
  );

  /// 12/16 · 500 · ls 0.5 · UPPERCASE — бейджи и надзаголовки.
  static const label = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: 0.5,
    color: AppColors.textTertiary,
  );

  /// 12 · 400 — мелкая метаинформация.
  static const caption = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.25,
    color: AppColors.textTertiary,
  );

  /// 11 · 400/600 — подпись таб-бара.
  static const tab = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.18,
    color: AppColors.textTertiary,
  );

  /// Табулярные цифры для произвольного стиля.
  static const tabularFigures = _tnum;
}
