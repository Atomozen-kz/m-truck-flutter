import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/tokens.dart';
import '../data/models/models.dart';
import 'map_base.dart';
import 'navigator_sheet.dart';
import 'primitives.dart';

/// Карта маршрута на тайлах OpenStreetMap.
///
/// Камера подгоняется по ломаной так, чтобы точки А и Б были видны целиком.
/// Встроенная в экран карта не перехватывает жесты — по тапу она открывается
/// на весь экран, где её уже можно двигать и приближать.
class RouteMapView extends StatefulWidget {
  const RouteMapView({
    super.key,
    required this.route,
    this.height = 200,
    this.progress,
    this.driver,
    this.from,
    this.to,
    this.interactive = false,
    this.expandable = true,
    this.title,
    this.onLocate,
  });

  /// Плановый маршрут. Если точек меньше двух, карта показывает пустую сетку.
  final RouteGeometry? route;

  final double height;

  /// Доля пройденного пути 0..1 — янтарная часть ломаной.
  final double? progress;

  /// Текущее положение машины; при null берётся точка по [progress].
  final ({double lat, double lng})? driver;

  /// Подписи к меткам А и Б — адреса погрузки и выгрузки.
  final GeoPoint? from;
  final GeoPoint? to;

  /// Можно ли двигать и приближать карту прямо здесь.
  final bool interactive;

  /// Открывать ли полноэкранную карту по тапу.
  final bool expandable;

  /// Заголовок полноэкранной карты.
  final String? title;

  /// Где сейчас водитель. Без колбэка кнопка «моё местоположение» не рисуется.
  final MapLocator? onLocate;

