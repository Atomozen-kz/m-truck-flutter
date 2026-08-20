import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../services/connectivity_service.dart';
import '../../state/payouts_controller.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/primitives.dart';
import '../../widgets/status_badge.dart';

/// S8 · Выплаты — сколько заработано, что уже пришло и что ещё ждёт.
///
/// Сводка вверху отвечает на главный вопрос водителя одним взглядом; список
/// ниже объясняет, из каких рейсов эти деньги сложились.
class PayoutsScreen extends StatefulWidget {
  const PayoutsScreen({super.key});

  @override
  State<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends State<PayoutsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PayoutsController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final payouts = context.watch<PayoutsController>();
    final isOffline = context.watch<ConnectivityService>().isOffline;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(),
            if (isOffline || payouts.isFromCache)
              OfflineBanner.cachedFeed(payouts.updatedAt)
            else if (payouts.error != null)
              _ErrorNotice(message: payouts.error!, onRetry: payouts.refresh),
            Expanded(
              child: RefreshIndicator(
                onRefresh: payouts.refresh,
                color: AppColors.accent,
                backgroundColor: AppColors.bgSurface,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: Gap.xxl),
                  children: [
                    _Summary(summary: payouts.summary),
                    const HairLine(),
                    _Filters(
                      selected: payouts.filter,
                      onSelect: payouts.setFilter,
                    ),
                    _List(payouts: payouts),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.screen, Gap.md),
        child: Row(
          children: [
            IconTapTarget(
              icon: PhosphorIcons.arrowLeft(),
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Назад',
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: Gap.xs),
            Expanded(child: Text('Выплаты', style: AppText.displayLg)),
          ],
        ),
      );
}

/// Две большие цифры: что уже на руках и что ещё в пути.
class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final PayoutsSummary summary;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.sm, Gap.screen, Gap.xl),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _BigMoney(
                  label: 'получено',
                  amount: summary.paidTotal,
                  count: summary.paidCount,
                ),
              ),
              const VerticalDivider(
                width: Gap.xxl,
                thickness: 1,
                color: AppColors.borderSubtle,
              ),
              Expanded(
                child: _BigMoney(
                  label: 'в ожидании',
                  amount: summary.pendingTotal,
                  count: summary.pendingCount,
                  // Ждущие деньги — то, ради чего экран открывают.
                  accent: summary.pendingTotal > 0,
                ),
              ),
            ],
          ),
        ),
      );
}

class _BigMoney extends StatelessWidget {
  const _BigMoney({
    required this.label,
    required this.amount,
    required this.count,
    this.accent = false,
  });

  final String label;
  final int amount;
  final int count;
  final bool accent;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(), style: AppText.label),
          const SizedBox(height: Gap.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Fmt.money(amount),
              style: AppText.price.copyWith(
                fontSize: 28,
                color: accent ? AppColors.accent : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            Fmt.trips(count),
            style: AppText.bodyMd.copyWith(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
}

class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onSelect});

  final PayoutStatus? selected;
  final ValueChanged<PayoutStatus?> onSelect;

  @override
  Widget build(BuildContext context) {
    const options = <({String label, PayoutStatus? status})>[
      (label: 'Все', status: null),
      (label: 'Ожидают', status: PayoutStatus.pending),
      (label: 'Выплачены', status: PayoutStatus.paid),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.lg, Gap.screen, Gap.xs),
      child: Row(
        children: [
          for (final (index, option) in options.indexed) ...[
            if (index > 0) const SizedBox(width: Gap.sm),
            FilterPill(
              label: option.label,
              selected: selected == option.status,
              onTap: () => onSelect(option.status),
            ),
          ],
        ],
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.payouts});

  final PayoutsController payouts;

  @override
  Widget build(BuildContext context) {
    if (payouts.isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: Gap.xxxl * 2),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (payouts.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: Gap.xxxl),
        child: EmptyState(
          icon: PhosphorIcons.wallet(),
          title: payouts.filter == null
              ? 'Выплат пока нет'
              : 'В этой вкладке пусто',
          message: payouts.filter == null
              ? 'Выплата появляется здесь, как только рейс закрыт и груз принят.'
              : 'Попробуйте вкладку «Все» — там видно все рейсы с суммами.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Gap.md),
        for (final payout in payouts.items) _PayoutRow(payout: payout),
      ],
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.payout});

  final Payout payout;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const HairLine(indent: Gap.screen),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screen, vertical: Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        Fmt.direction(payout.from, payout.to),
                        style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    Text(
                      Fmt.money(payout.amount),
                      style: AppText.stat.copyWith(
                        fontSize: 19,
                        color: payout.isPaid ? AppColors.textPrimary : AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    Fmt.dayMonth(payout.at),
                    if (payout.distanceKm != null) Fmt.km(payout.distanceKm),
                    if (payout.cargoType?.isNotEmpty ?? false) payout.cargoType!,
                  ].join(' · '),
                  style: AppText.bodyMd.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Gap.md),
                Row(
                  children: [
                    StatusBadge.forPayout(payout.status, compact: true),
                    if (payout.company?.isNotEmpty ?? false) ...[
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          payout.company!,
                          style: AppText.bodyMd.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      );
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.md),
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: Radii.cardAll,
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIcons.warningCircle(PhosphorIconsStyle.fill),
              size: 22,
              color: AppColors.danger,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(message, style: AppText.bodyMd.copyWith(fontSize: 14)),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Повторить',
                style: AppText.bodyMd.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Строка-вход в «Выплаты»: сумма, которую водитель ещё ждёт.
class PayoutsEntryRow extends StatelessWidget {
  const PayoutsEntryRow({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PayoutsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payouts = context.watch<PayoutsController>();
    final pending = payouts.pendingTotal;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.screen, vertical: Gap.lg),
          child: Row(
            children: [
              Icon(PhosphorIcons.wallet(), size: 24, color: AppColors.textSecondary),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Выплаты', style: AppText.bodyLg.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(payouts),
                      style: AppText.bodyMd.copyWith(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (pending > 0) ...[
                Text(
                  Fmt.money(pending),
                  style: AppText.stat.copyWith(fontSize: 17, color: AppColors.accent),
                ),
                const SizedBox(width: Gap.sm),
              ],
              Icon(PhosphorIcons.caretRight(), size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  /// Пока данные не доехали, честнее промолчать, чем показать «0 ₸ ожидает».
  static String _subtitle(PayoutsController payouts) {
    if (!payouts.hasLoaded) return 'Заработок по доставленным рейсам';
    final summary = payouts.summary;
    if (summary.isEmpty) return 'Пока ни одной выплаты';
    if (summary.pendingCount == 0) {
      return 'Всё выплачено · ${Fmt.money(summary.paidTotal)}';
    }
    return 'Ожидает ${Fmt.trips(summary.pendingCount)}';
  }
}
