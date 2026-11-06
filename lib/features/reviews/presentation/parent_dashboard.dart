import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/subject_icons.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../family/domain/family_models.dart';
import '../data/pending_reviews_service.dart';

/// Separador «Painel» da área do responsável (Stitch: 1. Painel do Responsável — Revisões Pendentes).
class ParentDashboard extends StatefulWidget {
  const ParentDashboard({
    super.key,
    required this.familyId,
    required this.children,
    required this.service,
    required this.onReview,
    required this.onEnterChild,
    this.onPendingCount,
    this.busy = false,
  });
  final String familyId;
  final List<ChildProfile> children;
  final PendingReviewsService service;
  final ValueChanged<String> onReview;
  final ValueChanged<String> onEnterChild;
  final ValueChanged<int>? onPendingCount;
  final bool busy;

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  static const recentLimit = 5;

  List<PendingReview> pending = [];
  List<PendingReview> completed = [];
  bool loading = true;
  String? error;
  String? selectedChildId;
  bool showCompleted = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = pending.isEmpty && completed.isEmpty; error = null; });
    try {
      final results = await Future.wait([
        widget.service.list(widget.familyId),
        widget.service.list(widget.familyId, completed: true),
      ]);
      if (!mounted) return;
      final open = results[0]..sort((a, b) => a.summary.submittedAt.compareTo(b.summary.submittedAt));
      final done = results[1]..sort((a, b) => b.summary.submittedAt.compareTo(a.summary.submittedAt));
      setState(() {
        pending = open;
        completed = done;
        selectedChildId ??= _defaultChild(open);
      });
      widget.onPendingCount?.call(open.length);
    } on PendingReviewsException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível carregar as revisões.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String? _defaultChild(List<PendingReview> open) {
    if (open.isNotEmpty) return open.first.child.id;
    return widget.children.isEmpty ? null : widget.children.first.id;
  }

  int pendingFor(String childId) => pending.where((row) => row.child.id == childId).length;

  @override
  Widget build(BuildContext context) {
    final child = widget.children.where((c) => c.id == selectedChildId).firstOrNull;
    final childPending = pending.where((row) => row.child.id == selectedChildId).toList();
    final childCompleted = completed.where((row) => row.child.id == selectedChildId).take(recentLimit).toList();
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(_gutter(context), 20, _gutter(context), 32),
        children: [
          _sectionLabel(context),
          const SizedBox(height: 12),
          _childTabs(),
          const SizedBox(height: 28),
          if (loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(
              child: CircularProgressIndicator(semanticsLabel: 'A carregar revisões')))
          else if (error != null)
            AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(error!),
              const SizedBox(height: 16),
              AppButton(label: 'Tentar novamente', variant: AppButtonVariant.secondary,
                icon: Icons.refresh_rounded, onPressed: load),
            ]))
          else ...[
            _summaryBanner(context, child, childPending),
            if (child != null) ...[
              const SizedBox(height: 16),
              _EnterChildCard(child: child, busy: widget.busy, onEnter: () => widget.onEnterChild(child.id)),
            ],
            if (childPending.isNotEmpty) ...[
              const SizedBox(height: 32),
              _sectionHeader(context,
                title: childPending.length == 1 ? 'Ficha Pendente' : 'Fichas Pendentes',
                dot: true,
                trailing: const Text('Prioritário', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))),
              const SizedBox(height: 16),
              for (final row in childPending) Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _PendingWorksheetCard(row: row, onReview: () => widget.onReview(row.summary.attemptId)),
              ),
            ],
            const SizedBox(height: 24),
            _sectionHeader(context,
              title: 'Fichas Concluídas',
              trailing: TextButton.icon(
                onPressed: () => setState(() => showCompleted = !showCompleted),
                iconAlignment: IconAlignment.end,
                icon: Icon(showCompleted ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: const Text('Histórico recente'),
              )),
            if (showCompleted) ...[
              const SizedBox(height: 12),
              if (childCompleted.isEmpty)
                const AppCard(child: Text('Ainda não há fichas com revisão concluída.'))
              else
                for (final row in childCompleted) Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CompletedWorksheetTile(row: row, onOpen: () => widget.onReview(row.summary.attemptId)),
                ),
            ],
            const SizedBox(height: 36),
            const _SupportNote(),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context) {
    final now = DateTime.now();
    final start = now.month >= 9 ? now.year : now.year - 1;
    return Row(children: [
      const Expanded(child: Text('FILHOS A CARGO', style: TextStyle(
        color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2))),
      Text('Ano Letivo $start/${(start + 1) % 100}', style: const TextStyle(
        color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _childTabs() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    child: Semantics(
      label: 'Educandos',
      child: Row(children: [
        for (final child in widget.children) Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _ChildTab(
            child: child,
            pending: pendingFor(child.id),
            selected: child.id == selectedChildId,
            onTap: () => setState(() => selectedChildId = child.id),
          ),
        ),
      ]),
    ),
  );

  Widget _summaryBanner(BuildContext context, ChildProfile? child, List<PendingReview> rows) {
    final count = rows.length;
    final latest = rows.isEmpty ? null : rows.reduce((a, b) => a.summary.submittedAt.isAfter(b.summary.submittedAt) ? a : b);
    final title = count == 0
        ? 'Tudo revisto por agora'
        : count == 1 ? '1 ficha aguarda a tua revisão' : '$count fichas aguardam a tua revisão';
    final subtitle = latest == null
        ? (child == null ? 'Não há fichas por rever.' : 'Não há fichas de ${child.displayName} por rever.')
        : '${latest.child.displayName} concluiu a ficha ${relativeMoment(latest.summary.submittedAt)}';
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: count == 0 ? AppColors.successSoft : AppColors.lavender,
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          ExcludeSemantics(child: CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.7),
            child: Icon(count == 0 ? Icons.task_alt_rounded : Icons.notifications_active_rounded,
              color: count == 0 ? AppColors.success : AppColors.primary, size: 28),
          )),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(
              color: count == 0 ? AppColors.success : AppColors.primary, fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: AppColors.text, fontSize: 15)),
          ])),
        ]),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, {required String title, Widget? trailing, bool dot = false}) => Row(children: [
    Expanded(child: Row(children: [
      Flexible(child: Semantics(header: true, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
        child: Text(title, maxLines: 1,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text))))),
      if (dot) ...[
        const SizedBox(width: 10),
        Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.coral, shape: BoxShape.circle)),
      ],
    ])),
    if (trailing != null) trailing,
  ]);

  double _gutter(BuildContext context) => MediaQuery.sizeOf(context).width < 640 ? 16 : 32;
}

