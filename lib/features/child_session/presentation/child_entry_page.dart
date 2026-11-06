import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/pin/app_pin_input.dart';
import '../../family/data/family_service.dart';
import '../../family/domain/family_models.dart';
import '../data/child_session_service.dart';
import '../../attempts/presentation/worksheet_attempt_page.dart';
import '../../attempts/presentation/child_feedback_page.dart';
import '../../attempts/data/attempt_service.dart';
import '../../attempts/presentation/widgets/repeat_worksheet_confirmation.dart';
import '../../worksheets/domain/worksheet_models.dart';
import '../../worksheets/presentation/widgets/assigned_worksheet_card.dart';

class ChildEntryPage extends StatefulWidget {
  const ChildEntryPage({super.key, required this.familyId, required this.families, required this.sessions, required this.onExitDevice, required this.onOpenParents, this.initialChildId, this.onChildSignedIn});
  final String familyId;
  final String? initialChildId;
  final FamilyService families;
  final ChildSessionService sessions;
  final Future<void> Function() onExitDevice;
  final VoidCallback onOpenParents;
  /// Chamado após o PIN correto, para lembrar este perfil no dispositivo.
  final ValueChanged<ChildProfile>? onChildSignedIn;

  @override
  State<ChildEntryPage> createState() => _ChildEntryPageState();
}

class _ChildEntryPageState extends State<ChildEntryPage> with WidgetsBindingObserver {
  List<ChildProfile> children = [];
  ChildProfile? selected;
  ChildProfile? authenticated;
  bool loading = true;
  bool busy = false;
  String? error;
  String pin = '';
  int inputVersion = 0;
  DateTime? blockedUntil;
  Timer? ticker;
  Timer? expiry;
  Future<List<AssignedWorksheet>>? assignedWorksheets;
  String? feedbackAttemptId;
  AssignedWorksheet? activeAssignment;
  AssignedWorksheet? repeatCandidate;
  String? repeatFromAttemptId;
  int childTab = 0;

