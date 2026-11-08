import '../../legal/data/legal_service.dart';
import '../../legal/presentation/legal_documents_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/request_id.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/premium_crown.dart';
import '../../billing/data/billing_service.dart';
import '../../billing/domain/billing_models.dart';
import '../../billing/presentation/premium_paywall.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand/app_logo.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../../auth/data/auth_service.dart';
import '../../parent_pin/data/parent_access_service.dart';
import '../../parent_pin/presentation/parent_unlock_page.dart';
import '../../parent_pin/presentation/parent_activity_boundary.dart';
import '../../child_session/data/child_session_service.dart';
import '../../child_session/presentation/child_entry_page.dart';
import '../../worksheets/data/worksheet_service.dart';
import '../../worksheets/presentation/prepare_worksheet_page.dart';
import '../../reviews/data/pending_reviews_service.dart';
import '../../reviews/presentation/parent_dashboard.dart';
import '../../reviews/presentation/parent_review_page.dart';
import '../../progress/data/child_progress_service.dart';
import '../../progress/presentation/child_progress_page.dart';
import '../data/family_service.dart';
import '../data/last_profile_store.dart';
import '../domain/family_models.dart';
import 'child_profile_page.dart';
import 'parent_shell.dart';

class FamilyWorkspacePage extends StatefulWidget {
  const FamilyWorkspacePage({super.key, required this.auth});
  final AuthService auth;

  @override
  State<FamilyWorkspacePage> createState() => _FamilyWorkspacePageState();
}

class _FamilyWorkspacePageState extends State<FamilyWorkspacePage> {
  late final FamilyService service;
  late final ChildSessionService childSessions;
  late final ParentAccessService parentAccess;
  late final WorksheetService worksheets;
  late final PendingReviewsService pendingReviews;
  late final ChildProgressService progressService;
  late final BillingService billing;
  /// Regresso do Stripe Checkout/portal (?billing=success|cancel|portal&child=…), só na Web.
  final Map<String, String> billingReturn = kIsWeb ? Map.of(Uri.base.queryParameters) : const {};
  bool billingHandled = false;
  bool preparing = false;
  ParentTab parentTab = ParentTab.dashboard;
  int pendingCount = 0;
  String? reviewingAttemptId;
  String? progressChildId;
  String? preferredChildId;
  String? returnFamilyId;
  bool requestingParent = false;
  /// O pedido de PIN do responsável veio do espaço infantil («Área do Responsável»), e não
  /// do arranque/bloqueio com o perfil Responsável como último perfil usado.
  bool parentRequestFromChild = false;
  bool enteringChildMode = false;
  bool parentViewReady = false;
  String? childModeFamilyId;
  bool modeLoaded = false;
  final familyRequestId = newRequestId();
  List<Family> families = [];
  Family? selectedFamily;
  List<ChildProfile> children = [];
  ChildProfile? savedChild;
  ChildProfile? editingChild;
  bool loading = true;
  bool editing = false;
  bool exiting = false;
  String? error;

  @override
  void initState() {
    super.initState();
    parentAccess = ParentAccessService(widget.auth.client);
    parentAccess.addListener(parentAccessChanged);
    service = FamilyService(widget.auth.client, parentToken: () => parentAccess.token, onParentLocked: parentAccess.forget);
    childSessions = ChildSessionService(widget.auth.client);
    pendingReviews=PendingReviewsService(widget.auth.client,parentToken:()=>parentAccess.token,onParentLocked:parentAccess.forget);
    progressService = ChildProgressService(widget.auth.client,parentToken:()=>parentAccess.token,onParentLocked:parentAccess.forget);
    worksheets = WorksheetService(widget.auth.client,parentToken:()=>parentAccess.token,onParentLocked:parentAccess.forget);
    billing = BillingService(widget.auth.client, parentToken: () => parentAccess.token, onParentLocked: parentAccess.forget);
    initializeWorkspace();
  }

  @override
  void dispose() {parentAccess.removeListener(parentAccessChanged); parentAccess.dispose(); childSessions.dispose(); super.dispose();}

