import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:m_truck/core/formatters.dart';
import 'package:m_truck/core/theme/app_theme.dart';
import 'package:m_truck/core/theme/tokens.dart';
import 'package:m_truck/data/api_client.dart';
import 'package:m_truck/data/local/cache_store.dart';
import 'package:m_truck/data/local/token_store.dart';
import 'package:m_truck/data/models/models.dart';
import 'package:m_truck/data/repositories/payout_repository.dart';
import 'package:m_truck/features/payouts/payouts_screen.dart';
import 'package:m_truck/services/connectivity_service.dart';
import 'package:m_truck/state/payouts_controller.dart';
import 'package:m_truck/widgets/brand.dart';
import 'package:m_truck/widgets/offline_banner.dart';
import 'package:m_truck/widgets/order_card.dart';
import 'package:m_truck/widgets/primitives.dart';
import 'package:m_truck/widgets/route_map.dart';
import 'package:m_truck/widgets/route_rail.dart';
import 'package:m_truck/widgets/status_badge.dart';
import 'package:m_truck/widgets/step_trail.dart';
import 'package:m_truck/widgets/swipe_action.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// Снимки экрана телефона из макета: 412×915 логических пикселей.
const _phone = Size(412, 915);

/// Те же делегаты, что и в боевом приложении — иначе снимок покажет не тот
/// набор системных строк.
const _localizations = <LocalizationsDelegate<Object>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Подгружает реальные шрифты в тестовую среду.
///
/// `flutter test` по умолчанию рисует всё заглушкой Ahem: без этого снимок
/// показал бы прямоугольники вместо текста и квадраты вместо иконок.
Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final loader = FontLoader(family)
      ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
    await loader.load();
  }

  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    await load('Inter', 'assets/fonts/Inter-$weight.ttf');
  }

  // Иконочный шрифт лежит в пакете — путь берём из карты пакетов проекта.
  final phosphor = _packageRoot('phosphor_flutter');
  if (phosphor == null) return;
  for (final (family, file) in const [
    ('PhosphorRegular', 'Phosphor.ttf'),
    ('PhosphorBold', 'Phosphor-Bold.ttf'),
    ('PhosphorFill', 'Phosphor-Fill.ttf'),
    ('PhosphorLight', 'Phosphor-Light.ttf'),
    ('PhosphorThin', 'Phosphor-Thin.ttf'),
    ('PhosphorDuotone', 'Phosphor-Duotone.ttf'),
  ]) {
    // IconData из пакета объявляет fontPackage, поэтому движок ищет семейство
    // под именем `packages/<пакет>/<семейство>`.
    await load('packages/phosphor_flutter/$family', '$phosphor/lib/fonts/$file');
  }
}

/// Корень пакета из `.dart_tool/package_config.json` — без хардкода пути к
/// кэшу pub, который у каждой машины свой.
String? _packageRoot(String name) {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) return null;
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map<String, dynamic>)['packages'] as List;
  for (final package in packages.cast<Map<String, dynamic>>()) {
    if (package['name'] != name) continue;
    final root = Uri.parse(package['rootUri'] as String);
    return root.isAbsolute
        ? root.toFilePath()
        : File('.dart_tool/${root.path}').absolute.path;
  }
  return null;
}

