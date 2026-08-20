import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:m_truck/data/models/models.dart';

import 'fixtures.dart';

/// Фрагменты настоящих ответов `m-truck.atomozen.kz` — со всеми их
/// особенностями: пустые объекты вместо `null`, лишние поля, ISO-даты.
Map<String, dynamic> _order() => jsonDecode('''
{
  "id": 2,
  "shipper_id": 2,
  "target_driver_id": null,
  "target_driver": {},
  "from": {"address": "Актау, порт", "lat": 43.641, "lng": 51.198},
  "to": {"address": "Жанаозен, база", "lat": 43.341, "lng": 52.861},
  "cargo_type": "продукты",
  "weight_kg": 1500,
  "requires_refrigeration": false,
  "photo_url": null,
  "pickup_from": "2026-08-20T08:00:00+00:00",
  "pickup_to": "2026-08-20T14:00:00+00:00",
  "price_offer": 31500,
  "price_final": null,
  "distance_km": 172.8,
  "duration_min": 160,
  "route_geometry": {"type": "LineString", "coordinates": [[51.198, 43.641], [52.861, 43.341]]},
  "status": "published",
  "published_at": "2026-08-19T13:04:19+00:00",
  "created_at": "2026-08-19T13:23:13+00:00",
  "shipper": {"id": 2, "name": "Иван", "company_name": "Береке ТОО", "phone": "77010000102"},
  "bids_count": {},
  "bids": [],
  "shipment": {},
  "pickup_distance_km": null,
  "offered_to_me": false,
  "my_bid": null
}
''') as Map<String, dynamic>;