  @override
  State<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends State<RouteMapView> {
  final _controller = MapController();
  bool _ready = false;
  LatLng? _me;

  List<LatLng> get _points =>
      widget.route?.points.map((p) => LatLng(p.lat, p.lng)).toList(growable: false) ??
      const [];

  /// Всё, что должно попасть в кадр: маршрут плюс машина.
  List<LatLng> get _framed {
    final driver = widget.driver;
    return [..._points, if (driver != null) LatLng(driver.lat, driver.lng)];
  }

  @override
  void didUpdateWidget(RouteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Маршрут меняется, когда рейс подгрузился с сервера, — переподгоняем кадр.
    if (_ready && !_sameRoute(oldWidget.route, widget.route)) _fit();
  }

  static bool _sameRoute(RouteGeometry? a, RouteGeometry? b) {
    if (a == null || b == null) return a == b;
    if (a.points.length != b.points.length) return false;
    for (final (index, point) in a.points.indexed) {
      if (point != b.points[index]) return false;
    }
    return true;
  }

  void _fit() {
    final fit = mapFit(_framed);
    if (fit != null) _controller.fitCamera(fit);
  }

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteMapScreen(
          route: widget.route,
          progress: widget.progress,
          driver: widget.driver,
          from: widget.from,
          to: widget.to,
          title: widget.title ?? 'Маршрут',
          onLocate: widget.onLocate,
        ),
      ),
    );
  }

  void _onLocated(LatLng at) {
    setState(() => _me = at);
    if (_ready) _controller.move(at, math.max(_controller.camera.zoom, 12));
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final map = SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRect(
        child: MapBackdrop(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (points.length >= 2)
                FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCameraFit: mapFit(_framed),
                    backgroundColor: Colors.transparent,
                    maxZoom: mapMaxZoom,
                    minZoom: 3,
                    onMapReady: () => _ready = true,
                    interactionOptions: InteractionOptions(
                      flags: widget.interactive ? mapGestures : InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    mapTileLayer(context),
                    PolylineLayer(polylines: _polylines(points)),
                    MarkerLayer(markers: [..._markers(points), ?myLocationMarker(_me)]),
                  ],
                )
              else
                const _EmptyRoute(),
              const Positioned(left: 6, bottom: 4, child: MapAttribution()),
              if (widget.expandable && points.length >= 2)
                const Positioned(left: Gap.md, top: Gap.md, child: _ExpandHint()),
              if (widget.onLocate != null)
                Positioned(
                  right: Gap.md,
                  bottom: Gap.md,
                  child: LocateButton(onLocate: widget.onLocate!, onLocated: _onLocated),
                ),
            ],
          ),
        ),
      ),
    );

    if (!widget.expandable || points.length < 2) return map;
    return GestureDetector(
      onTap: _openFullscreen,
      behavior: HitTestBehavior.opaque,
      child: map,
    );
  }

  List<Polyline> _polylines(List<LatLng> points) {
    final travelled = widget.progress?.clamp(0.0, 1.0);
    return [
      Polyline(
        points: points,
        strokeWidth: 5,
        color: travelled == null ? AppColors.textPrimary : AppColors.borderDefault,
        borderStrokeWidth: 2,
        borderColor: AppColors.bgBase.withValues(alpha: 0.6),
      ),
      if (travelled != null && travelled > 0)
        Polyline(
          points: _prefix(points, travelled),
          strokeWidth: 5,
          color: AppColors.accent,
        ),
    ];
  }

  List<Marker> _markers(List<LatLng> points) {
    final travelled = widget.progress?.clamp(0.0, 1.0);
    final driver = widget.driver;
    final vehicle = driver != null
        ? LatLng(driver.lat, driver.lng)
        : travelled == null
        ? null
        : _prefix(points, travelled).last;

    return [
      Marker(
        point: points.first,
        width: 34,
        height: 42,
        alignment: Alignment.topCenter,
        child: const _EndpointMarker(label: 'А', done: false),
      ),
      Marker(
        point: points.last,
        width: 34,
        height: 42,
        alignment: Alignment.topCenter,
        child: const _EndpointMarker(label: 'Б', done: false),
      ),
      if (vehicle != null)
        Marker(
          point: vehicle,
          width: 34,
          height: 34,
          child: _VehicleMarker(bearing: _bearing(points, vehicle)),
        ),
    ];
  }

  /// Начальный кусок ломаной длиной [fraction] от общей — пройденный путь.
  static List<LatLng> _prefix(List<LatLng> points, double fraction) {
    final lengths = <double>[];
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      final segment = _planar(points[i - 1], points[i]);
      lengths.add(segment);
      total += segment;
    }
    if (total <= 0) return [points.first];

    var target = total * fraction;
    final result = <LatLng>[points.first];
    for (var i = 0; i < lengths.length; i++) {
      if (target >= lengths[i]) {
        target -= lengths[i];
        result.add(points[i + 1]);
        continue;
      }
      final t = lengths[i] == 0 ? 0.0 : target / lengths[i];
      result.add(
        LatLng(
          points[i].latitude + (points[i + 1].latitude - points[i].latitude) * t,
          points[i].longitude + (points[i + 1].longitude - points[i].longitude) * t,
        ),
      );
      break;
    }
    return result;
  }

  /// Направление движения в точке [at] — по ближайшему сегменту ломаной.
  static double _bearing(List<LatLng> points, LatLng at) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 1; i < points.length; i++) {
      final distance = _planar(points[i], at);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    final a = points[bestIndex - 1];
    final b = points[bestIndex];
    final dx = (b.longitude - a.longitude) * math.cos(a.latitudeInRad);
    final dy = a.latitude - b.latitude; // экран растёт вниз
    return math.atan2(dy, dx);
  }

  /// Грубая метрика «на плоскости» — для сравнения отрезков этого хватает.
  static double _planar(LatLng a, LatLng b) {
    final dLat = a.latitude - b.latitude;
    final dLng = (a.longitude - b.longitude) * math.cos(a.latitudeInRad);
    return math.sqrt(dLat * dLat + dLng * dLng);
  }
}

/// Полноэкранная карта: тот же маршрут, но с жестами.
class RouteMapScreen extends StatelessWidget {
  const RouteMapScreen({
    super.key,
    required this.route,
    this.progress,
    this.driver,
    this.from,
    this.to,
    this.title = 'Маршрут',
    this.onLocate,
  });

