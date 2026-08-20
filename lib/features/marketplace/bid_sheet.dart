import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../widgets/primitives.dart';

/// Что водитель предложил заказчику.
class BidResult {
  const BidResult({required this.price, this.etaMinutes, this.comment});

  final int price;

  /// Через сколько минут водитель подаст машину.
  final int? etaMinutes;

  final String? comment;
}

/// Лист отклика: цена, время подачи и отправка.
///
/// Цена — единственное обязательное решение, поэтому она занимает весь верх и
/// поддержана подсказками: сколько предлагает заказчик и что вводят другие.
class BidSheet extends StatefulWidget {
  const BidSheet({super.key, required this.order, required this.vehicle});

  final Order order;
  final Vehicle vehicle;

  @override
  State<BidSheet> createState() => _BidSheetState();
}

class _BidSheetState extends State<BidSheet> {
  late final TextEditingController _price = TextEditingController(
    text: Fmt.moneyBare(widget.order.priceOffer),
  );
  final _comment = TextEditingController();

  /// Через сколько водитель подаст машину — пресеты вместо выбора даты.
  int _etaMinutes = 120;

  static const _etaOptions = <({int minutes, String label})>[
    (minutes: 60, label: 'Через час'),
    (minutes: 120, label: 'Через 2 часа'),
    (minutes: 240, label: 'Через 4 часа'),
    (minutes: 1440, label: 'Завтра'),
  ];

  @override
  void dispose() {
    _price.dispose();
    _comment.dispose();
    super.dispose();
  }

  int? get _priceValue {
    final digits = _price.text.replaceAll(RegExp(r'\D'), '');
    final value = int.tryParse(digits);
    return value == null || value <= 0 ? null : value;
  }

  /// Пресеты вокруг цены заказчика: как есть, +5 %, +10 %.
  List<int> get _pricePresets {
    final base = widget.order.priceOffer;
    if (base == null || base <= 0) return const [];
    return [base, (base * 1.05).round(), (base * 1.1).round()];
  }

  void _applyPreset(int value) {
    _price.text = Fmt.moneyBare(value);
    setState(() {});
  }

  void _submit() {
    final price = _priceValue;
    if (price == null) return;
    Navigator.of(context).pop(
      BidResult(
        price: price,
        etaMinutes: _etaMinutes,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.md, Gap.screen, Gap.screen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderDefault,
                    borderRadius: Radii.pillAll,
                  ),
                ),
              ),
              const SizedBox(height: Gap.xl),
              Row(
                children: [
                  Expanded(child: Text('Ваш отклик', style: AppText.displayMd)),
                  IconTapTarget(
                    icon: PhosphorIcons.x(),
                    color: AppColors.textPrimary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              Text('Ваша цена за рейс', style: AppText.bodyMd.copyWith(fontSize: 15)),
              const SizedBox(height: Gap.sm),
              _PriceField(controller: _price, onChanged: () => setState(() {})),
              const SizedBox(height: Gap.md),
              Text(_priceHint(), style: AppText.bodyMd.copyWith(fontSize: 13)),
              if (_pricePresets.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                Row(
                  children: [
                    for (final (index, preset) in _pricePresets.indexed) ...[
                      if (index > 0) const SizedBox(width: Gap.sm),
                      _PricePreset(
                        value: preset,
                        selected: _priceValue == preset,
                        onTap: () => _applyPreset(preset),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: Gap.xl),
              Text('Когда подадите машину', style: AppText.bodyMd.copyWith(fontSize: 15)),
              const SizedBox(height: Gap.sm),
              _EtaSelector(
                options: _etaOptions,
                selected: _etaMinutes,
                onSelect: (minutes) => setState(() => _etaMinutes = minutes),
              ),
              const SizedBox(height: Gap.lg),
              _CommentField(controller: _comment),
              const SizedBox(height: Gap.lg),
              _VehicleRow(vehicle: widget.vehicle),
              const SizedBox(height: Gap.lg),
              PrimaryButton(
                label: 'Отправить отклик',
                height: Touch.cta,
                onPressed: _priceValue == null ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _priceHint() {
    final offer = widget.order.priceOffer;
    if (offer == null) return 'Заказчик не указал цену — предложите свою';
    final mine = _priceValue;
    if (mine == null) return 'Заказчик предлагает ${Fmt.money(offer)}';
    final delta = mine - offer;
    if (delta == 0) return 'Ровно столько, сколько предлагает заказчик';
    if (delta > 0) {
      return 'На ${Fmt.money(delta)} выше цены заказчика '
          '(${Fmt.money(offer)}) — заказчик может выбрать дешевле';
    }
    return 'На ${Fmt.money(-delta)} ниже цены заказчика (${Fmt.money(offer)})';
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: Radii.cardAll,
        border: Border.all(color: AppColors.accent, width: 2),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [_ThousandsFormatter()],
              onChanged: (_) => onChanged(),
              style: AppText.price.copyWith(fontFeatures: AppText.tabularFigures),
              cursorColor: AppColors.accent,
              cursorWidth: 2,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: '0',
                hintStyle: AppText.price.copyWith(color: AppColors.textTertiary),
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Text(
            '₸',
            style: AppText.displayMd.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Разбивает вводимую сумму на разряды прямо во время набора.
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final value = int.tryParse(digits);
    if (value == null) return oldValue;
    final formatted = Fmt.moneyBare(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _PricePreset extends StatelessWidget {
  const _PricePreset({required this.value, required this.selected, required this.onTap});

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Material(
          color: selected ? AppColors.bgSurface3 : AppColors.bgSurface2,
          borderRadius: Radii.pillAll,
          child: InkWell(
            onTap: onTap,
            borderRadius: Radii.pillAll,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Fmt.moneyBare(value),
                  style: AppText.bodyMd.copyWith(
                    fontSize: 15,
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: AppText.tabularFigures,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _EtaSelector extends StatelessWidget {
  const _EtaSelector({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<({int minutes, String label})> options;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        for (final option in options)
          FilterPill(
            label: option.label,
            selected: option.minutes == selected,
            onTap: () => onSelect(option.minutes),
          ),
      ],
    );
  }
}

class _CommentField extends StatelessWidget {
  const _CommentField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLines: 2,
        style: AppText.bodyLg.copyWith(fontSize: 15),
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          hintText: 'Комментарий заказчику — необязательно',
          hintStyle: AppText.bodyMd.copyWith(fontSize: 15),
          filled: true,
          fillColor: AppColors.bgSurface2,
          contentPadding: const EdgeInsets.all(Gap.lg),
          border: const OutlineInputBorder(
            borderRadius: Radii.cardAll,
            borderSide: BorderSide.none,
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: Radii.cardAll,
            borderSide: BorderSide(color: AppColors.accent, width: 2),
          ),
        ),
      );
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(PhosphorIcons.truck(), size: 20, color: AppColors.textTertiary),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              'Поедет ${vehicle.plate} · ${vehicle.type} · '
              '${Fmt.weight(vehicle.capacityKg)}',
              style: AppText.bodyMd.copyWith(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}
