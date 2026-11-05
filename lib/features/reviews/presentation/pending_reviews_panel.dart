import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../family/domain/family_models.dart';
import '../data/pending_reviews_service.dart';

class PendingReviewsPanel extends StatefulWidget {
  const PendingReviewsPanel({super.key, required this.familyId, required this.service, required this.onReview});
  final String familyId;
  final PendingReviewsService service;
  final ValueChanged<String> onReview;
  @override
  State<PendingReviewsPanel> createState() => _PendingReviewsPanelState();
}
class _PendingReviewsPanelState extends State<PendingReviewsPanel> {
  late Future<List<PendingReview>> pending;
  bool completed = false;
  @override
  void initState() {
    super.initState();
    pending = Future<List<PendingReview>>.microtask(() => widget.service.list(widget.familyId));
  }
  void reload() {
    setState(() {
      pending = widget.service.list(widget.familyId, completed: completed);
    });
  }
  void selectCompleted(bool value) {
    if (completed == value) return;
    setState(() {
      completed = value;
      pending = widget.service.list(widget.familyId, completed: completed);
    });
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Row(children: [Expanded(child: Text('Revisão das fichas', style: Theme.of(context).textTheme.titleLarge)),
      IconButton(onPressed: reload, tooltip: 'Atualizar revisões', icon: const Icon(Icons.refresh_rounded))]),
    const SizedBox(height: 12),
    Wrap(spacing: 10, runSpacing: 8, children: [
      ChoiceChip(label: const Text('Pendentes'), selected: !completed, onSelected: (selected) { if (selected) selectCompleted(false); }),
      ChoiceChip(label: const Text('Revistas'), selected: completed, onSelected: (selected) { if (selected) selectCompleted(true); }),
    ]),
    const SizedBox(height: 16),
    FutureBuilder<List<PendingReview>>(future: pending, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator(semanticsLabel: 'A carregar revisões'));
      if (snapshot.hasError) {
        final error = snapshot.error;
        return AppCard(child: Text(error is PendingReviewsException ? error.message : 'Não foi possível carregar as revisões.'));
      }
      final rows = snapshot.data ?? [];
      if (rows.isEmpty) return AppCard(child: Text(completed ? 'Ainda não há fichas com revisão concluída.' : 'Não há respostas abertas pendentes de revisão.'));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final row in rows)
        Padding(padding: const EdgeInsets.only(bottom: 16), child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Text(ChildAvatars.emoji(row.child.avatarId), style: const TextStyle(fontSize: 36)), const SizedBox(width: 14),
            Expanded(child: Text('${row.child.displayName} • ${row.child.schoolYear}.º Ano', style: Theme.of(context).textTheme.titleMedium))]),
          const SizedBox(height: 14), Text(row.summary.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: [
            const AppBadge(label: 'Ficha entregue', icon: Icons.cloud_done_outlined),
            AppBadge(label: completed ? 'Revisão concluída' : '${row.summary.pendingReview} respostas por rever',
              background: completed ? AppColors.successSoft : AppColors.amberSoft, color: completed ? AppColors.success : AppColors.amber),
          ]),
          ExpansionTile(title: const Text('Resumo da ficha entregue'), children: [Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (row.summary.choiceTotal > 0) Text('${row.summary.choiceCorrect} de ${row.summary.choiceTotal} escolhas múltiplas corretas.'),
              const SizedBox(height: 8),
              Text(completed ? 'Abertas: ${row.summary.writtenCorrect} corretas • ${row.summary.writtenPartial} parcialmente corretas • ${row.summary.writtenIncorrect} incorretas.'
                : '${row.summary.pendingReview} respostas abertas aguardam revisão.'),
              if (row.summary.unansweredTotal > 0) ...[const SizedBox(height: 8), Text('${row.summary.unansweredTotal} perguntas ficaram sem resposta.')],
            ],
          ))]),
          const SizedBox(height: 12), AppButton(label: completed ? 'Consultar revisão' : 'Rever respostas',
            icon: Icons.rate_review_outlined, onPressed: () => widget.onReview(row.summary.attemptId)),
        ]))),
      ]);
    }),
    const SizedBox(height: 28),
  ]);
}
