import '../api_client.dart';
import '../local/cache_store.dart';
import '../models/models.dart';

/// Выплаты водителя: история доставленных заказов с суммами и сводка.
class PayoutRepository {
  PayoutRepository({required ApiClient api, required CacheStore cache})
      : _api = api,
        _cache = cache;

  final ApiClient _api;
  final CacheStore _cache;

  /// [status] — `paid` или `pending`; без него сервер отдаёт всё.
  ///
  /// Сводка на сервере считается по всем выплатам независимо от фильтра, так
  /// что цифры «выплачено / ожидает» не прыгают при переключении вкладок.
  Future<PayoutsPage> list({PayoutStatus? status}) async {
    final response = await _api.get(
      '/api/my/payouts',
      query: {'status': ?status?.wire},
    );
    final raw = response.asMap;
    // Кэшируем только полную выдачу, иначе офлайн покажет обрезок.
    if (status == null) await _cache.write(CacheStore.keyPayouts, raw);
    return PayoutsPage.parse(raw);
  }

  CachedSnapshot<PayoutsPage>? cached() {
    final snapshot = _cache.readMap(CacheStore.keyPayouts);
    if (snapshot == null) return null;
    return CachedSnapshot(
      value: PayoutsPage.parse(snapshot.value),
      savedAt: snapshot.savedAt,
    );
  }
}