  final RouteGeometry? route;
  final double? progress;
  final ({double lat, double lng})? driver;
  final GeoPoint? from;
  final GeoPoint? to;
  final String title;
  final MapLocator? onLocate;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bgBase,
    body: Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.screen, Gap.sm),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(PhosphorIcons.arrowLeft(), color: AppColors.textPrimary),
                  tooltip: 'Назад',
                ),
                Expanded(child: Text(title, style: AppText.displayMd)),
              ],
            ),
          ),
        ),
        Expanded(
          child: RouteMapView(
            route: route,
            height: double.infinity,
            progress: progress,
            driver: driver,
            from: from,
            to: to,
            interactive: true,
            expandable: false,
            onLocate: onLocate,
          ),
        ),
        if (from != null || to != null) _Legend(from: from, to: to),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({this.from, this.to});

  final GeoPoint? from;
  final GeoPoint? to;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(
      Gap.screen,
      Gap.md,
      Gap.screen,
      Gap.md + MediaQuery.paddingOf(context).bottom,
    ),
    decoration: const BoxDecoration(
      color: AppColors.bgBase,
      border: Border(top: BorderSide(color: AppColors.borderSubtle)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (from != null) _LegendRow(label: 'А', point: from!),
        if (to != null) _LegendRow(label: 'Б', point: to!),
      ],
    ),
  );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.label, required this.point});

  final String label;
  final GeoPoint point;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _Pin(label: label, done: false),
      const SizedBox(width: Gap.md),
      Expanded(
        child: Text(
          point.address.isEmpty ? '—' : point.address,
          style: AppText.bodyMd,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: Gap.sm),
      // Пошаговый маршрут строит навигатор водителя — 2ГИС, Яндекс или
      // Google. Наше дело — отдать ему точку.
      IconTapTarget(
        icon: PhosphorIcons.navigationArrow(PhosphorIconsStyle.fill),
        color: AppColors.accent,
        size: 20,
        tooltip: 'Открыть в навигаторе',
        onPressed: () => openInNavigator(
          context,
          lat: point.lat,
          lng: point.lng,
          title: 'Точка $label в навигаторе',
        ),
      ),
    ],
  );
}

/// Метка конца маршрута: кружок с буквой и хвостиком вниз, в точку.
class _EndpointMarker extends StatelessWidget {
  const _EndpointMarker({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Pin(label: label, done: done),
      CustomPaint(size: const Size(10, 8), painter: MapPinTail()),
    ],
  );
}

class _Pin extends StatelessWidget {
  const _Pin({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: done ? AppColors.accent : AppColors.textPrimary,
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.bgBase, width: 2),
    ),
    child: Text(
      label,
      style: AppText.label.copyWith(
        color: AppColors.bgBase,
        letterSpacing: 0,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Машина — янтарный круг со стрелкой по направлению движения.
class _VehicleMarker extends StatelessWidget {
  const _VehicleMarker({required this.bearing});

  final double bearing;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _VehiclePainter(bearing), size: const Size.square(34));
}

class _VehiclePainter extends CustomPainter {
  _VehiclePainter(this.bearing);

  final double bearing;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      15,
      Paint()..color = AppColors.bgBase.withValues(alpha: 0.85),
    );
    canvas.drawCircle(center, 13, Paint()..color = AppColors.accent);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(bearing);
    final arrow = Path()
      ..moveTo(7, 0)
      ..lineTo(-4.5, -5.5)
      ..lineTo(-2, 0)
      ..lineTo(-4.5, 5.5)
      ..close();
    canvas.drawPath(arrow, Paint()..color = AppColors.bgBase);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VehiclePainter oldDelegate) => oldDelegate.bearing != bearing;
}

class _ExpandHint extends StatelessWidget {
  const _ExpandHint();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.bgSurface2.withValues(alpha: 0.92),
      borderRadius: Radii.cardAll,
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(PhosphorIcons.arrowsOut(), size: 20, color: AppColors.textSecondary),
    ),
  );
}

class _EmptyRoute extends StatelessWidget {
  const _EmptyRoute();

  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Маршрут не задан', style: AppText.bodySm));
}
