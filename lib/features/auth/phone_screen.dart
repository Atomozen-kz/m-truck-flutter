import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/api_client.dart';
import '../../state/session_controller.dart';
import '../../widgets/brand.dart';
import '../../widgets/numeric_keypad.dart';
import '../../widgets/primitives.dart';
import 'code_screen.dart';

/// S9 · Вход — ввод номера телефона.
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  String _digits = '';
  bool _isSending = false;
  String? _error;

  bool get _isComplete => _digits.length == 10;

  void _append(String digit) {
    if (_digits.length >= 10) return;
    setState(() {
      _digits += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _submit() async {
    if (!_isComplete || _isSending) return;
    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      await context.read<SessionController>().requestCode('7$_digits');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CodeScreen()),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.xxl, Gap.screen, Gap.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandHeader(),
                    const SizedBox(height: Gap.xxxl),
                    Text('Введите номер телефона', style: AppText.displayLg),
                    const SizedBox(height: 6),
                    Text(
                      'Отправим SMS с кодом подтверждения',
                      style: AppText.bodyMd.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: Gap.xxl),
                    _PhoneField(digits: _digits, hasError: _error != null),
                    if (_error != null) ...[
                      const SizedBox(height: Gap.md),
                      Text(
                        _error!,
                        style: AppText.bodyMd.copyWith(color: AppColors.danger),
                      ),
                    ],
                    const SizedBox(height: Gap.lg),
                    PrimaryButton(
                      label: 'Получить код',
                      isLoading: _isSending,
                      onPressed: _isComplete ? _submit : null,
                      height: Touch.cta,
                    ),
                    const SizedBox(height: Gap.lg),
                    Text(
                      'Продолжая, вы принимаете условия использования '
                      'и политику конфиденциальности',
                      style: AppText.bodyMd.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            NumericKeypad(
              onDigit: _append,
              onBackspace: _backspace,
              onLongBackspace: () => setState(() => _digits = ''),
            ),
          ],
        ),
      ),
    );
  }
}

/// Поле номера с фиксированным «+7» и мигающим курсором.
class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.digits, required this.hasError});

  final String digits;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      decoration: BoxDecoration(
        borderRadius: Radii.cardAll,
        border: Border.all(
          color: hasError ? AppColors.danger : AppColors.accent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Text(
            '+7',
            style: AppText.displayLg.copyWith(
              color: AppColors.textTertiary,
              fontFeatures: AppText.tabularFigures,
            ),
          ),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: Gap.lg),
            color: AppColors.borderDefault,
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    Fmt.phoneNational(digits),
                    style: AppText.displayLg.copyWith(
                      fontFeatures: AppText.tabularFigures,
                    ),
                    maxLines: 1,
                  ),
                ),
                const _Caret(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Мигающий курсор — поле не использует системную клавиатуру, поэтому
/// собственный курсор показывает, что ввод активен.
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _controller.drive(CurveTween(curve: Curves.easeInOut)),
        child: Container(
          width: 2,
          height: 34,
          margin: const EdgeInsets.only(left: 3),
          color: AppColors.accent,
        ),
      );
}
