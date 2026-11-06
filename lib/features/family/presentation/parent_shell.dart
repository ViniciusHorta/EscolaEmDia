import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

enum ParentTab { dashboard, worksheets, family }

/// Estrutura da área do responsável: cabeçalho «Área do Responsável», estado do PIN,
/// menu de conta e barra de navegação inferior (Painel, Fichas, Família).
class ParentShell extends StatelessWidget {
  const ParentShell({
    super.key,
    required this.tab,
    required this.onTabChanged,
    required this.dashboard,
    required this.worksheets,
    required this.family,
    required this.onLock,
    required this.onSignOut,
    this.pendingCount = 0,
    this.busy = false,
  });

  final ParentTab tab;
  final ValueChanged<ParentTab> onTabChanged;
  final Widget dashboard;
  final Widget worksheets;
  final Widget family;
  final VoidCallback onLock;
  final VoidCallback onSignOut;
  final int pendingCount;
  final bool busy;

  static const titles = {
    ParentTab.dashboard: 'Revisões Pendentes',
    ParentTab.worksheets: 'Fichas',
    ParentTab.family: 'Família',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: Column(children: [
      _Header(title: titles[tab]!, onLock: busy ? null : onLock, onAccount: busy ? null : () => _accountSheet(context)),
      Expanded(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: IndexedStack(index: tab.index, children: [dashboard, worksheets, family]),
      ))),
    ]),
    bottomNavigationBar: NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.lavender,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 14,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w600,
          color: states.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted,
        )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          size: 28,
          color: states.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted,
        )),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -6)),
        ]),
        child: NavigationBar(
          selectedIndex: tab.index,
          onDestinationSelected: (index) => onTabChanged(ParentTab.values[index]),
          destinations: [
            NavigationDestination(
              icon: Badge(isLabelVisible: pendingCount > 0, label: Text('$pendingCount'),
                backgroundColor: AppColors.coral, child: const Icon(Icons.dashboard_outlined)),
              selectedIcon: Badge(isLabelVisible: pendingCount > 0, label: Text('$pendingCount'),
                backgroundColor: AppColors.coral, child: const Icon(Icons.dashboard_rounded)),
              label: 'Painel',
              tooltip: pendingCount > 0 ? 'Painel, $pendingCount por rever' : 'Painel',
            ),
            const NavigationDestination(
              icon: Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment_rounded),
              label: 'Fichas',
            ),
            const NavigationDestination(
              icon: Icon(Icons.group_outlined),
              selectedIcon: Icon(Icons.group_rounded),
              label: 'Família',
            ),
          ],
        ),
      ),
    ),
  );

  void _accountSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheet) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
          title: const Text('Bloquear área do responsável'),
          subtitle: const Text('Volta a pedir o PIN do responsável.'),
          onTap: () { Navigator.pop(sheet); onLock(); },
        ),
        ListTile(
          leading: const Icon(Icons.logout_rounded, color: AppColors.error),
          title: const Text('Sair da conta'),
          onTap: () { Navigator.pop(sheet); onSignOut(); },
        ),
      ]),
    )),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onLock, required this.onAccount});
  final String title;
  final VoidCallback? onLock;
  final VoidCallback? onAccount;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white, boxShadow: [
      BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
    ]),
    child: SafeArea(bottom: false, child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Padding(
        padding: EdgeInsets.fromLTRB(MediaQuery.sizeOf(context).width < 640 ? 16 : 32, 12, 16, 14),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ÁREA DO RESPONSÁVEL', style: TextStyle(
              color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 2),
            Semantics(header: true, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
              child: Text(title, maxLines: 1,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text)))),
          ])),
          const SizedBox(width: 8),
          Tooltip(
            message: 'PIN ativo. Tocar para bloquear a área do responsável.',
            child: Material(
              color: AppColors.softBlue,
              shape: const StadiumBorder(),
              child: InkWell(
                onTap: onLock,
                customBorder: const StadiumBorder(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_outline_rounded, color: AppColors.success, size: 20),
                    SizedBox(width: 6),
                    Text('PIN\nATIVO', style: TextStyle(
                      fontSize: 11, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.muted)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: onAccount,
            tooltip: 'Conta e definições',
            iconSize: 24,
            style: IconButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.person_outline_rounded),
          ),
        ]),
      ),
    ))),
  );
}
