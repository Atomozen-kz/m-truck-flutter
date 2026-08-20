import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import '../data/models/models.dart';
import '../data/repositories/payout_repository.dart';
import '../services/connectivity_service.dart';

/// Выплаты водителя: список, сводка и фильтр по статусу.
///
/// Деньги — то, ради чего водитель заходит в приложение чаще всего, поэтому
/// экран открывается на кэше мгновенно и лишь потом уточняется с сервера.
class PayoutsController extends ChangeNotifier {
  PayoutsController({
    required PayoutRepository repository,
    required ConnectivityService connectivity,
  })  : _repository = repository,
        _connectivity = connectivity;

  final PayoutRepository _repository;
  final ConnectivityService _connectivity;

  List<Payout> _items = const [];
  PayoutsSummary _summary = const PayoutsSummary();
  PayoutStatus? _filter;
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _error;
  DateTime? _updatedAt;
  bool _isFromCache = false;
  bool _hasLoaded = false;

  List<Payout> get items => _items;
  PayoutsSummary get summary => _summary;
  PayoutStatus? get filter => _filter;
  bool get isLoading => _isLoading && _items.isEmpty;
  bool get isRefreshing => _isRefreshing;
  String? get error => _error;
  DateTime? get updatedAt => _updatedAt;

  /// Показанные выплаты взяты из кэша, а не с сервера.
  bool get isFromCache => _isFromCache;

  /// Данные хоть раз доехали — до этого «0 ₸» показывать нечестно.
  bool get hasLoaded => _hasLoaded;

  /// Сумма, которую водитель ещё ждёт, — цифра для строки-входа в экран.
  int get pendingTotal => _summary.pendingTotal;

  /// Первая загрузка: сразу показываем кэш, затем идём в сеть.
  Future<void> load() async {
    if (_items.isEmpty && !_hasLoaded) _applyCache();
    await refresh();
  }

  Future<void> refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    _isLoading = _items.isEmpty;
    _error = null;
    notifyListeners();

    try {
      final page = await _repository.list(status: _filter);
      _items = page.items;
      // Сводка приходит по всем выплатам, фильтр на неё не влияет.
      _summary = page.summary;
      _updatedAt = DateTime.now();
      _isFromCache = false;
      _hasLoaded = true;
      _connectivity.reportSuccess();
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _connectivity.reportFailure();
        _fallBackToCache();
      } else {
        _error = e.message;
      }
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// Переключает фильтр «Все / Выплачено / Ожидает».
  Future<void> setFilter(PayoutStatus? status) async {
    if (_filter == status) return;
    _filter = status;
    _items = const [];
    notifyListeners();
    await refresh();
  }

  void _applyCache() {
    final cached = _repository.cached();
    if (cached == null) return;
    _items = _matchingFilter(cached.value.items);
    _summary = cached.value.summary;
    _updatedAt = cached.savedAt;
    _isFromCache = true;
    _hasLoaded = true;
    notifyListeners();
  }

  void _fallBackToCache() {
    final cached = _repository.cached();
    if (cached == null) {
      if (_items.isEmpty) _error = 'Нет сети и нет сохранённых выплат';
      return;
    }
    _items = _matchingFilter(cached.value.items);
    _summary = cached.value.summary;
    _updatedAt = cached.savedAt;
    _isFromCache = true;
    _hasLoaded = true;
  }

  /// В кэше лежит полная выдача — фильтруем её на месте, без сети.
  List<Payout> _matchingFilter(List<Payout> all) {
    final status = _filter;
    if (status == null) return all;
    return all.where((p) => p.status == status).toList(growable: false);
  }
}
