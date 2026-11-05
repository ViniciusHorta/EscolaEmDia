import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../../../shared/widgets/pin/app_pin_input.dart';
import '../../family/data/family_service.dart';
import '../../family/domain/family_models.dart';
import '../data/child_session_service.dart';
import '../../attempts/presentation/worksheet_attempt_page.dart';
import '../../attempts/presentation/widgets/repeat_worksheet_confirmation.dart';
import '../../worksheets/domain/worksheet_models.dart';
import '../../worksheets/presentation/widgets/assigned_worksheet_card.dart';

class ChildEntryPage extends StatefulWidget {
  const ChildEntryPage({super.key, required this.familyId, required this.families, required this.sessions, required this.onExitDevice, required this.onOpenParents, this.initialChildId});
  final String familyId;
  final String? initialChildId;
  final FamilyService families;
  final ChildSessionService sessions;
  final Future<void> Function() onExitDevice;
  final VoidCallback onOpenParents;

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
  AssignedWorksheet? activeAssignment;
  AssignedWorksheet? repeatCandidate;
  String? repeatFromAttemptId;

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
      setState(() {authenticated = child; activeAssignment=null;repeatCandidate=null;repeatFromAttemptId=null; pin = ''; inputVersion++; assignedWorksheets=fetchAssignments(child.id);});
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
      if (mounted) setState(() {authenticated = null; activeAssignment=null;repeatCandidate=null;repeatFromAttemptId=null; error = 'A tua sessão terminou. Introduz o PIN para continuar.';});
    });
  }

  Future<void> validateSession() async {
    setState(() {busy = true; error = null;});
    try {
      final child = await widget.sessions.profile();
      if (mounted) {setState(() {authenticated=child;assignedWorksheets=fetchAssignments(child.id);}); scheduleExpiry();}
    } on ChildSessionException catch (failure) {
      if (mounted) setState(() {error = failure.message; if (failure.ended) {authenticated = null; activeAssignment=null;repeatCandidate=null;repeatFromAttemptId=null;}});
    } finally {if (mounted) setState(() => busy = false);}
  }

  Future<List<AssignedWorksheet>> fetchAssignments(String childId) async {
    try {return await widget.sessions.assignments(childId);}
    on ChildSessionException catch(failure){
      if(failure.ended && mounted && authenticated?.id==childId)setState((){authenticated=null;activeAssignment=null;repeatCandidate=null;repeatFromAttemptId=null;});
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
        SizedBox(height:10),Text('Quando os teus pais prepararem uma ficha, ela vai aparecer aqui.',textAlign:TextAlign.center),
      ]));
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[for(final item in items)
        Padding(padding:const EdgeInsets.only(bottom:20),child:AssignedWorksheetCard(assignment:item,onStart:busy?null:()=>openAssignment(item),
          onRepeat:busy||!item.canRepeat?null:()=>prepareRepeat(item,item.latestAttemptId!)))]);
    },
  );

  void openAssignment(AssignedWorksheet assignment) {
    if(busy||authenticated?.id!=assignment.childId)return;
    setState(() { activeAssignment=assignment;repeatCandidate=null;repeatFromAttemptId=null; });
  }
  void prepareRepeat(AssignedWorksheet assignment,String previousId) {
    if(busy||authenticated?.id!=assignment.childId)return;
    setState(() { activeAssignment=null;repeatCandidate=assignment;repeatFromAttemptId=previousId; });
  }
  void beginRepeat() {
    final candidate=repeatCandidate;
    if(candidate==null||repeatFromAttemptId==null||authenticated?.id!=candidate.childId)return;
    setState(() { activeAssignment=candidate;repeatCandidate=null; });
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
      if (mounted) setState(() {authenticated = null; activeAssignment=null;repeatCandidate=null;repeatFromAttemptId=null; pin = ''; inputVersion++;});
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
    if(authenticated!=null && activeAssignment!=null)return WorksheetAttemptPage(
      key:ValueKey('${activeAssignment!.id}-${repeatFromAttemptId??'open'}'),repeatFromAttemptId:repeatFromAttemptId,assignment:activeAssignment!,childId:authenticated!.id,sessions:widget.sessions,
      onPause:()=>setState((){activeAssignment=null;repeatCandidate=null;repeatFromAttemptId=null;assignedWorksheets=fetchAssignments(authenticated!.id);}),
      onExpired:()=>setState((){activeAssignment=null;repeatCandidate=null;repeatFromAttemptId=null;authenticated=null;error='A tua sessão terminou. Introduz o PIN para continuar.';}),
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
    return PopScope(canPop: false, child: AppPage(
      title: 'Quem vai aprender hoje?', subtitle: 'Toca no teu perfil para começar.',
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth >= 600 ? (constraints.maxWidth - 20) / 2 : constraints.maxWidth;
          return Wrap(spacing: 20, runSpacing: 20, children: [for (final child in children)
            SizedBox(width: width, child: AppCard(selected: selected?.id == child.id,
              onTap: busy ? null : () => choose(child),
              child: Column(children: [
                ExcludeSemantics(child: Text(ChildAvatars.emoji(child.avatarId), style: const TextStyle(fontSize: 64))),
                const SizedBox(height: 12),
                Text(child.displayName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6), Text('${child.schoolYear}.º Ano'),
                const SizedBox(height: 10),
                Icon(selected?.id == child.id ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
                  color: AppColors.primary, semanticLabel: selected?.id == child.id ? 'Selecionado' : 'Selecionar perfil'),
              ]))),
          ]);
        }),
        if (selected != null) ...[
          const SizedBox(height: 28),
          AppCard(child: Column(children: [
            AppPinInput(key: ValueKey(inputVersion), label: 'PIN de ${selected!.displayName}',
              enabled: !busy && waitSeconds == 0,
              onChanged: (value) => setState(() {pin = value; error = null;})),
            feedback(),
            if (waitSeconds > 0) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('Tenta novamente dentro de $waitSeconds segundos.')),
            const SizedBox(height: 20),
            AppButton(label: 'Entrar', icon: Icons.rocket_launch_rounded, loading: busy,
              onPressed: busy || waitSeconds > 0 || pin.length != 4 ? null : login),
          ])),
        ] else ...[
          feedback(),
          const SizedBox(height: 20),
          const Text('Ainda não há perfis disponíveis nesta família.'),
          AppButton(label: 'Atualizar perfis', onPressed: busy ? null : load),
        ],
        const SizedBox(height: 24),
        TextButton.icon(onPressed: busy ? null : widget.onOpenParents,
          icon: const Icon(Icons.lock_outline_rounded), label: const Text('Área dos pais')),
        TextButton.icon(onPressed: busy ? null : exitDevice,
          icon: const Icon(Icons.logout_rounded), label: const Text('Sair do dispositivo')),
      ],
    ));
  }

  Widget studySpace(ChildProfile child) => PopScope(canPop: false, child: AppPage(
    title: 'Olá, ${child.displayName}!', subtitle: 'O meu espaço de estudo',
    children: [
      AppCard(color: AppColors.lavender, child: Row(children: [
        ExcludeSemantics(child: Text(ChildAvatars.emoji(child.avatarId), style: const TextStyle(fontSize: 64))),
        const SizedBox(width: 20),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(child.displayName, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 10), AppBadge(label: '${child.schoolYear}.º Ano', icon: Icons.star_rounded),
        ])),
      ])),
      const SizedBox(height: 28),
      assignmentsSection(child),
      feedback(),
      const SizedBox(height: 20),
      AppButton(label: 'Mudar de utilizador', variant: AppButtonVariant.secondary,
        loading: busy, icon: Icons.switch_account_outlined, onPressed: busy ? null : changeUser),
      const SizedBox(height: 16),
      TextButton.icon(onPressed: busy ? null : widget.onOpenParents,
        icon: const Icon(Icons.lock_outline_rounded), label: const Text('Área dos pais')),
      TextButton(onPressed: busy ? null : exitDevice, child: const Text('Sair do dispositivo')),
    ],
  ));
}
