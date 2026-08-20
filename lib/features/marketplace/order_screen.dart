import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/api_client.dart';
import '../../data/local/outbox.dart';
import '../../data/models/models.dart';
import '../../data/repositories/marketplace_repository.dart';
import '../../services/connectivity_service.dart';
import '../../services/location_service.dart';
import '../../services/sync_service.dart';
import '../../state/feed_controller.dart';
import '../../state/session_controller.dart';
import '../../widgets/primitives.dart';
import '../../widgets/route_map.dart';
import '../../widgets/route_rail.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/step_trail.dart';
import 'bid_sheet.dart';

/// S2 · Карточка заявки — всё, что нужно решить «беру или нет».
class OrderScreen extends StatefulWidget {
  const OrderScreen({
    super.key,
    required this.orderId,
    this.preloaded,
    this.autoBid = false,
  });

  final int orderId;

  /// Заявка из ленты — показываем сразу, пока грузим подробности.
  final Order? preloaded;

  /// Открыть лист отклика немедленно (тап по «Откликнуться» в ленте).
  final bool autoBid;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  Order? _order;
  bool _isLoading = true;
  String? _error;

  /// Отклик ушёл в офлайн-очередь и ждёт сети.
  bool _isQueued = false;

  @override
  void initState() {
    super.initState();
    _order = widget.preloaded;
    _isQueued = context.read<SyncService>().hasPendingBid(widget.orderId);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final order = await context.read<MarketplaceRepository>().order(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _isLoading = false;
      });
      if (widget.autoBid && order.myBid == null && !_isQueued) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openBidSheet());
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) context.read<ConnectivityService>().reportFailure();
      setState(() {
        _isLoading = false;
        // Карточка из ленты уже на экране — ошибку показываем только без неё.
        _error = _order == null ? e.message : null;
      });
    }
  }

  Future<void> _openBidSheet() async {
    final order = _order;
    if (order == null) return;

    final session = context.read<SessionController>();
    final vehicle = session.user?.primaryVehicle;
    if (vehicle == null) {
      _snack('Сначала добавьте машину в профиле');
      return;
    }

    final result = await showModalBottomSheet<BidResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      builder: (_) => BidSheet(order: order, vehicle: vehicle),
    );
    if (result == null || !mounted) return;

    await _submitBid(order, vehicle, result);
  }

  Future<void> _submitBid(Order order, Vehicle vehicle, BidResult result) async {
    final marketplace = context.read<MarketplaceRepository>();
    final sync = context.read<SyncService>();
    final feed = context.read<FeedController>();

    try {
      final bid = await marketplace.placeBid(
        orderId: order.id,
        price: result.price,
        vehicleId: vehicle.id,
        etaMinutes: result.etaMinutes,
        comment: result.comment,
      );
      if (!mounted) return;
      feed.markBidPlaced(order.id, bid);
      setState(() => _order = order.copyWith(myBid: bid));
      _snack('Отклик отправлен');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        await sync.enqueue(OutboxKind.bid, {
          'order_id': order.id,
          'price': result.price,
          'vehicle_id': vehicle.id,
          if (result.etaMinutes != null) 'eta_minutes': result.etaMinutes,
          if (result.comment != null) 'comment': result.comment,
        });
        if (!mounted) return;
        setState(() => _isQueued = true);
        _snack('Нет сети — отклик уйдёт автоматически');
      } else {
        _snack(e.message);
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _callShipper() async {
    final phone = _order?.shipper?.phone;
    if (phone == null) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (mounted) _snack('Не удалось открыть звонилку');
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;

    if (order == null) {
      return Scaffold(
        appBar: AppBar(leading: const _BackButton()),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(
                icon: PhosphorIcons.warningCircle(),
                title: 'Заявка недоступна',
                message: _error,
                actionLabel: 'Назад',
                onAction: () => Navigator.of(context).maybePop(),
              ),
      );
    }

    final hasBid = order.myBid != null || _isQueued;
    final canBid = context.select<SessionController, bool>((s) => s.canBid);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(order: order, hasBid: hasBid, isQueued: _isQueued),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  RouteMapView(
                    route: order.mapRoute,
                    height: 210,
                    from: order.from,
                    to: order.to,
                    title: 'Заявка №${order.id}',
                    onLocate: context.read<LocationService>().currentLatLng,
                  ),
                  StatStrip(
                    items: [
                      (value: Fmt.km(order.distanceKm), label: 'расстояние'),
                      (value: Fmt.duration(order.durationMin), label: 'в пути'),
                      (value: Fmt.weight(order.weightKg), label: 'вес'),
                    ],
                  ),
                  const HairLine(),
                  Padding(
                    padding: const EdgeInsets.all(Gap.screen),
                    child: RouteRail(
                      stops: [
                        RailStop(
                          title: order.from?.address ?? '—',
                          subtitle: 'Погрузка: ${Fmt.window(order.pickupFrom, order.pickupTo)}',
                          marker: 'А',
                        ),
                        RailStop(
                          title: order.to?.address ?? '—',
                          subtitle: order.pickupTo == null
                              ? 'Выгрузка: по договорённости'
                              : 'Выгрузка: ${Fmt.pickupAt(order.pickupTo)}',
                          marker: 'Б',
                        ),
                      ],
                    ),
                  ),
                  const HairLine(),
                  _CargoSection(order: order),
                  if (order.comment != null && order.comment!.isNotEmpty)
                    _CommentSection(comment: order.comment!),
                  if (order.shipper != null)
                    _ShipperSection(
                      shipper: order.shipper!,
                      onCall: hasBid ? _callShipper : null,
                    ),
                  if (hasBid) _BidStatusSection(order: order, isQueued: _isQueued),
                  const SizedBox(height: Gap.xxl),
                ],
              ),
            ),
            _BottomBar(
              order: order,
              hasBid: hasBid,
              canBid: canBid,
              onBid: _openBidSheet,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => IconTapTarget(
        icon: PhosphorIcons.arrowLeft(),
        color: AppColors.textPrimary,
        onPressed: () => Navigator.of(context).maybePop(),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.order, required this.hasBid, required this.isQueued});

  final Order order;
  final bool hasBid;
  final bool isQueued;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.screen, Gap.md),
      child: Row(
        children: [
          const _BackButton(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Заявка №${order.id}', style: AppText.displayMd),
                const SizedBox(height: 1),
                Text(
                  order.publishedAt == null
                      ? 'Опубликована'
                      : 'Опубликована ${Fmt.ago(order.publishedAt)}',
                  style: AppText.bodySm,
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.md),
          if (isQueued)
            StatusBadge.queued(compact: true)
          else if (hasBid)
            StatusBadge.bidSent(compact: true)
          else if (order.offeredToMe)
            StatusBadge.targeted(compact: true)
          else
            StatusBadge.newOrder(compact: true),
        ],
      ),
    );
  }
}

