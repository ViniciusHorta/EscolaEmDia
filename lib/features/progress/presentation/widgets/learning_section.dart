import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../data/child_progress_service.dart';
import '../../domain/learning_models.dart';
import 'learning_detail_sheet.dart';
import 'learning_radar.dart';

typedef LearningLoader = Future<LearningOverview> Function(LearningPeriod period, String? subjectId);
/// Abre a preparação de atividades com a disciplina e o tema já escolhidos (quando conhecidos).
typedef LearningPrepare = void Function({String? subjectId, String? topicId});

/// Máximo de eixos no radar; com mais temas, o radar mostra os mais praticados e a lista mostra todos (HP10).
const _maxRadarAxes = 8;

/// Visão de Aprendizagem: radar Prática vs. Desempenho por disciplina (ou por tema, no Premium),
/// com painel de detalhe e sugestões de estudo.
class LearningSection extends StatefulWidget {
  const LearningSection({super.key, required this.load, required this.isPremium, this.onUpgrade, this.onPrepare});
  final LearningLoader load;
  /// Plano conhecido antes de carregar (o servidor confirma em [LearningOverview.isPremium]).
  final bool isPremium;
  final VoidCallback? onUpgrade;
  final LearningPrepare? onPrepare;
  @override
  State<LearningSection> createState() => _LearningSectionState();
}

class _LearningSectionState extends State<LearningSection> {
  LearningPeriod period = LearningPeriod.days30;
  LearningOverview? data;
  String? error, selectedId;
  /// Disciplina explorada por tema (null = vista por disciplina).
  String? subjectId;
  bool loading = true;
  int _request = 0;

