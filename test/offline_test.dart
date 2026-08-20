import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m_truck/data/api_client.dart';
import 'package:m_truck/data/local/cache_store.dart';
import 'package:m_truck/data/local/outbox.dart';
import 'package:m_truck/data/local/token_store.dart';
import 'package:m_truck/data/models/models.dart';
import 'package:m_truck/data/repositories/marketplace_repository.dart';
import 'package:m_truck/data/repositories/payout_repository.dart';
import 'package:m_truck/data/repositories/shipment_repository.dart';
import 'package:m_truck/services/connectivity_service.dart';
import 'package:m_truck/services/location_service.dart';
import 'package:m_truck/services/sync_service.dart';
import 'package:m_truck/state/payouts_controller.dart';
import 'package:m_truck/state/trip_controller.dart';
import 'package:m_truck/widgets/navigator_sheet.dart';
import 'package:m_truck/widgets/step_trail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// Ответ в конверте платформы.
http.Response _ok(Object? data, {Map<String, dynamic>? meta}) => http.Response(
      jsonEncode({'success': true, 'data': data, 'message': 'Success', 'meta': meta}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  group('ApiClient', () {
    test('снимает конверт и отдаёт data', () async {
      final prefs = await _prefs();
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((_) async => _ok({'exists': true, 'code_sent': true})),
      );

      final response = await api.post('/api/auth/phone/check', body: {'phone': '7'});
      expect(response.asMap['exists'], isTrue);
    });

    test('подставляет Bearer-токен в каждый запрос', () async {
      final prefs = await _prefs();
      final tokens = TokenStore(prefs);
      await tokens.write('1|secret');

      String? seen;
      final api = ApiClient(
        tokens: tokens,
        httpClient: MockClient((request) async {
          seen = request.headers['Authorization'];
          return _ok(const <dynamic>[]);
        }),
      );

      await api.get('/api/marketplace/orders');
      expect(seen, 'Bearer 1|secret');
    });

    test('ошибки валидации раскладываются по полям', () async {
      final prefs = await _prefs();
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'success': false,
                'data': {
                  'code': ['Код неверный'],
                },
                'message': 'Неверный код подтверждения',
              }),
              422,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );

      await expectLater(
        api.post('/api/auth/phone/verify'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.fieldError('code'), 'ошибка поля', 'Код неверный')
              .having((e) => e.isNetwork, 'сетевая', isFalse),
        ),
      );
    });

    test('401 закрывает сессию через колбэк', () async {
      final prefs = await _prefs();
      var signedOut = false;
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((_) async => http.Response('{"message":"Unauthenticated."}', 401)),
      )..onUnauthorized = () => signedOut = true;

      await expectLater(api.get('/api/auth/me'), throwsA(isA<ApiException>()));
      expect(signedOut, isTrue);
    });

    test('обрыв связи помечается как сетевая ошибка', () async {
      final prefs = await _prefs();
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((_) async => throw http.ClientException('failed host lookup')),
      );

      await expectLater(
        api.get('/api/marketplace/orders'),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'сетевая', isTrue)),
      );
    });

    test('не-JSON ответ не роняет клиент', () async {
      final prefs = await _prefs();
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((_) async => http.Response('<html>502</html>', 502)),
      );

      await expectLater(
        api.get('/api/settlements'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 502)),
      );
    });
  });

  group('CacheStore', () {
    test('лента переживает перезапуск и помнит время снимка', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);

      await cache.write(CacheStore.keyMarketplace, [
        {'id': 1, 'cargo_type': 'продукты', 'weight_kg': 100},
      ]);

      final snapshot = cache.readList(CacheStore.keyMarketplace)!;
      expect(snapshot.value.single['id'], 1);
      expect(DateTime.now().difference(snapshot.savedAt).inSeconds, lessThan(5));
    });

    test('запись null очищает ключ', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);

      await cache.write(CacheStore.keyCurrentShipment, {'id': 1});
      await cache.write(CacheStore.keyCurrentShipment, null);

      expect(cache.readMap(CacheStore.keyCurrentShipment), isNull);
    });
  });

  group('Outbox', () {
    test('хранит порядок добавления', () async {
      final outbox = Outbox(await _prefs());

      await outbox.add(OutboxKind.bid, {'order_id': 1});
      await outbox.add(OutboxKind.shipmentStatus, {'shipment_id': 2});

      expect(outbox.read().map((i) => i.kind).toList(), [
        OutboxKind.bid,
        OutboxKind.shipmentStatus,
      ]);
    });

    test('считает GPS-точки в буфере отдельно от действий', () async {
      final outbox = Outbox(await _prefs());

      await outbox.add(OutboxKind.tracking, {
        'shipment_id': 1,
        'points': List.generate(42, (i) => {'lat': i, 'lng': i}),
      });
      await outbox.add(OutboxKind.bid, {'order_id': 5});

      expect(outbox.bufferedPoints(), 42);
      expect(outbox.pendingActions(), 1);
    });

    test('знает про неотправленный отклик по заявке', () async {
      final outbox = Outbox(await _prefs());
      await outbox.add(OutboxKind.bid, {'order_id': 77});

      expect(outbox.hasPendingBid(77), isTrue);
      expect(outbox.hasPendingBid(78), isFalse);
    });

    test('идентификаторы уникальны при добавлении подряд', () async {
      // Регрессия: id из одной микросекунды совпадали, и удаление одного
      // элемента уносило соседний.
      final outbox = Outbox(await _prefs());
      for (var i = 0; i < 20; i++) {
        await outbox.add(OutboxKind.bid, {'order_id': i});
      }

      final ids = outbox.read().map((i) => i.id).toSet();
      expect(ids.length, 20);
    });

    test('удаление трогает только свой элемент', () async {
      final outbox = Outbox(await _prefs());
      final first = await outbox.add(OutboxKind.bid, {'order_id': 1});
      await outbox.add(OutboxKind.bid, {'order_id': 2});

      await outbox.remove(first.id);

      expect(outbox.read().map((i) => i.payload['order_id']).toList(), [2]);
    });

    test('переживает перезапуск приложения', () async {
      final prefs = await _prefs();
      await Outbox(prefs).add(OutboxKind.bid, {'order_id': 9});

      // Новый экземпляр поверх того же хранилища — как после холодного старта.
      expect(Outbox(prefs).read().single.payload['order_id'], 9);
    });
  });

  group('SyncService', () {
    late SharedPreferences prefs;
    late Outbox outbox;
    late ConnectivityService connectivity;

    setUp(() async {
      prefs = await _prefs();
      outbox = Outbox(prefs);
      connectivity = ConnectivityService();
    });

    tearDown(() => connectivity.dispose());

    SyncService buildSync(MockClient client) {
      final api = ApiClient(tokens: TokenStore(prefs), httpClient: client);
      final cache = CacheStore(prefs);
      return SyncService(
        outbox: outbox,
        connectivity: connectivity,
        marketplace: MarketplaceRepository(api: api, cache: cache),
        shipments: ShipmentRepository(api: api, cache: cache),
      );
    }

    test('отправляет отложенный отклик и очищает очередь', () async {
      final sent = <String>[];
      final sync = buildSync(MockClient((request) async {
        sent.add(request.url.path);
        return _ok({'id': 1, 'order_id': 4, 'price': 190000, 'status': 'pending'});
      }));

      await outbox.add(OutboxKind.bid, {
        'order_id': 4,
        'price': 190000,
        'vehicle_id': 2,
      });
      await sync.flush();

      expect(sent, ['/api/orders/4/bids']);
      expect(outbox.read(), isEmpty);
      sync.dispose();
    });

    test('без сети действие остаётся в очереди', () async {
      final sync = buildSync(MockClient((_) async => throw http.ClientException('offline')));

      await outbox.add(OutboxKind.shipmentStatus, {
        'shipment_id': 3,
        'status': 'picked_up',
      });
      await sync.flush();

      expect(outbox.read().single.attempts, 1);
      expect(connectivity.isOffline, isTrue);
      sync.dispose();
    });

    test('отказ сервера не крутится вечно', () async {
      // 409 значит «заявку уже забрали» — повторять бессмысленно.
      final sync = buildSync(MockClient((_) async => http.Response(
            jsonEncode({'success': false, 'message': 'Заявку уже забрали'}),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )));

      await outbox.add(OutboxKind.bid, {'order_id': 4, 'price': 1, 'vehicle_id': 2});
      await sync.flush();

      expect(outbox.read(), isEmpty);
      sync.dispose();
    });

    test('порядок сохраняется: первый сбой останавливает разбор очереди', () async {
      var call = 0;
      final sync = buildSync(MockClient((request) async {
        call++;
        // Первый запрос проходит, второй обрывается — третий не должен уйти.
        if (call >= 2) throw http.ClientException('offline');
        return _ok({'id': 1, 'order_id': 1, 'price': 1, 'status': 'pending'});
      }));

      await outbox.add(OutboxKind.bid, {'order_id': 1, 'price': 1, 'vehicle_id': 1});
      await outbox.add(OutboxKind.bid, {'order_id': 2, 'price': 2, 'vehicle_id': 1});
      await outbox.add(OutboxKind.bid, {'order_id': 3, 'price': 3, 'vehicle_id': 1});
      await sync.flush();

      expect(call, 2);
      expect(outbox.read().map((i) => i.payload['order_id']).toList(), [2, 3]);
      sync.dispose();
    });
  });

  group('MarketplaceRepository', () {
    test('успешная лента ложится в кэш и читается обратно', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((_) async => _ok([
              {
                'id': 4,
                'cargo_type': 'стройматериалы',
                'weight_kg': 3000,
                'status': 'published',
                'price_offer': 14000,
                'from': {'address': 'Актау', 'lat': 43.6, 'lng': 51.1},
                'to': {'address': 'Курык', 'lat': 43.1, 'lng': 51.6},
              },
            ])),
      );
      final repo = MarketplaceRepository(api: api, cache: cache);

      final live = await repo.feed(const MarketplaceFilters());
      expect(live.single.id, 4);

      final cached = repo.cachedFeed()!;
      expect(cached.value.single.cargoType, 'стройматериалы');
    });

    test('отфильтрованная выдача кэш не перетирает', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((_) async => _ok(const <dynamic>[])),
      );
      final repo = MarketplaceRepository(api: api, cache: cache);

      await cache.write(CacheStore.keyMarketplace, [
        {'id': 1, 'cargo_type': 'продукты', 'weight_kg': 10, 'status': 'published'},
      ]);
      await repo.feed(const MarketplaceFilters(maxWeightKg: 5000));

      // Иначе офлайн показал бы обрезок вместо полной ленты.
      expect(repo.cachedFeed()!.value.single.id, 1);
    });
  });

  group('PayoutRepository', () {
    test('полная выдача кэшируется и читается без сети', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      final repo = PayoutRepository(
        api: ApiClient(
          tokens: TokenStore(prefs),
          httpClient: MockClient((_) async => _ok(Fixtures.payoutsJson())),
        ),
        cache: cache,
      );

      await repo.list();
      final cached = repo.cached()!;

      expect(cached.value.items, hasLength(2));
      expect(cached.value.summary.pendingTotal, 240000);
    });

    test('фильтр по статусу уходит в запрос и кэш не перетирает', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      await cache.write(CacheStore.keyPayouts, Fixtures.payoutsJson());

      String? seenQuery;
      final repo = PayoutRepository(
        api: ApiClient(
          tokens: TokenStore(prefs),
          httpClient: MockClient((request) async {
            seenQuery = request.url.query;
            return _ok({'items': const <dynamic>[], 'summary': const <String, dynamic>{}});
          }),
        ),
        cache: cache,
      );

      await repo.list(status: PayoutStatus.pending);

      expect(seenQuery, 'status=pending');
      // Обрезанная выдача не должна стать тем, что покажет офлайн.
      expect(repo.cached()!.value.items, hasLength(2));
    });
  });

  group('PayoutsController', () {
    test('без сети показывает кэш и фильтрует его на месте', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      await cache.write(CacheStore.keyPayouts, Fixtures.payoutsJson());

      final connectivity = ConnectivityService();
      addTearDown(connectivity.dispose);
      final controller = PayoutsController(
        repository: PayoutRepository(
          api: ApiClient(
            tokens: TokenStore(prefs),
            httpClient: MockClient((_) async => throw const SocketException('нет сети')),
          ),
          cache: cache,
        ),
        connectivity: connectivity,
      );

      await controller.load();

      expect(controller.items, hasLength(2));
      expect(controller.isFromCache, isTrue);
      expect(controller.pendingTotal, 240000);
      expect(controller.error, isNull);

      await controller.setFilter(PayoutStatus.pending);

      expect(controller.items, hasLength(1));
      expect(controller.items.single.status, PayoutStatus.pending);
      // Сводка считается по всем выплатам — фильтр её не трогает.
      expect(controller.summary.paidTotal, 180000);
    });

    test('без сети и без кэша объясняет, почему пусто', () async {
      final prefs = await _prefs();
      final connectivity = ConnectivityService();
      addTearDown(connectivity.dispose);
      final controller = PayoutsController(
        repository: PayoutRepository(
          api: ApiClient(
            tokens: TokenStore(prefs),
            httpClient: MockClient((_) async => throw const SocketException('нет сети')),
          ),
          cache: CacheStore(prefs),
        ),
        connectivity: connectivity,
      );

      await controller.load();

      expect(controller.items, isEmpty);
      expect(controller.hasLoaded, isFalse);
      expect(controller.error, 'Нет сети и нет сохранённых выплат');
    });
  });

  group('MarketplaceRepository · заявки в откликах', () {
    test('заявка берётся из кэша ленты, без лишнего запроса', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      await cache.write(CacheStore.keyMarketplace, [Fixtures.orderJson()]);

      final paths = <String>[];
      final repo = MarketplaceRepository(
        api: ApiClient(
          tokens: TokenStore(prefs),
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            // Сервер отдаёт отклик без вложенной заявки — так и есть в API.
            return _ok([
              {'id': 1, 'order_id': 4821, 'price': 190000, 'status': 'pending'},
            ]);
          }),
        ),
        cache: cache,
      );

      final bids = await repo.myBids();

      expect(bids.single.order?.from?.address, 'Актау, морпорт, причал №3');
      expect(paths, ['/api/my/bids']);
    });

    test('заявки нет в кэше — догружается карточкой', () async {
      final prefs = await _prefs();
      final repo = MarketplaceRepository(
        api: ApiClient(
          tokens: TokenStore(prefs),
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/my/bids') {
              return _ok([
                {'id': 1, 'order_id': 4821, 'price': 190000, 'status': 'pending'},
              ]);
            }
            return _ok(Fixtures.orderJson());
          }),
        ),
        cache: CacheStore(prefs),
      );

      final bids = await repo.myBids();

      expect(bids.single.order?.to?.address, 'Жанаозен, база АМУ');
      // Заявка попадает и в кэш: без сети «Отклики» не потеряют адреса.
      expect(repo.cachedBids()!.value.single.order, isNotNull);
    });

    test('снятая с публикации заявка не роняет список откликов', () async {
      final prefs = await _prefs();
      final repo = MarketplaceRepository(
        api: ApiClient(
          tokens: TokenStore(prefs),
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/my/bids') {
              return _ok([
                {'id': 1, 'order_id': 4821, 'price': 190000, 'status': 'rejected'},
              ]);
            }
            return http.Response(
              jsonEncode({'success': false, 'message': 'Не найдено'}),
              404,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
        cache: CacheStore(prefs),
      );

      final bids = await repo.myBids();

      expect(bids.single.order, isNull);
      expect(bids.single.status, BidStatus.rejected);
    });
  });

  group('Шаги сделки', () {
    test('отклик не уезжает дальше «Принят»', () {
      expect(DeliveryStep.forBid(BidStatus.pending), DeliveryStep.bid);
      expect(DeliveryStep.forBid(BidStatus.accepted), DeliveryStep.accepted);
      expect(DeliveryStep.forBid(BidStatus.rejected), isNull);
    });

    test('рейс проходит погрузку, дорогу и сдачу', () {
      expect(DeliveryStep.forShipment(ShipmentStatus.assigned), DeliveryStep.accepted);
      expect(DeliveryStep.forShipment(ShipmentStatus.pickedUp), DeliveryStep.pickup);
      expect(DeliveryStep.forShipment(ShipmentStatus.inTransit), DeliveryStep.transit);
      expect(DeliveryStep.forShipment(ShipmentStatus.delivered), DeliveryStep.delivered);
      expect(DeliveryStep.forShipment(ShipmentStatus.closed), DeliveryStep.delivered);
    });
  });

  group('Внешние навигаторы', () {
    test('2ГИС получает координаты в порядке «долгота, широта»', () {
      final uri = ExternalNavigator.twogis.appUri(43.641, 51.198);
      expect(uri.scheme, 'dgis');
      expect(uri.toString(), endsWith('/to/51.198,43.641'));
      expect(
        ExternalNavigator.twogis.webUri(43.641, 51.198).host,
        '2gis.kz',
      );
    });

    test('у каждого навигатора есть запасная ссылка в браузер', () {
      for (final navigator in ExternalNavigator.values) {
        expect(navigator.webUri(43.6, 51.2).scheme, 'https');
      }
    });
  });

  group('TripController', () {
    test('принятый отклик уезжает из «Откликов» в «Рейсы»', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/my/bids') {
            return _ok([
              {
                'id': 1,
                'order_id': 4821,
                'price': 190000,
                'status': 'accepted',
                'order': Fixtures.orderJson(),
              },
              {
                'id': 2,
                'order_id': 4822,
                'price': 90000,
                'status': 'pending',
                'order': Fixtures.orderJson(id: 4822),
              },
            ]);
          }
          if (path == '/api/my/shipments') {
            return _ok([
              {
                'id': 7,
                'order_id': 4821,
                'status': 'assigned',
                'order': Fixtures.orderJson(),
              },
            ]);
          }
          return _ok(const <String, dynamic>{});
        }),
      );

      final connectivity = ConnectivityService();
      addTearDown(connectivity.dispose);
      final outbox = Outbox(prefs);
      final marketplace = MarketplaceRepository(api: api, cache: cache);
      final shipments = ShipmentRepository(api: api, cache: cache);
      final sync = SyncService(
        outbox: outbox,
        connectivity: connectivity,
        marketplace: marketplace,
        shipments: shipments,
      );
      addTearDown(sync.dispose);
      final trips = TripController(
        shipments: shipments,
        marketplace: marketplace,
        location: LocationService(),
        connectivity: connectivity,
        sync: sync,
        outbox: outbox,
      );
      addTearDown(trips.dispose);

      await trips.load();

      expect(trips.bids, hasLength(2));
      // Принятый отклик уже стал рейсом — во вкладке «Отклики» ему не место.
      expect(trips.openBids.map((b) => b.id), [2]);
      expect(trips.liveShipments.map((s) => s.id), [7]);
    });
  });

  group('ShipmentRepository', () {
    test('пустой ответ значит «рейса нет»', () async {
      final prefs = await _prefs();
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((_) async => _ok(const <String, dynamic>{})),
      );
      final repo = ShipmentRepository(api: api, cache: CacheStore(prefs));

      expect(await repo.current(), isNull);
    });

    test('активный рейс кэшируется для работы без сети', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((_) async => _ok({
              'id': 12,
              'order_id': 4,
              'status': 'in_transit',
              'track_token': 'abc',
            })),
      );
      final repo = ShipmentRepository(api: api, cache: cache);

      await repo.current();
      final cached = repo.cachedCurrent()!;

      expect(cached.value.id, 12);
      expect(cached.value.status, ShipmentStatus.inTransit);
    });

    test('статус, проставленный без сети, переживает перезапуск', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((_) async => _ok({
              'id': 12,
              'order_id': 4,
              'status': 'assigned',
              'order': {
                'id': 4,
                'from': {'address': 'Актау', 'lat': 43.6, 'lng': 51.2},
                'price_offer': 180000,
              },
            })),
      );
      final repo = ShipmentRepository(api: api, cache: cache);
      await repo.current();

      final patched = await repo.cacheLocalStatus(
        shipmentId: 12,
        status: ShipmentStatus.pickedUp,
      );

      expect(patched!.status, ShipmentStatus.pickedUp);
      expect(patched.pickedUpAt, isNotNull);
      // Заявка внутри рейса не теряется — экран остаётся с адресом и ценой.
      expect(patched.order?.from?.address, 'Актау');

      // Новый запуск читает тот же кэш.
      final afterRestart = ShipmentRepository(api: api, cache: CacheStore(prefs));
      expect(afterRestart.cachedCurrent()!.value.status, ShipmentStatus.pickedUp);
    });

    test('статус чужого рейса не затирает кэш активного', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      await cache.write(CacheStore.keyCurrentShipment, {
        'id': 12,
        'order_id': 4,
        'status': 'in_transit',
      });
      final repo = ShipmentRepository(
        api: ApiClient(tokens: TokenStore(prefs), httpClient: MockClient((_) async => _ok(null))),
        cache: cache,
      );

      expect(
        await repo.cacheLocalStatus(shipmentId: 99, status: ShipmentStatus.delivered),
        isNull,
      );
      expect(repo.cachedCurrent()!.value.status, ShipmentStatus.inTransit);
    });

    test('ответ сервера без заявки не обедняет кэш рейса', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      await cache.write(CacheStore.keyCurrentShipment, {
        'id': 12,
        'order_id': 4,
        'status': 'assigned',
        'order': {
          'id': 4,
          'to': {'address': 'Жанаозен', 'lat': 43.3, 'lng': 52.8},
        },
      });
      final repo = ShipmentRepository(
        api: ApiClient(
          tokens: TokenStore(prefs),
          // Сервер отвечает урезанным рейсом — так делает часть эндпоинтов.
          httpClient: MockClient((_) async => _ok({'id': 12, 'status': 'picked_up'})),
        ),
        cache: cache,
      );

      final updated = await repo.changeStatus(
        shipmentId: 12,
        status: ShipmentStatus.pickedUp,
      );

      expect(updated.status, ShipmentStatus.pickedUp);
      expect(updated.order?.to?.address, 'Жанаозен');
      expect(repo.cachedCurrent()!.value.order?.to?.address, 'Жанаозен');
    });

    test('завершённый рейс убирается из кэша', () async {
      final prefs = await _prefs();
      final cache = CacheStore(prefs);
      await cache.write(CacheStore.keyCurrentShipment, {'id': 12, 'status': 'delivered'});
      final repo = ShipmentRepository(
        api: ApiClient(tokens: TokenStore(prefs), httpClient: MockClient((_) async => _ok(null))),
        cache: cache,
      );

      await repo.forgetCurrent();

      expect(repo.cachedCurrent(), isNull);
    });

    test('пачка точек режется до лимита сервера в 200', () async {
      final prefs = await _prefs();
      var seenCount = 0;
      final api = ApiClient(
        tokens: TokenStore(prefs),
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          seenCount = (body['points'] as List).length;
          return _ok({'accepted': seenCount});
        }),
      );
      final repo = ShipmentRepository(api: api, cache: CacheStore(prefs));

      await repo.pushTracking(
        shipmentId: 1,
        points: List.generate(250, (i) => {'lat': i, 'lng': i}),
      );

      expect(seenCount, 200);
    });
  });
}