  @override
  void initState() {super.initState(); WidgetsBinding.instance.addObserver(this); load();}

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel(); expiry?.cancel(); pin = '';
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && authenticated != null && !busy) validateSession();
  }

  int get waitSeconds {
    final seconds = blockedUntil?.difference(DateTime.now()).inSeconds ?? 0;
    return seconds > 0 ? seconds + 1 : 0;
  }

  Future<void> load() async {
    setState(() {loading = true; error = null;});
    try {
      final profiles = await widget.families.listChildren(widget.familyId);
      if (mounted) setState(() {
        children=profiles;selected=profiles.isEmpty?null:profiles.first;
        for(final profile in profiles){if(profile.id==widget.initialChildId)selected=profile;}
      });
    } on FamilyException catch (failure) {if (mounted) setState(() => error = failure.message);}
    catch (_) {if (mounted) setState(() => error = 'Não foi possível carregar os perfis.');}
    finally {if (mounted) setState(() => loading = false);}
  }

  void choose(ChildProfile child) {
    if (busy) return;
    ticker?.cancel();
    setState(() {selected = child; pin = ''; inputVersion++; error = null; blockedUntil = null;});
  }

  Future<void> login() async {
    if (busy || waitSeconds > 0 || pin.length != 4 || selected == null) return;
    setState(() {busy = true; error = null;});
    FocusScope.of(context).unfocus();
    try {
      final child = await widget.sessions.login(selected!.id, pin);
      if (!mounted) return;
      widget.onChildSignedIn?.call(child);
      setState(() {authenticated = child; childTab = 0; activeAssignment=null;feedbackAttemptId=null;repeatCandidate=null;repeatFromAttemptId=null; pin = ''; inputVersion++; assignedWorksheets=fetchAssignments(child.id);});
      scheduleExpiry();
    } on ChildSessionException catch (failure) {
      if (!mounted) return;
      setState(() {
        error = failure.message; pin = ''; inputVersion++;
        if (failure.retryAfter != null) blockedUntil = DateTime.now().add(Duration(seconds: failure.retryAfter!));
      });
      if (failure.retryAfter != null) {
        ticker?.cancel();
        ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {timer.cancel(); return;}
          setState(() {});
          if (waitSeconds == 0) timer.cancel();
        });
      }
    } finally {if (mounted) setState(() => busy = false);}
  }

  void scheduleExpiry() {
    expiry?.cancel();
    final remaining = widget.sessions.expiresAt?.difference(DateTime.now()) ?? Duration.zero;
    expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      widget.sessions.forgetExpired();
      if (mounted) setState(() {authenticated = null; activeAssignment=null;feedbackAttemptId=null;repeatCandidate=null;repeatFromAttemptId=null; error = 'A tua sessão terminou. Introduz o PIN para continuar.';});
    });
  }

  Future<void> validateSession() async {
    setState(() {busy = true; error = null;});
    try {
      final child = await widget.sessions.profile();
      if (mounted) {setState(() {authenticated=child;assignedWorksheets=fetchAssignments(child.id);}); scheduleExpiry();}
    } on ChildSessionException catch (failure) {
      if (mounted) setState(() {error = failure.message; if (failure.ended) {authenticated = null; activeAssignment=null;feedbackAttemptId=null;repeatCandidate=null;repeatFromAttemptId=null;}});
    } finally {if (mounted) setState(() => busy = false);}
  }

  Future<List<AssignedWorksheet>> fetchAssignments(String childId) async {
    try {return await widget.sessions.assignments(childId);}
    on ChildSessionException catch(failure){
      if(failure.ended && mounted && authenticated?.id==childId)setState((){authenticated=null;activeAssignment=null;feedbackAttemptId=null;repeatCandidate=null;repeatFromAttemptId=null;});
      rethrow;
    }
  }

  Widget assignmentsSection(ChildProfile child)=>FutureBuilder<List<AssignedWorksheet>>(
    future:assignedWorksheets,
    builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator(semanticsLabel:'A carregar as tuas fichas'));
      if(snapshot.hasError){
        final failure=snapshot.error;
        return AppCard(child:Column(children:[
          Text(failure is ChildSessionException?failure.message:'Não foi possível carregar as tuas fichas.'),
          const SizedBox(height:16),
          AppButton(label:'Tentar novamente',onPressed:busy?null:()=>setState((){assignedWorksheets=fetchAssignments(child.id);})),
        ]));
      }
      final items=snapshot.data??[];
      if(items.isEmpty)return const AppCard(child:Column(children:[
        Icon(Icons.menu_book_rounded,size:56,color:AppColors.primary),SizedBox(height:18),
        Text('Ainda não tens fichas para fazer.',textAlign:TextAlign.center,style:TextStyle(fontSize:20,fontWeight:FontWeight.w700)),
        SizedBox(height:10),Text('Quando o teu responsável preparar uma ficha, ela vai aparecer aqui.',textAlign:TextAlign.center),
      ]));
      Widget card(AssignedWorksheet item,{bool featured=false})=>Padding(padding:const EdgeInsets.only(bottom:16),
        child:(featured?AssignedWorksheetCard.new:AssignedWorksheetTile.new)(assignment:item,onStart:busy?null:()=>openAssignment(item),
          onRepeat:busy||!item.canRepeat?null:()=>prepareRepeat(item,item.latestAttemptId!),
          onViewFeedback:busy?null:()=>showFeedback(item)));
      final todo=items.where((item)=>item.stage==AssignmentStage.todo).toList();
      final paused=items.where((item)=>item.stage==AssignmentStage.paused).toList();
      final delivered=items.where((item)=>item.stage==AssignmentStage.delivered).toList();
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        for(final item in todo)card(item,featured:true),
        if(paused.isNotEmpty)...[
          if(todo.isNotEmpty)const SizedBox(height:12),
          const _SectionLabel(icon:Icons.pause_circle_outline_rounded,label:'Em pausa'),
          for(final item in paused)card(item),
        ],
        if(delivered.isNotEmpty)...[
          const SizedBox(height:12),
          const _SectionLabel(icon:Icons.task_alt_rounded,label:'Já entregues'),
          for(final item in delivered)card(item),
        ],
      ]);
    },
  );

  void showFeedback(AssignedWorksheet assignment) {
    if(busy||authenticated?.id!=assignment.childId||assignment.latestCompletedAttemptId==null)return;
    setState(() {
      activeAssignment=null;repeatCandidate=null;repeatFromAttemptId=null;
      feedbackAttemptId=assignment.latestCompletedAttemptId;
    });
  }
  void openAssignment(AssignedWorksheet assignment) {
    if(busy||authenticated?.id!=assignment.childId)return;
    setState(() { activeAssignment=assignment;feedbackAttemptId=null;repeatCandidate=null;repeatFromAttemptId=null; });
  }
  void prepareRepeat(AssignedWorksheet assignment,String previousId) {
    if(busy||authenticated?.id!=assignment.childId)return;
    setState(() { activeAssignment=null;feedbackAttemptId=null;repeatCandidate=assignment;repeatFromAttemptId=previousId; });
  }
  void beginRepeat() {
    final candidate=repeatCandidate;
    if(candidate==null||repeatFromAttemptId==null||authenticated?.id!=candidate.childId)return;
    setState(() { activeAssignment=candidate;feedbackAttemptId=null;repeatCandidate=null; });
  }
  void cancelRepeat() {
    setState(() {
      repeatCandidate=null;repeatFromAttemptId=null;
      if(authenticated!=null)assignedWorksheets=fetchAssignments(authenticated!.id);
    });
  }

  Future<void> changeUser() async {
    if (busy) return;
    setState(() {busy = true; error = null;});
    try {
      await widget.sessions.endSession();
      expiry?.cancel();
      if (mounted) setState(() {authenticated = null; activeAssignment=null;feedbackAttemptId=null;repeatCandidate=null;repeatFromAttemptId=null; pin = ''; inputVersion++;});
    } on ChildSessionException catch (failure) {if (mounted) setState(() => error = failure.message);}
    finally {if (mounted) setState(() => busy = false);}
  }

  Future<void> exitDevice() async {
    if (busy) return;
    setState(() {busy = true; error = null;});
    try {await widget.sessions.endSession(); await widget.onExitDevice();}
    catch (_) {if (mounted) setState(() => error = 'Não foi possível sair do dispositivo. Tenta novamente.');}
    finally {if (mounted) setState(() => busy = false);}
  }

  Widget feedback() => error == null ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Semantics(liveRegion: true, child: Text(error!, textAlign: TextAlign.center)));

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator(semanticsLabel: 'A carregar os perfis')));
    if(authenticated!=null&&feedbackAttemptId!=null)return ChildFeedbackPage(
      key:ValueKey(feedbackAttemptId),attemptId:feedbackAttemptId!,childId:authenticated!.id,
      service:AttemptService(widget.sessions),onParents:widget.onOpenParents,
      onClose:(){
        final child=authenticated;if(child==null)return;
        setState((){feedbackAttemptId=null;assignedWorksheets=fetchAssignments(child.id);});
      },
      onExpired:()=>setState((){feedbackAttemptId=null;activeAssignment=null;repeatCandidate=null;repeatFromAttemptId=null;
        authenticated=null;error='A tua sessão terminou. Introduz o PIN para continuar.';}),
    );
    if(authenticated!=null && activeAssignment!=null)return WorksheetAttemptPage(
      key:ValueKey('${activeAssignment!.id}-${repeatFromAttemptId??'open'}'),repeatFromAttemptId:repeatFromAttemptId,assignment:activeAssignment!,childId:authenticated!.id,sessions:widget.sessions,
      childName:authenticated!.displayName,childEmoji:ChildAvatars.emoji(authenticated!.avatarId),
      onPause:()=>setState((){activeAssignment=null;feedbackAttemptId=null;repeatCandidate=null;repeatFromAttemptId=null;assignedWorksheets=fetchAssignments(authenticated!.id);}),
      onExpired:()=>setState((){activeAssignment=null;feedbackAttemptId=null;repeatCandidate=null;repeatFromAttemptId=null;authenticated=null;error='A tua sessão terminou. Introduz o PIN para continuar.';}),
      onOpenParents:widget.onOpenParents,
      onRepeat:(previousId){
        final assignment=activeAssignment;
        if(assignment!=null)prepareRepeat(assignment,previousId);
      },
    );
    if(authenticated!=null&&repeatCandidate!=null)return RepeatWorksheetConfirmation(
      title:repeatCandidate!.worksheet.title,onConfirm:beginRepeat,onCancel:cancelRepeat,onParents:widget.onOpenParents,
    );
    if (authenticated != null) return studySpace(authenticated!);
    return PopScope(canPop: false, child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: SingleChildScrollView(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter(context), 28, gutter(context), 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(header: true, child: const Text('Quem vai aprender hoje?', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 36, height: 1.15, fontWeight: FontWeight.w800, color: AppColors.text))),
            const SizedBox(height: 10),
            const Text('Toca no teu perfil para começar', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: AppColors.muted)),
            const SizedBox(height: 28),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 520 ? 3 : 2;
              final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
              return Wrap(spacing: 16, runSpacing: 16, alignment: WrapAlignment.center, children: [for (final child in children)
                SizedBox(width: width, child: _ProfileCard(child: child, selected: selected?.id == child.id,
                  onTap: busy ? null : () => choose(child))),
              ]);
            }),
            const SizedBox(height: 14),
            _ParentsCard(onTap: busy ? null : widget.onOpenParents),
            if (selected != null) ...[
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(36),
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.07), blurRadius: 24, offset: const Offset(0, 10))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(child: AppPinInput(key: ValueKey(inputVersion), label: 'PIN de ${selected!.displayName}',
                    enabled: !busy && waitSeconds == 0,
                    onHelp: () => showDialog<void>(context: context, builder: (dialog) => AlertDialog(
                      icon: const Icon(Icons.help_rounded, color: Color(0xFFFBBF24), size: 40),
                      title: const Text('Esqueceste o teu PIN?'),
                      content: const Text('Não faz mal! Pede ajuda ao teu responsável. Se te enganaste num número, toca em «Apagar» e tenta outra vez.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Está bem'))],
                    )),
                    onChanged: (value) => setState(() {pin = value; error = null;}))),
                  feedback(),
                  if (waitSeconds > 0) Padding(padding: const EdgeInsets.only(bottom: 16),
                    child: Text('Tenta novamente dentro de $waitSeconds segundos.', textAlign: TextAlign.center)),
                  const SizedBox(height: 20),
                  AppButton(label: 'Entrar 🚀', loading: busy,
                    onPressed: busy || waitSeconds > 0 || pin.length != 4 ? null : login),
                ]),
              ),
            ] else ...[
              feedback(),
              const SizedBox(height: 20),
              const Text('Ainda não há perfis disponíveis nesta família.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              AppButton(label: 'Atualizar perfis', onPressed: busy ? null : load),
            ],
            const SizedBox(height: 24),
            Center(child: TextButton(onPressed: busy ? null : exitDevice,
              style: TextButton.styleFrom(foregroundColor: AppColors.muted),
              child: const Text('Sair do dispositivo'))),
          ]),
        ),
      )))),
    ));
  }

  double gutter(BuildContext context) => MediaQuery.sizeOf(context).width < 640 ? 16 : 32;

  void showAccountSheet() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheet) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.switch_account_rounded, color: AppColors.primary),
          title: const Text('Mudar de utilizador'),
          onTap: () {Navigator.pop(sheet); changeUser();}),
        ListTile(leading: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
          title: const Text('Área do Responsável'),
          onTap: () {Navigator.pop(sheet); widget.onOpenParents();}),
        ListTile(leading: const Icon(Icons.logout_rounded, color: AppColors.muted),
          title: const Text('Sair do dispositivo'),
          onTap: () {Navigator.pop(sheet); exitDevice();}),
      ]),
    )),
  );

  Widget studySpace(ChildProfile child) => PopScope(canPop: false, child: Scaffold(
    backgroundColor: AppColors.background,
    body: Column(children: [
      _StudyTopBar(child: child, busy: busy, onParents: widget.onOpenParents, onAccount: showAccountSheet),
      Expanded(child: RefreshIndicator(
        onRefresh: () async {
          final next = fetchAssignments(child.id);
          setState(() => assignedWorksheets = next);
          try {await next;} catch (_) {}
        },
        child: ListView(
          key: ValueKey('child-tab-$childTab'),
          padding: EdgeInsets.fromLTRB(gutter(context), 20, gutter(context), 28),
          children: [Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: childTab == 0 ? [
              _StudyHero(child: child, assignments: assignedWorksheets),
              const SizedBox(height: 28),
              assignmentsSection(child),
              feedback(),
              const SizedBox(height: 12),
              Center(child: TextButton.icon(onPressed: busy ? null : changeUser,
                icon: const Icon(Icons.lock_outline_rounded), label: const Text('Mudar de utilizador'),
                style: TextButton.styleFrom(foregroundColor: AppColors.muted))),
            ] : familyTab(child))))],
        ),
      )),
    ]),
    bottomNavigationBar: NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.lavender,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(fontSize: 15,
          fontWeight: FontWeight.w700, color: states.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(size: 28,
          color: states.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted)),
      ),
      child: NavigationBar(
        selectedIndex: childTab,
        onDestinationSelected: busy ? null : (index) => setState(() => childTab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories_rounded), label: 'Fichas'),
          NavigationDestination(icon: Icon(Icons.family_restroom_outlined), selectedIcon: Icon(Icons.family_restroom_rounded), label: 'Família'),
        ],
      ),
    ),
  ));

  List<Widget> familyTab(ChildProfile current) => [
    const Text('A minha família', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text)),
    const SizedBox(height: 6),
    const Text('Para estudar com outro perfil, muda de utilizador. Vai ser preciso o PIN dessa pessoa.',
      style: TextStyle(fontSize: 15, color: AppColors.muted)),
    const SizedBox(height: 20),
    for (final member in children) Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(18),
        selected: member.id == current.id,
        onTap: busy || member.id == current.id ? null : () async {
          await changeUser();
          if (mounted && authenticated == null) {setState(() => childTab = 0); choose(member);}
        },
        child: Row(children: [
          ExcludeSemantics(child: CircleAvatar(radius: 28, backgroundColor: AppColors.lavender,
            child: Text(ChildAvatars.emoji(member.avatarId), style: const TextStyle(fontSize: 30)))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(member.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('${member.schoolYear}.º Ano', style: const TextStyle(color: AppColors.muted)),
          ])),
          member.id == current.id
            ? const AppBadge(label: 'Sou eu', icon: Icons.check_rounded)
            : const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
        ]),
      ),
    ),
    const SizedBox(height: 16),
    AppButton(label: 'Área do Responsável', icon: Icons.lock_outline_rounded, variant: AppButtonVariant.neutral,
      onPressed: busy ? null : widget.onOpenParents),
    const SizedBox(height: 8),
    Center(child: TextButton(onPressed: busy ? null : exitDevice,
      style: TextButton.styleFrom(foregroundColor: AppColors.muted), child: const Text('Sair do dispositivo'))),
  ];
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.child, required this.selected, required this.onTap});
  final ChildProfile child;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true, selected: selected, excludeSemantics: true,
    label: '${child.displayName}, ${child.schoolYear}.º Ano${selected ? ', selecionado' : ''}',
    child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: selected ? AppColors.primary : AppColors.outline, offset: const Offset(0, 6))],
      ),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32),
          side: BorderSide(color: selected ? AppColors.lavender : Colors.transparent, width: 2)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 24, 12, 22),
          child: Column(children: [
            SizedBox(width: 104, height: 100, child: Stack(children: [
              Positioned(left: 0, top: 0, child: Container(
                width: 96, height: 96, alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.lavender, shape: BoxShape.circle,
                  border: Border.all(color: selected ? const Color(0xFFC7BFFF) : AppColors.softBlue, width: 4)),
                child: Text(ChildAvatars.emoji(child.avatarId), style: const TextStyle(fontSize: 50)),
              )),
              Positioned(right: 0, bottom: 0, child: CircleAvatar(
                radius: 18,
                backgroundColor: selected ? AppColors.primary : AppColors.softBlue,
                child: Icon(selected ? Icons.check_rounded : Icons.lock_outline_rounded,
                  size: 20, color: selected ? Colors.white : AppColors.muted),
              )),
            ])),
            const SizedBox(height: 14),
            Text(child.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 4),
            Text('${child.schoolYear}.º Ano', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
              color: selected ? AppColors.primary : AppColors.muted)),
          ]),
        )),
      ),
    ),
  );
}

