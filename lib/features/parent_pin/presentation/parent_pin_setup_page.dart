import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/layout/onboarding_header.dart';
import '../../../shared/widgets/pin/app_pin_input.dart';
import '../data/parent_pin_service.dart';

class ParentPinSetupPage extends StatefulWidget {
  const ParentPinSetupPage({super.key, required this.service, required this.onSaved, required this.onExit});
  final ParentPinService service;
  final VoidCallback onSaved;
  final Future<void> Function() onExit;

  @override
  State<ParentPinSetupPage> createState() => _ParentPinSetupPageState();
}

class _ParentPinSetupPageState extends State<ParentPinSetupPage> {
  String firstPin = '';
  String pin = '';
  bool confirming = false;
  bool busy = false;
  int inputVersion = 0;
  String? error;

  @override
  void dispose() {
    firstPin = '';
    pin = '';
    super.dispose();
  }

  Future<void> back() async {
    if (busy) return;
    if (confirming) {
      setState(() {
        confirming = false; firstPin = ''; pin = ''; error = null; inputVersion++;
      });
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await widget.onExit();
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível sair da conta. Tenta novamente.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> continueSetup() async {
    if (busy || pin.length != 4) return;
    FocusScope.of(context).unfocus();
    if (!confirming) {
      setState(() {
        firstPin = pin; pin = ''; confirming = true; inputVersion++; error = null;
      });
      return;
    }
    if (pin != firstPin) {
      setState(() { error = 'Os PINs não coincidem. Repete o primeiro PIN.'; pin = ''; inputVersion++; });
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await widget.service.setup(pin);
      if (!mounted) return;
      firstPin = ''; pin = '';
      widget.onSaved();
    } on ParentPinException catch (failure) {
      if (!mounted) return;
      if (failure.alreadyConfigured) {
        firstPin = ''; pin = '';
        widget.onSaved();
      } else {
        setState(() => error = failure.message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: SingleChildScrollView(key: ValueKey('pin-setup-$confirming'), child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Padding(
        padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 640 ? 16 : 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OnboardingHeader(title: 'Configurar PIN do Responsável', step: 2, onBack: busy ? null : back),
          const SizedBox(height: 32),
          const Center(child: AppBadge(label: 'Passo 2 de 4 • Segurança', icon: Icons.verified_user_outlined)),
          const SizedBox(height: 20),
          Text(confirming ? 'Confirma o PIN do responsável' : 'Define o PIN do responsável',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(confirming
              ? 'Repete os mesmos 4 dígitos para garantir que ficou tudo certo.'
              : 'Escolhe um código de 4 dígitos para o acesso à área do responsável.',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 28),
          Center(child: AppPinInput(
            key: ValueKey(inputVersion),
            label: confirming ? 'Repetir PIN' : 'PIN do responsável',
            enabled: !busy,
            errorText: error,
            onChanged: (value) => setState(() { pin = value; error = null; }),
          )),
          const SizedBox(height: 24),
          const ExpansionTile(
            leading: Icon(Icons.lightbulb_outline_rounded, color: AppColors.amber),
            title: Text('Dica de segurança'),
            childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [Text('Evita combinações óbvias, como 1234 ou 0000, e datas de nascimento. Escolhe um PIN diferente do das crianças.')],
          ),
          const SizedBox(height: 32),
          AppButton(
            label: confirming ? 'Guardar PIN e continuar' : 'Continuar',
            icon: Icons.arrow_forward_rounded,
            loading: busy,
            onPressed: busy || pin.length != 4 ? null : continueSetup,
          ),
          const SizedBox(height: 18),
          const Text('O PIN do responsável é uma proteção adicional. A tua conta continua a usar o e-mail e a palavra-passe.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 20),
          TextButton(onPressed: busy ? null : () async {
            setState(() { busy = true; error = null; });
            try { await widget.onExit(); }
            catch (_) { if (mounted) setState(() => error = 'Não foi possível sair da conta.'); }
            finally { if (mounted) setState(() => busy = false); }
          }, child: const Text('Sair da conta')),
        ]),
      ),
    )))),
  );
}
