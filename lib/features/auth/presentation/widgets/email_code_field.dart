import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';

/// Pedido e introdução de um código de verificação enviado por e-mail.
/// Antes do envio mostra o botão «Enviar código»; depois, o campo do código e
/// «Reenviar código» com espera de 60 segundos.
class EmailCodeField extends StatefulWidget {
  const EmailCodeField({
    super.key,
    required this.controller,
    required this.onSend,
    this.email,
    this.enabled = true,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;
  /// Envia o código. Devolve a mensagem de erro a mostrar, ou null se foi enviado.
  final Future<String?> Function() onSend;
  final String? email;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  @override
  State<EmailCodeField> createState() => _EmailCodeFieldState();
}

class _EmailCodeFieldState extends State<EmailCodeField> {
  static const cooldown = 60;
  bool sent = false;
  bool sending = false;
  int wait = 0;
  String? sendError;
  Timer? timer;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> send() async {
    if (sending || wait > 0) return;
    setState(() { sending = true; sendError = null; });
    try {
      final failure = await widget.onSend();
      if (!mounted) return;
      if (failure != null) {
        setState(() => sendError = failure);
        return;
      }
      setState(() { sent = true; wait = cooldown; });
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => wait = wait > 0 ? wait - 1 : 0);
        if (wait == 0) t.cancel();
      });
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.email == null ? 'o e-mail da conta' : widget.email!;
    if (!sent) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Vamos enviar um código de verificação para $target.',
          style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.text)),
        if (sendError != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(sendError!,
            style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
        const SizedBox(height: 16),
        AppButton(label: 'Enviar código', icon: Icons.mark_email_unread_outlined,
          variant: AppButtonVariant.secondary, loading: sending,
          onPressed: widget.enabled && !sending ? send : null),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Enviámos um código para $target. Verifica também a pasta de spam.',
        style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.muted)),
      const SizedBox(height: 16),
      AppTextField(
        label: 'Código de verificação',
        hint: 'Código recebido por e-mail',
        controller: widget.controller,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        autofillHints: const [AutofillHints.oneTimeCode],
        textInputAction: widget.textInputAction,
        prefixIcon: Icons.pin_outlined,
        errorText: widget.errorText ?? sendError,
        onChanged: (value) {
          if (sendError != null) setState(() => sendError = null);
          widget.onChanged?.call(value);
        },
        onSubmitted: widget.onSubmitted,
      ),
      Align(alignment: Alignment.centerLeft, child: TextButton(
        onPressed: widget.enabled && !sending && wait == 0 ? send : null,
        child: Text(wait > 0 ? 'Reenviar código (${wait}s)' : 'Reenviar código'),
      )),
    ]);
  }
}
