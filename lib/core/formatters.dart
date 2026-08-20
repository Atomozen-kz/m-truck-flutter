import 'package:intl/intl.dart';

/// Форматирование чисел и дат в том виде, в каком они нарисованы в макете:
/// «180 000 ₸», «152 км · 20 т», «3 ч 22 мин», «Погрузка сегодня 14:00».
///
/// Пробел между числом и его единицей — всегда неразрывный: цена и тоннаж не
/// должны разрываться переносом строки в узкой карточке.
abstract final class Fmt {
  /// Неразрывный пробел. Вынесен в константу, чтобы его было видно в коде.
  static const nbsp = ' ';

  static final _thousands = NumberFormat('#,##0', 'ru');
  static final _oneDecimal = NumberFormat('#,##0.#', 'ru');
  static final _time = DateFormat('HH:mm', 'ru');
  static final _dayMonth = DateFormat('d MMM', 'ru');
  static final _monthDay = DateFormat('d MMMM', 'ru');

  /// Приводит разделитель разрядов к неразрывному пробелу.
  ///
  /// Трогаем только пробельные символы: запятая в русской локали означает
  /// десятичную часть («12,5 т»), и заменять её нельзя.
  static String _group(String value) => value.replaceAll(RegExp(r'\s'), nbsp);

  /// Склеивает число с единицей неразрывным пробелом: «152 км».
  static String _unit(String value, String unit) => '$value$nbsp$unit';

  /// «180 000 ₸»
  static String money(num? value) {
    if (value == null) return '—';
    return _unit(_group(_thousands.format(value)), '₸');
  }

  /// «180 000» — без знака валюты (для полей ввода и чипов).
  static String moneyBare(num? value) {
    if (value == null) return '';
    return _group(_thousands.format(value));
  }

  /// «152 км», дробные значения — с одним знаком: «7,4 км».
  static String km(num? value) {
    if (value == null) return '—';
    return _unit(_group(_oneDecimal.format(value)), 'км');
  }

  /// «20 т» для тяжёлых грузов, «850 кг» для лёгких.
  static String weight(int? kg) {
    if (kg == null) return '—';
    if (kg >= 1000) {
      final tons = kg / 1000;
      return _unit(_group(_oneDecimal.format(tons)), 'т');
    }
    return _unit(_group(_thousands.format(kg)), 'кг');
  }

  /// «3 ч 22 мин», «45 мин».
  static String duration(int? minutes) {
    if (minutes == null) return '—';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return _unit('$m', 'мин');
    if (m == 0) return _unit('$h', 'ч');
    return '${_unit('$h', 'ч')} ${_unit('$m', 'мин')}';
  }

  /// «14:00»
  static String time(DateTime? dt) => dt == null ? '—' : _time.format(dt.toLocal());

  /// «20 авг»
  static String dayMonth(DateTime? dt) => dt == null ? '—' : _dayMonth.format(dt.toLocal());

  /// «14–20 августа»
  static String dayRange(DateTime from, DateTime to) {
    final f = from.toLocal();
    final t = to.toLocal();
    if (f.month == t.month) return '${f.day}–${_monthDay.format(t)}';
    return '${_dayMonth.format(f)} – ${_dayMonth.format(t)}';
  }

  /// «сегодня 14:00», «завтра 08:00», «20 авг 14:00».
  static String pickupAt(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final today = DateUtilsLite.startOfDay(DateTime.now());
    final day = DateUtilsLite.startOfDay(local);
    final diff = day.difference(today).inDays;
    final t = _time.format(local);
    return switch (diff) {
      0 => 'сегодня $t',
      1 => 'завтра $t',
      -1 => 'вчера $t',
      _ => '${_dayMonth.format(local)} $t',
    };
  }

  /// «сегодня, 14:00–16:00» — окно погрузки.
  static String window(DateTime? from, DateTime? to) {
    if (from == null && to == null) return 'время не указано';
    if (from == null) return 'до ${_time.format(to!.toLocal())}';
    if (to == null) return pickupAt(from);
    final base = pickupAt(from);
    final head = base.substring(0, base.lastIndexOf(' '));
    return '$head, ${_time.format(from.toLocal())}–${_time.format(to.toLocal())}';
  }

  /// «только что», «12 мин назад», «2 ч назад», «вчера», «18 авг».
  static String ago(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.isNegative || diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${_unit('${diff.inMinutes}', 'мин')} назад';
    if (diff.inHours < 24) return '${_unit('${diff.inHours}', 'ч')} назад';
    if (diff.inDays == 1) return 'вчера';
    return _dayMonth.format(dt.toLocal());
  }

  /// «4,8» — рейтинг с запятой, как в макете.
  static String rating(num? value) =>
      value == null ? '—' : value.toStringAsFixed(1).replaceAll('.', ',');

  /// «+7 707 123 45 67»
  static String phone(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final national = digits.length == 11 ? digits.substring(1) : digits;
    if (national.length != 10) return raw;
    return '+7 ${national.substring(0, 3)} ${national.substring(3, 6)} '
        '${national.substring(6, 8)} ${national.substring(8)}';
  }

  /// Маска ввода телефона без кода страны: «707 123 45 67».
  static String phoneNational(String digits) {
    final d = digits.length > 10 ? digits.substring(0, 10) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 3 || i == 6 || i == 8) buf.write(' ');
      buf.write(d[i]);
    }
    return buf.toString();
  }

  /// «Актау → Жанаозен» — короткое направление из полных адресов.
  static String direction(String? from, String? to) =>
      '${shortPlace(from)} → ${shortPlace(to)}';

  /// «Актау, морской порт» → «Актау».
  static String shortPlace(String? address) {
    if (address == null || address.trim().isEmpty) return '—';
    final head = address.split(RegExp(r'[,·]')).first.trim();
    return head.isEmpty ? address.trim() : head;
  }

  /// «1 рейс · 2 рейса · 5 рейсов» — счётчик с русским склонением.
  static String trips(int count) => _plural(count, 'рейс', 'рейса', 'рейсов');

  /// «1 заявка · 2 заявки · 5 заявок».
  static String orders(int count) => _plural(count, 'заявка', 'заявки', 'заявок');

  /// Русское склонение по правилам для 1 / 2-4 / 5-20.
  static String _plural(int count, String one, String few, String many) {
    final mod100 = count % 100;
    final mod10 = count % 10;
    final form = (mod100 >= 11 && mod100 <= 14) || mod10 == 0 || mod10 >= 5
        ? many
        : mod10 == 1
            ? one
            : few;
    return '$count$nbsp$form';
  }

  /// «ЕС» — инициалы для аватара.
  static String initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first._head(2);
    return '${parts[0]._head(1)}${parts[1]._head(1)}';
  }
}

extension on String {
  /// Первые [n] символов в верхнем регистре.
  String _head(int n) => (length <= n ? this : substring(0, n)).toUpperCase();
}

/// Минимальные операции над датами без тяжёлых зависимостей.
abstract final class DateUtilsLite {
  static DateTime startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static DateTime startOfWeek(DateTime dt) {
    final day = startOfDay(dt);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  static DateTime startOfMonth(DateTime dt) => DateTime(dt.year, dt.month);
}
