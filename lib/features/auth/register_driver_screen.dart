import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../data/api_client.dart';
import '../../state/session_controller.dart';
import '../../widgets/primitives.dart';

/// Анкета водителя: права и машина уходят на модерацию.
class RegisterDriverScreen extends StatefulWidget {
  const RegisterDriverScreen({super.key});

  @override
  State<RegisterDriverScreen> createState() => _RegisterDriverScreenState();
}

class _RegisterDriverScreenState extends State<RegisterDriverScreen> {
  /// Типы кузова из справочника API.
  static const _vehicleTypes = ['тент', 'рефрижератор', 'самосвал', 'бортовой', 'манипулятор'];

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _licenseNo = TextEditingController();
  final _plate = TextEditingController();
  final _capacity = TextEditingController();

  String _vehicleType = _vehicleTypes.first;
  bool _hasRefrigeration = false;
  String? _licensePhotoPath;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.text = context.read<SessionController>().user?.name ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _licenseNo.dispose();
    _plate.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _pickLicensePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked != null) setState(() => _licensePhotoPath = picked.path);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await context.read<SessionController>().registerDriver(
            name: _name.text.trim(),
            licenseNo: _licenseNo.text.trim(),
            plate: _plate.text.trim(),
            vehicleType: _vehicleType,
            capacityKg: int.parse(_capacity.text.trim()),
            hasRefrigeration: _hasRefrigeration || _vehicleType == 'рефрижератор',
            licensePhotoPath: _licensePhotoPath,
          );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.fieldErrors.values.firstOrNull?.first ?? e.message);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.xxl, Gap.screen, Gap.xxxl),
            children: [
              Text('Заполните профиль', style: AppText.displayLg),
              const SizedBox(height: 6),
              Text(
                'Проверим документы и откроем доступ к заявкам — обычно в течение дня',
                style: AppText.bodyMd.copyWith(fontSize: 15),
              ),
              const SizedBox(height: Gap.xxl),
              _Field(
                controller: _name,
                label: 'Имя и фамилия',
                hint: 'Ерлан Сағынов',
                textCapitalization: TextCapitalization.words,
              ),
              _Field(
                controller: _licenseNo,
                label: 'Номер водительского удостоверения',
                hint: '12АБ345678',
                textCapitalization: TextCapitalization.characters,
              ),
              _LicensePhotoPicker(
                path: _licensePhotoPath,
                onPick: _pickLicensePhoto,
                onClear: () => setState(() => _licensePhotoPath = null),
              ),
              const SizedBox(height: Gap.xxl),
              Text('Машина', style: AppText.displayMd),
              const SizedBox(height: Gap.lg),
              _Field(
                controller: _plate,
                label: 'Госномер',
                hint: '847 ABC 12',
                textCapitalization: TextCapitalization.characters,
              ),
              _TypeSelector(
                types: _vehicleTypes,
                selected: _vehicleType,
                onSelect: (type) => setState(() => _vehicleType = type),
              ),
              const SizedBox(height: Gap.lg),
              _Field(
                controller: _capacity,
                label: 'Грузоподъёмность, кг',
                hint: '20000',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  final kg = int.tryParse(value?.trim() ?? '');
                  if (kg == null || kg <= 0) return 'Укажите грузоподъёмность';
                  if (kg > 60000) return 'Слишком большое значение';
                  return null;
                },
              ),
              if (_vehicleType != 'рефрижератор')
                _RefrigerationToggle(
                  value: _hasRefrigeration,
                  onChanged: (value) => setState(() => _hasRefrigeration = value),
                ),
              if (_error != null) ...[
                const SizedBox(height: Gap.lg),
                Text(_error!, style: AppText.bodyMd.copyWith(color: AppColors.danger)),
              ],
              const SizedBox(height: Gap.xxl),
              PrimaryButton(
                label: 'Отправить на проверку',
                isLoading: _isSubmitting,
                onPressed: _submit,
                height: Touch.cta,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.bodyMd.copyWith(fontSize: 13)),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            textCapitalization: textCapitalization,
            style: AppText.bodyLg,
            cursorColor: AppColors.accent,
            validator: validator ??
                (value) => (value?.trim().isEmpty ?? true) ? 'Заполните поле' : null,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppText.bodyLg.copyWith(color: AppColors.textTertiary),
              filled: true,
              fillColor: AppColors.bgSurface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.lg,
              ),
              border: const OutlineInputBorder(
                borderRadius: Radii.cardAll,
                borderSide: BorderSide(color: AppColors.borderSubtle),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: Radii.cardAll,
                borderSide: BorderSide(color: AppColors.borderSubtle),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: Radii.cardAll,
                borderSide: BorderSide(color: AppColors.accent, width: 2),
              ),
              errorBorder: const OutlineInputBorder(
                borderRadius: Radii.cardAll,
                borderSide: BorderSide(color: AppColors.danger),
              ),
              focusedErrorBorder: const OutlineInputBorder(
                borderRadius: Radii.cardAll,
                borderSide: BorderSide(color: AppColors.danger, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.types,
    required this.selected,
    required this.onSelect,
  });

  final List<String> types;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Тип кузова', style: AppText.bodyMd.copyWith(fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final type in types)
              FilterPill(
                label: type[0].toUpperCase() + type.substring(1),
                selected: type == selected,
                onTap: () => onSelect(type),
              ),
          ],
        ),
      ],
    );
  }
}

class _LicensePhotoPicker extends StatelessWidget {
  const _LicensePhotoPicker({
    required this.path,
    required this.onPick,
    required this.onClear,
  });

  final String? path;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: path == null ? onPick : null,
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
              path == null
                  ? PhosphorIcons.camera()
                  : PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
              size: 24,
              color: path == null ? AppColors.textSecondary : AppColors.success,
            ),
          ),
          const SizedBox(width: Gap.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  path == null ? 'Фото прав' : 'Фото добавлено',
                  style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  path == null ? 'Снимите лицевую сторону' : 'Можно заменить',
                  style: AppText.bodyMd.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          if (path != null)
            IconTapTarget(icon: PhosphorIcons.arrowClockwise(), onPressed: onPick)
          else
            Icon(PhosphorIcons.caretRight(), size: 20, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

class _RefrigerationToggle extends StatelessWidget {
  const _RefrigerationToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Есть холодильная установка',
              style: AppText.bodyLg.copyWith(fontSize: 15),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.bgBase,
            activeTrackColor: AppColors.accent,
            inactiveThumbColor: AppColors.textTertiary,
            inactiveTrackColor: AppColors.bgSurface2,
          ),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