/// Ex.: «hoje às 16:45», «ontem às 09:10», «há 3 dias», «em 02/10».
String relativeMoment(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(local.year, local.month, local.day)).inDays;
  final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (days <= 0) return 'hoje às $time';
  if (days == 1) return 'ontem às $time';
  if (days < 7) return 'há $days dias';
  return 'em ${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
}

/// Versão curta para listas: «hoje», «ontem», «há 3 dias», «em 02/10».
String relativeDay(DateTime value) {
  final moment = relativeMoment(value);
  return moment.startsWith('hoje') ? 'hoje' : moment.startsWith('ontem') ? 'ontem' : moment;
}

String _capitalize(String text) => text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

class _ChildTab extends StatelessWidget {
  const _ChildTab({required this.child, required this.pending, required this.selected, required this.onTap});
  final ChildProfile child;
  final int pending;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.text;
    return Semantics(
      selected: selected,
      button: true,
      label: '${child.displayName}, ${child.schoolYear}.º Ano, '
          '${pending == 1 ? '1 ficha por rever' : '$pending fichas por rever'}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.softBlue,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: selected ? const [BoxShadow(color: AppColors.primaryPressed, offset: Offset(0, 4))] : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(radius: 24, backgroundColor: selected ? Colors.white : AppColors.lavender,
                  child: Text(ChildAvatars.emoji(child.avatarId), style: const TextStyle(fontSize: 26))),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(child.displayName, style: TextStyle(color: foreground, fontSize: 17, fontWeight: FontWeight.w700)),
                  Text('${child.schoolYear}.º Ano', style: TextStyle(
                    color: selected ? Colors.white.withValues(alpha: 0.85) : AppColors.muted, fontSize: 14)),
                ]),
                const SizedBox(width: 14),
                Container(
                  constraints: const BoxConstraints(minWidth: 28),
                  height: 28,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: pending > 0 ? AppColors.coral : AppColors.blueBorder,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text('$pending', style: TextStyle(
                    color: pending > 0 ? Colors.white : AppColors.muted, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingWorksheetCard extends StatelessWidget {
  const _PendingWorksheetCard({required this.row, required this.onReview});
  final PendingReview row;
  final VoidCallback onReview;

  static const coralText = Color(0xFFB4421F);

  @override
  Widget build(BuildContext context) {
    final s = row.summary;
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(child: Container(
            width: 64, height: 64,
            decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(20)),
            child: Icon(subjectIcon(s.subjectName), color: AppColors.primary, size: 32),
          )),
          const Spacer(),
          const AppBadge(label: 'Por rever', icon: Icons.pending_actions_rounded,
            background: AppColors.coralSoft, color: coralText),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppBadge(label: s.subjectName.toUpperCase()),
          if (s.attemptNumber > 1) Text('• Tentativa ${s.attemptNumber}',
            style: const TextStyle(color: AppColors.muted, fontSize: 14)),
        ]),
        const SizedBox(height: 8),
        Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.25)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(20)),
          child: Wrap(spacing: 16, runSpacing: 16, children: [
            _Stat(
              icon: Icons.help_center_outlined,
              color: AppColors.primary,
              value: s.pendingReview == 1 ? '1 resposta' : '${s.pendingReview} respostas',
              label: 'Abertas / Por validar',
            ),
            if (s.choiceTotal > 0) _Stat(
              icon: Icons.check_circle_rounded,
              color: const Color(0xFF10B981),
              value: s.choiceTotal == 1 ? '1 automática' : '${s.choiceTotal} automáticas',
              label: 'Já corrigidas (${s.choiceCorrect} certas)',
            ),
          ]),
        ),
        const SizedBox(height: 24),
        AppButton(label: 'Rever ficha agora', icon: Icons.draw_rounded, onPressed: onReview),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.color, required this.value, required this.label});
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 130, maxWidth: 220),
    child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: color, size: 24)),
      const SizedBox(width: 10),
      Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text)),
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
      ])),
    ]),
  );
}