class _StudyTopBar extends StatelessWidget {
  const _StudyTopBar({required this.child, required this.busy, required this.onParents, required this.onAccount});
  final ChildProfile child;
  final bool busy;
  final VoidCallback onParents;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppColors.background, boxShadow: [
      BoxShadow(color: AppColors.primary.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 6)),
    ]),
    child: SafeArea(bottom: false, child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(children: [
          ExcludeSemantics(child: Container(
            width: 52, height: 52, alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.lavender, shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFC7BFFF), width: 3)),
            child: Text(ChildAvatars.emoji(child.avatarId), style: const TextStyle(fontSize: 26)),
          )),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Olá, ${child.displayName}! 👋', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
            Semantics(header: true, child: const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
              child: Text('O Meu Espaço de Estudo',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)))),
          ])),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: busy ? null : onParents, tooltip: 'Área do Responsável',
            style: IconButton.styleFrom(backgroundColor: AppColors.softBlue, minimumSize: const Size(52, 52)),
            icon: const Icon(Icons.lock_outline_rounded, color: AppColors.amber)),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: busy ? null : onAccount, tooltip: 'Mudar de utilizador ou sair',
            style: IconButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(52, 52)),
            icon: const Icon(Icons.person_outline_rounded)),
        ]),
      ),
    ))),
  );
}

