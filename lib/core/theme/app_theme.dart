import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Тёмная тема приложения водителя, собранная поверх дизайн-токенов.
abstract final class AppTheme {
  static const systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.bgBase,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData build() {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.bgBase,
      secondary: AppColors.accent,
      onSecondary: AppColors.bgBase,
      surface: AppColors.bgSurface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: AppColors.bgBase,
      outline: AppColors.borderDefault,
      outlineVariant: AppColors.borderSubtle,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: AppColors.bgBase,
      canvasColor: AppColors.bgBase,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displayLarge: AppText.displayLg,
        displayMedium: AppText.displayMd,
        titleLarge: AppText.titleLg,
        bodyLarge: AppText.bodyLg,
        bodyMedium: AppText.bodyMd,
        bodySmall: AppText.bodySm,
        labelLarge: AppText.label,
        labelSmall: AppText.caption,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: systemOverlay,
        titleTextStyle: AppText.displayMd,
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 24),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: Radii.sheetTop),
        showDragHandle: false,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.bgSurface2,
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          height: 1.4,
          color: AppColors.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: Radii.cardAll),
        insetPadding: EdgeInsets.all(Gap.screen),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.bgSurface2,
        circularTrackColor: Colors.transparent,
      ),
      // Курсор и выделение в полях ввода — акцентные.
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accentSoft,
        selectionHandleColor: AppColors.accent,
      ),
    );
  }
}