class _CargoSection extends StatelessWidget {
  const _CargoSection({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final tags = <String>[
      Fmt.weight(order.weightKg),
      if (order.cargoType.isNotEmpty) _capitalize(order.cargoType),
      if (order.requiresRefrigeration) 'Рефрижератор',
    ];

    return Padding(
      padding: const EdgeInsets.all(Gap.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_capitalize(order.cargoType), style: AppText.displayMd),
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [for (final tag in tags) SpecTag(tag)],
          ),
          if (order.photoUrl != null) ...[
            const SizedBox(height: Gap.lg),
            ClipRRect(
              borderRadius: Radii.cardAll,
              child: Image.network(
                order.photoUrl!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _capitalize(String value) =>
      value.isEmpty ? 'Груз' : value[0].toUpperCase() + value.substring(1);
}

class _CommentSection extends StatelessWidget {
  const _CommentSection({required this.comment});

  final String comment;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.screen),
        child: SurfaceCard(
          color: AppColors.bgSurface2,
          border: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('КОММЕНТАРИЙ ЗАКАЗЧИКА', style: AppText.label),
              const SizedBox(height: Gap.sm),
              Text(comment, style: AppText.bodyMd.copyWith(fontSize: 15)),
            ],
          ),
        ),
      );
}

class _ShipperSection extends StatelessWidget {
  const _ShipperSection({required this.shipper, this.onCall});

  final Shipper shipper;

  /// Телефон открывается только после отклика — до этого его незачем дёргать.
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.screen),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.bgSurface2,
              borderRadius: Radii.cardAll,
            ),
            child: Text(
              Fmt.initials(shipper.displayName),
              style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shipper.displayName,
                  style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text('Заказчик на платформе', style: AppText.bodyMd.copyWith(fontSize: 13)),
              ],
            ),
          ),
          if (onCall != null)
            IconTapTarget(
              icon: PhosphorIcons.phone(PhosphorIconsStyle.fill),
              color: AppColors.accent,
              onPressed: onCall,
              tooltip: 'Позвонить заказчику',
            ),
        ],
      ),
    );
  }
}

class _BidStatusSection extends StatelessWidget {
  const _BidStatusSection({required this.order, required this.isQueued});

  final Order order;
  final bool isQueued;

  @override
  Widget build(BuildContext context) {
    final bid = order.myBid;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SurfaceCard(
            color: AppColors.accentSoft,
            border: false,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isQueued
                        ? PhosphorIcons.arrowClockwise()
                        : PhosphorIcons.clock(PhosphorIconsStyle.fill),
                    size: 22,
                    color: AppColors.bgBase,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isQueued ? 'Отклик в очереди' : 'Отклик отправлен',
                        style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bid == null
                            ? 'Уйдёт, как только появится сеть'
                            : '${Fmt.money(bid.price)}'
                                '${bid.etaAt == null ? '' : ' · подача ${Fmt.pickupAt(bid.etaAt)}'}',
                        style: AppText.bodyMd.copyWith(fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          // Один бейдж не отвечает на вопрос «сколько ещё шагов до сдачи» —
          // показываем весь путь целиком.
          StepTrail(current: DeliveryStep.forBid(bid?.status ?? BidStatus.pending)),
          const SizedBox(height: Gap.lg),
          Text(
            isQueued
                ? 'Отклик сохранён на телефоне и отправится автоматически.'
                : 'Заказчик обычно отвечает за 15–40 минут. Пришлём уведомление.',
            style: AppText.bodyMd.copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Нижняя панель: цена заказчика слева, действие справа.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.order,
    required this.hasBid,
    required this.canBid,
    required this.onBid,
  });

  final Order order;
  final bool hasBid;
  final bool canBid;
  final VoidCallback onBid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        Gap.screen,
        Gap.md,
        Gap.screen,
        Gap.md + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgBase,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(hasBid ? 'ВАША ЦЕНА' : 'ЦЕНА ЗАКАЗЧИКА', style: AppText.label),
              const SizedBox(height: 2),
              Text(
                Fmt.money(hasBid ? order.myBid?.price ?? order.displayPrice
                    : order.displayPrice),
                style: AppText.price.copyWith(fontSize: 26),
              ),
            ],
          ),
          const SizedBox(width: Gap.lg),
          Expanded(
            child: hasBid
                ? SecondaryButton(
                    label: 'К моим откликам',
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : PrimaryButton(
                    label: 'Откликнуться',
                    onPressed: canBid ? onBid : null,
                  ),
          ),
        ],
      ),
    );
  }
}
