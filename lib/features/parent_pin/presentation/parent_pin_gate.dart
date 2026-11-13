import 'package:flutter/material.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/brand/app_logo.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../../auth/data/auth_service.dart';
import '../data/parent_access_service.dart';
import '../data/parent_pin_service.dart';
import 'parent_pin_setup_page.dart';

class ParentPinGate extends StatefulWidget {
  const ParentPinGate({super.key, required this.auth, required this.builder});
  final AuthService auth;

  /// [unlocked]: acesso do responsável já desbloqueado com o PIN acabado de
  /// definir (evita pedir o PIN outra vez); null no arranque normal. Quem o
  /// recebe passa a ser dono dele e tem de o libertar.
  final Widget Function(ParentAccessService? unlocked) builder;

  @override
  State<ParentPinGate> createState() => _ParentPinGateState();
}

class _ParentPinGateState extends State<ParentPinGate> {
  late final ParentPinService service;
  late Future<bool> status;
  bool saved = false;
  ParentAccessService? unlocked;
  bool exiting = false;
  String? exitError;

  @override
  void initState() {
    super.initState();
    service = ParentPinService(widget.auth.client);
    status = service.isConfigured();
  }

  Future<void> exit() async {
    if (exiting) return;
    setState(() { exiting = true; exitError = null; });
    try { await widget.auth.signOut(); }
    catch (_) { if (mounted) setState(() => exitError = 'Não foi possível sair da conta. Tenta novamente.'); }
    finally { if (mounted) setState(() => exiting = false); }
  }

  Future<void> pinSaved(String? pin) async {
    ParentAccessService? access;
    if (pin != null) {
      access = ParentAccessService(widget.auth.client);
      try {
        await access.verify(pin);
      } catch (_) {
        // Sem desbloqueio automático, o espaço de trabalho pede o PIN como habitualmente.
        access.dispose();
        access = null;
      }
    }
    if (!mounted) {
      access?.dispose();
      return;
    }
    setState(() { saved = true; unlocked = access; });
  }

  @override
  Widget build(BuildContext context) {
    if (saved) return widget.builder(unlocked);
    return FutureBuilder<bool>(
      future: status,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return AppPage(
            title: 'Vamos preparar o teu acesso',
            subtitle: error is ParentPinException ? error.message : 'Não foi possível consultar o PIN do responsável.',
            children: [
              AppButton(label: 'Tentar novamente', onPressed: exiting ? null : () => setState(() => status = service.isConfigured())),
              const SizedBox(height: 16),
              if (exitError != null) Text(exitError!),
              AppButton(label: 'Sair da conta', variant: AppButtonVariant.secondary, loading: exiting, onPressed: exiting ? null : exit),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const AppSplash(message: 'A preparar o acesso do responsável');
        }
        if (snapshot.data!) return widget.builder(null);
        return ParentPinSetupPage(service: service, onSaved: pinSaved, onExit: widget.auth.signOut);
      },
    );
  }
}
