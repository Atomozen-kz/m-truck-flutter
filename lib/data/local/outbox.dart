import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Тип отложенного действия.
enum OutboxKind {
  /// Отклик на заявку: `POST /api/orders/{order}/bids`.
  bid,

  /// Смена статуса рейса: `POST /api/shipments/{shipment}/status`.
  shipmentStatus,

  /// Пачка GPS-точек: `POST /api/tracking/batch`.
  tracking,

  /// Подтверждение доставки с фото: `POST /api/shipments/{shipment}/proof`.
  proof;

  static OutboxKind parse(String raw) =>
      OutboxKind.values.firstWhere((k) => k.name == raw, orElse: () => OutboxKind.tracking);
}

/// Действие, которое водитель совершил без сети.
///
/// «Статус сохранится на телефоне и уйдёт, когда появится сеть» — обещание из
/// макета, за которое отвечает эта очередь.
class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final OutboxKind kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  OutboxItem copyWith({int? attempts, String? lastError}) => OutboxItem(
        id: id,
        kind: kind,
        payload: payload,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'attempts': attempts,
        if (lastError != null) 'last_error': lastError,
      };

  static OutboxItem? tryParse(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final payload = json['payload'];
    if (id is! String || payload is! Map<String, dynamic>) return null;
    return OutboxItem(
      id: id,
      kind: OutboxKind.parse(json['kind'] as String? ?? ''),
      payload: payload,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastError: json['last_error'] as String?,
    );
  }
}

/// Персистентная очередь FIFO для действий, не доехавших до сервера.
class Outbox {
  Outbox(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'outbox.items';

  /// Сколько раз пробуем отправить, прежде чем считать действие безнадёжным.
  static const maxAttempts = 8;

  List<OutboxItem> read() {
    final raw = _prefs.getStringList(_key);
    if (raw == null) return const [];
    return raw
        .map((line) {
          try {
            return OutboxItem.tryParse(jsonDecode(line));
          } on FormatException {
            return null;
          }
        })
        .nonNulls
        .toList();
  }

  Future<void> _write(List<OutboxItem> items) =>
      _prefs.setStringList(_key, items.map((i) => jsonEncode(i.toJson())).toList());

  /// Счётчик внутри одной сессии: часы могут отдать одинаковую микросекунду
  /// двум подряд идущим добавлениям, а совпавший id стирает чужой элемент.
  int _sequence = 0;

  Future<OutboxItem> add(OutboxKind kind, Map<String, dynamic> payload) async {
    final item = OutboxItem(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      kind: kind,
      payload: payload,
      createdAt: DateTime.now(),
    );
    await _write([...read(), item]);
    return item;
  }

  Future<void> remove(String id) async {
    await _write(read().where((i) => i.id != id).toList());
  }

  Future<void> update(OutboxItem item) async {
    await _write([
      for (final existing in read()) existing.id == item.id ? item : existing,
    ]);
  }

  /// Сколько GPS-точек ждут отправки — цифра на бейдже «42 GPS-точки в буфере».
  int bufferedPoints() => read()
      .where((i) => i.kind == OutboxKind.tracking)
      .fold(0, (sum, i) => sum + ((i.payload['points'] as List?)?.length ?? 0));

  /// Действия водителя (без GPS) — их число рисуется в шапке «Нет сети».
  int pendingActions() => read().where((i) => i.kind != OutboxKind.tracking).length;

  /// Есть ли неотправленный отклик по конкретной заявке.
  bool hasPendingBid(int orderId) => read()
      .any((i) => i.kind == OutboxKind.bid && i.payload['order_id'] == orderId);

  Future<void> clear() => _prefs.remove(_key);
}
