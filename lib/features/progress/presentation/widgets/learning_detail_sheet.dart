import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../domain/learning_models.dart';
import 'learning_radar.dart';

/// Painel de detalhe de uma disciplina ou tema (PRD §14).
Future<void> showLearningDetail(BuildContext context, {required LearningOverview overview, required LearningAxis axis,
    VoidCallback? onPrepare, VoidCallback? onExploreTopics, VoidCallback? onUpgrade}) =>
  showModalBottomSheet<void>(
    context: context, isScrollControlled: true, showDragHandle: true, backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card))),
    builder: (context) => LearningDetail(overview: overview, axis: axis, onPrepare: onPrepare,
      onExploreTopics: onExploreTopics, onUpgrade: onUpgrade),
  );

class LearningDetail extends StatelessWidget {
  const LearningDetail({super.key, required this.overview, required this.axis, this.onPrepare,
    this.onExploreTopics, this.onUpgrade});
  final LearningOverview overview;
  final LearningAxis axis;
  final VoidCallback? onPrepare, onExploreTopics, onUpgrade;

  void _then(BuildContext context, VoidCallback? action) {
    Navigator.pop(context);
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final evolution = overview.isPremium ? axis.evolution : null;
    final notice = switch (axis.state) {
      PerformanceState.none => axis.exercises == 0
        ? 'Ainda não há exercícios neste período.'
        : 'Ainda não há respostas avaliadas para calcular o desempenho.',
      PerformanceState.initial => 'Dados iniciais: com menos de ${LearningThresholds.enoughEvaluated} perguntas avaliadas, '
        'o desempenho ainda pode variar bastante.',
      PerformanceState.available => null,
    };
    return SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(overview.byTopic ? '${overview.subjectName} • ${overview.period.label}' : overview.period.label,
          style: text.labelMedium?.copyWith(color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(axis.name, style: text.headlineSmall),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _Metric(label: 'Prática', value: percentLabel(axis.practice), color: LearningColors.practice,
            background: LearningColors.practiceSoft, fraction: axis.practice / 100, square: true)),
          const SizedBox(width: 12),
          Expanded(child: _Metric(label: 'Desempenho', value: percentLabel(axis.performance),
            color: LearningColors.performance, background: LearningColors.performanceSoft,
            fraction: (axis.performance ?? 0) / 100, square: false)),
        ]),
        if (evolution != null) ...[
          const SizedBox(height: 10),
          Text('Evolução: ${evolutionLabel(evolution)} face ao período anterior '
            '(${percentLabel(axis.previous!.performance)}).', style: text.bodyMedium),
        ],
        if (notice != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(AppRadii.input)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.muted), const SizedBox(width: 8),
              Expanded(child: Text(notice, style: text.bodyMedium)),
            ]))),
        ],
        const SizedBox(height: 16),
        _Count('Fichas entregues', axis.attempts),
        _Count('Exercícios realizados', axis.exercises),
        _Count('Perguntas avaliadas', axis.answers.evaluated),
        _Count('Respostas por rever', axis.pending),
        const SizedBox(height: 12),
        Text('A prática mostra como os exercícios se distribuem entre ${overview.byTopic ? 'os temas' : 'as disciplinas'} '
          '(80% em todas = equilíbrio); não é uma percentagem de acertos. O desempenho usa a entrega mais recente de cada '
          'ficha; respostas parcialmente corretas contam metade.', style: text.bodySmall?.copyWith(color: AppColors.muted)),
        const SizedBox(height: 20),
        if (!overview.byTopic) ...[
          if (overview.isPremium)
            AppButton(label: 'Explorar temas', variant: AppButtonVariant.secondary, icon: Icons.travel_explore_rounded,
              onPressed: onExploreTopics == null ? null : () => _then(context, onExploreTopics))
          else
            AppButton(label: 'Explorar temas (Premium)', variant: AppButtonVariant.secondary, icon: Icons.lock_outline_rounded,
              onPressed: onUpgrade == null ? null : () => _then(context, onUpgrade)),
          const SizedBox(height: 12),
        ],
        if (onPrepare != null) AppButton(label: 'Preparar atividade', icon: Icons.edit_note_rounded,
          onPressed: () => _then(context, onPrepare)),
      ])));
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color, required this.background,
    required this.fraction, required this.square});
  final String label, value;
  final Color color, background;
  final double fraction;
  final bool square;
  @override
  Widget build(BuildContext context) => Semantics(label: '$label: ${value == '—' ? 'sem dados' : value}', excludeSemantics: true,
    child: Container(padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadii.input)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color,
            shape: square ? BoxShape.rectangle : BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(AppRadii.pill), child: LinearProgressIndicator(
          value: fraction.clamp(0, 1), minHeight: 6, color: color, backgroundColor: color.withValues(alpha: 0.15))),
      ])));
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value);
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
    Expanded(child: Text(label)),
    Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
  ]));
}
