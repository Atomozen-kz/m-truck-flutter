import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/tokens.dart';
import 'features/auth/moderation_screen.dart';
import 'features/auth/phone_screen.dart';
import 'features/auth/register_driver_screen.dart';
import 'features/shell/home_shell.dart';
import 'state/session_controller.dart';
import 'widgets/brand.dart';

/// Корень приложения: тема, локаль и выбор экрана по стадии сессии.
class MTruckApp extends StatelessWidget {
  const MTruckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mangystau Truck',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      themeMode: ThemeMode.dark,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Системный масштаб текста ограничиваем: крупные цены не должны ломать
      // вёрстку карточек на телефоне в держателе.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _RootGate(),
    );
  }
}

/// Разводит пользователя по стадиям: вход → анкета → модерация → приложение.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final stage = context.select<SessionController, SessionStage>((s) => s.stage);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: switch (stage) {
        SessionStage.loading => const _Splash(),
        SessionStage.signedOut => const PhoneScreen(key: ValueKey('phone')),
        SessionStage.needsDriverProfile =>
          const RegisterDriverScreen(key: ValueKey('register')),
        SessionStage.pendingModeration => const ModerationScreen(key: ValueKey('moderation')),
        SessionStage.ready => const HomeShell(key: ValueKey('home')),
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.bgBase,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLogo(size: 96),
              SizedBox(height: Gap.xxl),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      );
}