class _StudyHero extends StatelessWidget {
  const _StudyHero({required this.child, required this.assignments});
  final ChildProfile child;
  final Future<List<AssignedWorksheet>>? assignments;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AssignedWorksheet>>(
    future: assignments,
    builder: (context, snapshot) {
      final items = snapshot.data ?? const <AssignedWorksheet>[];
      final todo = items.where((item) => item.stage == AssignmentStage.todo).length;
      final paused = items.where((item) => item.stage == AssignmentStage.paused).length;
      final message = snapshot.connectionState != ConnectionState.done
          ? 'A preparar o teu dia…'
          : todo > 0
              ? (todo == 1 ? 'A tua missão de hoje está pronta!' : 'Tens $todo missões prontas para hoje!')
              : paused > 0 ? 'Há uma ficha à tua espera para continuar.' : 'Hoje não há fichas novas. Bom descanso!';
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.lavender,
          borderRadius: BorderRadius.circular(36),
          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppBadge(label: '${child.schoolYear}.º Ano', icon: Icons.star_rounded, background: Colors.white, color: AppColors.primary),
            const SizedBox(height: 12),
            Text('Olá, ${child.displayName}! 👋',
              style: const TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w800, color: AppColors.primary)),
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(message, style: const TextStyle(fontSize: 18, height: 1.4, color: AppColors.text))),
          ])),
          const SizedBox(width: 12),
          ExcludeSemantics(child: SizedBox(width: 96, height: 96, child: Stack(children: [
            Positioned(left: 0, bottom: 0, child: Container(
              width: 88, height: 88, alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.12), blurRadius: 16)]),
              child: Text(ChildAvatars.emoji(child.avatarId), style: const TextStyle(fontSize: 46)),
            )),
            const Positioned(right: 0, top: 0, child: CircleAvatar(radius: 17, backgroundColor: Color(0xFF10B981),
              child: Icon(Icons.bolt_rounded, color: Colors.white, size: 22))),
          ]))),
        ]),
      );
    },
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon,required this.label});
  final IconData icon;
  final String label;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(left:4,bottom:12),child:Row(children:[
    Icon(icon,color:AppColors.muted,size:24),const SizedBox(width:10),
    Semantics(header:true,child:Text(label,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w700,color:AppColors.muted))),
  ]));
}

/// Perfil «Responsável» no seletor: abre o pedido de PIN do responsável.
class _ParentsCard extends StatelessWidget {
  const _ParentsCard({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true, excludeSemantics: true, label: 'Perfil Responsável. Pede o PIN do responsável.',
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        boxShadow: const [BoxShadow(color: AppColors.outline, offset: Offset(0, 4))],
      ),
      child: Material(
        color: AppColors.surface,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
          child: Row(children: [
            const CircleAvatar(radius: 24, backgroundColor: AppColors.amberSoft,
              child: Icon(Icons.family_restroom_rounded, color: AppColors.amber)),
            const SizedBox(width: 14),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Responsável', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
              Text('Entrar com o PIN do responsável', style: TextStyle(fontSize: 14, color: AppColors.muted)),
            ])),
            const Icon(Icons.lock_outline_rounded, color: AppColors.muted),
          ]),
        )),
      ),
    ),
  );
}
