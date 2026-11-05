import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/pin/app_pin_input.dart';
import '../data/parent_access_service.dart';
import '../data/parent_pin_service.dart';
import 'parent_pin_reset_page.dart';

class ParentUnlockPage extends StatefulWidget {
  const ParentUnlockPage({super.key, required this.access, required this.onUnlocked, required this.onExit, this.onCancel, this.cancelLabel = 'Voltar ao espaço infantil'});
  final ParentAccessService access;
  final Future<void> Function() onUnlocked;
  final Future<void> Function() onExit;
  final VoidCallback? onCancel;
  final String cancelLabel;
  @override
  State<ParentUnlockPage> createState() => _ParentUnlockPageState();
}

class _ParentUnlockPageState extends State<ParentUnlockPage> {
  String pin = '';
  bool busy = false;
  String? error;
  int inputVersion = 0;
  DateTime? blockedUntil;
  Timer? ticker;
  int get waitSeconds {
    final seconds = blockedUntil?.difference(DateTime.now()).inSeconds ?? 0;
    return seconds > 0 ? seconds + 1 : 0;
  }
  @override
  void dispose() {pin = ''; ticker?.cancel(); super.dispose();}

  Future<void> unlock() async {
    if (busy || pin.length != 4 || waitSeconds > 0) return;
    setState(() {busy = true; error = null;});
    FocusScope.of(context).unfocus();
    try {
      await widget.access.verify(pin);
      if (!mounted || !widget.access.unlocked) return;
      pin = '';
      await widget.onUnlocked();
    } on ParentAccessException catch (failure) {
      if (!mounted) return;
      setState(() {
        error = failure.message; pin = ''; inputVersion++;
        if (failure.retryAfter != null) blockedUntil = DateTime.now().add(Duration(seconds: failure.retryAfter!));
      });
      if (failure.retryAfter != null) {
        ticker?.cancel();
        ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {timer.cancel(); return;}
          setState(() {}); if (waitSeconds == 0) timer.cancel();
        });
      }
    } catch (_) {
      if (mounted) setState(() {error = 'Não foi possível abrir a área dos pais. Tenta novamente.'; pin = ''; inputVersion++;});
    } finally {if (mounted) setState(() => busy = false);}
  }

  Future<void> forgotPin() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    final unlocked = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ParentPinResetPage(service: ParentPinService(widget.access.client), access: widget.access),
    ));
    if (!mounted) return;
    if (unlocked == true && widget.access.unlocked) {
      setState(() => busy = true);
      try {await widget.onUnlocked();} finally {if (mounted) setState(() => busy = false);}
    } else if (unlocked == false) {
      setState(() {pin = ''; inputVersion++; error = null;});
    }
  }

  Future<void> exit() async {
    if (busy) return;
    setState(() {busy = true; error = null;});
    try {await widget.onExit();}
    catch (_) {if (mounted) setState(() => error = 'Não foi possível sair da conta. Tenta novamente.');}
    finally {if (mounted) setState(() => busy = false);}
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: false, child: Scaffold(body: SafeArea(child: SingleChildScrollView(
    child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 32),
        const CircleAvatar(radius: 36, backgroundColor: AppColors.lavender,
          child: Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 36)),
        const SizedBox(height: 24),
        Text('Área dos pais', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        const Text('Introduz o PIN parental para continuar.', textAlign: TextAlign.center),
        const SizedBox(height: 28),
        AppCard(child: Column(children: [
          AppPinInput(key: ValueKey(inputVersion), label: 'PIN parental', enabled: !busy && waitSeconds == 0,
            errorText: error, onChanged: (value) => setState(() {pin = value; error = null;})),
          if (waitSeconds > 0) Padding(padding: const EdgeInsets.only(top: 16), child: Text('Tenta novamente dentro de $waitSeconds segundos.')),
          const SizedBox(height: 24),
          AppButton(label: 'Desbloquear', icon: Icons.lock_open_rounded, loading: busy,
            onPressed: busy || pin.length != 4 || waitSeconds > 0 ? null : unlock),
          const SizedBox(height: 8),
          TextButton(onPressed: busy ? null : forgotPin, child: const Text('Esqueci-me do PIN')),
        ])),
        const SizedBox(height: 20),
        const Text('A área dos pais volta a bloquear após cinco minutos sem atividade.', textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 13)),
        if (widget.onCancel != null) ...[
          const SizedBox(height: 16),
          AppButton(label: widget.cancelLabel, icon: Icons.switch_account_rounded, variant: AppButtonVariant.neutral,
            onPressed: busy ? null : widget.onCancel),
        ],
        const SizedBox(height: 12),
        TextButton(onPressed: busy ? null : exit, child: const Text('Sair da conta')),
      ]),
    ))),
  ))));
}
