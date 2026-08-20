import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../state/payouts_controller.dart';
import '../../state/trip_controller.dart';
import '../../widgets/primitives.dart';
import '../payouts/payouts_screen.dart';

/// Период, за который считается заработок.
enum EarningsPeriod {
  day('День'),
  week('Неделя'),
  month('Месяц'),

  /// Произвольный диапазон — водитель выбирает даты сам.
  custom('Период');

  const EarningsPeriod(this.label);

  final String label;

  /// Начало периода от текущего момента. Для [custom] границы задаёт водитель.
  DateTime start(DateTime now) => switch (this) {
        EarningsPeriod.day => DateUtilsLite.startOfDay(now),
        EarningsPeriod.week => DateUtilsLite.startOfWeek(now),
        EarningsPeriod.month || EarningsPeriod.custom =>
          DateUtilsLite.startOfMonth(now),
      };
}

/// S6 · История и заработок.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  EarningsPeriod _period = EarningsPeriod.week;

  /// Диапазон, выбранный вручную. Живёт только вместе с [EarningsPeriod.custom].
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TripController>().load();
      // Строка «Выплаты» показывает сумму — значит, её надо подгрузить здесь,
      // а не только при открытии самого экрана.
      context.read<PayoutsController>().load();
    });
  }

  /// Спрашивает даты и переключает экран на произвольный диапазон.
  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      // Рейсы старше двух лет в приложении водителя никого не интересуют.
      firstDate: DateTime(now.year - 2),
      lastDate: DateUtilsLite.startOfDay(now),
      initialDateRange: _range ??
          DateTimeRange(
            start: DateUtilsLite.startOfMonth(now),
            end: DateUtilsLite.startOfDay(now),
          ),
      helpText: 'Период заработка',
      saveText: 'Готово',
      locale: const Locale('ru'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _range = picked;
      _period = EarningsPeriod.custom;
    });
  }

  void _selectPeriod(EarningsPeriod period) {
    if (period == EarningsPeriod.custom) {
      unawaited(_pickRange());
      return;
    }
    setState(() => _period = period);
  }

  /// Границы выборки: конец — всегда исключающий, поэтому берём начало
  /// следующего дня, иначе рейсы последнего дня выпадут из подсчёта.
  ({DateTime from, DateTime to}) get _bounds {
    final now = DateTime.now();
    final range = _range;
    if (_period == EarningsPeriod.custom && range != null) {
      return (
        from: DateUtilsLite.startOfDay(range.start),
        to: DateUtilsLite.startOfDay(range.end).add(const Duration(days: 1)),
      );
    }
    return (from: _period.start(now), to: now.add(const Duration(days: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final trips = context.watch<TripController>();
    final bounds = _bounds;
    final from = bounds.from;
    final now = _period == EarningsPeriod.custom
        ? bounds.to.subtract(const Duration(days: 1))
        : DateTime.now();
    final completed = trips.completedBetween(from, bounds.to);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.sm, Gap.screen, Gap.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('История', style: AppText.displayLg),
            ),
          ),
          _PeriodSelector(
            selected: _period,
            rangeLabel: _period == EarningsPeriod.custom && _range != null
                ? Fmt.dayRange(_range!.start, _range!.end)
                : null,
            onSelect: _selectPeriod,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: trips.refresh,
              color: AppColors.accent,
              backgroundColor: AppColors.bgSurface,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: Gap.xxl),
                children: [
                  _Summary(shipments: completed, from: from, to: now),
                  const HairLine(),
                  // Заработок выше считается по рейсам за период, а выплаты —
                  // это деньги: сколько уже пришло и сколько ещё ждёт.
                  const PayoutsEntryRow(),
                  const HairLine(),
                  _CompletedList(shipments: completed, period: _period),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.selected,
    required this.onSelect,
    this.rangeLabel,
  });

  final EarningsPeriod selected;
  final ValueChanged<EarningsPeriod> onSelect;

  /// Подпись выбранного диапазона вместо слова «Период».
  final String? rangeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      margin: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.lg),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: Radii.cardAll,
      ),
      child: Row(
        children: [
          for (final period in EarningsPeriod.values)
            Expanded(
              child: Material(
                color: period == selected ? AppColors.bgSurface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  onTap: () => onSelect(period),
                  borderRadius: BorderRadius.circular(9),
                  child: Center(
                    child: Text(
                      period == EarningsPeriod.custom && rangeLabel != null
                          ? rangeLabel!
                          : period.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyLg.copyWith(
                        fontSize: 15,
                        fontWeight:
                            period == selected ? FontWeight.w600 : FontWeight.w400,
                        color: period == selected
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.shipments, required this.from, required this.to});

  final List<Shipment> shipments;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final total = shipments.fold<int>(0, (sum, s) => sum + (s.earning ?? 0));
    final distance = shipments.fold<double>(0, (sum, s) => sum + (s.order?.distanceKm ?? 0));
    final average = shipments.isEmpty ? 0 : total ~/ shipments.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ЗАРАБОТОК · ${Fmt.dayRange(from, to)}'.toUpperCase(), style: AppText.label),
          const SizedBox(height: Gap.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(Fmt.money(total), style: AppText.price),
          ),
          const SizedBox(height: Gap.lg),
          StatStrip(
            padding: EdgeInsets.zero,
            items: [
              (value: '${shipments.length}', label: 'рейсов'),
              (value: Fmt.km(distance), label: 'пробег'),
              (value: Fmt.moneyBare(average), label: 'средний ₸'),
            ],
          ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }
}

class _CompletedList extends StatelessWidget {
  const _CompletedList({required this.shipments, required this.period});

  final List<Shipment> shipments;
  final EarningsPeriod period;

  @override
  Widget build(BuildContext context) {
    if (shipments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: Gap.xxxl * 2),
        child: EmptyState(
          icon: PhosphorIcons.clockCounterClockwise(),
          title: 'Нет завершённых рейсов',
          message: 'За выбранный период рейсов не было — '
              'попробуйте другие даты.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.lg, Gap.screen, Gap.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text('Завершённые рейсы', style: AppText.displayMd)),
              Text(
                period == EarningsPeriod.custom
                    ? '${shipments.length} за период'
                    : '${shipments.length} за ${period.label.toLowerCase()}',
                style: AppText.bodyMd.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
        for (final shipment in shipments) _CompletedRow(shipment: shipment),
      ],
    );
  }
}

class _CompletedRow extends StatelessWidget {
  const _CompletedRow({required this.shipment});

  final Shipment shipment;

  @override
  Widget build(BuildContext context) {
    final order = shipment.order;
    return Column(
      children: [
        const HairLine(indent: Gap.screen),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.screen, vertical: Gap.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Fmt.direction(order?.from?.address, order?.to?.address),
                      style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        Fmt.dayMonth(shipment.deliveredAt),
                        Fmt.km(order?.distanceKm),
                        Fmt.duration(shipment.actualMinutes ?? order?.durationMin),
                      ].join(' · '),
                      style: AppText.bodyMd.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              Text(
                Fmt.money(shipment.earning),
                style: AppText.stat.copyWith(fontSize: 19),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