  bool get premium => data?.isPremium ?? widget.isPremium;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(load);
  }

  Future<void> load() async {
    final request = ++_request;
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.load(period, subjectId);
      if (!mounted || request != _request) return;
      setState(() { data = result; selectedId = null; });
    } catch (failure) {
      if (!mounted || request != _request) return;
      // Nunca mostrar indicadores antigos ou incorretos depois de uma falha (§19).
      setState(() { data = null; error = failure is ChildProgressException ? failure.message
        : 'Não foi possível carregar a aprendizagem. Tenta novamente.'; });
    } finally {
      if (mounted && request == _request) setState(() => loading = false);
    }
  }

  void choosePeriod(LearningPeriod value) {
    if (value == period) return;
    if (!premium && !value.freeAvailable) {
      widget.onUpgrade?.call();
      return;
    }
    setState(() => period = value);
    load();
  }

  void scope(String? value) {
    if (value == subjectId) return;
    setState(() => subjectId = value);
    load();
  }

  void prepare(LearningOverview overview, LearningAxis? axis) {
    final action = widget.onPrepare;
    if (action == null) return;
    if (overview.byTopic) {
      action(subjectId: overview.subjectId, topicId: axis?.id);
    } else {
      action(subjectId: axis?.id);
    }
  }

  Future<void> open(LearningAxis axis) async {
    final overview = data;
    if (overview == null) return;
    setState(() => selectedId = axis.id);
    await showLearningDetail(context, overview: overview, axis: axis, onUpgrade: widget.onUpgrade,
      onExploreTopics: overview.byTopic || !premium ? null : () => scope(axis.id),
      onPrepare: widget.onPrepare == null ? null : () => prepare(overview, axis));
    if (mounted) setState(() => selectedId = null);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final overview = data;
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Aprendizagem', style: text.titleLarge),
          const SizedBox(height: 2),
          Text(overview?.byTopic == true ? 'Temas de ${overview!.subjectName}' : 'Prática e desempenho por disciplina',
            style: text.bodySmall?.copyWith(color: AppColors.muted)),
        ])),
        IconButton(tooltip: 'Como ler o radar', icon: const Icon(Icons.help_outline_rounded),
          onPressed: () => _explain(context)),
      ]),
      if (subjectId != null) Align(alignment: Alignment.centerLeft, child: TextButton.icon(
        onPressed: loading ? null : () => scope(null),
        icon: const Icon(Icons.arrow_back_rounded, size: 18), label: const Text('Todas as disciplinas'))),
      const SizedBox(height: 12),
      _PeriodSelector(value: period, premium: premium, enabled: !loading, onChanged: choosePeriod),
      const SizedBox(height: 16),
      if (loading) const Padding(padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(semanticsLabel: 'A carregar aprendizagem'))),
      if (!loading && error != null) ...[
        Semantics(liveRegion: true, child: Text(error!)),
        const SizedBox(height: 12),
        AppButton(label: 'Tentar novamente', variant: AppButtonVariant.secondary, onPressed: load),
      ],
      if (!loading && error == null && overview != null) ..._content(context, overview),
    ]));
  }

  List<Widget> _content(BuildContext context, LearningOverview overview) {
    final text = Theme.of(context).textTheme;
    if (overview.radarState == RadarState.empty) {
      return [
        const Icon(Icons.insights_rounded, size: 40, color: AppColors.outline),
        const SizedBox(height: 8),
        Text('Ainda não há fichas entregues — ${overview.period.label.toLowerCase()}.', textAlign: TextAlign.center,
          style: text.titleMedium),
        const SizedBox(height: 6),
        Text(overview.byTopic
            ? 'Quando ${overview.childName} entregar fichas de ${overview.subjectName}, os temas aparecem aqui.'
            : 'Quando ${overview.childName} entregar fichas, a prática e o desempenho de cada disciplina aparecem aqui.',
          textAlign: TextAlign.center),
        if (widget.onPrepare != null) ...[
          const SizedBox(height: 16),
          AppButton(label: 'Preparar atividade', icon: Icons.edit_note_rounded, onPressed: () => prepare(overview, null)),
        ],
      ];
    }
    final axes = overview.axes;
    var radarAxes = axes;
    if (axes.length > _maxRadarAxes) {
      radarAxes = ([...axes.where((a) => a.exercises > 0)]..sort((a, b) => b.exercises.compareTo(a.exercises)))
        .take(_maxRadarAxes).toList();
      final order = {for (var i = 0; i < axes.length; i++) axes[i].id: i};
      radarAxes.sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
    }
    final unit = overview.byTopic ? 'tema' : 'disciplina';
    final suggestions = premium ? studySuggestions(axes) : const <StudySuggestion>[];
    return [
      if (overview.radarState == RadarState.initial)
        _Notice(icon: Icons.eco_outlined, text: 'Dados iniciais: ${overview.completedAttempts} '
          '${overview.completedAttempts == 1 ? 'ficha entregue' : 'fichas entregues'} neste período. '
          'Os resultados vão ficar mais claros com mais atividade.'),
      if (overview.pending > 0)
        _Notice(icon: Icons.rate_review_outlined, text: '${overview.pending} '
          '${overview.pending == 1 ? 'resposta aguarda' : 'respostas aguardam'} revisão. Já contam para a prática; '
          'o desempenho é atualizado depois de rever.'),
      if (radarAxes.length >= 3) ...[
        if (radarAxes.length < axes.length)
          Text('O radar mostra os ${radarAxes.length} temas mais praticados; a lista abaixo tem todos.',
            textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: AppColors.muted)),
        LearningRadar(axes: radarAxes, selectedId: selectedId, onSelect: open),
        const SizedBox(height: 20),
        const _Legend(),
        const SizedBox(height: 16),
      ],
      // Representação textual dos valores (RNF09) e acesso direto ao detalhe.
      for (final axis in axes) _AxisRow(axis: axis, onTap: () => open(axis)),
      const SizedBox(height: 8),
      Text('Toca num${unit == 'tema' ? '' : 'a'} $unit para ver o detalhe.', textAlign: TextAlign.center,
        style: text.bodySmall?.copyWith(color: AppColors.muted)),
      // Sugestões (Premium). Sem sugestões relevantes, a secção é omitida (§16.9).
      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('Sugestões de estudo', style: text.titleMedium),
        const SizedBox(height: 4),
        Text('Com base na prática e no desempenho — ${overview.period.label.toLowerCase()}.',
          style: text.bodySmall?.copyWith(color: AppColors.muted)),
        const SizedBox(height: 12),
        for (final item in suggestions) _SuggestionTile(suggestion: item,
          onOpen: () => open(item.axis),
          onPrepare: widget.onPrepare == null ? null : () => prepare(overview, item.axis)),
      ],
      if (!premium && widget.onUpgrade != null) ...[
        const SizedBox(height: 20),
        _PremiumTeaser(onTap: widget.onUpgrade!),
      ],
    ];
  }

  void _explain(BuildContext context) => showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: const Text('Como ler o radar'),
    content: const SingleChildScrollView(child: Text(
      'Prática — como os exercícios feitos se distribuem entre disciplinas. Quando todas são praticadas por igual, '
      'ficam nos 80%. Não é uma percentagem de acertos nem do programa concluído.\n\n'
      'Desempenho — percentagem de respostas certas (as parcialmente certas contam metade), usando a entrega mais '
      'recente de cada ficha. As respostas por rever ficam de fora até serem revistas.\n\n'
      'Sem respostas avaliadas, o desempenho aparece como «—» e não como 0%.\n\n'
      'Estes indicadores ajudam a preparar o estudo; não são notas nem substituem a avaliação da escola.')),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Percebi'))],
  ));
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.premium, required this.enabled, required this.onChanged});
  final LearningPeriod value;
  final bool premium, enabled;
  final ValueChanged<LearningPeriod> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(AppRadii.pill)),
    child: Row(children: [
      for (final option in LearningPeriod.values) Expanded(child: () {
        final selected = option == value, locked = !premium && !option.freeAvailable;
        return Semantics(selected: selected, button: true,
          label: locked ? '${option.label}, disponível no Premium' : option.label, excludeSemantics: true,
          child: Material(
            color: selected ? LearningColors.practice : Colors.transparent,
            shape: const StadiumBorder(),
            child: InkWell(customBorder: const StadiumBorder(), onTap: enabled ? () => onChanged(option) : null,
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2), child: Row(
                mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                  if (locked) const Padding(padding: EdgeInsets.only(right: 2),
                    child: Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.muted)),
                  Flexible(child: Text(option.shortLabel, maxLines: 2, textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.muted))),
                ])))),
        );
      }()),
    ]),
  );
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: Wrap(alignment: WrapAlignment.center, spacing: 16,
    runSpacing: 6, children: [
      _item(context, 'Prática', LearningColors.practice, BoxShape.rectangle, 'linha contínua'),
      _item(context, 'Desempenho', LearningColors.performance, BoxShape.circle, 'linha tracejada'),
    ]));
  Widget _item(BuildContext context, String label, Color color, BoxShape shape, String line) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: shape)),
      const SizedBox(width: 6),
      Text('$label ($line)', style: Theme.of(context).textTheme.labelSmall),
    ]);
}

