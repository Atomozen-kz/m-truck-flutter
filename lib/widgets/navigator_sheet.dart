import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/tokens.dart';
import 'primitives.dart';

/// Внешний навигатор, в который водитель уходит за пошаговым маршрутом.
///
/// Приложение маршрут не строит: в кабине уже стоит привычный навигатор, и
/// спорить с ним бессмысленно. Наше дело — отдать ему точку.
enum ExternalNavigator {
  twogis('2ГИС'),
  yandex('Яндекс Навигатор'),
  google('Google Карты');

  const ExternalNavigator(this.label);

  final String label;

  /// Ссылка в приложение навигатора.
  Uri appUri(double lat, double lng) => switch (this) {
        // 2ГИС и Яндекс ждут координаты в порядке «долгота, широта».
        ExternalNavigator.twogis =>
          Uri.parse('dgis://2gis.ru/routeSearch/rsType/car/to/$lng,$lat'),
        ExternalNavigator.yandex =>
          Uri.parse('yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lng'),
        ExternalNavigator.google => Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
      };

  /// Запасная ссылка в браузер, если приложение не установлено.
  Uri webUri(double lat, double lng) => switch (this) {
        ExternalNavigator.twogis =>
          Uri.parse('https://2gis.kz/directions/points/%7C$lng,$lat'),
        ExternalNavigator.yandex =>
          Uri.parse('https://yandex.ru/maps/?rtext=~$lat,$lng&rtt=auto'),
        ExternalNavigator.google => Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
          ),
      };

  IconData get icon => switch (this) {
        ExternalNavigator.twogis => PhosphorIcons.mapTrifold(PhosphorIconsStyle.fill),
        ExternalNavigator.yandex => PhosphorIcons.navigationArrow(PhosphorIconsStyle.fill),
        ExternalNavigator.google => PhosphorIcons.mapPin(PhosphorIconsStyle.fill),
      };

  /// Открывает точку: сначала приложением, иначе — сайтом.
  Future<bool> open(double lat, double lng) async {
    try {
      if (await launchUrl(appUri(lat, lng), mode: LaunchMode.externalApplication)) {
        return true;
      }
    } on Exception {
      // Схема не зарегистрирована — уходим на веб-версию.
    }
    return launchUrl(webUri(lat, lng), mode: LaunchMode.externalApplication);
  }
}

/// Спрашивает, каким навигатором вести, и открывает его.
Future<void> openInNavigator(
  BuildContext context, {
  required double lat,
  required double lng,
  String title = 'Открыть в навигаторе',
}) async {
  final choice = await showModalBottomSheet<ExternalNavigator>(
    context: context,
    backgroundColor: AppColors.bgSurface,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.xl, Gap.screen, Gap.md),
            child: Text(title, style: AppText.displayMd),
          ),
          for (final navigator in ExternalNavigator.values)
            _NavigatorRow(
              navigator: navigator,
              onTap: () => Navigator.of(sheetContext).pop(navigator),
            ),
          const SizedBox(height: Gap.md),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final opened = await choice.open(lat, lng);
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('Не удалось открыть ${choice.label}')));
}

class _NavigatorRow extends StatelessWidget {
  const _NavigatorRow({required this.navigator, required this.onTap});

  final ExternalNavigator navigator;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.screen,
              vertical: Gap.lg,
            ),
            child: Row(
              children: [
                Icon(navigator.icon, size: 24, color: AppColors.accent),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    navigator.label,
                    style: AppText.bodyLg.copyWith(fontSize: 16),
                  ),
                ),
                Icon(
                  PhosphorIcons.arrowUpRight(),
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      );
}

/// Кнопка «Навигатор» с выбором приложения.
class NavigateButton extends StatelessWidget {
  const NavigateButton({super.key, required this.lat, required this.lng, this.label});

  final double lat;
  final double lng;
  final String? label;

  @override
  Widget build(BuildContext context) => SecondaryButton(
        label: label ?? 'Навигатор',
        icon: PhosphorIcons.navigationArrow(PhosphorIconsStyle.fill),
        onPressed: () => openInNavigator(context, lat: lat, lng: lng),
      );
}
