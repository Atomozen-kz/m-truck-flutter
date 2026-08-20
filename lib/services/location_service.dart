import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Доступ к GPS: разрешения, текущая точка и поток координат в рейсе.
class LocationService {
  StreamSubscription<Position>? _subscription;

  /// Точки чаще, чем раз в 50 метров, для дальнобоя избыточны.
  static const _trackingSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 50,
  );

  bool get isTracking => _subscription != null;

  /// Запрашивает разрешение. Возвращает `false`, если водитель отказал или
  /// служба геолокации выключена.
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<Position?> current() async {
    if (!await ensurePermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 12));
    } on Exception {
      // Нет фикса — экран просто обойдётся без «рядом с вами».
      return await Geolocator.getLastKnownPosition();
    }
  }

  /// Текущая точка в том виде, в каком её ждут карты.
  Future<({double lat, double lng})?> currentLatLng() async {
    final position = await current();
    return position == null
        ? null
        : (lat: position.latitude, lng: position.longitude);
  }

  /// Включает поток координат на время рейса.
  Future<bool> startTracking(void Function(Position) onPosition) async {
    if (_subscription != null) return true;
    if (!await ensurePermission()) return false;

    _subscription = Geolocator.getPositionStream(locationSettings: _trackingSettings)
        .listen(onPosition, onError: (_) {});
    return true;
  }

  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Расстояние между двумя точками по прямой, км.
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
}