  void parentAccessChanged() {
    if (!mounted) return;
    setState(() {
      if (!parentAccess.unlocked) {
        parentViewReady = false; preparing = false; reviewingAttemptId = null; progressChildId = null; editingChild = null;
        if (childModeFamilyId == null && returnFamilyId != null) {
          childModeFamilyId = returnFamilyId;
          // Bloqueio da área do responsável: o último perfil continua a ser «Responsável»,
          // por isso volta a pedir o PIN do responsável (com opção de alterar perfil).
          if (!enteringChildMode) {requestingParent = true; parentRequestFromChild = false;}
          ChildModeStore.enter(widget.auth.user!.id, returnFamilyId!).catchError((Object _) {
            // Reload still requires a fresh parental PIN if this preference cannot be saved.
          });
        }
      }
    });
  }

  Future<void> openParents() async {
    await childSessions.endSession();
    if (!mounted || !parentAccess.unlocked) return;
    setState(() {
      returnFamilyId = childModeFamilyId ?? selectedFamily?.id;
      childModeFamilyId = null; requestingParent = false; parentViewReady = true;
      savedChild = null; editing = false; editingChild = null; preparing = false; reviewingAttemptId = null; progressChildId = null;
    });
    await load(familyId: returnFamilyId);
    LastProfileStore.remember(widget.auth.user!.id, LastProfile.parent(selectedFamily?.id ?? returnFamilyId));
  }

  void childSignedIn(ChildProfile child) {
    preferredChildId = child.id;
    LastProfileStore.remember(widget.auth.user!.id, LastProfile.child(child.familyId, child.id));
  }

  Future<void> cancelParentUnlock() async {
    await parentAccess.lock();
    if (mounted) setState(() => requestingParent = false);
  }

  Future<void> initializeWorkspace() async {
    setState(() {loading = true; error = null;});
    try {
      final adultId = widget.auth.user!.id;
      final stored = await ChildModeStore.read(adultId);
      final last = await LastProfileStore.read(adultId);
      if (!mounted) return;
      // Pede sempre o PIN do último perfil usado neste dispositivo: o teclado da
      // criança (já selecionada) ou o PIN do responsável por cima do seletor de perfis.
      final familyId = stored ?? last?.familyId;
      setState(() {
        childModeFamilyId = familyId; returnFamilyId = familyId;
        preferredChildId = last?.childId;
        requestingParent = familyId != null && (last?.isParent ?? false);
        parentRequestFromChild = false;
        modeLoaded = true; loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {loading = false; error = 'Não foi possível recuperar o modo de acesso deste dispositivo.';});
    }
  }

  Future<void> enterChildMode() async {
    final family = selectedFamily;
    if (family == null || exiting) return;
    setState(() {exiting = true; error = null;});
    try {
      final adultId = widget.auth.user!.id;
      await ChildModeStore.enter(adultId, family.id);
      returnFamilyId = family.id;
      // O espaço infantil abre com a criança indicada (ou a primeira) já selecionada.
      final childId = preferredChildId ?? (children.isEmpty ? null : children.first.id);
      if (childId != null) await LastProfileStore.remember(adultId, LastProfile.child(family.id, childId));
      enteringChildMode = true;
      try {await parentAccess.lock();} finally {enteringChildMode = false;}
      if (mounted) setState(() {childModeFamilyId = family.id; requestingParent = false;});
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível abrir o espaço infantil. Tenta novamente.');
    } finally {if (mounted) setState(() => exiting = false);}
  }

  Future<void> enterAsChild(String childId) async {
    setState(() => preferredChildId = childId);
    await enterChildMode();
  }

  Future<void> exitChildDevice() async {
    final adultId = widget.auth.user!.id;
    await parentAccess.lock();
    await widget.auth.signOut();
    await ChildModeStore.clear(adultId);
  }

  Future<void> load({Family? family, String? familyId}) async {
    setState(() {loading = true; error = null;});
    try {
      final available = await service.listFamilies();
      final wantedId = family?.id ?? familyId ?? selectedFamily?.id;
      Family? selected;
      if (wantedId != null) {
        for (final item in available) {if (item.id == wantedId) selected = item;}
      } else if (available.length == 1) {selected = available.first;}
      final profiles = selected == null ? <ChildProfile>[] : await service.listChildren(selected.id);
      if (!mounted) return;
      setState(() {
        families = available; selectedFamily = selected; children = profiles;
        editing = available.isEmpty || (selected != null && profiles.isEmpty);
        if (selected != null && profiles.isNotEmpty) returnFamilyId = selected.id;
      });
      if (!billingHandled && selected != null && billingReturn['billing'] != null) {
        billingHandled = true;
        handleBillingReturn();
      }
    } on FamilyException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível carregar a tua família. Tenta novamente.');
    } finally {if (mounted) setState(() => loading = false);}
  }

