import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:m_truck/data/api_client.dart';
import 'package:m_truck/data/local/cache_store.dart';
import 'package:m_truck/data/local/token_store.dart';
import 'package:m_truck/data/repositories/auth_repository.dart';
import 'package:m_truck/features/auth/phone_screen.dart';
import 'package:m_truck/services/connectivity_service.dart';
import 'package:m_truck/state/session_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

http.Response _ok(Object? data) => http.Response(
      jsonEncode({'success': true, 'data': data, 'message': 'Success'}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Экран телефона из макета. По умолчанию тест рисует 800×600 — на такой
/// «ландшафтной» поверхности вёрстка сворачивается и кнопки не попадают под тап.
const _phone = Size(412, 915);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  /// Прокачивает кадры вручную.
  ///
  /// `pumpAndSettle` здесь не годится: мигающий курсор и отсчёт до повторной
  /// отправки кода — бесконечные анимации, и ожидание покоя никогда не кончится.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Собирает экран входа поверх подменённого API и возвращает журнал запросов.
  Future<(SessionController, List<String>)> pumpAuth(
    WidgetTester tester, {
    required http.Response Function(http.Request request) respond,
  }) async {
    tester.view
      ..physicalSize = _phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final log = <String>[];

    final api = ApiClient(
      tokens: TokenStore(prefs),
      httpClient: MockClient((request) async {
        log.add('${request.method} ${request.url.path}');
        return respond(request);
      }),
    );
    final session = SessionController(
      auth: AuthRepository(api: api, tokens: TokenStore(prefs), cache: CacheStore(prefs)),
      tokens: TokenStore(prefs),
      connectivity: ConnectivityService(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: const MaterialApp(
          locale: Locale('ru'),
          home: PhoneScreen(),
        ),
      ),
    );
    return (session, log);
  }

  Future<void> tapDigits(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.widgetWithText(InkWell, digit).first);
      await tester.pump();
    }
  }

  testWidgets('кнопка кода включается только на полном номере', (tester) async {
    await pumpAuth(tester, respond: (_) => _ok({'exists': true, 'code_sent': true}));

    await tapDigits(tester, '70712345');
    await tester.pump();

    // Девять цифр — ещё не номер: кнопка обязана быть недоступна.
    final button = tester.widget<Material>(
      find.ancestor(
        of: find.text('ПОЛУЧИТЬ КОД'),
        matching: find.byType(Material),
      ).first,
    );
    expect(button.color, isNot(const Color(0xFFF59E0B)));

    await tapDigits(tester, '67');
    await tester.pump();
    expect(find.text('707 123 45 67'), findsOneWidget);
  });

  testWidgets('номер уходит на сервер с кодом страны', (tester) async {
    final (_, log) = await pumpAuth(
      tester,
      respond: (_) => _ok({'exists': true, 'code_sent': true}),
    );

    await tapDigits(tester, '7071234567');
    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await settle(tester);

    expect(log, contains('POST /api/auth/phone/check'));
  });

  testWidgets('верный код доводит сессию до готовности', (tester) async {
    final (session, log) = await pumpAuth(tester, respond: (request) {
      if (request.url.path.endsWith('/verify')) {
        return _ok({
          'token': '1|test-token',
          'is_new': false,
          'user': Fixtures.userJson(),
        });
      }
      return _ok({'exists': true, 'code_sent': true});
    });

    await tapDigits(tester, '7071234567');
    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await settle(tester);

    // Экран кода: вход происходит сам на последней цифре.
    expect(find.text('Введите код из SMS'), findsOneWidget);
    await tapDigits(tester, '5555');
    await settle(tester);

    expect(log, contains('POST /api/auth/phone/verify'));
    expect(session.stage, SessionStage.ready);
    expect(session.canBid, isTrue);
  });

  testWidgets(
      'верный код закрывает экран кода и открывает следующий по стадии',
      (tester) async {
    // CodeScreen — маршрут, вытолкнутый Navigator.push поверх корневого
    // переключателя стадий (как в app.dart::_RootGate). Если после verifyCode
    // никто не вызовет pop, экран так и останется висеть с заполненным кодом.
    tester.view
      ..physicalSize = _phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final api = ApiClient(
      tokens: TokenStore(prefs),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          return _ok({
            'token': '1|test-token',
            'is_new': false,
            'user': Fixtures.userJson(),
          });
        }
        return _ok({'exists': true, 'code_sent': true});
      }),
    );
    final session = SessionController(
      auth: AuthRepository(api: api, tokens: TokenStore(prefs), cache: CacheStore(prefs)),
      tokens: TokenStore(prefs),
      connectivity: ConnectivityService(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          locale: const Locale('ru'),
          home: Builder(
            builder: (context) {
              final stage = context.select<SessionController, SessionStage>((s) => s.stage);
              return stage == SessionStage.ready
                  ? const Scaffold(body: Center(child: Text('HOME')))
                  : const PhoneScreen();
            },
          ),
        ),
      ),
    );

    await tapDigits(tester, '7071234567');
    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await settle(tester);
    await tapDigits(tester, '5555');
    await settle(tester);

    expect(session.stage, SessionStage.ready);
    expect(find.text('Введите код из SMS'), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('водитель на модерации не попадает на биржу', (tester) async {
    final (session, _) = await pumpAuth(tester, respond: (request) {
      if (request.url.path.endsWith('/verify')) {
        return _ok({
          'token': '1|test-token',
          'is_new': true,
          'user': Fixtures.userJson(status: 'pending'),
        });
      }
      return _ok({'exists': false, 'code_sent': true});
    });

    await tapDigits(tester, '7071234567');
    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await settle(tester);
    await tapDigits(tester, '5555');
    await settle(tester);

    expect(session.stage, SessionStage.pendingModeration);
    expect(session.canBid, isFalse);
  });

  testWidgets('новый водитель отправляется заполнять профиль', (tester) async {
    final (session, _) = await pumpAuth(tester, respond: (request) {
      if (request.url.path.endsWith('/verify')) {
        return _ok({
          'token': '1|test-token',
          'is_new': true,
          'user': {
            'id': 10,
            'name': 'Новый',
            'phone': '77071234567',
            'role': 'driver',
            'rating': 5,
            'is_active': true,
            'driver': null,
            'vehicles': <dynamic>[],
          },
        });
      }
      return _ok({'exists': false, 'code_sent': true});
    });

    await tapDigits(tester, '7071234567');
    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await settle(tester);
    await tapDigits(tester, '5555');
    await settle(tester);

    expect(session.stage, SessionStage.needsDriverProfile);
  });

  testWidgets('неверный код показывает сообщение сервера и чистит поле',
      (tester) async {
    await pumpAuth(tester, respond: (request) {
      if (request.url.path.endsWith('/verify')) {
        return http.Response(
          jsonEncode({
            'success': false,
            'data': {
              'code': ['Код неверный'],
            },
            'message': 'Неверный код подтверждения',
          }),
          422,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return _ok({'exists': true, 'code_sent': true});
    });

    await tapDigits(tester, '7071234567');
    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await settle(tester);
    await tapDigits(tester, '1234');
    await settle(tester);

    expect(find.text('Код неверный'), findsOneWidget);
    // Поле очищено — водитель набирает заново, не стирая по цифре.
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('нет сети — понятное сообщение вместо технической ошибки',
      (tester) async {
    await pumpAuth(tester, respond: (_) => throw http.ClientException('offline'));

    await tapDigits(tester, '7071234567');
    await tester.tap(find.text('ПОЛУЧИТЬ КОД'));
    await settle(tester);

    expect(find.text('Введите код из SMS'), findsNothing);
    expect(find.text('Нет связи с сервером'), findsOneWidget);
  });
}
