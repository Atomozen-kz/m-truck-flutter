import 'package:m_truck/data/models/models.dart';

/// Данные для тестов, повторяющие сценарий из макета Brilliant:
/// рейс Актау → Жанаозен, стройматериалы, 20 т, 180 000 ₸.
abstract final class Fixtures {
  /// Фиксированная «сейчас», чтобы снимки экрана не плыли между запусками.
  static final now = DateTime(2026, 8, 20, 9, 41);

  static Map<String, dynamic> get shipperJson => {
        'id': 2,
        'name': 'Асхат Нурланов',
        'company_name': 'ТОО «АктауМунайСервис»',
        'phone': '77010000102',
      };

  static Map<String, dynamic> orderJson({
    int id = 4821,
    String fromAddress = 'Актау, морпорт, причал №3',
    String toAddress = 'Жанаозен, база АМУ',
    int price = 180000,
    int weightKg = 20000,
    double distanceKm = 152,
    int durationMin = 190,
    String cargoType = 'стройматериалы',
    bool refrigerated = false,
    Map<String, dynamic>? myBid,
    String? comment,
  }) =>
      {
        'id': id,
        'shipper_id': 2,
        'from': {'address': fromAddress, 'lat': 43.641, 'lng': 51.198},
        'to': {'address': toAddress, 'lat': 43.341, 'lng': 52.861},
        'cargo_type': cargoType,
        'weight_kg': weightKg,
        'requires_refrigeration': refrigerated,
        'pickup_from': now.add(const Duration(hours: 4, minutes: 19)).toIso8601String(),
        'pickup_to': now.add(const Duration(hours: 6, minutes: 19)).toIso8601String(),
        'price_offer': price,
        'distance_km': distanceKm,
        'duration_min': durationMin,
        'route_geometry': {
          'type': 'LineString',
          'coordinates': [
            [51.198, 43.641],
            [51.86, 43.52],
            [52.31, 43.44],
            [52.861, 43.341],
          ],
        },
        'status': 'published',
        'published_at': now.subtract(const Duration(minutes: 12)).toIso8601String(),
        'shipper': shipperJson,
        'bids': <dynamic>[],
        'my_bid': myBid,
        'comment': comment,
      };

  static Order order({
    int id = 4821,
    String fromAddress = 'Актау, морпорт, причал №3',
    String toAddress = 'Жанаозен, база АМУ',
    int price = 180000,
    int weightKg = 20000,
    double distanceKm = 152,
    String cargoType = 'стройматериалы',
    bool refrigerated = false,
    Bid? myBid,
    String? comment,
  }) =>
      Order.parse(orderJson(
        id: id,
        fromAddress: fromAddress,
        toAddress: toAddress,
        price: price,
        weightKg: weightKg,
        distanceKm: distanceKm,
        cargoType: cargoType,
        refrigerated: refrigerated,
        myBid: myBid == null
            ? null
            : {
                'id': myBid.id,
                'order_id': myBid.orderId,
                'price': myBid.price,
                'status': myBid.status.name,
              },
        comment: comment,
      ));

  /// Три заявки ленты — как на макете S1.
  static List<Order> feed() => [
        order(),
        order(
          id: 4822,
          fromAddress: 'Актау, СЭЗ «Морпорт»',
          toAddress: 'Курык, паромный терминал',
          price: 95000,
          weightKg: 12000,
          distanceKm: 68,
          cargoType: 'скоропорт',
          refrigerated: true,
        ),
        order(
          id: 4823,
          fromAddress: 'Актау, мкр 28',
          toAddress: 'Бейнеу, элеватор',
          price: 240000,
          weightKg: 20000,
          distanceKm: 450,
          cargoType: 'продукты',
        ),
      ];

  static Bid bid({
    int id = 1,
    int orderId = 4821,
    int price = 190000,
    BidStatus status = BidStatus.pending,
    int? etaMinutes = 120,
    Order? order,
  }) =>
      Bid.parse({
        'id': id,
        'order_id': orderId,
        'price': price,
        'status': status.name,
        'eta_minutes': etaMinutes,
        'created_at': now.subtract(const Duration(minutes: 12)).toIso8601String(),
        'order': order == null ? null : orderJson(id: orderId),
      });

  static Shipment shipment({
    int id = 1247,
    ShipmentStatus status = ShipmentStatus.inTransit,
    DateTime? pickedUpAt,
    DateTime? deliveredAt,
  }) =>
      Shipment.parse({
        'id': id,
        'order_id': 4821,
        'status': status.wire,
        'track_token': 'demo-token',
        'assigned_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
        'picked_up_at':
            (pickedUpAt ?? now.subtract(const Duration(hours: 1))).toIso8601String(),
        'delivered_at': deliveredAt?.toIso8601String(),
        'order': orderJson(),
        'vehicle': vehicleJson,
      });

  static Map<String, dynamic> payoutJson({
    int id = 91,
    int orderId = 4821,
    int amount = 180000,
    String status = 'paid',
    String from = 'Актау, морпорт, причал №3',
    String to = 'Жанаозен, база АМУ',
    String cargoType = 'стройматериалы',
  }) =>
      {
        'id': id,
        'order_id': orderId,
        'from': from,
        'to': to,
        'cargo_type': cargoType,
        'weight_kg': 20000,
        'distance_km': 152,
        'company': 'ТОО «АктауМунайСервис»',
        'amount': amount,
        'status': status,
        'delivered_at': now.subtract(const Duration(days: 2)).toIso8601String(),
        'paid_at':
            status == 'paid' ? now.subtract(const Duration(days: 1)).toIso8601String() : null,
      };

  /// Выдача `/api/my/payouts`: одна выплата пришла, вторая ещё ждёт.
  static Map<String, dynamic> payoutsJson() => {
        'items': [
          payoutJson(),
          payoutJson(
            id: 92,
            orderId: 4823,
            amount: 240000,
            status: 'pending',
            from: 'Актау, мкр 28',
            to: 'Бейнеу, элеватор',
            cargoType: 'продукты',
          ),
        ],
        'summary': {
          'paid_total': 180000,
          'pending_total': 240000,
          'paid_count': 1,
          'pending_count': 1,
        },
      };

  static PayoutsPage payouts() => PayoutsPage.parse(payoutsJson());

  static Map<String, dynamic> get vehicleJson => {
        'id': 7,
        'plate': '847 ABC 12',
        'type': 'тент',
        'capacity_kg': 20000,
        'has_refrigeration': false,
        'status': 'en_route',
      };

  static Vehicle get vehicle => Vehicle.tryParse(vehicleJson)!;

  static Map<String, dynamic> userJson({String status = 'approved'}) => {
        'id': 10,
        'name': 'Ерлан Сағынов',
        'phone': '77071234567',
        'role': 'driver',
        'rating': 4.9,
        'is_active': true,
        'driver': {'id': 3, 'license_no': '12АБ345678', 'status': status},
        'vehicles': [vehicleJson],
      };

  static User user({String status = 'approved'}) => User.parse(userJson(status: status));
}
