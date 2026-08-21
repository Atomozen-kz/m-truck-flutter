import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme/tokens.dart';
import '../../data/api_client.dart';
import '../../state/session_controller.dart';
import '../../widgets/numeric_keypad.dart';
import '../../widgets/primitives.dart';

/// S9 · Вход — ввод кода из SMS.
///
/// Вход происходит сам, как только введена последняя цифра: лишнее нажатие
/// «Подтвердить» на морозе никому не нужно.
class CodeScreen extends StatefulWidget {
  const CodeScreen({super.key});

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  static const _length = 4;
  static const _resendSeconds = 60;

  String _code = '';
  bool _isVerifying = false;
  String? _error;
  int _secondsLeft = _resendSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _append(String digit) {
    if (_code.length >= _length || _isVerifying) return;
    setState(() {
      _code += digit;
      _error = null;
    });
    if (_code.length == _length) unawaited(_verify());
  }

  void _backspace() {
    if (_code.isEmpty || _isVerifying) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _isVerifying = true);
    try {
      await context.read<SessionController>().verifyCode(_code);
      if (!mounted) return;
      // CodeScreen — отдельный маршрут поверх _RootGate: сама смена стадии
      // сессии его не закроет, иначе экран так и останется висеть с кодом.
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.fieldError('code') ?? e.message;
        _code = '';
      });
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    final session = context.read<SessionController>();
    final phone = session.pendingPhone;
    if (phone == null) return;
    try {
      await session.requestCode(phone);
      _startCountdown();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.select<SessionController, String?>((s) => s.pendingPhone);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.screen, Gap.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconTapTarget(
                      icon: PhosphorIcons.arrowLeft(),
                      color: AppColors.textPrimary,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: Gap.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: Gap.lg),
                          Text('Введите код из SMS', style: AppText.displayLg),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Отправили на ${Fmt.phone(phone)}',
                                  style: AppText.bodyMd.copyWith(fontSize: 15),
                                ),
                              ),
                              const SizedBox(width: Gap.sm),
                              GestureDetector(
                                onTap: () => Navigator.of(context).maybePop(),
                                child: Text(
                                  'Изменить',
                                  style: AppText.bodyMd.copyWith(
                                    fontSize: 15,
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Gap.xxl),
                          _CodeBoxes(
                            code: _code,
                            length: _length,
                            hasError: _error != null,
                            isBusy: _isVerifying,
                          ),
                          const SizedBox(height: Gap.lg),
                          if (_error != null)
                            Text(
                              _error!,
                              style: AppText.bodyMd.copyWith(color: AppColors.danger),
                            )
                          else ...[
                            _ResendRow(secondsLeft: _secondsLeft, onResend: _resend),
                            const SizedBox(height: 6),
                            Text(
                              'Войдём автоматически, как только введёте последнюю цифру',
                              style: AppText.bodyMd.copyWith(fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            NumericKeypad(
              onDigit: _append,
              onBackspace: _backspace,
              onLongBackspace: () => setState(() => _code = ''),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.code,
    required this.length,
    required this.hasError,
    required this.isBusy,
  });

  final String code;
  final int length;
  final bool hasError;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < length; index++) ...[
          if (index > 0) const SizedBox(width: Gap.md),
          Expanded(
            child: _CodeBox(
              value: index < code.length ? code[index] : null,
              isActive: index == code.length && !isBusy,
              hasError: hasError,
            ),
          ),
        ],
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.value, required this.isActive, required this.hasError});

  final String? value;
  final bool isActive;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? AppColors.danger
        : (isActive ? AppColors.accent : AppColors.borderSubtle);

    return Container(
      height: 88,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: value == null ? Colors.transparent : AppColors.bgSurface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: borderColor, width: isActive || hasError ? 2 : 1),
      ),
      child: value == null
          ? (isActive
              ? Container(width: 2, height: 34, color: AppColors.accent)
              : const SizedBox.shrink())
          : Text(
              value!,
              style: AppText.displayLg.copyWith(fontFeatures: AppText.tabularFigures),
            ),
    );
  }
}

class _ResendRow extends StatelessWidget {
  const _ResendRow({required this.secondsLeft, required this.onResend});

  final int secondsLeft;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    if (secondsLeft > 0) {
      final minutes = secondsLeft ~/ 60;
      final seconds = (secondsLeft % 60).toString().padLeft(2, '0');
      return Text(
        'Отправить код повторно можно через $minutes:$seconds',
        style: AppText.bodyMd.copyWith(fontFeatures: AppText.tabularFigures),
      );
    }
    return GestureDetector(
      onTap: onResend,
      child: Text(
        'Отправить код повторно',
        style: AppText.bodyMd.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }
}
