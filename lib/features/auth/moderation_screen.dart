import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../state/session_controller.dart';
import '../../widgets/primitives.dart';

/// Экран ожидания модерации: доступ к бирже откроется после проверки прав.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  bool _isChecking = false;

  Future<void> _check() async {
    setState(() => _isChecking = true);
    await context.read<SessionController>().refresh();
    if (mounted) setState(() => _isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.screen),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIcons.clock(PhosphorIconsStyle.fill),
                  size: 42,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: Gap.xxl),
              Text(
                'Проверяем документы',
                style: AppText.displayLg,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gap.md),
              Text(
                'Обычно это занимает несколько часов. Как только права одобрят, '
                'откроется биржа заявок — мы пришлём уведомление.',
                style: AppText.bodyMd.copyWith(fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gap.xxl),
              if (user != null)
                SurfaceCard(
                  child: Column(
                    children: [
                      _Row(label: 'Водитель', value: user.name),
                      const SizedBox(height: Gap.md),
                      _Row(label: 'Телефон', value: Fmt.phone(user.phone)),
                      if (user.driver != null) ...[
                        const SizedBox(height: Gap.md),
                        _Row(label: 'Права', value: user.driver!.licenseNo),
                      ],
                      if (user.primaryVehicle != null) ...[
                        const SizedBox(height: Gap.md),
                        _Row(label: 'Машина', value: user.primaryVehicle!.plate),
                      ],
                    ],
                  ),
                ),
              const Spacer(),
              PrimaryButton(
                label: 'Проверить статус',
                icon: PhosphorIcons.arrowClockwise(),
                isLoading: _isChecking,
                onPressed: _check,
              ),
              const SizedBox(height: Gap.md),
              SecondaryButton(
                label: 'Выйти',
                onPressed: () => context.read<SessionController>().signOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.bodyMd),
          Flexible(
            child: Text(
              value,
              style: AppText.bodyMd.copyWith(color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}
