import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Наблюдение за наличием сети.
///
/// Приложение считает себя офлайн и тогда, когда интерфейс есть, но запросы
/// падают: [reportFailure] позволяет репозиториям опустить флаг, не дожидаясь
/// системного события.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _hasInterface = true;
  bool _lastRequestFailed = false;

  /// Сеть доступна: есть интерфейс и последний запрос не упал по сети.
  bool get isOnline => _hasInterface && !_lastRequestFailed;
  bool get isOffline => !isOnline;

  Future<void> start() async {
    _apply(await _connectivity.checkConnectivity());
    _subscription = _connectivity.onConnectivityChanged.listen(_apply);
  }

  void _apply(List<ConnectivityResult> results) {
    final connected = results.any((r) => r != ConnectivityResult.none);
    if (connected == _hasInterface) return;
    _hasInterface = connected;
    // Появившийся интерфейс снимает «подозрение» с прошлых сбоев.
    if (connected) _lastRequestFailed = false;
    notifyListeners();
  }

  /// Запрос не дошёл до сервера.
  void reportFailure() {
    if (_lastRequestFailed) return;
    _lastRequestFailed = true;
    notifyListeners();
  }

  /// Запрос прошёл — связь есть независимо от того, что говорит система.
  void reportSuccess() {
    if (!_lastRequestFailed && _hasInterface) return;
    _lastRequestFailed = false;
    _hasInterface = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