/// Догружает картинки из ассетов.
///
/// Декодирование PNG идёт по-настоящему асинхронно, а `pumpAndSettle` крутит
/// только фейковые таймеры — без этого логотип не успевает попасть в снимок.
Future<void> _settleImages(WidgetTester tester) async {
  final images = find.byType(Image).evaluate().toList();
  if (images.isEmpty) return;
  await tester.runAsync(() async {
    for (final element in images) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await _loadFonts();
    // Кэш тайлов по умолчанию спрашивает путь у path_provider, а плагинов в
    // тестовой среде нет. Отдаём ему временную папку.
    BuiltInMapCachingProvider.getOrCreateInstance(
      cacheDirectory: Directory.systemTemp.createTempSync('m_truck_tiles').path,
    );
  });

  Future<void> pumpScreen(WidgetTester tester, Widget child) async {
    tester.view
      ..physicalSize = _phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        locale: const Locale('ru'),
        localizationsDelegates: _localizations,
        // Выравнивание по верху даёт свободные вертикальные ограничения —
        // такие же, как у списка или колонки в настоящем экране.
        home: Scaffold(
          body: SafeArea(child: Align(alignment: Alignment.topCenter, child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _settleImages(tester);
  }

  group('карточка заявки', () {
    testWidgets('открытая заявка показывает цену, маршрут и CTA', (tester) async {
      await pumpScreen(
        tester,
        Padding(
          padding: const EdgeInsets.all(Gap.screen),
          child: OrderCard(
            order: Fixtures.order(),
            state: OrderCardState.open,
            onBid: () {},
          ),
        ),
      );

      // Цена — первое, что видит водитель.
      expect(find.text(Fmt.money(180000)), findsOneWidget);
      expect(find.text('Актау, морпорт, причал №3'), findsOneWidget);
      expect(find.text('Жанаозен, база АМУ'), findsOneWidget);
      expect(find.text('ОТКЛИКНУТЬСЯ'), findsOneWidget);
      // Вместо слова «НОВАЯ» — возраст заявки: он говорит, успел ли её
      // кто-то разобрать.
      expect(find.text('НОВАЯ'), findsNothing);
      expect(find.text(Fmt.ago(Fixtures.order().publishedAt)), findsOneWidget);

      await expectLater(
        find.byType(OrderCard),
        matchesGoldenFile('goldens/order_card_open.png'),
      );
    });

    testWidgets('отклик в очереди заменяет кнопку объяснением', (tester) async {
      await pumpScreen(
        tester,
        Padding(
          padding: const EdgeInsets.all(Gap.screen),
          child: OrderCard(order: Fixtures.order(), state: OrderCardState.bidQueued),
        ),
      );

      expect(find.text('ОТКЛИКНУТЬСЯ'), findsNothing);
      expect(find.text('ОТКЛИК В ОЧЕРЕДИ'), findsOneWidget);
      expect(
        find.text('Отправится автоматически, когда появится сеть'),
        findsOneWidget,
      );

      await expectLater(
        find.byType(OrderCard),
        matchesGoldenFile('goldens/order_card_queued.png'),
      );
    });

    testWidgets('водитель на модерации не видит кнопку отклика', (tester) async {
      await pumpScreen(
        tester,
        Padding(
          padding: const EdgeInsets.all(Gap.screen),
          child: OrderCard(order: Fixtures.order(), state: OrderCardState.blocked),
        ),
      );

      expect(find.text('ОТКЛИКНУТЬСЯ'), findsNothing);
      expect(find.text('ПРАВА НА МОДЕРАЦИИ'), findsOneWidget);
    });
  });

  group('бейджи статусов', () {
    testWidgets('каждый статус несёт цвет, иконку и текст', (tester) async {
      await pumpScreen(
        tester,
        Padding(
          padding: const EdgeInsets.all(Gap.screen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final badge in [
                StatusBadge.newOrder(),
                StatusBadge.bidSent(),
                StatusBadge.assigned(),
                StatusBadge.inTransit(),
                StatusBadge.completed(),
                StatusBadge.rejected(),
                StatusBadge.queued(),
                StatusBadge.backload(),
              ])
                Padding(padding: const EdgeInsets.only(bottom: Gap.sm), child: badge),
            ],
          ),
        ),
      );

      // Цвета мало: у каждого бейджа обязана быть иконка.
      expect(find.byType(Icon), findsNWidgets(8));

      await expectLater(
        find.byType(Column).first,
        matchesGoldenFile('goldens/status_badges.png'),
      );
    });
  });

  group('схема маршрута', () {
    testWidgets('рисует ломаную и метки', (tester) async {
      await pumpScreen(
        tester,
        RouteMapView(route: Fixtures.order().mapRoute, height: 260),
      );

      await expectLater(
        find.byType(RouteMapView),
        matchesGoldenFile('goldens/route_map.png'),
      );
    });

    testWidgets('показывает пройденный участок и машину', (tester) async {
      await pumpScreen(
        tester,
        RouteMapView(route: Fixtures.order().mapRoute, height: 260, progress: 0.55),
      );

      await expectLater(
        find.byType(RouteMapView),
        matchesGoldenFile('goldens/route_map_progress.png'),
      );
    });

    testWidgets('пустой маршрут не роняет виджет', (tester) async {
      await pumpScreen(tester, const RouteMapView(route: null, height: 200));
      expect(tester.takeException(), isNull);
    });
  });

  group('рельс точек', () {
    testWidgets('пройденная точка помечается галочкой', (tester) async {
      await pumpScreen(
        tester,
        const Padding(
          padding: EdgeInsets.all(Gap.screen),
          child: RouteRail(
            stops: [
              RailStop(
                title: 'Актау, морской порт',
                subtitle: 'Загружено · 13:40',
                state: RailStopState.done,
              ),
              RailStop(
                title: 'Жанаозен, база АМУ',
                subtitle: 'Выгрузка · ожидается 15:20',
                state: RailStopState.current,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Актау, морской порт'), findsOneWidget);
      await expectLater(
        find.byType(RouteRail),
        matchesGoldenFile('goldens/route_rail.png'),
      );
    });
  });

  group('офлайн', () {
    testWidgets('плашка ленты объясняет, что показано из кэша', (tester) async {
      await pumpScreen(
        tester,
        OfflineBanner.cachedFeed(DateTime.now().subtract(const Duration(minutes: 12))),
      );

      expect(find.text('Нет сети'), findsOneWidget);
      expect(find.textContaining('12 мин назад'), findsOneWidget);

      await expectLater(
        find.byType(OfflineBanner),
        matchesGoldenFile('goldens/offline_banner_feed.png'),
      );
    });

    testWidgets('плашка рейса считает отложенные действия', (tester) async {
      await pumpScreen(tester, OfflineBanner.queuedActions(3));

      expect(find.text('Статусы отправятся автоматически'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await expectLater(
        find.byType(OfflineBanner),
        matchesGoldenFile('goldens/offline_banner_trip.png'),
      );
    });

    testWidgets('буфер GPS-точек виден на карте', (tester) async {
      await pumpScreen(
        tester,
        const Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.all(Gap.screen),
            child: GpsPill(isTracking: true, bufferedPoints: 42),
          ),
        ),
      );

      expect(find.text('42 GPS-точки в буфере'), findsOneWidget);
    });
  });

  group('свайп подтверждения', () {
    testWidgets('срабатывает только после протаскивания через дорожку',
        (tester) async {
      var confirmed = false;
      await pumpScreen(
        tester,
        Padding(
          padding: const EdgeInsets.all(Gap.screen),
          child: SwipeAction(
            label: 'Смахните: прибыл',
            onConfirmed: () async => confirmed = true,
          ),
        ),
      );

      final knob = find.byType(GestureDetector).last;

      // Короткий сдвиг — случайное касание в трясущейся кабине.
      await tester.drag(knob, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);

      // Полное протаскивание — осознанное действие.
      await tester.drag(knob, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });

    testWidgets('без сети объясняет, что будет со статусом', (tester) async {
      await pumpScreen(
        tester,
        Padding(
          padding: const EdgeInsets.all(Gap.screen),
          child: SwipeAction(
            label: 'Смахните: прибыл',
            hint: 'Статус сохранится на телефоне и уйдёт, когда появится сеть',
            onConfirmed: () async {},
          ),
        ),
      );

      await expectLater(
        find.byType(SwipeAction),
        matchesGoldenFile('goldens/swipe_action.png'),
      );
    });
  });

  group('зоны нажатия', () {
    testWidgets('главная кнопка не ниже 56 dp', (tester) async {
      await pumpScreen(
        tester,
        Padding(
          padding: const EdgeInsets.all(Gap.screen),
          child: PrimaryButton(label: 'Откликнуться', onPressed: () {}),
        ),
      );

      // Водитель в перчатке: мелкие цели недопустимы.
      expect(tester.getSize(find.byType(PrimaryButton)).height, greaterThanOrEqualTo(56));
    });

    testWidgets('кнопка-иконка занимает 56×56', (tester) async {
      await pumpScreen(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: IconTapTarget(icon: Icons.add, onPressed: () {}),
        ),
      );

      final size = tester.getSize(find.byType(IconTapTarget));
      expect(size.width, greaterThanOrEqualTo(56));
      expect(size.height, greaterThanOrEqualTo(56));
    });
  });

  group('пустое состояние', () {
    testWidgets('предлагает выход, а не только констатирует пустоту',
        (tester) async {
      var reset = false;
      await pumpScreen(
        tester,
        EmptyState(
          icon: Icons.inbox,
          title: 'Пока нет заявок по вашим фильтрам',
          message: 'Проверяем новые заявки каждую минуту.',
          actionLabel: 'Сбросить фильтры',
          onAction: () => reset = true,
        ),
      );

      await tester.tap(find.text('Сбросить фильтры'));
      await tester.pumpAndSettle();
      expect(reset, isTrue);

      await expectLater(
        find.byType(EmptyState),
        matchesGoldenFile('goldens/empty_state.png'),
      );
    });
  });

  group('бренд', () {
    testWidgets('шапка входа показывает логотип и название', (tester) async {
      await pumpScreen(
        tester,
        const Padding(
          padding: EdgeInsets.all(Gap.screen),
          child: BrandHeader(),
        ),
      );

      // Логотип — картинка, а не иконка-заглушка.
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Mangystau Truck'), findsOneWidget);
      expect(find.text('Кабинет перевозчика'), findsOneWidget);

      await expectLater(
        find.byType(BrandHeader),
        matchesGoldenFile('goldens/brand_header.png'),
      );
    });
  });

  group('выплаты', () {
    /// Экран выплат на фиксированной выдаче сервера.
    Future<PayoutsController> pumpPayouts(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final connectivity = ConnectivityService();
      addTearDown(connectivity.dispose);

      final controller = PayoutsController(
        repository: PayoutRepository(
          api: ApiClient(
            tokens: TokenStore(prefs),
            // Сервер уважает фильтр `status`, сводка от него не зависит.
            httpClient: MockClient((request) async {
              final page = Fixtures.payoutsJson();
              final wanted = request.url.queryParameters['status'];
              if (wanted != null) {
                page['items'] = (page['items'] as List)
                    .where((item) => (item as Map)['status'] == wanted)
                    .toList();
              }
              return http.Response(
                jsonEncode({'success': true, 'data': page}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
          cache: CacheStore(prefs),
        ),
        connectivity: connectivity,
      );
      addTearDown(controller.dispose);

      await pumpScreen(
        tester,
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: connectivity),
            ChangeNotifierProvider.value(value: controller),
          ],
          child: const SizedBox(width: 412, height: 860, child: PayoutsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('сводка и список показывают, что пришло и что ждёт', (tester) async {
      await pumpPayouts(tester);

      expect(find.text('Выплаты'), findsOneWidget);
      // Обе цифры сводки на экране: выплачено и ожидает.
      expect(find.text(Fmt.money(180000)), findsWidgets);
      expect(find.text(Fmt.money(240000)), findsWidgets);
      expect(find.text('ПОЛУЧЕНО'), findsOneWidget);
      expect(find.text('В ОЖИДАНИИ'), findsOneWidget);
      // Бейджи статусов в строках списка.
      expect(find.text('ВЫПЛАЧЕНО'), findsOneWidget);
      expect(find.text('ОЖИДАЕТ'), findsOneWidget);
      expect(find.text('Актау → Жанаозен'), findsOneWidget);
      expect(find.text('Актау → Бейнеу'), findsOneWidget);

      await expectLater(
        find.byType(PayoutsScreen),
        matchesGoldenFile('goldens/payouts.png'),
      );
    });

    testWidgets('фильтр «Ожидают» оставляет только неоплаченные', (tester) async {
      final controller = await pumpPayouts(tester);

      await controller.setFilter(PayoutStatus.pending);
      await tester.pumpAndSettle();

      expect(find.text('Актау → Жанаозен'), findsNothing);
      expect(find.text('Актау → Бейнеу'), findsOneWidget);
      // Сводка считается по всем выплатам и от фильтра не зависит.
      expect(find.text('ПОЛУЧЕНО'), findsOneWidget);
      expect(find.text(Fmt.money(180000)), findsOneWidget);
    });
  });

  group('шаги сделки', () {
    testWidgets('полоса показывает весь путь от отклика до сдачи', (tester) async {
      await pumpScreen(
        tester,
        Padding(
          padding: const EdgeInsets.all(Gap.screen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final step in [
                DeliveryStep.bid,
                DeliveryStep.pickup,
                DeliveryStep.delivered,
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.xl),
                  child: StepTrail(current: step),
                ),
              StepTrail.forBid(Fixtures.bid(status: BidStatus.rejected)),
            ],
          ),
        ),
      );

      // Каждый шаг подписан — цвета точки мало на засвеченном экране.
      for (final step in DeliveryStep.values) {
        expect(find.text(step.label), findsNWidgets(3));
      }
      expect(
        find.text('Сделка не состоялась — заказчик выбрал другого перевозчика'),
        findsOneWidget,
      );

      await expectLater(
        find.byType(Column).first,
        matchesGoldenFile('goldens/step_trail.png'),
      );
    });
  });
}