  /// Pagamento Web (Stripe Checkout). Nas apps móveis o pagamento chega com as lojas (Fases 5–6).
  PremiumSubscribe? subscribeFor(String childId) => !kIsWeb ? null : () async {
    try {
      final url = await billing.checkoutUrl(childId);
      if (!await launchUrl(url, webOnlyWindowName: '_self')) return 'Não foi possível abrir o pagamento.';
      return null;
    } on BillingException catch (failure) {
      if (failure.code == 'CHILD_ALREADY_PREMIUM') load();
      return failure.message;
    }
  };

  Future<void> manageSubscription() async {
    final family = selectedFamily;
    if (family == null) return;
    try {
      final url = await billing.portalUrl(family.id);
      if (!await launchUrl(url, webOnlyWindowName: '_self')) throw const BillingException('Não foi possível abrir a gestão da subscrição.');
    } on BillingException catch (failure) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  /// O Premium é ativado pelo webhook do Stripe: depois do pagamento, aguardamos a confirmação.
  Future<void> handleBillingReturn() async {
    final kind = billingReturn['billing'], childId = billingReturn['child'];
    final messenger = ScaffoldMessenger.of(context);
    String name() => children.where((c) => c.id == childId).firstOrNull?.displayName ?? 'a criança';
    if (kind == 'cancel') {
      messenger.showSnackBar(const SnackBar(content: Text('Pagamento cancelado. Não foi cobrado nada.')));
      return;
    }
    if (kind != 'success' || childId == null) return;
    messenger.showSnackBar(SnackBar(duration: const Duration(seconds: 30),
      content: Text('Pagamento recebido! A ativar o Premium de ${name()}…')));
    for (var i = 0; i < 10 && !children.any((c) => c.id == childId && c.isPremium); i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final family = selectedFamily;
      if (!mounted || family == null) return;
      try {
        final profiles = await service.listChildren(family.id);
        if (mounted) setState(() => children = profiles);
      } catch (_) {/* tenta de novo */}
    }
    if (!mounted) return;
    final active = children.any((c) => c.id == childId && c.isPremium);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(active
      ? 'Premium ativo para ${name()} 🎉'
      : 'O pagamento foi recebido. O Premium fica ativo dentro de instantes — atualiza a página daqui a pouco.')));
  }

  String shortDate(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  /// Estado da assinatura no cartão da criança (só Premium).
  String? subscriptionText(ChildProfile child) {
    final sub = child.subscription;
    if (!child.isPremium || sub == null) return null;
    final end = sub.currentPeriodEnd;
    return sub.inGrace
      ? 'Pagamento em atraso — atualiza o cartão para manter o Premium.'
      : !sub.isStripe
        ? (end == null ? 'Premium oferecido.' : 'Premium oferecido até ${shortDate(end)}.')
        : sub.autoRenew
          ? (end == null ? 'Subscrição ativa.' : 'Renova a ${shortDate(end)} • $premiumPriceLabel')
          : (end == null ? 'Subscrição cancelada.' : 'Cancelada — Premium até ${shortDate(end)}.');
  }

  List<Widget> subscriptionInfo(ChildProfile child) {
    final text = subscriptionText(child);
    if (text == null) return const [];
    return [
      const SizedBox(height: 12),
      Text(text, style: TextStyle(fontSize: 14,
        color: child.subscription!.inGrace ? AppColors.error : AppColors.muted)),
    ];
  }

  /// Detalhe da assinatura de uma criança (menu ⋮ → Ver assinatura).
  void showSubscriptionSheet(ChildProfile child) {
    final sub = child.subscription;
    final planLabel = child.isPremium ? 'Premium' : child.plan == 'free' ? 'Gratuito' : 'Sem plano ativo';
    final origin = switch (sub?.channel) {
      'stripe' => 'Cartão (pagamento web)',
      'google_play' => 'Google Play',
      'app_store' => 'App Store',
      'manual' => 'Oferta da Escola em Dia',
      _ => null,
    };
    Widget row(String label, String value) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppColors.muted))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text))),
      ]));
    showModalBottomSheet<void>(
      context: context, showDragHandle: true, isScrollControlled: true, backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Flexible(child: Text('Assinatura de ${child.displayName}', style: Theme.of(context).textTheme.titleLarge)),
            PremiumCrown(isPremium: child.isPremium, size: 24),
          ]),
          const SizedBox(height: 18),
          row('Plano', planLabel),
          if (origin != null) row('Origem', origin),
          if (subscriptionText(child) case final text?) row('Estado', text),
          if (!child.isPremium) row('Inclui', child.plan == 'free'
            ? '1 ficha por dia e catálogo Free.'
            : 'A vaga gratuita da família está ocupada por outra criança.'),
          const SizedBox(height: 8),
          if (sub != null && sub.isStripe && kIsWeb)
            AppButton(label: 'Gerir assinatura', icon: Icons.credit_card_rounded, variant: AppButtonVariant.secondary,
              onPressed: () {Navigator.pop(sheetContext); manageSubscription();}),
          if (sub != null && sub.isStripe && kIsWeb) const Padding(padding: EdgeInsets.only(top: 8),
            child: Text('Cancelar, trocar o cartão ou ver faturas.', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted))),
          if (sub != null && (sub.channel == 'google_play' || sub.channel == 'app_store'))
            Text('Esta assinatura é gerida na ${origin!}.', textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted)),
          if (!child.isPremium)
            AppButton(label: 'Ativar Premium', icon: Icons.workspace_premium_rounded, variant: AppButtonVariant.success,
              onPressed: () {
                Navigator.pop(sheetContext);
                showPremiumPaywall(context, childName: child.displayName,
                  reason: child.plan == 'locked' ? PaywallReason.locked : PaywallReason.general,
                  onSubscribe: subscribeFor(child.id));
              }),
        ]),
      )),
    );
  }

  Future<ChildProfile> save(ChildProfileDraft draft) async {
    var family = selectedFamily;
    if (family == null) {
      family = await service.createFamily(familyRequestId);
      if (!mounted) throw const FamilyException('Volta a entrar para continuar.');
      // Keep the family ID on a failed child request so retrying cannot create another family.
      selectedFamily = family;
      families = [family];
    }
    return service.createChild(family.id, draft);
  }

  Set<String> get premiumChildIds => {for (final c in children) if (c.isPremium) c.id};

  void profileSaved(ChildProfile child) => setState(() {
    children = [...children.where((item) => item.id != child.id), child];
    editing = false; savedChild = child; error = null; returnFamilyId = child.familyId;
  });

  void profileUpdated(ChildProfile child) => setState(() {
    children = [for (final item in children) item.id == child.id ? child.withPlanFrom(item) : item];
    editingChild = null; error = null;
  });

  Future<void> signOut() async {
    if (exiting) return;
    setState(() {exiting = true; error = null;});
    try {await parentAccess.lock(); await widget.auth.signOut();}
    catch (_) {if (mounted) setState(() => error = 'Não foi possível sair da conta. Tenta novamente.');}
    finally {if (mounted) setState(() => exiting = false);}
  }

  Widget exitButton() => AppButton(label: 'Sair da conta', variant: AppButtonVariant.secondary,
    loading: exiting, onPressed: exiting ? null : signOut);

  @override
  Widget build(BuildContext context) => ParentActivityBoundary(access: parentAccess, child: buildWorkspace(context));

  Widget buildWorkspace(BuildContext context) {
    if (loading) return const AppSplash(message: 'A carregar a família');
    if (childModeFamilyId != null) return Stack(children: [
      Offstage(offstage: requestingParent, child: ChildEntryPage(
        key: ValueKey(childModeFamilyId), familyId: childModeFamilyId!, initialChildId: preferredChildId,
        families: service, sessions: childSessions, onExitDevice: exitChildDevice,
        onChildSignedIn: childSignedIn,
        onOpenParents: () {FocusScope.of(context).unfocus(); setState(() {requestingParent = true; parentRequestFromChild = true;});},
      )),
      if (requestingParent) Positioned.fill(child: ParentUnlockPage(
        access: parentAccess, onUnlocked: openParents, onExit: exitChildDevice,
        onCancel: cancelParentUnlock,
        cancelLabel: parentRequestFromChild ? 'Voltar ao espaço infantil' : 'Alterar perfil',
      )),
    ]);
    if (modeLoaded && (!parentAccess.unlocked || !parentViewReady)) return ParentUnlockPage(
      access: parentAccess, onUnlocked: openParents, onExit: signOut,
    );
    if (error != null) return AppPage(title: 'Vamos tentar outra vez?', subtitle: error!, children: [
      AppButton(label: 'Tentar novamente', onPressed: exiting ? null : () {if (modeLoaded) {load();} else {initializeWorkspace();}}),
      const SizedBox(height: 16), exitButton(),
    ]);
    if (reviewingAttemptId != null) return ParentReviewPage(
      key: ValueKey(reviewingAttemptId), attemptId: reviewingAttemptId!, service: pendingReviews, premiumChildIds: premiumChildIds,
      onClose: () => setState(() => reviewingAttemptId = null),
      onPrepareWorksheet: children.isEmpty ? null : () => setState(() {reviewingAttemptId = null; progressChildId = null; preparing = true;}),
    );
    if (progressChildId != null) return ChildProgressPage(
      key: ValueKey(progressChildId), childId: progressChildId!, service: progressService, isPremium: premiumChildIds.contains(progressChildId),
      onClose: () => setState(() { progressChildId = null; }),
      onReview: (attemptId) => setState(() { reviewingAttemptId = attemptId; }),
    );
    if (preparing) return PrepareWorksheetPage(children: List<ChildProfile>.unmodifiable(children),service:worksheets,
      subscribeFor: subscribeFor,
      onClose:()=>setState(()=>preparing=false),onViewChild:(childId) async {
        setState((){preferredChildId=childId;preparing=false;});
        await enterChildMode();
      });
    if (editingChild != null) return ChildProfilePage.edit(
      key: ValueKey('edit-${editingChild!.id}'), child: editingChild!,
      onUpdate: (update) => service.updateChild(editingChild!, update),
      onSaved: profileUpdated,
      onBack: () => setState(() => editingChild = null),
    );
    if (savedChild != null) return readyPage(savedChild!);
    if (editing) return ChildProfilePage(
      onSave: save, onSaved: profileSaved,
      onBack: children.isNotEmpty
          ? () => setState(() => editing = false)
          : exiting ? null : signOut,
    );
    if (selectedFamily == null) return AppPage(
      title: 'Escolhe a tua família', subtitle: 'Em que família queres gerir os perfis?',
      children: [
        for (var i = 0; i < families.length; i++) Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: AppButton(label: 'Família ${i + 1} • criada em ${date(families[i].createdAt)}',
            variant: AppButtonVariant.secondary, icon: Icons.family_restroom_rounded,
            onPressed: () => load(family: families[i])),
        ),
        const SizedBox(height: 16), exitButton(),
      ],
    );
    return ParentShell(
      tab: parentTab,
      onTabChanged: (tab) => setState(() => parentTab = tab),
      pendingCount: pendingCount,
      busy: exiting,
      onLock: () => parentAccess.lock(),
      onSignOut: signOut,
      onOpenLegal: () => LegalDocumentsPage.open(context, LegalService(widget.auth.client)),
      dashboard: ParentDashboard(
        key: ValueKey(selectedFamily!.id),
        familyId: selectedFamily!.id,
        children: List<ChildProfile>.unmodifiable(children),
        service: pendingReviews,
        onReview: (attemptId) => setState(() => reviewingAttemptId = attemptId),
        onEnterChild: enterAsChild,
        busy: exiting,
        onPendingCount: (count) { if (mounted && count != pendingCount) setState(() => pendingCount = count); },
      ),
      worksheets: worksheetsTab(),
      family: familyTab(),
    );
  }

  Widget tabList(List<Widget> items) => ListView(
    padding: EdgeInsets.fromLTRB(MediaQuery.sizeOf(context).width < 640 ? 16 : 32, 24,
      MediaQuery.sizeOf(context).width < 640 ? 16 : 32, 32),
    children: items,
  );

  Widget worksheetsTab() => tabList([
    AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const CircleAvatar(radius: 32, backgroundColor: AppColors.lavender,
        child: Icon(Icons.auto_stories_rounded, color: AppColors.primary, size: 32)),
      const SizedBox(height: 16),
      Text('Preparar uma nova ficha', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Escolhe a criança, a disciplina e os temas. A ficha fica disponível no espaço infantil.',
        textAlign: TextAlign.center),
      const SizedBox(height: 24),
      AppButton(label: 'Preparar ficha', icon: Icons.add_rounded,
        onPressed: exiting || children.isEmpty ? null : () => setState(() => preparing = true)),
    ])),
    const SizedBox(height: 20),
    AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Hora de estudar?', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      const Text('Entrega o dispositivo à criança. A área do responsável volta a pedir o PIN.'),
      const SizedBox(height: 20),
      AppButton(label: 'Entrar no espaço infantil', icon: Icons.rocket_launch_rounded,
        variant: AppButtonVariant.secondary, loading: exiting, onPressed: exiting ? null : enterChildMode),
    ])),
  ]);

  /// Cartão de uma criança no separador Família.
  Widget childCard(ChildProfile child) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ExcludeSemantics(child: Text(ChildAvatars.emoji(child.avatarId), style: const TextStyle(fontSize: 48))),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(child.displayName, style: Theme.of(context).textTheme.titleLarge)),
                PremiumCrown(isPremium: child.isPremium, size: 24),
              ]),
              const SizedBox(height: 6),
              Text('${child.schoolYear}.º Ano • ${ChildAvatars.label(child.avatarId)}'),
            ])),
            PopupMenuButton<String>(
              tooltip: 'Mais opções de ${child.displayName}',
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.muted),
              enabled: !exiting,
              onSelected: (action) {
                if (action == 'edit') setState(() => editingChild = child);
                if (action == 'subscription') showSubscriptionSheet(child);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Editar perfil'))),
                PopupMenuItem(value: 'subscription', child: ListTile(leading: Icon(Icons.workspace_premium_rounded), title: Text('Ver assinatura'))),
              ],
            ),
          ]),
          const SizedBox(height: 18),
          Wrap(spacing: 8, runSpacing: 8, children: [
            const AppBadge(label: 'PIN definido', icon: Icons.lock_outline_rounded),
            if (child.plan == 'locked') const AppBadge(label: 'Sem plano ativo', icon: Icons.lock_clock_rounded,
              background: Color(0xFFFFF3CC), color: AppColors.amber),
          ]),
          if (child.plan == 'locked') ...[
            const SizedBox(height: 12),
            AppButton(label: 'Ativar Premium', icon: Icons.workspace_premium_rounded, variant: AppButtonVariant.success,
              onPressed: () => showPremiumPaywall(context, childName: child.displayName, reason: PaywallReason.locked,
                onSubscribe: subscribeFor(child.id))),
          ],
          // Criança Free: oferta discreta, sempre disponível (não só quando bate no limite).
          if (child.plan == 'free') ...[
            const SizedBox(height: 12),
            AppButton(label: 'Passar a Premium', icon: Icons.workspace_premium_rounded, variant: AppButtonVariant.neutral,
              onPressed: () => showPremiumPaywall(context, childName: child.displayName, reason: PaywallReason.general,
                onSubscribe: subscribeFor(child.id))),
          ],
          ...subscriptionInfo(child),
          const Spacer(),
          const SizedBox(height: 18),
          AppButton(label: 'Ver acompanhamento', variant: AppButtonVariant.secondary,
            icon: Icons.insights_rounded, onPressed: () => setState(() { progressChildId = child.id; })),
          const SizedBox(height: 12),
          AppButton(label: 'Entrar como ${child.displayName}', variant: AppButtonVariant.success,
            icon: Icons.rocket_launch_rounded, loading: exiting,
            onPressed: exiting ? null : () => enterAsChild(child.id)),
  ]));

  Widget familyTab() => tabList([
    LayoutBuilder(builder: (context, constraints) {
      // Web/ecrãs largos: grelha (até 3 colunas); telemóvel: um cartão por baixo do outro.
      final columns = constraints.maxWidth >= 1000 ? 3 : constraints.maxWidth >= 640 ? 2 : 1;
      // Linhas da grelha: todos os cartões de uma linha ficam com a altura do mais alto
      // (IntrinsicHeight + stretch) e os botões principais alinham-se no fundo (Spacer).
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var start = 0; start < children.length; start += columns) Padding(
          padding: EdgeInsets.only(top: start == 0 ? 0 : 20),
          child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = start; i < start + columns; i++) ...[
              if (i > start) const SizedBox(width: 20),
              Expanded(child: i < children.length ? childCard(children[i]) : const SizedBox.shrink()),
            ],
          ])),
        ),
      ]);
    }),
    const SizedBox(height: 28),
    AppButton(label: 'Adicionar criança', icon: Icons.person_add_alt_1_rounded,
      onPressed: () => setState(() => editing = true)),
    if (families.length > 1) ...[
      const SizedBox(height: 16),
      AppButton(label: 'Mudar de família', variant: AppButtonVariant.secondary,
        onPressed: () => setState(() {selectedFamily = null; children = [];})),
    ],
    const SizedBox(height: 16), exitButton(),
  ]);

  Widget readyPage(ChildProfile child) => AppPage(
    title: 'Tudo a postos para começar!',
    subtitle: 'O perfil de ${child.displayName} já está guardado na tua família.',
    children: [
      const Wrap(children: [AppBadge(label: 'Passo 4 de 4 • Finalização', icon: Icons.check_circle_outline_rounded)]),
      const SizedBox(height: 24),
      AppCard(child: Column(children: [
        const Icon(Icons.celebration_rounded, color: AppColors.primary, size: 64),
        const SizedBox(height: 20),
        ExcludeSemantics(child: Text(ChildAvatars.emoji(child.avatarId), style: const TextStyle(fontSize: 64))),
        const SizedBox(height: 12),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(child.displayName, style: Theme.of(context).textTheme.headlineMedium)),
          PremiumCrown(isPremium: child.isPremium, size: 28),
        ]),
        const SizedBox(height: 8), Text('${child.schoolYear}.º Ano • PIN infantil definido'),
      ])),
      const SizedBox(height: 24),
      AppButton(label: 'Preparar a primeira ficha',icon:Icons.auto_stories_rounded,
        onPressed:exiting?null:()=>setState((){savedChild=null;preparing=true;})),
      const SizedBox(height:16),
      AppButton(label: 'Entrar no espaço infantil', icon: Icons.rocket_launch_rounded,
        loading: exiting, onPressed: exiting ? null : enterChildMode),
      const SizedBox(height: 16),
      AppButton(label: 'Ver perfis da família', icon: Icons.family_restroom_rounded,
        onPressed: () => setState(() => savedChild = null)),
      const SizedBox(height: 16),
      AppButton(label: 'Adicionar outra criança', variant: AppButtonVariant.secondary,
        icon: Icons.person_add_alt_1_rounded,
        onPressed: () => setState(() {savedChild = null; editing = true;})),
      const SizedBox(height: 16), exitButton(),
    ],
  );

  String date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
