import 'package:flutter/material.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../../child_session/data/child_session_service.dart';
import '../data/attempt_service.dart';
import '../domain/child_feedback_models.dart';
import 'widgets/child_feedback_card.dart';

class ChildFeedbackPage extends StatefulWidget {
  const ChildFeedbackPage({super.key, required this.attemptId, required this.childId, required this.service,
    required this.onClose, required this.onParents, required this.onExpired});
  final String attemptId, childId;
  final AttemptService service;
  final VoidCallback onClose, onParents, onExpired;
  @override
  State<ChildFeedbackPage> createState() => _ChildFeedbackPageState();
}
class _ChildFeedbackPageState extends State<ChildFeedbackPage> {
  ChildAttemptFeedback? feedback;
  bool loading = true, onlyPractice = true, requestRunning = false;
  String? error;
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(load);
  }
  Future<void> load() async {
    if (!mounted || requestRunning) return;
    requestRunning = true;
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.service.feedback(widget.attemptId, widget.childId);
      if (mounted) setState(() { feedback = result; });
    } on ChildSessionException catch (failure) {
      if (!mounted) return;
      if (failure.ended) { widget.onExpired(); return; }
      setState(() { error = failure.message; });
    } catch (_) {
      if (mounted) setState(() { error = 'Não foi possível carregar a correção. Tenta novamente.'; });
    } finally { requestRunning = false; if (mounted) setState(() { loading = false; }); }
  }
  @override
  Widget build(BuildContext context) {
    final data = feedback;
    final questions = data?.questions.where((question) => !onlyPractice || question.needsPractice).toList() ?? <ChildFeedbackQuestion>[];
    final practiceCount = data?.questions.where((question) => question.needsPractice).length ?? 0;
    return PopScope(canPop: false, child: AppPage(title: 'Vamos aprender com a ficha',
      subtitle: data == null ? 'Consulta a tua correção, sem pressa.' : '${data.summary.title} • Tentativa ${data.summary.attemptNumber}', children: [
        AppButton(label: 'Voltar', variant: AppButtonVariant.secondary, icon: Icons.arrow_back_rounded, onPressed: widget.onClose),
        const SizedBox(height: 20),
        if (loading) const Center(child: CircularProgressIndicator(semanticsLabel: 'A carregar a correção')),
        if (!loading && error != null) ...[
          AppCard(child: Semantics(liveRegion: true, child: Text(error!))), const SizedBox(height: 16),
          AppButton(label: 'Tentar novamente', onPressed: load),
        ],
        if (!loading && error == null && data != null) ...[
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppBadge(label: 'Tentativa ${data.summary.attemptNumber}', icon: Icons.history_rounded),
            const SizedBox(height: 14), Text(practiceCount == 0 ? 'Todas as respostas desta tentativa estão corretas. Muito bem!'
              : 'Errar também faz parte de aprender. Vamos descobrir o que podes melhorar.', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10), Text('$practiceCount de ${data.questions.length} perguntas para rever com calma.'),
          ])),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 8, children: [
            ChoiceChip(label: const Text('O que posso melhorar'), selected: onlyPractice,
              onSelected: (_) => setState(() { onlyPractice = true; })),
            ChoiceChip(label: const Text('Todas as respostas'), selected: !onlyPractice,
              onSelected: (_) => setState(() { onlyPractice = false; })),
          ]),
          const SizedBox(height: 18),
          if (data.instructions.isNotEmpty || data.text.isNotEmpty || data.audioText.isNotEmpty) ...[
            AppCard(child: ExpansionTile(title: const Text('Recordar o contexto da ficha'), children: [
              Padding(padding: const EdgeInsets.all(12), child: SelectableText([
                data.instructions, data.text, data.audioText,
              ].where((item) => item.isNotEmpty).join('\n\n'))),
            ])), const SizedBox(height: 18),
          ],
          if (questions.isEmpty) const AppCard(child: Text('Não há perguntas por melhorar nesta tentativa. Podes ver todas as tuas respostas.')),
          for (final question in questions) Padding(padding: const EdgeInsets.only(bottom: 18),
            child: ChildFeedbackCard(key: ValueKey(question.id), question: question)),
          AppButton(label: 'Atualizar correção', variant: AppButtonVariant.secondary, icon: Icons.refresh_rounded, onPressed: load),
          const SizedBox(height: 16),
        ],
        TextButton.icon(onPressed: widget.onParents, icon: const Icon(Icons.lock_outline_rounded), label: const Text('Área dos pais')),
      ],
    ));
  }
}
