import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/api_client.dart';
import '../../data/models/models.dart';
import '../../state/trip_controller.dart';
import '../../widgets/primitives.dart';
import '../../widgets/route_rail.dart';
import 'trip_done_screen.dart';

/// S4 · Завершение рейса — заработок, документы и подтверждение сдачи груза.
class FinishTripScreen extends StatefulWidget {
  const FinishTripScreen({super.key, required this.shipment});

  final Shipment shipment;

  @override
  State<FinishTripScreen> createState() => _FinishTripScreenState();
}

class _FinishTripScreenState extends State<FinishTripScreen> {
  final List<String> _documents = [];
  bool _noComplaints = true;
  bool _isSubmitting = false;

  Future<void> _addDocument() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked != null) setState(() => _documents.add(picked.path));
  }

  Future<void> _finish() async {
    setState(() => _isSubmitting = true);
    final trips = context.read<TripController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // Сначала документы, затем финальный статус: если сеть пропадёт между
      // шагами, оба уйдут из очереди в том же порядке.
      for (final path in _documents) {
        await trips.submitProof(photoPath: path);
      }
      if (widget.shipment.status != ShipmentStatus.delivered) {
        await trips.advanceStatus(ShipmentStatus.delivered);
      }
      if (!mounted) return;

      final completed = trips.active ?? widget.shipment;
      await trips.clearActive();
      if (!mounted) return;

      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => TripDoneScreen(shipment: completed)),
      );
    } on ApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shipment = widget.shipment;
    final order = shipment.order;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(shipment: shipment),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _EarningCard(shipment: shipment),
                  StatStrip(
                    items: [
                      (value: Fmt.km(order?.distanceKm), label: 'пройдено'),
                      (
                        value: Fmt.duration(shipment.actualMinutes ?? order?.durationMin),
                        label: 'в пути',
                      ),
                      (value: Fmt.weight(order?.weightKg), label: 'груз'),
                    ],
                  ),
                  const HairLine(),
                  Padding(
                    padding: const EdgeInsets.all(Gap.screen),
                    child: RouteRail(
                      stops: [
                        RailStop(
                          title: order?.from?.address ?? '—',
                          subtitle: 'Загружено ${Fmt.time(shipment.pickedUpAt)}',
                          state: RailStopState.done,
                        ),
                        RailStop(
                          title: order?.to?.address ?? '—',
                          subtitle: 'Выгружено ${Fmt.time(shipment.deliveredAt ?? DateTime.now())}',
                          state: RailStopState.done,
                        ),
                      ],
                    ),
                  ),
                  const HairLine(),
                  _DocumentsSection(
                    documents: _documents,
                    onAdd: _addDocument,
                    onRemove: (path) => setState(() => _documents.remove(path)),
                  ),
                  _NoComplaintsRow(
                    value: _noComplaints,
                    onChanged: (value) => setState(() => _noComplaints = value),
                  ),
                  const SizedBox(height: Gap.xxl),
                ],
              ),
            ),
            Container(
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
              child: PrimaryButton(
                label: 'Завершить рейс',
                height: Touch.cta,
                isLoading: _isSubmitting,
                onPressed: _finish,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.shipment});

  final Shipment shipment;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.screen, Gap.md),
        child: Row(
          children: [
            IconTapTarget(
              icon: PhosphorIcons.arrowLeft(),
              color: AppColors.textPrimary,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Завершение рейса', style: AppText.displayMd),
                  const SizedBox(height: 1),
                  Text(
                    'Рейс №${shipment.id} · груз выгружен '
                    'в ${Fmt.time(shipment.deliveredAt ?? DateTime.now())}',
                    style: AppText.bodySm,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _EarningCard extends StatelessWidget {
  const _EarningCard({required this.shipment});

  final Shipment shipment;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(Gap.screen, Gap.sm, Gap.screen, Gap.lg),
        padding: const EdgeInsets.all(Gap.xl),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: Radii.cardAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ЗАРАБОТОК ЗА РЕЙС', style: AppText.label),
            const SizedBox(height: Gap.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(Fmt.money(shipment.earning), style: AppText.price),
            ),
            const SizedBox(height: Gap.lg),
            const HairLine(),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Icon(PhosphorIcons.clock(), size: 18, color: AppColors.textTertiary),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    'Оплата поступит на счёт в течение 3 рабочих дней',
                    style: AppText.bodyMd.copyWith(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({
    required this.documents,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> documents;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Gap.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text('Документы', style: AppText.displayMd)),
              Text(
                'ТТН, накладная · необязательно',
                style: AppText.bodyMd.copyWith(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          Wrap(
            spacing: Gap.md,
            runSpacing: Gap.md,
            children: [
              for (final (index, path) in documents.indexed)
                _DocumentTile(
                  label: 'Фото ${index + 1}',
                  path: path,
                  onRemove: () => onRemove(path),
                ),
              _AddDocumentTile(onTap: onAdd),
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.label, required this.path, required this.onRemove});

  final String label;
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Container(
            width: 98,
            height: 98,
            decoration: BoxDecoration(
              color: AppColors.bgSurface2,
              borderRadius: Radii.cardAll,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIcons.file(), size: 30, color: AppColors.textSecondary),
                const SizedBox(height: Gap.sm),
                Text(label, style: AppText.caption),
              ],
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: IconTapTarget(
              icon: PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
              size: 22,
              onPressed: onRemove,
            ),
          ),
        ],
      );
}

class _AddDocumentTile extends StatelessWidget {
  const _AddDocumentTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: Radii.cardAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.cardAll,
          child: Ink(
            width: 98,
            height: 98,
            decoration: BoxDecoration(
              borderRadius: Radii.cardAll,
              border: Border.all(color: AppColors.borderDefault),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIcons.camera(), size: 30, color: AppColors.textSecondary),
                const SizedBox(height: Gap.sm),
                Text('Добавить', style: AppText.caption),
              ],
            ),
          ),
        ),
      );
}

class _NoComplaintsRow extends StatelessWidget {
  const _NoComplaintsRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.screen),
        child: Material(
          color: Colors.transparent,
          borderRadius: Radii.cardAll,
          child: InkWell(
            onTap: () => onChanged(!value),
            borderRadius: Radii.cardAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.md),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value ? AppColors.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: value ? AppColors.accent : AppColors.borderDefault,
                        width: 2,
                      ),
                    ),
                    child: value
                        ? Icon(
                            PhosphorIcons.check(PhosphorIconsStyle.bold),
                            size: 16,
                            color: AppColors.bgBase,
                          )
                        : null,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      'Груз сдан без замечаний',
                      style: AppText.bodyLg.copyWith(fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
