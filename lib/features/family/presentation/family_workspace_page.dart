import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/request_id.dart';
import '../../../shared/widgets/app_badge.dart';
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
  bool preparing = false;
  ParentTab parentTab = ParentTab.dashboard;
  int pendingCount = 0;
  String? reviewingAttemptId;
  String? progressChildId;
  String? preferredChildId;
  String? returnFamilyId;
  bool requestingParent = false;
  bool parentViewReady = false;
  String? childModeFamilyId;
  bool modeLoaded = false;
  final familyRequestId = newRequestId();
  List<Family> families = [];
  Family? selectedFamily;
  List<ChildProfile> children = [];
  ChildProfile? savedChild;
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
    initializeWorkspace();
  }

  @override
  void dispose() {parentAccess.removeListener(parentAccessChanged); parentAccess.dispose(); childSessions.dispose(); super.dispose();}

  void parentAccessChanged() {
    if (!mounted) return;
    setState(() {
      if (!parentAccess.unlocked) {
        parentViewReady = false; preparing = false; reviewingAttemptId = null; progressChildId = null;
        if (childModeFamilyId == null && returnFamilyId != null) {
          childModeFamilyId = returnFamilyId;
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
      savedChild = null; editing = false; preparing = false; reviewingAttemptId = null; progressChildId = null;
    });
    await load(familyId: returnFamilyId);
  }

  Future<void> cancelParentUnlock() async {
    await parentAccess.lock();
    if (mounted) setState(() => requestingParent = false);
  }

  Future<void> initializeWorkspace() async {
    setState(() {loading = true; error = null;});
    try {
      final stored = await ChildModeStore.read(widget.auth.user!.id);
      if (!mounted) return;
      setState(() {childModeFamilyId = stored; returnFamilyId = stored; modeLoaded = true; loading = false;});
    } catch (_) {
      if (mounted) setState(() {loading = false; error = 'Não foi possível recuperar o modo de acesso deste dispositivo.';});
    }
  }

  Future<void> enterChildMode() async {
    final family = selectedFamily;
    if (family == null || exiting) return;
    setState(() {exiting = true; error = null;});
    try {
      await ChildModeStore.enter(widget.auth.user!.id, family.id);
      returnFamilyId = family.id;
      await parentAccess.lock();
      if (mounted) setState(() => childModeFamilyId = family.id);
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
    } on FamilyException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível carregar a tua família. Tenta novamente.');
    } finally {if (mounted) setState(() => loading = false);}
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

  void profileSaved(ChildProfile child) => setState(() {
    children = [...children.where((item) => item.id != child.id), child];
    editing = false; savedChild = child; error = null; returnFamilyId = child.familyId;
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
        onOpenParents: () {FocusScope.of(context).unfocus(); setState(() => requestingParent = true);},
      )),
      if (requestingParent) Positioned.fill(child: ParentUnlockPage(
        access: parentAccess, onUnlocked: openParents, onExit: exitChildDevice,
        onCancel: cancelParentUnlock,
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
      key: ValueKey(reviewingAttemptId), attemptId: reviewingAttemptId!, service: pendingReviews,
      onClose: () => setState(() => reviewingAttemptId = null),
    );
    if (progressChildId != null) return ChildProgressPage(
      key: ValueKey(progressChildId), childId: progressChildId!, service: progressService,
      onClose: () => setState(() { progressChildId = null; }),
      onReview: (attemptId) => setState(() { reviewingAttemptId = attemptId; }),
    );
    if (preparing) return PrepareWorksheetPage(children: List<ChildProfile>.unmodifiable(children),service:worksheets,
      onClose:()=>setState(()=>preparing=false),onViewChild:(childId) async {
        setState((){preferredChildId=childId;preparing=false;});
        await enterChildMode();
      });
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
      const Text('Entrega o dispositivo à criança. A área dos pais volta a pedir o PIN.'),
      const SizedBox(height: 20),
      AppButton(label: 'Entrar no espaço infantil', icon: Icons.rocket_launch_rounded,
        variant: AppButtonVariant.secondary, loading: exiting, onPressed: exiting ? null : enterChildMode),
    ])),
  ]);

  Widget familyTab() => tabList([
    LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth >= 700 ? (constraints.maxWidth - 20) / 2 : constraints.maxWidth;
      return Wrap(spacing: 20, runSpacing: 20, children: [for (final child in children)
        SizedBox(width: width, child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ExcludeSemantics(child: Text(ChildAvatars.emoji(child.avatarId), style: const TextStyle(fontSize: 48))),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(child.displayName, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('${child.schoolYear}.º Ano • ${ChildAvatars.label(child.avatarId)}'),
            ])),
          ]),
          const SizedBox(height: 18),
          const AppBadge(label: 'PIN definido', icon: Icons.lock_outline_rounded),
          const SizedBox(height: 18),
          AppButton(label: 'Ver acompanhamento', variant: AppButtonVariant.secondary,
            icon: Icons.insights_rounded, onPressed: () => setState(() { progressChildId = child.id; })),
          const SizedBox(height: 12),
          AppButton(label: 'Entrar como ${child.displayName}', variant: AppButtonVariant.success,
            icon: Icons.rocket_launch_rounded, loading: exiting,
            onPressed: exiting ? null : () => enterAsChild(child.id)),
        ]))),
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
        Text(child.displayName, style: Theme.of(context).textTheme.headlineMedium),
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
