/// Модели предметной области, разобранные из `data` единого конверта API.
///
/// Разбор намеренно снисходительный: сервер отдаёт часть связей пустым
/// объектом `{}` вместо `null`, числа приходят то строкой, то числом, а даты —
/// в ISO-8601 c таймзоной. Всё это нормализуется здесь, чтобы экраны работали
/// с чистыми типами.
library;

int? _asInt(dynamic v) => switch (v) {
      int i => i,
      num n => n.round(),
      String s => int.tryParse(s) ?? double.tryParse(s)?.round(),
      _ => null,
    };

double? _asDouble(dynamic v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

bool _asBool(dynamic v) => switch (v) {
      bool b => b,
      num n => n != 0,
      String s => s == '1' || s.toLowerCase() == 'true',
      _ => false,
    };

DateTime? _asDate(dynamic v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

/// Пустой объект `{}` от сервера означает «связи нет».
Map<String, dynamic>? _asMap(dynamic v) {
  if (v is! Map<String, dynamic> || v.isEmpty) return null;
  return v;
}

List<Map<String, dynamic>> _asList(dynamic v) => v is List
    ? v.whereType<Map<String, dynamic>>().toList(growable: false)
    : const [];

/// Точка на карте с человекочитаемым адресом.
class GeoPoint {
  const GeoPoint({required this.address, required this.lat, required this.lng});

  final String address;
  final double lat;
  final double lng;

  static GeoPoint? tryParse(dynamic json) {
    final map = _asMap(json);
    final lat = _asDouble(map?['lat']);
    final lng = _asDouble(map?['lng']);
    if (lat == null || lng == null) return null;
    return GeoPoint(
      address: (map?['address'] ?? map?['address_text'] ?? '') as String,
      lat: lat,
      lng: lng,
    );
  }
}

/// Ломаная маршрута из GeoJSON `LineString` с координатами в порядке [lng, lat].
class RouteGeometry {
  const RouteGeometry(this.points);

  /// Точки в порядке следования, уже перевёрнутые в (lat, lng).
  final List<({double lat, double lng})> points;

  bool get isEmpty => points.length < 2;

  static RouteGeometry? tryParse(dynamic json) {
    final map = _asMap(json);
    final coords = map?['coordinates'];
    if (coords is! List) return null;
    final points = <({double lat, double lng})>[];
    for (final pair in coords) {
      if (pair is! List || pair.length < 2) continue;
      final lng = _asDouble(pair[0]);
      final lat = _asDouble(pair[1]);
      if (lat == null || lng == null) continue;
      points.add((lat: lat, lng: lng));
    }
    return points.length < 2 ? null : RouteGeometry(points);
  }

  /// Прямая от точки А к точке Б — запасной вариант, когда маршрута нет.
  static RouteGeometry? straight(GeoPoint? from, GeoPoint? to) {
    if (from == null || to == null) return null;
    return RouteGeometry([
      (lat: from.lat, lng: from.lng),
      (lat: to.lat, lng: to.lng),
    ]);
  }
}

/// Статус модерации водительского удостоверения.
enum DriverStatus {
  pending,
  approved,
  rejected;

  static DriverStatus? tryParse(String? raw) => switch (raw) {
        'pending' => DriverStatus.pending,
        'approved' => DriverStatus.approved,
        'rejected' => DriverStatus.rejected,
        _ => null,
      };

  bool get canBid => this == DriverStatus.approved;
}

/// Профиль водителя внутри пользователя.
class DriverProfile {
  const DriverProfile({required this.id, required this.licenseNo, required this.status});

  final int id;
  final String licenseNo;
  final DriverStatus status;

  static DriverProfile? tryParse(dynamic json) {
    final map = _asMap(json);
    final id = _asInt(map?['id']);
    if (id == null) return null;
    return DriverProfile(
      id: id,
      licenseNo: (map?['license_no'] ?? '') as String,
      status: DriverStatus.tryParse(map?['status'] as String?) ?? DriverStatus.pending,
    );
  }
}

/// Машина водителя.
class Vehicle {
  const Vehicle({
    required this.id,
    required this.plate,
    required this.type,
    required this.capacityKg,
    required this.hasRefrigeration,
    this.lastLat,
    this.lastLng,
    this.status,
  });

  final int id;
  final String plate;
  final String type;
  final int capacityKg;
  final bool hasRefrigeration;
  final double? lastLat;
  final double? lastLng;
  final String? status;

  bool get isEnRoute => status == 'en_route';

  static Vehicle? tryParse(dynamic json) {
    final map = _asMap(json);
    final id = _asInt(map?['id']);
    if (id == null) return null;
    return Vehicle(
      id: id,
      plate: (map?['plate'] ?? '') as String,
      type: (map?['type'] ?? '') as String,
      capacityKg: _asInt(map?['capacity_kg']) ?? 0,
      hasRefrigeration: _asBool(map?['has_refrigeration']),
      lastLat: _asDouble(map?['last_lat']),
      lastLng: _asDouble(map?['last_lng']),
      status: map?['status'] as String?,
    );
  }
}

/// Пользователь платформы. Для мобилки роль всегда `driver`.
class User {
  const User({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    required this.rating,
    required this.isActive,
    this.companyName,
    this.driver,
    this.vehicles = const [],
  });

  final int id;
  final String name;
  final String phone;
  final String role;
  final double rating;
  final bool isActive;
  final String? companyName;
  final DriverProfile? driver;
  final List<Vehicle> vehicles;

  /// Водитель прошёл модерацию и может откликаться на заявки.
  bool get canBid => driver?.status.canBid ?? false;

  Vehicle? get primaryVehicle => vehicles.isEmpty ? null : vehicles.first;

  static User parse(Map<String, dynamic> json) => User(
        id: _asInt(json['id']) ?? 0,
        name: (json['name'] ?? '') as String,
        phone: (json['phone'] ?? '') as String,
        role: (json['role'] ?? 'driver') as String,
        rating: _asDouble(json['rating']) ?? 5,
        isActive: _asBool(json['is_active']),
        companyName: json['company_name'] as String?,
        driver: DriverProfile.tryParse(json['driver']),
        vehicles: _asList(json['vehicles']).map(Vehicle.tryParse).nonNulls.toList(),
      );
}

/// Краткая карточка заказчика в заявке.
class Shipper {
  const Shipper({required this.id, required this.name, this.companyName, this.phone});

  final int id;
  final String name;
  final String? companyName;
  final String? phone;

  /// В карточке показываем компанию, если она есть, иначе имя.
  String get displayName => (companyName?.isNotEmpty ?? false) ? companyName! : name;

  static Shipper? tryParse(dynamic json) {
    final map = _asMap(json);
    final id = _asInt(map?['id']);
    if (id == null) return null;
    return Shipper(
      id: id,
      name: (map?['name'] ?? '') as String,
      companyName: map?['company_name'] as String?,
      phone: map?['phone'] as String?,
    );
  }
}

/// Заявка на перевозку.
class Order {
  const Order({
    required this.id,
    required this.cargoType,
    required this.weightKg,
    required this.requiresRefrigeration,
    required this.status,
    this.from,
    this.to,
    this.photoUrl,
    this.pickupFrom,
    this.pickupTo,
    this.priceOffer,
    this.priceFinal,
    this.distanceKm,
    this.durationMin,
    this.routeGeometry,
    this.publishedAt,
    this.shipper,
    this.bids = const [],
    this.pickupDistanceKm,
    this.myBid,
    this.offeredToMe = false,
    this.comment,
  });

  final int id;
  final String cargoType;
  final int weightKg;
  final bool requiresRefrigeration;
  final String status;
  final GeoPoint? from;
  final GeoPoint? to;
  final String? photoUrl;
  final DateTime? pickupFrom;
  final DateTime? pickupTo;
  final int? priceOffer;
  final int? priceFinal;
  final double? distanceKm;
  final int? durationMin;
  final RouteGeometry? routeGeometry;
  final DateTime? publishedAt;
  final Shipper? shipper;
  final List<Bid> bids;

  /// Расстояние от водителя до точки погрузки — только в ленте биржи.
  final double? pickupDistanceKm;

  /// Отклик текущего водителя на эту заявку, если он уже отправлен.
  final Bid? myBid;

  /// Заявка адресована лично этому водителю.
  final bool offeredToMe;

  final String? comment;

  /// Цена, которую показываем водителю: финальная, если сделка закрыта.
  int? get displayPrice => priceFinal ?? priceOffer;

  /// Маршрут для карты: реальная геометрия либо прямая А→Б.
  RouteGeometry? get mapRoute => routeGeometry ?? RouteGeometry.straight(from, to);

  /// Копия с подменёнными полями — экраны обновляют заявку локально,
  /// не дожидаясь ответа сервера.
  Order copyWith({Bid? myBid, String? status}) => Order(
        id: id,
        cargoType: cargoType,
        weightKg: weightKg,
        requiresRefrigeration: requiresRefrigeration,
        status: status ?? this.status,
        from: from,
        to: to,
        photoUrl: photoUrl,
        pickupFrom: pickupFrom,
        pickupTo: pickupTo,
        priceOffer: priceOffer,
        priceFinal: priceFinal,
        distanceKm: distanceKm,
        durationMin: durationMin,
        routeGeometry: routeGeometry,
        publishedAt: publishedAt,
        shipper: shipper,
        bids: bids,
        pickupDistanceKm: pickupDistanceKm,
        myBid: myBid ?? this.myBid,
        offeredToMe: offeredToMe,
        comment: comment,
      );

  static Order parse(Map<String, dynamic> json) => Order(
        id: _asInt(json['id']) ?? 0,
        cargoType: (json['cargo_type'] ?? '') as String,
        weightKg: _asInt(json['weight_kg']) ?? 0,
        requiresRefrigeration: _asBool(json['requires_refrigeration']),
        status: (json['status'] ?? 'published') as String,
        from: GeoPoint.tryParse(json['from']),
        to: GeoPoint.tryParse(json['to']),
        photoUrl: json['photo_url'] as String?,
        pickupFrom: _asDate(json['pickup_from']),
        pickupTo: _asDate(json['pickup_to']),
        priceOffer: _asInt(json['price_offer']),
        priceFinal: _asInt(json['price_final']),
        distanceKm: _asDouble(json['distance_km']),
        durationMin: _asInt(json['duration_min']),
        routeGeometry: RouteGeometry.tryParse(json['route_geometry']),
        publishedAt: _asDate(json['published_at']) ?? _asDate(json['created_at']),
        shipper: Shipper.tryParse(json['shipper']),
        bids: _asList(json['bids']).map(Bid.parse).toList(),
        pickupDistanceKm: _asDouble(json['pickup_distance_km']),
        myBid: _asMap(json['my_bid']) == null ? null : Bid.parse(json['my_bid']),
        offeredToMe: _asBool(json['offered_to_me']),
        comment: json['comment'] as String?,
      );
}

/// Статус отклика водителя.
enum BidStatus {
  pending,
  accepted,
  rejected;

  static BidStatus parse(String? raw) => switch (raw) {
        'accepted' => BidStatus.accepted,
        'rejected' => BidStatus.rejected,
        _ => BidStatus.pending,
      };
}

/// Отклик водителя на заявку.
class Bid {
  const Bid({
    required this.id,
    required this.orderId,
    required this.price,
    required this.status,
    this.etaMinutes,
    this.comment,
    this.vehicle,
    this.createdAt,
    this.order,
  });

  final int id;
  final int orderId;
  final int price;
  final BidStatus status;
  final int? etaMinutes;
  final String? comment;
  final Vehicle? vehicle;
  final DateTime? createdAt;

  /// Заявка приходит вложенной в «Мои отклики».
  final Order? order;

  /// Ожидаемое время подачи машины, посчитанное от момента отклика.
  DateTime? get etaAt => etaMinutes == null
      ? null
      : (createdAt ?? DateTime.now()).add(Duration(minutes: etaMinutes!));

  static Bid parse(Map<String, dynamic> json) => Bid(
        id: _asInt(json['id']) ?? 0,
        orderId: _asInt(json['order_id']) ?? 0,
        price: _asInt(json['price']) ?? 0,
        status: BidStatus.parse(json['status'] as String?),
        etaMinutes: _asInt(json['eta_minutes']),
        comment: json['comment'] as String?,
        vehicle: Vehicle.tryParse(json['vehicle']),
        createdAt: _asDate(json['created_at']),
        order: _asMap(json['order']) == null ? null : Order.parse(json['order']),
      );
}

/// Статус рейса. Порядок объявления совпадает с порядком выполнения.
enum ShipmentStatus {
  assigned,
  pickedUp,
  inTransit,
  delivered,
  closed;

  static ShipmentStatus parse(String? raw) => switch (raw) {
        'picked_up' => ShipmentStatus.pickedUp,
        'in_transit' => ShipmentStatus.inTransit,
        'delivered' => ShipmentStatus.delivered,
        'closed' => ShipmentStatus.closed,
        _ => ShipmentStatus.assigned,
      };

  String get wire => switch (this) {
        ShipmentStatus.assigned => 'assigned',
        ShipmentStatus.pickedUp => 'picked_up',
        ShipmentStatus.inTransit => 'in_transit',
        ShipmentStatus.delivered => 'delivered',
        ShipmentStatus.closed => 'closed',
      };

  /// Рейс ещё в работе — держим GPS-трекинг включённым.
  bool get isLive => this == ShipmentStatus.assigned ||
      this == ShipmentStatus.pickedUp ||
      this == ShipmentStatus.inTransit;

  bool get isFinished => this == ShipmentStatus.delivered || this == ShipmentStatus.closed;

  /// Следующий шаг водителя: «Загрузился» → «Прибыл».
  ShipmentStatus? get next => switch (this) {
        ShipmentStatus.assigned => ShipmentStatus.pickedUp,
        ShipmentStatus.pickedUp => ShipmentStatus.inTransit,
        ShipmentStatus.inTransit => ShipmentStatus.delivered,
        _ => null,
      };
}

/// Назначенный рейс.
class Shipment {
  const Shipment({
    required this.id,
    required this.orderId,
    required this.status,
    this.trackToken,
    this.routeGeometry,
    this.assignedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.order,
    this.vehicle,
  });

  final int id;
  final int orderId;
  final ShipmentStatus status;
  final String? trackToken;
  final RouteGeometry? routeGeometry;
  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final Order? order;
  final Vehicle? vehicle;

  /// Маршрут для карты. Сервер часто кладёт в рейс прямую из двух точек, а
  /// подробную ломаную по дорогам — в заявку: берём ту, где точек больше.
  RouteGeometry? get mapRoute {
    final own = routeGeometry;
    final fromOrder = order?.routeGeometry;
    if (own == null || (fromOrder != null && fromOrder.points.length > own.points.length)) {
      return fromOrder ?? own ?? RouteGeometry.straight(order?.from, order?.to);
    }
    return own;
  }

  /// Заработок за рейс: финальная цена, иначе предложение заказчика.
  int? get earning => order?.priceFinal ?? order?.priceOffer;

  /// Фактическая длительность рейса, если он завершён.
  int? get actualMinutes {
    final start = pickedUpAt ?? assignedAt;
    final end = deliveredAt;
    if (start == null || end == null) return null;
    return end.difference(start).inMinutes;
  }

  static Shipment parse(Map<String, dynamic> json) => Shipment(
        id: _asInt(json['id']) ?? 0,
        orderId: _asInt(json['order_id']) ?? 0,
        status: ShipmentStatus.parse(json['status'] as String?),
        trackToken: json['track_token'] as String?,
        routeGeometry: RouteGeometry.tryParse(json['route_geometry']),
        assignedAt: _asDate(json['assigned_at']),
        pickedUpAt: _asDate(json['picked_up_at']),
        deliveredAt: _asDate(json['delivered_at']),
        order: _asMap(json['order']) == null ? null : Order.parse(json['order']),
        vehicle: Vehicle.tryParse(json['vehicle']),
      );
}

/// Состояние выплаты по доставленному заказу.
enum PayoutStatus {
  pending,
  paid;

  static PayoutStatus parse(String? raw) =>
      raw == 'paid' ? PayoutStatus.paid : PayoutStatus.pending;

  /// Значение для query-параметра `status`.
  String get wire => name;
}

/// Выплата за доставленный заказ.
class Payout {
  const Payout({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.status,
    this.from,
    this.to,
    this.cargoType,
    this.weightKg,
    this.distanceKm,
    this.company,
    this.deliveredAt,
    this.paidAt,
  });

  final int id;
  final int orderId;

  /// Сумма выплаты в тенге.
  final int amount;
  final PayoutStatus status;

  /// Адреса приходят строками, а не объектами: карта здесь не нужна.
  final String? from;
  final String? to;

  final String? cargoType;
  final int? weightKg;
  final double? distanceKm;

  /// Компания-заказчик.
  final String? company;

  final DateTime? deliveredAt;
  final DateTime? paidAt;

  bool get isPaid => status == PayoutStatus.paid;

  /// Дата, по которой строка сортируется и подписывается.
  DateTime? get at => paidAt ?? deliveredAt;

  static Payout parse(Map<String, dynamic> json) => Payout(
        id: _asInt(json['id']) ?? 0,
        orderId: _asInt(json['order_id']) ?? 0,
        amount: _asInt(json['amount']) ?? 0,
        status: PayoutStatus.parse(json['status'] as String?),
        from: json['from'] as String?,
        to: json['to'] as String?,
        cargoType: json['cargo_type'] as String?,
        weightKg: _asInt(json['weight_kg']),
        distanceKm: _asDouble(json['distance_km']),
        company: json['company'] as String?,
        deliveredAt: _asDate(json['delivered_at']),
        paidAt: _asDate(json['paid_at']),
      );
}

/// Сводка по заработку водителя: сколько уже выплачено и сколько ждёт.
class PayoutsSummary {
  const PayoutsSummary({
    this.paidTotal = 0,
    this.pendingTotal = 0,
    this.paidCount = 0,
    this.pendingCount = 0,
  });

  final int paidTotal;
  final int pendingTotal;
  final int paidCount;
  final int pendingCount;

  int get total => paidTotal + pendingTotal;

  bool get isEmpty => paidCount == 0 && pendingCount == 0;

  static PayoutsSummary parse(dynamic json) {
    final map = _asMap(json);
    if (map == null) return const PayoutsSummary();
    return PayoutsSummary(
      paidTotal: _asInt(map['paid_total']) ?? 0,
      pendingTotal: _asInt(map['pending_total']) ?? 0,
      paidCount: _asInt(map['paid_count']) ?? 0,
      pendingCount: _asInt(map['pending_count']) ?? 0,
    );
  }
}

/// Ответ `/api/my/payouts`: список выплат вместе со сводкой.
class PayoutsPage {
  const PayoutsPage({required this.items, required this.summary});

  final List<Payout> items;
  final PayoutsSummary summary;

  static PayoutsPage parse(Map<String, dynamic> json) => PayoutsPage(
        items: _asList(json['items']).map(Payout.parse).toList(growable: false),
        summary: PayoutsSummary.parse(json['summary']),
      );
}

/// Одна GPS-точка трека.
class TrackPoint {
  const TrackPoint({required this.lat, required this.lng, this.at});

  final double lat;
  final double lng;
  final DateTime? at;

  static TrackPoint? tryParse(Map<String, dynamic> json) {
    final lat = _asDouble(json['lat']);
    final lng = _asDouble(json['lng']);
    if (lat == null || lng == null) return null;
    return TrackPoint(lat: lat, lng: lng, at: _asDate(json['at']));
  }
}

/// Данные трекинга рейса: плановый маршрут + пройденный трек.
class TrackPayload {
  const TrackPayload({
    required this.shipmentId,
    required this.status,
    this.current,
    this.routeGeometry,
    this.from,
    this.to,
    this.points = const [],
  });

  final int shipmentId;
  final ShipmentStatus status;
  final TrackPoint? current;
  final RouteGeometry? routeGeometry;
  final GeoPoint? from;
  final GeoPoint? to;
  final List<TrackPoint> points;

  static TrackPayload parse(Map<String, dynamic> json) => TrackPayload(
        shipmentId: _asInt(json['shipment_id']) ?? 0,
        status: ShipmentStatus.parse(json['status'] as String?),
        current: _asMap(json['current']) == null ? null : TrackPoint.tryParse(json['current']),
        routeGeometry: RouteGeometry.tryParse(json['route_geometry']),
        from: GeoPoint.tryParse(json['from']),
        to: GeoPoint.tryParse(json['to']),
        points: _asList(json['points']).map(TrackPoint.tryParse).nonNulls.toList(),
      );
}

/// Результат предпросчёта маршрута.
class RouteEstimate {
  const RouteEstimate({this.distanceKm, this.durationMin, this.geometry});

  final double? distanceKm;
  final int? durationMin;
  final RouteGeometry? geometry;

  static RouteEstimate parse(Map<String, dynamic> json) => RouteEstimate(
        distanceKm: _asDouble(json['distance_km']),
        durationMin: _asInt(json['duration_min']),
        geometry: RouteGeometry.tryParse(json['geometry']),
      );
}
