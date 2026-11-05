import 'package:flutter/material.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../../family/domain/family_models.dart';
import '../data/child_progress_service.dart';
import '../domain/child_progress_models.dart';
import 'widgets/attempt_history_card.dart';
import 'widgets/progress_stat_card.dart';
import 'widgets/subject_progress_card.dart';

class ChildProgressPage extends StatefulWidget {
  const ChildProgressPage({super.key, required this.childId, required this.service, required this.onClose, required this.onReview});
  final String childId;
  final ChildProgressService service;
  final VoidCallback onClose;
  final ValueChanged<String> onReview;
  @override
  State<ChildProgressPage> createState() => _ChildProgressPageState();
}
class _ChildProgressPageState extends State<ChildProgressPage> {
  ChildProgress? progress;
  List<AttemptHistoryEntry> history = [];
  final seenCursors = <String>{};
  String? cursor, subjectId, status, overviewError, historyError;
  bool loading = true, historyLoading = false, moreLoading = false;
  bool get busy => loading || historyLoading || moreLoading;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(load);
  }
  Future<void> load() async {
    if (!mounted || historyLoading || moreLoading) return;
    setState(() { loading = true; overviewError = null; });
    try {
      final result = await widget.service.overview(widget.childId);
      if (!mounted) return;
      setState(() {
        progress = result;
        if (!result.subjects.any((item) => item.id == subjectId)) subjectId = null;
      });
      await loadHistory();
    } catch (error) {
      if (mounted) setState(() { overviewError = message(error); });
    } finally { if (mounted) setState(() { loading = false; }); }
  }
  Future<void> loadHistory({bool more = false}) async {
    if (!mounted || historyLoading || moreLoading || (more && cursor == null)) return;
    final requestedCursor = more ? cursor : null;
    setState(() {
      historyError = null;
      if (more) {
        moreLoading = true;
      } else {
        historyLoading = true; history = []; cursor = null; seenCursors.clear();
      }
    });
    try {
      final page = await widget.service.history(widget.childId, cursor: requestedCursor, subjectId: subjectId, status: status);
      if (!mounted) return;
      if (page.nextCursor != null && !seenCursors.add(page.nextCursor!)) {
        throw const ChildProgressException('Não foi possível continuar a paginação. Atualiza o acompanhamento.');
      }
      setState(() {
        final existing = history.map((item) => item.id).toSet();
        history = [...history, ...page.items.where((item) => existing.add(item.id))];
        cursor = page.nextCursor;
      });
    } catch (error) {
      if (mounted) setState(() { historyError = message(error); });
    } finally {
      if (mounted) setState(() { historyLoading = false; moreLoading = false; });
    }
  }
  void filterStatus(String? value) {
    if (busy || status == value) return;
    setState(() { status = value; });
    loadHistory();
  }
  void filterSubject(String? value) {
    if (busy || subjectId == value) return;
    setState(() { subjectId = value; });
    loadHistory();
  }
  String message(Object error) => error is ChildProgressException ? error.message : 'Não foi possível carregar o acompanhamento. Tenta novamente.';

  @override
  Widget build(BuildContext context) {
    final data = progress;
    return AppPage(title: 'Acompanhamento', subtitle: data == null ? 'O percurso de cada criança, ao seu ritmo.'
      : '${ChildAvatars.emoji(data.child.avatarId)} ${data.child.displayName} • ${data.child.schoolYear}.º Ano', children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        AppButton(label: 'Voltar aos perfis', expand: false, variant: AppButtonVariant.secondary, icon: Icons.arrow_back_rounded, onPressed: widget.onClose),
        AppButton(label: 'Atualizar', expand: false, icon: Icons.refresh_rounded, loading: loading, onPressed: busy ? null : load),
      ]),
      const SizedBox(height: 24),
      if (loading) const Center(child: CircularProgressIndicator(semanticsLabel: 'A carregar acompanhamento')),
      if (!loading && overviewError != null) ...[
        AppCard(child: Semantics(liveRegion: true, child: Text(overviewError!))),
        const SizedBox(height: 12), AppButton(label: 'Tentar novamente', onPressed: busy ? null : load),
      ],
      if (!loading && overviewError == null && data != null) ...[
        Text('Visão geral', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 16),
        stats(data.overview), const SizedBox(height: 20),
        const Text('As entregas contam cada realização da ficha. Os resultados usam apenas respostas já entregues; as respostas em curso ficam fora das contagens de acertos.'),
        const SizedBox(height: 28), Text('Resultados por disciplina', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        if (data.subjects.isEmpty) const AppCard(child: Text('Ainda não há fichas atribuídas ou realizações para este perfil.')),
        for (final subject in data.subjects) Padding(padding: const EdgeInsets.only(bottom: 16), child: SubjectProgressCard(subject: subject)),
        const SizedBox(height: 12), Text('Histórico de fichas', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8), const Text('Da realização iniciada mais recentemente para a mais antiga. Os filtros abaixo aplicam-se ao histórico.'),
        const SizedBox(height: 16),
        InputDecorator(decoration: const InputDecoration(labelText: 'Disciplina'),
          child: DropdownButtonHideUnderline(child: DropdownButton<String>(
            value: subjectId ?? '', isExpanded: true,
            items: [const DropdownMenuItem(value: '', child: Text('Todas as disciplinas')),
              for (final subject in data.subjects) DropdownMenuItem(value: subject.id, child: Text(subject.name))],
            onChanged: busy ? null : (value) => filterSubject(value == '' ? null : value),
          )),
        ),
        const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('Todas'), selected: status == null, onSelected: busy ? null : (_) => filterStatus(null)),
          for (final value in ['in_progress', 'submitted', 'pending_review', 'completed', 'abandoned'])
            ChoiceChip(label: Text(historyStatusLabel(value)), selected: status == value,
              onSelected: busy ? null : (_) => filterStatus(value)),
        ]),
        const SizedBox(height: 20),
        if (historyLoading) const Center(child: CircularProgressIndicator(semanticsLabel: 'A carregar histórico')),
        if (historyError != null) ...[
          AppCard(child: Semantics(liveRegion: true, child: Text(historyError!))), const SizedBox(height: 12),
          AppButton(label: 'Tentar carregar histórico novamente', variant: AppButtonVariant.secondary,
            onPressed: busy ? null : () => loadHistory(more: history.isNotEmpty && cursor != null)),
          const SizedBox(height: 16),
        ],
        if (!historyLoading && history.isEmpty && historyError == null)
          const AppCard(child: Text('Não há realizações para estes filtros. As fichas ainda por começar aparecem no resumo acima.')),
        for (final attempt in history) Padding(padding: const EdgeInsets.only(bottom: 16),
          child: AttemptHistoryCard(attempt: attempt, onReview: () => widget.onReview(attempt.id))),
        if (cursor != null && historyError == null) AppButton(label: 'Carregar mais', variant: AppButtonVariant.secondary,
          loading: moreLoading, onPressed: busy ? null : () => loadHistory(more: true)),
      ],
    ]);
  }
  Widget stats(ProgressTotals totals) => LayoutBuilder(builder: (context, constraints) {
    final columns = constraints.maxWidth >= 850 ? 4 : constraints.maxWidth >= 480 ? 2 : 1;
    final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
    final items = <(String, int, IconData)>[
      ('Atribuições ativas', totals.assignedTotal, Icons.assignment_outlined),
      ('Por começar', totals.toStart, Icons.play_circle_outline_rounded),
      ('Em curso', totals.inProgress, Icons.edit_note_rounded),
      ('Entregas', totals.delivered, Icons.cloud_done_outlined),
      ('Concluídas', totals.completed, Icons.task_alt_rounded),
      ('Entregas por rever', totals.pendingAttempts, Icons.rate_review_outlined),
      ('Respostas por rever', totals.pendingAnswers, Icons.question_answer_outlined),
    ];
    return Wrap(spacing: 16, runSpacing: 16, children: [for (final item in items)
      SizedBox(width: width, child: ProgressStatCard(label: item.$1, value: item.$2, icon: item.$3)),
    ]);
  });
}