class _AxisRow extends StatelessWidget {
  const _AxisRow({required this.axis, required this.onTap});
  final LearningAxis axis;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final perf = axis.performance;
    final initial = axis.state == PerformanceState.initial;
    return Semantics(button: true, excludeSemantics: true,
      label: '${axis.name}. Prática ${percentLabel(axis.practice)}. Desempenho '
        '${perf == null ? 'sem dados' : percentLabel(perf)}${initial ? ', poucos dados' : ''}.',
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppRadii.input), child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Expanded(child: Text(axis.name, style: const TextStyle(fontWeight: FontWeight.w600))),
          _value(context, Icons.square_rounded, LearningColors.practice, percentLabel(axis.practice)),
          const SizedBox(width: 12),
          _value(context, Icons.circle, LearningColors.performance, percentLabel(perf)),
          SizedBox(width: 20, child: initial ? const Tooltip(message: 'Poucos dados',
            child: Icon(Icons.eco_outlined, size: 16, color: AppColors.amber)) : null),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ]),
      )));
  }
  Widget _value(BuildContext context, IconData icon, Color color, String value) => SizedBox(width: 60,
    child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 9, color: color), const SizedBox(width: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ])));
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(AppRadii.input)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 20, color: AppColors.muted), const SizedBox(width: 8),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
    ])));
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion, required this.onOpen, this.onPrepare});
  final StudySuggestion suggestion;
  final VoidCallback onOpen;
  final VoidCallback? onPrepare;
  static IconData _icon(SuggestionKind kind) => switch (kind) {
    SuggestionKind.review => Icons.menu_book_rounded,
    SuggestionKind.reinforce => Icons.fitness_center_rounded,
    SuggestionKind.consolidate => Icons.auto_awesome_rounded,
    SuggestionKind.moreData => Icons.travel_explore_rounded,
    SuggestionKind.maintain => Icons.verified_rounded,
  };
  @override
  Widget build(BuildContext context) {
    final axis = suggestion.axis;
    final text = Theme.of(context).textTheme;
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: AppColors.blueBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(onTap: onOpen, borderRadius: BorderRadius.circular(AppRadii.input), child: Row(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: LearningColors.practiceSoft,
              borderRadius: BorderRadius.circular(12)),
              child: Icon(_icon(suggestion.kind), size: 20, color: LearningColors.practice)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(suggestion.title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Prática ${percentLabel(axis.practice)} • Desempenho ${percentLabel(axis.performance)}'
                '${axis.state == PerformanceState.available ? '' : ' (poucos dados)'}',
                style: text.labelSmall?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 6),
              Text(suggestion.reason, style: text.bodySmall),
            ])),
          ])),
        if (onPrepare != null) ...[
          const SizedBox(height: 10),
          AppButton(label: 'Preparar atividade', variant: AppButtonVariant.secondary, icon: Icons.edit_note_rounded,
            onPressed: onPrepare),
        ],
      ])));
  }
}

class _PremiumTeaser extends StatelessWidget {
  const _PremiumTeaser({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(button: true, child: InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(AppRadii.input),
    child: Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFFFF3CC), borderRadius: BorderRadius.circular(AppRadii.input)),
      child: Row(children: [
        const Icon(Icons.workspace_premium_rounded, color: AppColors.amber),
        const SizedBox(width: 12),
        Expanded(child: Text('No Premium: sugestões de estudo, temas de cada disciplina, evolução e mais períodos.',
          style: Theme.of(context).textTheme.bodySmall)),
        const Icon(Icons.chevron_right_rounded, color: AppColors.amber),
      ]))));
}
