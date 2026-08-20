import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'data/api_client.dart';
import 'data/local/cache_store.dart';
import 'data/local/outbox.dart';
import 'data/local/token_store.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/marketplace_repository.dart';
import 'data/repositories/payout_repository.dart';
import 'data/repositories/shipment_repository.dart';
import 'services/connectivity_service.dart';
import 'services/location_service.dart';
import 'services/sync_service.dart';
import 'state/feed_controller.dart';
import 'state/payouts_controller.dart';
import 'state/session_controller.dart';
import 'state/trip_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Форматирование дат на русском нужно ещё до первого кадра.
  await initializeDateFormatting('ru');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemOverlay);

  final prefs = await SharedPreferences.getInstance();
  runApp(_composeRoot(prefs));
}

/// Собирает граф зависимостей приложения.
///
/// Порядок важен: [ApiClient] знает о токене, службы — о клиенте, контроллеры —
/// о службах. Всё создаётся один раз и живёт столько же, сколько приложение.
Widget _composeRoot(SharedPreferences prefs) {
  final tokens = TokenStore(prefs);
  final cache = CacheStore(prefs);
  final outbox = Outbox(prefs);
  final api = ApiClient(tokens: tokens);

  final connectivity = ConnectivityService();
  final location = LocationService();

  final auth = AuthRepository(api: api, tokens: tokens, cache: cache);
  final marketplace = MarketplaceRepository(api: api, cache: cache);
  final shipments = ShipmentRepository(api: api, cache: cache);
  final payouts = PayoutRepository(api: api, cache: cache);

  final sync = SyncService(
    outbox: outbox,
    connectivity: connectivity,
    marketplace: marketplace,
    shipments: shipments,
  );

  final session = SessionController(
    auth: auth,
    tokens: tokens,
    connectivity: connectivity,
  );

  // 401 от любого запроса закрывает сессию — токен Sanctum отозван.
  api.onUnauthorized = session.signOut;

  connectivity.start();
  session.restore().then((_) => sync.flush());

  return MultiProvider(
    providers: [
      Provider.value(value: api),
      Provider.value(value: outbox),
      Provider.value(value: auth),
      Provider.value(value: marketplace),
      Provider.value(value: shipments),
      Provider.value(value: payouts),
      Provider.value(value: location),
      ChangeNotifierProvider.value(value: connectivity),
      ChangeNotifierProvider.value(value: sync),
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider(
        create: (_) => FeedController(
          repository: marketplace,
          connectivity: connectivity,
          location: location,
          sync: sync,
        ),
      ),
      ChangeNotifierProvider(
        create: (_) => PayoutsController(
          repository: payouts,
          connectivity: connectivity,
        ),
      ),
      ChangeNotifierProvider(
        create: (_) => TripController(
          shipments: shipments,
          marketplace: marketplace,
          location: location,
          connectivity: connectivity,
          sync: sync,
          outbox: outbox,
        ),
      ),
    ],
    child: const MTruckApp(),
  );
}
