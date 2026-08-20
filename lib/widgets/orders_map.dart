import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/formatters.dart';
import '../core/theme/tokens.dart';
import '../data/models/models.dart';
import 'map_base.dart';

/// Карта заявок: где стоят грузы и куда их везти.
///
/// В списке заявка — это две строки адреса, и понять «по пути ли мне» можно
/// только сложив карту в голове. Карта отвечает на это сразу: точки погрузки
/// видны все разом, а выбранная заявка показывает свой путь и дистанцию.
class OrdersMapView extends StatefulWidget {
  const OrdersMapView({
    super.key,
    required this.orders,
    this.height = 160,
    this.interactive = false,
    this.selectedId,
    this.onSelect,
    this.onLocate,
  });

  final List<Order> orders;
  final double height;
  final bool interactive;

  /// Заявка, чей маршрут подсвечен.
  final int? selectedId;

  final ValueChanged<Order>? onSelect;
  final MapLocator? onLocate;

  @override
  State<OrdersMapView> createState() => _OrdersMapViewState();
}

class _OrdersMapViewState extends State<OrdersMapView> {
  final _controller = MapController();
  bool _ready = false;
  LatLng? _me;

  /// Точки погрузки — то, вокруг чего строится кадр.
  List<LatLng> get _pickups => [
        for (final order in widget.orders)
          if (order.from != null) LatLng(order.from!.lat, order.from!.lng),
      ];

  Order? get _selected {
    final id = widget.selectedId;
    if (id == null) return null;
    for (final order in widget.orders) {
      if (order.id == id) return order;
    }
    return null;
  }

  @override
  void didUpdateWidget(OrdersMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready && oldWidget.orders.length != widget.orders.length) _fit();
  }

  void _fit() {
    final fit = mapFit(_pickups);
    if (fit != null) _controller.fitCamera(fit);
  }

  void _onLocated(LatLng at) {
    setState(() => _me = at);
    if (_ready) _controller.move(at, 11);
  }

  @override
  Widget build(BuildContext context) {
    final pickups = _pickups;
    if (pickups.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const MapBackdrop(child: Center(child: _NoPoints())),
      );
    }

    final selected = _selected;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            MapBackdrop(
              child: FlutterMap(
                mapController: _controller,
                options: MapOptions(
                  initialCameraFit: mapFit([...pickups, ...?_selectedRoute(selected)]),
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
                  if (selected != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _selectedRoute(selected) ?? const [],
                          strokeWidth: 5,
                          color: AppColors.accent,
                          borderStrokeWidth: 2,
                          borderColor: AppColors.bgBase.withValues(alpha: 0.6),
                        ),
                      ],
                    ),
                  MarkerLayer(markers: [..._markers(selected), ?myLocationMarker(_me)]),
                ],
              ),
            ),
            const Positioned(left: 6, bottom: 4, child: MapAttribution()),
            if (widget.onLocate != null)
              Positioned(
                right: Gap.md,
                top: Gap.md,
                child: LocateButton(onLocate: widget.onLocate!, onLocated: _onLocated),
              ),
          ],
        ),
      ),
    );
  }

  List<LatLng>? _selectedRoute(Order? order) {
    final route = order?.mapRoute;
    if (route == null || route.isEmpty) return null;
    return route.points.map((p) => LatLng(p.lat, p.lng)).toList(growable: false);
  }

  List<Marker> _markers(Order? selected) {
    final markers = <Marker>[];

    // Точка выгрузки рисуется только у выбранной заявки: иначе на карте
    // вдвое больше меток, и ни одна ничего не значит.
    final to = selected?.to;
    if (to != null) {
      markers.add(Marker(
        point: LatLng(to.lat, to.lng),
        width: 34,
        height: 42,
        alignment: Alignment.topCenter,
        child: const _DropPin(),
      ));
    }

    for (final order in widget.orders) {
      final from = order.from;
      if (from == null) continue;
      final isSelected = order.id == selected?.id;
      markers.add(Marker(
        point: LatLng(from.lat, from.lng),
        width: 104,
        height: 44,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: widget.onSelect == null ? null : () => widget.onSelect!(order),
          child: _PricePin(order: order, selected: isSelected),
        ),
      ));
    }
    return markers;
  }
}

/// Метка заявки: цена прямо на карте — по ней и выбирают.
class _PricePin extends StatelessWidget {
  const _PricePin({required this.order, required this.selected});

  final Order order;
  final bool selected;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : AppColors.bgSurface,
              borderRadius: Radii.pillAll,
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.borderDefault,
              ),
            ),
            child: Text(
              Fmt.moneyBare(order.displayPrice),
              maxLines: 1,
              style: AppText.label.copyWith(
                letterSpacing: 0,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.bgBase : AppColors.textPrimary,
              ),
            ),
          ),
          CustomPaint(
            size: const Size(10, 7),
            painter: MapPinTail(
              color: selected ? AppColors.accent : AppColors.borderDefault,
            ),
          ),
        ],
      );
}

/// Точка выгрузки выбранной заявки.
class _DropPin extends StatelessWidget {
  const _DropPin();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.textPrimary,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.bgBase, width: 2),
            ),
            child: Text(
              'Б',
              style: AppText.label.copyWith(
                color: AppColors.bgBase,
                letterSpacing: 0,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          CustomPaint(
            size: const Size(10, 8),
            painter: MapPinTail(color: AppColors.textPrimary),
          ),
        ],
      );
}

class _NoPoints extends StatelessWidget {
  const _NoPoints();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Gap.screen),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.mapTrifold(), size: 20, color: AppColors.textTertiary),
            const SizedBox(width: Gap.sm),
            Flexible(
              child: Text(
                'Заявок на карте пока нет',
                style: AppText.bodySm,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
}