class _CompletedWorksheetTile extends StatelessWidget {
  const _CompletedWorksheetTile({required this.row, required this.onOpen});
  final PendingReview row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = row.summary;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(children: [
        ExcludeSemantics(child: CircleAvatar(
          radius: 28, backgroundColor: AppColors.softBlue,
          child: Icon(subjectIcon(s.subjectName), color: AppColors.muted),
        )),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s.subjectName}: ${s.title}', maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.text)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_capitalize(relativeDay(s.submittedAt)),
              style: const TextStyle(color: AppColors.muted, fontSize: 14)),
            const Text('•', style: TextStyle(color: AppColors.muted)),
            const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_rounded, size: 16, color: AppColors.success),
              SizedBox(width: 2),
              Text('Validada', style: TextStyle(color: AppColors.success, fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ])),
        const SizedBox(width: 8),
        DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.pill)),
            boxShadow: [BoxShadow(color: AppColors.blueBorder, offset: Offset(0, 3))],
          ),
          child: TextButton(
            onPressed: onOpen,
            style: TextButton.styleFrom(
              backgroundColor: AppColors.softBlue,
              foregroundColor: AppColors.primary,
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: const StadiumBorder(side: BorderSide(color: AppColors.blueBorder)),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14),
            ),
            child: const Text('Ver resultado'),
          ),
        ),
      ]),
    );
  }
}

class _EnterChildCard extends StatelessWidget {
  const _EnterChildCard({required this.child, required this.onEnter, this.busy = false});
  final ChildProfile child;
  final VoidCallback onEnter;
  final bool busy;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        ExcludeSemantics(child: CircleAvatar(radius: 26, backgroundColor: AppColors.amberSoft,
          child: Text(ChildAvatars.emoji(child.avatarId), style: const TextStyle(fontSize: 28)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hora de estudar, ${child.displayName}?', style: const TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 2),
          const Text('Entrega o dispositivo. A área do responsável volta a pedir o PIN.',
            style: TextStyle(color: AppColors.muted, fontSize: 14)),
        ])),
      ]),
      const SizedBox(height: 16),
      AppButton(
        label: 'Entrar no espaço de ${child.displayName}',
        icon: Icons.rocket_launch_rounded,
        variant: AppButtonVariant.success,
        loading: busy,
        onPressed: busy ? null : onEnter,
      ),
    ]),
  );
}

class _SupportNote extends StatelessWidget {
  const _SupportNote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(AppRadii.card)),
    child: const Row(children: [
      ExcludeSemantics(child: CircleAvatar(radius: 22, backgroundColor: AppColors.lavender,
        child: Icon(Icons.stars_rounded, color: AppColors.primary))),
      SizedBox(width: 16),
      Expanded(child: Text(
        'A rever em família: validar o raciocínio estimula a confiança escolar sem sobrecarregar o teu tempo.',
        style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.45))),
    ]),
  );
}
