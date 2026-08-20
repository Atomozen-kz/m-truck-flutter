import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'local/token_store.dart';

/// Базовый адрес API. Меняется через `--dart-define=API_BASE_URL=...`.
const kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://m-truck.atomozen.kz',
);

/// Ошибка обращения к API.
///
/// [fieldErrors] заполняется для 422: бэкенд кладёт поля формы в `data`
/// (например `data: {"code": ["Код неверный"]}`).
class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.fieldErrors = const {},
    this.isNetwork = false,
    this.details,
  });

  /// Сетевой сбой одним текстом на всех: водителю всё равно, оборвался ли
  /// сокет или не разрешилось имя хоста — важно, что связи нет.
  factory ApiException.offline([String? details]) =>
      ApiException('Нет связи с сервером', isNetwork: true, details: details);

  /// Текст для водителя.
  final String message;

  /// Техническая подробность для логов — на экран не попадает.
  final String? details;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  /// Запрос не дошёл до сервера — можно отложить в офлайн-очередь.
  final bool isNetwork;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isConflict => statusCode == 409;

  /// Первая ошибка по конкретному полю, если есть.
  String? fieldError(String field) => fieldErrors[field]?.firstOrNull;

  @override
  String toString() => details == null ? message : '$message ($details)';
}

/// Разобранный ответ в едином конверте `{success, data, message, meta}`.
class ApiResponse {
  const ApiResponse(this.data, {this.meta, this.message});

  final dynamic data;
  final Map<String, dynamic>? meta;
  final String? message;

  Map<String, dynamic> get asMap =>
      data is Map<String, dynamic> ? data as Map<String, dynamic> : const {};

  List<Map<String, dynamic>> get asList => data is List
      ? (data as List).whereType<Map<String, dynamic>>().toList(growable: false)
      : const [];
}

/// HTTP-клиент платформы: конверт ответов, Bearer-токен, разбор ошибок.
///
/// Клиент ничего не знает об экранах — он лишь снимает конверт и превращает
/// сетевые/серверные сбои в [ApiException].
class ApiClient {
  ApiClient({required TokenStore tokens, http.Client? httpClient, String? baseUrl})
    : _tokens = tokens,
      _http = httpClient ?? http.Client(),
      _baseUrl = baseUrl ?? kApiBaseUrl;

  final TokenStore _tokens;
  final http.Client _http;
  final String _baseUrl;

  static const _timeout = Duration(seconds: 20);

  /// Вызывается, когда сервер ответил 401 — сессия протухла.
  void Function()? onUnauthorized;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final cleaned = query?.entries
        .where((e) => e.value != null)
        .map((e) => MapEntry(e.key, '${e.value}'));
    return Uri.parse('$_baseUrl$path').replace(
      queryParameters: cleaned == null || cleaned.isEmpty ? null : Map.fromEntries(cleaned),
    );
  }

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _tokens.read();
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<ApiResponse> get(String path, {Map<String, dynamic>? query}) =>
      _send(() async => _http.get(_uri(path, query), headers: await _headers(json: false)));

  Future<ApiResponse> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() async => _http.post(
            _uri(path, query),
            headers: await _headers(),
            body: body == null ? null : jsonEncode(body),
          ));

  Future<ApiResponse> delete(String path) =>
      _send(() async => _http.delete(_uri(path), headers: await _headers(json: false)));

  /// multipart/form-data — нужен для фото груза, прав и подтверждения доставки.
  Future<ApiResponse> multipart(
    String path, {
    Map<String, String> fields = const {},
    Map<String, String> files = const {},
  }) =>
      _send(() async {
        final request = http.MultipartRequest('POST', _uri(path))
          ..headers.addAll(await _headers(json: false))
          ..fields.addAll(fields);
        for (final entry in files.entries) {
          if (entry.value.isEmpty) continue;
          request.files.add(await http.MultipartFile.fromPath(entry.key, entry.value));
        }
        return http.Response.fromStream(await request.send());
      });

  Future<ApiResponse> _send(Future<http.Response> Function() run) async {
    final http.Response response;
    try {
      response = await run().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Сервер не отвечает', isNetwork: true);
    } on SocketException catch (e) {
      throw ApiException.offline(e.message);
    } on http.ClientException catch (e) {
      throw ApiException.offline(e.message);
    }
    return _decode(response);
  }

  ApiResponse _decode(http.Response response) {
    final status = response.statusCode;
    Map<String, dynamic> envelope = const {};
    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) envelope = decoded;
      } on FormatException {
        // Не-JSON ответ (например, HTML страницы ошибки) — обрабатываем ниже.
      }
    }

    if (status >= 200 && status < 300 && envelope['success'] != false) {
      return ApiResponse(
        envelope['data'],
        meta: envelope['meta'] is Map<String, dynamic>
            ? envelope['meta'] as Map<String, dynamic>
            : null,
        message: envelope['message'] as String?,
      );
    }

    if (status == 401) {
      onUnauthorized?.call();
      throw ApiException(
        _message(envelope) ?? 'Сессия истекла, войдите заново',
        statusCode: status,
      );
    }

    throw ApiException(
      _message(envelope) ?? _fallbackMessage(status),
      statusCode: status,
      fieldErrors: _fieldErrors(envelope),
    );
  }

  String? _message(Map<String, dynamic> envelope) {
    final message = envelope['message'];
    return message is String && message.isNotEmpty ? message : null;
  }

  /// Ошибки полей приходят либо в `data` (наш конверт), либо в `errors`
  /// (стандартный ответ валидации Laravel).
  Map<String, List<String>> _fieldErrors(Map<String, dynamic> envelope) {
    final source = envelope['errors'] ?? envelope['data'];
    if (source is! Map) return const {};
    final result = <String, List<String>>{};
    source.forEach((key, value) {
      if (value is List) {
        final messages = value.whereType<String>().toList(growable: false);
        if (messages.isNotEmpty) result['$key'] = messages;
      } else if (value is String) {
        result['$key'] = [value];
      }
    });
    return result;
  }

  String _fallbackMessage(int status) => switch (status) {
        403 => 'Действие недоступно',
        404 => 'Не найдено',
        409 => 'Заявку уже забрали',
        422 => 'Проверьте заполненные поля',
        >= 500 => 'Сервер временно недоступен',
        _ => 'Не удалось выполнить запрос',
      };

  void dispose() => _http.close();
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
