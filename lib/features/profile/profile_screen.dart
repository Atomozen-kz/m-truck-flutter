import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../services/sync_service.dart';
import '../../state/session_controller.dart';
import '../../state/trip_controller.dart';
import '../../widgets/locked_row.dart';
import '../../widgets/primitives.dart';
import '../payouts/payouts_screen.dart';

/// S7 · Профиль и машина.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.user;
    final trips = context.watch<TripController>();
    final sync = context.watch<SyncService>();

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final completed = trips.history.where((s) => s.status.isFinished).toList();
    final totalKm = completed.fold<double>(0, (sum, s) => sum + (s.order?.distanceKm ?? 0));

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: Gap.xxl),
        children: [
          _Identity(user: user),
          StatStrip(
            items: [
              (value: '${completed.length}', label: 'рейса'),
              (value: Fmt.km(totalKm), label: 'пробег'),
              (value: Fmt.rating(user.rating), label: 'рейтинг'),
            ],
          ),
          const HairLine(),
          const PayoutsEntryRow(),
          const HairLine(),
          _VehicleSection(vehicles: user.vehicles),
          const HairLine(),
          _DocumentsSection(user: user),
          const HairLine(),
          if (sync.hasPending) ...[
            _SyncRow(sync: sync),
            const HairLine(),
          ],
          _AccountSection(user: user),
          const HairLine(),
          SettingsRow(
            icon: PhosphorIcons.bell(),
            label: 'Уведомления',
            locked: const LockedReason(
              title: 'Уведомления',
              message: 'Push-уведомлений в этой сборке нет: для них нужен '
                  'Firebase-проект и приём токена устройства на сервере.',
              workaround: 'Списки обновляются сами, когда вы открываете экран '
                  'или тянете его вниз.',
            ),
          ),
          SettingsRow(
            icon: PhosphorIcons.translate(),
            label: 'Язык',
            value: 'Русский',
            locked: const LockedReason(
              title: 'Язык интерфейса',
              message: 'Казахская локализация ещё не переведена — приложение '
                  'работает на русском.',
            ),
          ),
          const HairLine(),
          _SignOutRow(onTap: () => _confirmSignOut(context, session)),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, SessionController session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetAll),
        title: Text('Выйти из аккаунта?', style: AppText.displayMd.copyWith(fontSize: 20)),
        content: Text(
          'Незавершённые действия из офлайн-очереди будут потеряны.',
          style: AppText.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Отмена', style: AppText.bodyLg.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Выйти', style: AppText.bodyLg.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await session.signOut();
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.sm, Gap.screen, Gap.lg),
        child: Row(
          children: [
            _Avatar(user: user),
            const SizedBox(width: Gap.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name.isEmpty ? 'Водитель' : user.name,
                    style: AppText.displayMd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        PhosphorIcons.star(PhosphorIconsStyle.fill),
                        size: 15,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        Fmt.rating(user.rating),
                        style: AppText.bodyMd.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontFeatures: AppText.tabularFigures,
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Flexible(
                        child: Text(
                          '· ${Fmt.phone(user.phone)}',
                          style: AppText.bodyMd.copyWith(fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Аватар водителя.
///
/// Фото пока негде хранить — в API нет загрузки аватара, — но значок камеры
/// оставлен: по тапу он честно объясняет, почему кнопка не работает.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final User user;

  static const _reason = LockedReason(
    title: 'Фото профиля',
    message: 'Аватар пока некуда загрузить: приёма фотографии пользователя '
        'в API нет. Фото прав при регистрации сохраняется отдельно.',
    workaround: LockedReason.askDispatcher,
  );

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => showLockedSheet(context, _reason),
        child: SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: Radii.cardAll,
                ),
                child: Text(
                  Fmt.initials(user.name),
                  style: AppText.displayMd.copyWith(color: AppColors.textSecondary),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface3,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bgBase, width: 2),
                  ),
                  child: Icon(
                    PhosphorIcons.camera(PhosphorIconsStyle.fill),
                    size: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _VehicleSection extends StatelessWidget {
  const _VehicleSection({required this.vehicles});

  final List<Vehicle> vehicles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Gap.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(vehicles.length > 1 ? 'Машины' : 'Машина', style: AppText.displayMd),
          const SizedBox(height: Gap.md),
          if (vehicles.isEmpty)
            Text(
              'Машина не добавлена — без неё нельзя откликаться на заявки.',
              style: AppText.bodyMd,
            )
          else
            for (final (index, vehicle) in vehicles.indexed) ...[
              if (index > 0) const SizedBox(height: Gap.betweenCards),
              _VehicleCard(vehicle: vehicle),
            ],
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.bgSurface,
        border: false,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: Radii.cardAll,
              ),
              child: Icon(
                PhosphorIcons.truck(PhosphorIconsStyle.fill),
                size: 26,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.type.isEmpty ? 'Грузовик' : _capitalize(vehicle.type),
                    style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      Fmt.weight(vehicle.capacityKg),
                      if (vehicle.hasRefrigeration) 'холодильник',
                      if (vehicle.isEnRoute) 'в рейсе',
                    ].join(' · '),
                    style: AppText.bodyMd.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.sm),
            SpecTag(vehicle.plate, emphasized: true),
          ],
        ),
      );

  static String _capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final driver = user.driver;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.screen, Gap.screen, Gap.sm),
          child: Text('Документы', style: AppText.displayMd),
        ),
        _DocumentRow(
          icon: PhosphorIcons.identificationCard(),
          title: 'Водительское удостоверение',
          subtitle: driver == null
              ? 'Не загружено'
              : (driver.licenseNo.isEmpty ? 'Номер не указан' : driver.licenseNo),
          status: driver?.status,
        ),
        _DocumentRow(
          icon: PhosphorIcons.fileText(),
          title: 'Техпаспорт',
          subtitle: user.primaryVehicle == null
              ? 'Машина не добавлена'
              : 'Госномер ${user.primaryVehicle!.plate}',
          status: user.primaryVehicle == null ? null : DriverStatus.approved,
        ),
      ],
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final DriverStatus? status;

  static const _reason = LockedReason(
    title: 'Документы',
    message: 'Права и техпаспорт загружаются один раз при регистрации. '
        'Перезалить их из приложения нельзя: метода на обновление документов '
        'в API нет.',
    workaround: LockedReason.askDispatcher,
  );

  @override
  Widget build(BuildContext context) {
    final (statusIcon, statusColor) = switch (status) {
      DriverStatus.approved => (
          PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
          AppColors.success,
        ),
      DriverStatus.pending => (
          PhosphorIcons.clock(PhosphorIconsStyle.fill),
          AppColors.accent,
        ),
      DriverStatus.rejected => (
          PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
          AppColors.danger,
        ),
      null => (PhosphorIcons.warningCircle(PhosphorIconsStyle.fill), AppColors.textTertiary),
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showLockedSheet(context, _reason),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.screen, vertical: Gap.md),
          child: Row(
            children: [
              Icon(icon, size: 24, color: AppColors.textSecondary),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.bodyLg.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppText.bodyMd.copyWith(fontSize: 13)),
                  ],
                ),
              ),
              Icon(statusIcon, size: 22, color: statusColor),
              const SizedBox(width: Gap.sm),
              Icon(
                PhosphorIcons.lockSimple(),
                size: 16,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка о неотправленных действиях — честный ответ на «а где мои данные».
class _SyncRow extends StatelessWidget {
  const _SyncRow({required this.sync});

  final SyncService sync;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.screen, vertical: Gap.lg),
        child: Row(
          children: [
            Icon(
              PhosphorIcons.cloudArrowUp(),
              size: 24,
              color: sync.isFlushing ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sync.isFlushing ? 'Отправляем данные' : 'Ждут отправки',
                    style: AppText.bodyLg.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (sync.pendingActions > 0) '${sync.pendingActions} действий',
                      if (sync.bufferedPoints > 0) '${sync.bufferedPoints} GPS-точек',
                    ].join(' · '),
                    style: AppText.bodyMd.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: sync.isFlushing ? null : sync.flush,
              child: Text(
                'Отправить',
                style: AppText.bodyMd.copyWith(
                  color: sync.isFlushing ? AppColors.textTertiary : AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Аккаунт: то, что водитель хочет менять сам, но пока не может.
///
/// Мобильное API платформы состоит из чтения и действий по рейсу — методов
/// записи в профиль, машину, документы и реквизиты в нём нет. Пункты стоят на
/// своих местах закрытыми: так видно, что функция задумана, и понятно, к кому
/// идти сейчас.
class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.screen, Gap.screen, Gap.sm),
            child: Text('Аккаунт', style: AppText.displayMd),
          ),
          SettingsRow(
            icon: PhosphorIcons.userCircle(),
            label: 'Данные профиля',
            value: user.name.isEmpty ? null : user.name,
            locked: const LockedReason(
              title: 'Данные профиля',
              message: 'Имя, телефон и фото пока меняются только на стороне '
                  'платформы: мобильное API умеет профиль читать, но не '
                  'записывать.',
              workaround: LockedReason.askDispatcher,
            ),
          ),
          SettingsRow(
            icon: PhosphorIcons.userSwitch(),
            label: 'Роль',
            value: _roleLabel(user.role),
            locked: const LockedReason(
              title: 'Смена роли',
              message: 'Это приложение — кабинет дальнобойщика. Роль заказчика '
                  'живёт в веб-кабинете, и переключать её из мобильного нельзя.',
              workaround: 'Если нужен доступ заказчика, попросите платформу '
                  'завести отдельный аккаунт.',
            ),
          ),
          SettingsRow(
            icon: PhosphorIcons.truck(),
            label: 'Тип транспорта',
            value: _vehicleLabel(user.primaryVehicle),
            locked: const LockedReason(
              title: 'Тип транспорта',
              message: 'Тип кузова, тоннаж и госномер задаются при регистрации '
                  'и потом меняются только платформой — метода на изменение '
                  'машины в API нет.',
              workaround: LockedReason.askDispatcher,
            ),
          ),
          SettingsRow(
            icon: PhosphorIcons.creditCard(),
            label: 'Банковская карта',
            value: 'не привязана',
            locked: const LockedReason(
              title: 'Банковская карта',
              message: 'Реквизиты для выплат платформа пока не принимает: '
                  'эндпоинта для карты в API нет.',
              workaround: 'Деньги приходят по договору с платформой — суммы '
                  'и статусы видны в разделе «Выплаты».',
            ),
          ),
        ],
      );

  static String _roleLabel(String role) => switch (role) {
        'driver' => 'Водитель',
        'shipper' => 'Заказчик',
        'admin' => 'Администратор',
        _ => role,
      };

  static String? _vehicleLabel(Vehicle? vehicle) {
    if (vehicle == null) return 'не добавлен';
    final type = vehicle.type.isEmpty ? 'машина' : vehicle.type;
    return '$type · ${Fmt.weight(vehicle.capacityKg)}';
  }
}

class _SignOutRow extends StatelessWidget {
  const _SignOutRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.screen, vertical: Gap.lg),
            child: Row(
              children: [
                Icon(PhosphorIcons.signOut(), size: 24, color: AppColors.danger),
                const SizedBox(width: Gap.md),
                Text(
                  'Выйти',
                  style: AppText.bodyLg.copyWith(fontSize: 15, color: AppColors.danger),
                ),
              ],
            ),
          ),
        ),
      );
}
