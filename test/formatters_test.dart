import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:m_truck/core/formatters.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  // Все пробелы между числом и единицей — неразрывные. Собираем ожидания
  // помощником, иначе тест зависел бы от невидимого символа в исходнике.
  String u(Object value, String unit) => '$value${Fmt.nbsp}$unit';

  group('деньги', () {
    test('разбивает разряды неразрывным пробелом', () {
      expect(Fmt.money(180000), u(u(180, '000'), '₸'));
      expect(Fmt.money(1240000), u(u(u(1, '240'), '000'), '₸'));
    });

    test('пустое значение показывает прочерк, а не ноль', () {
      expect(Fmt.money(null), '—');
    });

    test('moneyBare пригоден для поля ввода', () {
      expect(Fmt.moneyBare(190000), u(190, '000'));
      expect(Fmt.moneyBare(null), '');
    });
  });

  group('вес', () {
    test('тяжёлый груз переводится в тонны', () {
      expect(Fmt.weight(20000), u(20, 'т'));
      expect(Fmt.weight(12500), u('12,5', 'т'));
    });

    test('лёгкий груз остаётся в килограммах', () {
      expect(Fmt.weight(850), u(850, 'кг'));
    });

    test('десятичная запятая переживает разбивку разрядов', () {
      // Регрессия: разделитель разрядов однажды затирал запятую дробной части.
      expect(Fmt.weight(12500).contains(','), isTrue);
      expect(Fmt.km(7.43).contains(','), isTrue);
    });
  });

  group('длительность', () {
    test('часы и минуты', () {
      expect(Fmt.duration(202), '${u(3, 'ч')} ${u(22, 'мин')}');
      expect(Fmt.duration(45), u(45, 'мин'));
      expect(Fmt.duration(120), u(2, 'ч'));
    });
  });

  group('расстояние', () {
    test('целое без дробной части, дробное с одним знаком', () {
      expect(Fmt.km(152), u(152, 'км'));
      expect(Fmt.km(7.43), u('7,4', 'км'));
    });
  });

  group('телефон', () {
    test('форматирует 11 цифр с кодом страны', () {
      expect(Fmt.phone('77071234567'), '+7 707 123 45 67');
    });

    test('нераспознанный номер возвращается как есть', () {
      expect(Fmt.phone('123'), '123');
    });

    test('маска ввода расставляет пробелы по мере набора', () {
      expect(Fmt.phoneNational('707'), '707');
      expect(Fmt.phoneNational('7071234'), '707 123 4');
      expect(Fmt.phoneNational('7071234567'), '707 123 45 67');
    });

    test('маска обрезает лишние цифры', () {
      expect(Fmt.phoneNational('70712345678888'), '707 123 45 67');
    });
  });

  group('время погрузки', () {
    test('сегодняшняя дата подписывается словом', () {
      final today = DateTime.now().copyWith(hour: 14, minute: 0);
      expect(Fmt.pickupAt(today), 'сегодня 14:00');
    });

    test('завтрашняя дата подписывается словом', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1)).copyWith(hour: 8, minute: 0);
      expect(Fmt.pickupAt(tomorrow), 'завтра 08:00');
    });

    test('окно погрузки сворачивается в один диапазон', () {
      final from = DateTime.now().copyWith(hour: 14, minute: 0);
      final to = DateTime.now().copyWith(hour: 16, minute: 0);
      expect(Fmt.window(from, to), 'сегодня, 14:00–16:00');
    });

    test('без времени окно честно об этом говорит', () {
      expect(Fmt.window(null, null), 'время не указано');
    });
  });

  group('направление', () {
    test('берёт головную часть адреса', () {
      expect(
        Fmt.direction('Актау, морской порт', 'Жанаозен, база АМУ'),
        'Актау → Жанаозен',
      );
    });

    test('пустой адрес не ломает строку', () {
      expect(Fmt.direction(null, 'Курык'), '— → Курык');
    });
  });

  group('инициалы', () {
    test('двухсловное имя даёт две буквы', () {
      expect(Fmt.initials('Ерлан Сағынов'), 'ЕС');
    });

    test('односложное имя обрезается до двух букв', () {
      expect(Fmt.initials('Береке'), 'БЕ');
    });

    test('пустое имя даёт вопросительный знак', () {
      expect(Fmt.initials('   '), '?');
    });
  });

  test('рейтинг пишется через запятую', () {
    expect(Fmt.rating(4.8), '4,8');
    expect(Fmt.rating(5), '5,0');
    expect(Fmt.rating(null), '—');
  });
}
