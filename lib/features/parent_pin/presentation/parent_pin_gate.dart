import 'package:flutter/material.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../../auth/data/auth_service.dart';
import '../data/parent_pin_service.dart';
import 'parent_pin_setup_page.dart';

class ParentPinGate extends StatefulWidget {
  const ParentPinGate({super.key, required this.auth, required this.child});
  final AuthService auth;
  final Widget child;

  @override
  State<ParentPinGate> createState() => _ParentPinGateState();
}

class _ParentPinGateState extends State<ParentPinGate> {
  late final ParentPinService service;
  late Future<bool> status;
  bool saved = false;
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

  @override
  Widget build(BuildContext context) {
    if (saved) return widget.child;
    return FutureBuilder<bool>(
      future: status,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return AppPage(
            title: 'Vamos preparar o teu acesso',
            subtitle: error is ParentPinException ? error.message : 'Não foi possível consultar o PIN parental.',
            children: [
              AppButton(label: 'Tentar novamente', onPressed: exiting ? null : () => setState(() => status = service.isConfigured())),
              const SizedBox(height: 16),
              if (exitError != null) Text(exitError!),
              AppButton(label: 'Sair da conta', variant: AppButtonVariant.secondary, loading: exiting, onPressed: exiting ? null : exit),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(semanticsLabel: 'A preparar o acesso parental')));
        }
        if (snapshot.data!) return widget.child;
        return ParentPinSetupPage(service: service, onSaved: () => setState(() => saved = true), onExit: widget.auth.signOut);
      },
    );
  }
}
