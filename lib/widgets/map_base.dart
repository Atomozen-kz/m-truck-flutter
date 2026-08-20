/// Общая основа всех карт приложения: тайлы, фон, подпись, «я здесь».
///
/// Карта маршрута и карта заявок отличаются только слоями поверх — всё
/// остальное у них обязано выглядеть и вести себя одинаково.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/tokens.dart';

/// Тайлы OpenStreetMap. Кэш на диске включён во flutter_map по умолчанию:
/// однажды показанный участок степи откроется и без сети.
const mapTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Политика OSM требует опознаваемый User-Agent у каждого запроса тайла.
const mapTileUserAgent = 'com.example.m_truck';

/// Дальше 17-го зума OSM отдаёт всё, но водителю хватает обзора трассы.
const mapMaxZoom = 17.0;

/// Жесты интерактивной карты. Поворот выключен: развёрнутая карта в кабине
/// сбивает с толку сильнее, чем помогает.
const mapGestures = InteractiveFlag.drag |
    InteractiveFlag.pinchZoom |
    InteractiveFlag.doubleTapZoom |
    InteractiveFlag.flingAnimation;

/// Как карта узнаёт, где сейчас водитель.
///
/// Карта намеренно не ходит в GPS сама: экраны отдают ей готовую функцию, и
/// виджет остаётся без зависимости от служб и провайдеров.
typedef MapLocator = Future<({double lat, double lng})?> Function();

/// Кадр, в который помещаются все [points] целиком.
CameraFit? mapFit(List<LatLng> points) {
  if (points.isEmpty) return null;
  return CameraFit.bounds(
    bounds: LatLngBounds.fromPoints(points),
    // Метки рисуются над точкой — оставляем им место у краёв.
    padding: const EdgeInsets.fromLTRB(48, 56, 48, 40),
    maxZoom: mapMaxZoom,
  );
}

/// Слой тайлов, затемнённый под тему приложения.
Widget mapTileLayer(BuildContext context) => darkModeTilesContainerBuilder(
      context,
      TileLayer(
        urlTemplate: mapTileUrl,
        userAgentPackageName: mapTileUserAgent,
        maxNativeZoom: 18,
        // Без сети тайл просто не приходит — это не ошибка экрана.
        tileProvider: NetworkTileProvider(silenceExceptions: true),
      ),
    );

/// Фон под тайлами: сетка светится сквозь дыры, и без сети карта не пустеет.
class MapBackdrop extends StatelessWidget {
  const MapBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _GridPainter(), size: Size.infinite),
          child,
        ],
      );
}

class _GridPainter extends CustomPainter {
  static const _step = 64.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.bgSurface);

    final paint = Paint()
      ..color = AppColors.borderSubtle.withValues(alpha: 0.55)
      ..strokeWidth = 1;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = 0.0; x < size.width; x += _step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += _step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

/// Требование лицензии OSM — подпись источника тайлов.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bgBase.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          child: Text(
            '© OpenStreetMap',
            style: AppText.label.copyWith(
              fontSize: 9,
              letterSpacing: 0,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      );
}

/// Хвостик метки, упирающийся остриём в координату.
class MapPinTail extends CustomPainter {
  MapPinTail({this.color = AppColors.textPrimary});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(MapPinTail oldDelegate) => oldDelegate.color != color;
}

/// Синяя точка «я здесь» — на всех картах приложения одинаковая.
Marker? myLocationMarker(LatLng? at) => at == null
    ? null
    : Marker(point: at, width: 26, height: 26, child: const _MyLocationDot());

class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.info,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.textPrimary, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.info.withValues(alpha: 0.45),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      );
}

/// Кнопка «моё местоположение».
///
/// Пока GPS ищет фикс, показывает спиннер: в степи это занимает секунды, и
/// водителю важно видеть, что нажатие сработало.
class LocateButton extends StatefulWidget {
  const LocateButton({super.key, required this.onLocate, required this.onLocated});

  final MapLocator onLocate;
  final ValueChanged<LatLng> onLocated;

  @override
  State<LocateButton> createState() => _LocateButtonState();
}

class _LocateButtonState extends State<LocateButton> {
  bool _busy = false;

  Future<void> _locate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final at = await widget.onLocate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (at == null) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Не удалось определить местоположение — проверьте GPS'),
          ),
        );
      return;
    }
    widget.onLocated(LatLng(at.lat, at.lng));
  }

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.bgSurface2.withValues(alpha: 0.92),
        borderRadius: Radii.cardAll,
        child: InkWell(
          onTap: _locate,
          borderRadius: Radii.cardAll,
          child: SizedBox(
            width: Touch.min,
            height: Touch.min,
            child: _busy
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                : Icon(
                    PhosphorIcons.crosshair(),
                    size: 24,
                    color: AppColors.textSecondary,
                  ),
          ),
        ),
      );
}