void main() {
  group('Order', () {
    test('разбирает боевой ответ биржи', () {
      final order = Order.parse(_order());

      expect(order.id, 2);
      expect(order.from?.address, 'Актау, порт');
      expect(order.to?.lat, 43.341);
      expect(order.weightKg, 1500);
      expect(order.priceOffer, 31500);
      expect(order.distanceKm, 172.8);
      expect(order.durationMin, 160);
      expect(order.status, 'published');
      expect(order.shipper?.displayName, 'Береке ТОО');
      expect(order.publishedAt, isNotNull);
    });

    test('пустой объект связи читается как её отсутствие', () {
      // Сервер отдаёт `{}` вместо `null` для незаполненных связей.
      final order = Order.parse(_order());
      expect(order.myBid, isNull);
      expect(order.bids, isEmpty);
    });

    test('координаты GeoJSON переворачиваются в (lat, lng)', () {
      final order = Order.parse(_order());
      final points = order.routeGeometry!.points;

      // В GeoJSON порядок [lng, lat] — модель обязана его развернуть.
      expect(points.first.lat, 43.641);
      expect(points.first.lng, 51.198);
    });

    test('без геометрии маршрут превращается в прямую А→Б', () {
      final json = _order()..remove('route_geometry');
      final order = Order.parse(json);

      expect(order.routeGeometry, isNull);
      expect(order.mapRoute!.points.length, 2);
      expect(order.mapRoute!.points.last.lat, 43.341);
    });

    test('финальная цена вытесняет предложение заказчика', () {
      final json = _order()..['price_final'] = 40000;
      expect(Order.parse(json).displayPrice, 40000);
    });

    test('числа в виде строк не ломают разбор', () {
      final json = _order()
        ..['weight_kg'] = '1500'
        ..['distance_km'] = '172.8';
      final order = Order.parse(json);

      expect(order.weightKg, 1500);
      expect(order.distanceKm, 172.8);
    });

    test('copyWith подставляет отклик, не трогая остальное', () {
      final order = Order.parse(_order());
      final bid = Bid.parse({'id': 7, 'order_id': 2, 'price': 33000, 'status': 'pending'});
      final updated = order.copyWith(myBid: bid);

      expect(updated.myBid?.price, 33000);
      expect(updated.id, order.id);
      expect(updated.from?.address, order.from?.address);
    });
  });

  group('User', () {
    test('водитель без профиля должен пройти регистрацию', () {
      final user = User.parse({
        'id': 10,
        'name': 'Test Driver',
        'phone': '77011234567',
        'role': 'driver',
        'rating': 5,
        'is_active': true,
        'driver': null,
        'vehicles': <dynamic>[],
      });

      expect(user.driver, isNull);
      expect(user.canBid, isFalse);
      expect(user.primaryVehicle, isNull);
    });

    test('одобренный водитель может откликаться', () {
      final user = User.parse({
        'id': 10,
        'name': 'Ерлан',
        'phone': '77011234567',
        'role': 'driver',
        'rating': 4.9,
        'is_active': true,
        'driver': {'id': 3, 'license_no': '12АБ345678', 'status': 'approved'},
        'vehicles': [
          {
            'id': 4,
            'plate': '847ABC12',
            'type': 'тент',
            'capacity_kg': 20000,
            'has_refrigeration': false,
            'status': 'idle',
          },
        ],
      });

      expect(user.canBid, isTrue);
      expect(user.driver!.status, DriverStatus.approved);
      expect(user.primaryVehicle!.plate, '847ABC12');
    });

    test('водитель на модерации откликаться не может', () {
      final user = User.parse({
        'id': 10,
        'name': 'Ерлан',
        'phone': '7',
        'role': 'driver',
        'rating': 5,
        'is_active': true,
        'driver': {'id': 3, 'license_no': 'X', 'status': 'pending'},
        'vehicles': <dynamic>[],
      });

      expect(user.canBid, isFalse);
      expect(user.driver, isNotNull);
    });
  });

  group('ShipmentStatus', () {
    test('следующий шаг ведёт от назначения к доставке', () {
      expect(ShipmentStatus.assigned.next, ShipmentStatus.pickedUp);
      expect(ShipmentStatus.pickedUp.next, ShipmentStatus.inTransit);
      expect(ShipmentStatus.inTransit.next, ShipmentStatus.delivered);
      expect(ShipmentStatus.delivered.next, isNull);
    });

    test('живые статусы держат GPS включённым', () {
      expect(ShipmentStatus.assigned.isLive, isTrue);
      expect(ShipmentStatus.inTransit.isLive, isTrue);
      expect(ShipmentStatus.delivered.isLive, isFalse);
      expect(ShipmentStatus.closed.isFinished, isTrue);
    });

    test('строка с сервера переводится в enum и обратно', () {
      expect(ShipmentStatus.parse('picked_up'), ShipmentStatus.pickedUp);
      expect(ShipmentStatus.pickedUp.wire, 'picked_up');
      expect(ShipmentStatus.parse('какая-то ерунда'), ShipmentStatus.assigned);
    });
  });

  group('Shipment', () {
    test('считает фактическую длительность рейса', () {
      final shipment = Shipment.parse({
        'id': 1,
        'order_id': 2,
        'status': 'delivered',
        'picked_up_at': '2026-08-20T13:40:00+00:00',
        'delivered_at': '2026-08-20T17:02:00+00:00',
        'order': _order(),
      });

      expect(shipment.actualMinutes, 202);
      expect(shipment.earning, 31500);
    });

    test('без отметок времени длительность неизвестна', () {
      final shipment = Shipment.parse({'id': 1, 'order_id': 2, 'status': 'assigned'});
      expect(shipment.actualMinutes, isNull);
    });
  });

  group('Bid', () {
    test('время подачи считается от момента отклика', () {
      final bid = Bid.parse({
        'id': 1,
        'order_id': 2,
        'price': 190000,
        'status': 'pending',
        'eta_minutes': 120,
        'created_at': '2026-08-20T12:00:00Z',
      });

      expect(bid.etaAt, DateTime.parse('2026-08-20T14:00:00Z'));
    });

    test('без eta время подачи не выдумывается', () {
      final bid = Bid.parse({'id': 1, 'order_id': 2, 'price': 1, 'status': 'rejected'});
      expect(bid.etaAt, isNull);
      expect(bid.status, BidStatus.rejected);
    });
  });

  group('Payout', () {
    test('разбирает выплату вместе со сводкой', () {
      final page = PayoutsPage.parse(Fixtures.payoutsJson());

      expect(page.items, hasLength(2));
      expect(page.summary.paidTotal, 180000);
      expect(page.summary.pendingTotal, 240000);
      expect(page.summary.total, 420000);
      expect(page.summary.isEmpty, isFalse);

      final paid = page.items.first;
      expect(paid.isPaid, isTrue);
      expect(paid.company, 'ТОО «АктауМунайСервис»');
      // Подписываем строку датой выплаты, если она есть.
      expect(paid.at, paid.paidAt);

      final pending = page.items.last;
      expect(pending.status, PayoutStatus.pending);
      expect(pending.paidAt, isNull);
      expect(pending.at, pending.deliveredAt);
    });

    test('пустая выдача не роняет разбор', () {
      final page = PayoutsPage.parse(const {});

      expect(page.items, isEmpty);
      expect(page.summary.isEmpty, isTrue);
      expect(page.summary.total, 0);
    });

    test('неизвестный статус считается ожиданием, а не выплатой', () {
      expect(PayoutStatus.parse('processing'), PayoutStatus.pending);
      expect(PayoutStatus.parse(null), PayoutStatus.pending);
      expect(PayoutStatus.paid.wire, 'paid');
    });
  });
}
