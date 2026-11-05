import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/request_id.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../data/pending_reviews_service.dart';
import '../domain/parent_review_models.dart';
import 'widgets/answer_review_card.dart';

class ParentReviewPage extends StatefulWidget {
  const ParentReviewPage({super.key, required this.attemptId, required this.service, required this.onClose});
  final String attemptId;
  final PendingReviewsService service;
  final VoidCallback onClose;
  @override
  State<ParentReviewPage> createState() => _ParentReviewPageState();
}

class _ParentReviewPageState extends State<ParentReviewPage> {
  ParentAttemptReview? detail;
  ReviewChange? unconfirmed;
  bool loading = true, saving = false, needsRefresh = false;
  String? error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(load);
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.service.detail(widget.attemptId);
      if (mounted) setState(() { detail = result; unconfirmed = null; needsRefresh = false; });
    } on PendingReviewsException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível carregar a ficha para revisão.');
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> classify(ParentReviewQuestion question, ReviewClassification classification) async {
    if (saving || loading || needsRefresh || unconfirmed != null || question.answerId == null) return;
    final change = ReviewChange(answerId: question.answerId!, classification: classification,
      baseRevision: question.review?.revision ?? 0, operationId: newRequestId());
    await save(change);
  }

  Future<void> save(ReviewChange change) async {
    if (saving || loading) return;
    setState(() { saving = true; error = null; unconfirmed = change; });
    try {
      final result = await widget.service.save(change);
      if (!mounted) return;
      setState(() {
        detail = result;
        unconfirmed = null;
      });
    } on PendingReviewsException catch (failure) {
      if (!mounted) return;
      setState(() {
        error = failure.message;
        if (!failure.uncertain) {
          unconfirmed = null;
          needsRefresh = true;
        }
      });
    } finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final data = detail;
    final blocked = loading || saving || needsRefresh || unconfirmed != null;
    return AppPage(title: 'Rever ficha', subtitle: data == null ? 'Consulta as respostas da criança.'
      : '${data.child.displayName} • ${data.summary.title}', children: [
      AppButton(label: 'Voltar à área dos pais', variant: AppButtonVariant.secondary,
        icon: Icons.arrow_back_rounded, onPressed: saving || unconfirmed != null ? null : widget.onClose),
      const SizedBox(height: 20),
      if (loading) const Center(child: CircularProgressIndicator(semanticsLabel: 'A carregar a revisão')),
      if (error != null) ...[
        AppCard(color: AppColors.coralSoft, child: Semantics(liveRegion: true, child: Text(error!))),
        const SizedBox(height: 12),
        if (unconfirmed != null) ...[
          const Text('A classificação ainda não está confirmada. Podes repetir o mesmo pedido ou consultar o estado guardado no servidor.'),
          const SizedBox(height: 12),
          AppButton(label: 'Tentar confirmar novamente', loading: saving,
            onPressed: saving || loading ? null : () => save(unconfirmed!)),
          const SizedBox(height: 12),
        ],
        AppButton(label: unconfirmed != null ? 'Consultar estado no servidor' : 'Atualizar ficha',
          variant: AppButtonVariant.secondary, onPressed: saving || loading ? null : load),
        const SizedBox(height: 24),
      ],
      if (data != null && !loading) ...[
        AppCard(color: data.summary.pendingReview == 0 ? AppColors.successSoft : AppColors.lavender,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppBadge(label: data.summary.pendingReview == 0 ? 'Revisão concluída' : '${data.summary.pendingReview} respostas por rever',
              icon: data.summary.pendingReview == 0 ? Icons.task_alt_rounded : Icons.rate_review_outlined),
            const SizedBox(height: 16),
            Text(data.summary.pendingReview == 0 ? 'Todas as respostas abertas estão revistas.'
              : '${data.summary.writtenAnswered - data.summary.pendingReview} de ${data.summary.writtenAnswered} respostas abertas revistas.',
              style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: data.summary.writtenAnswered == 0 ? 1
              : (data.summary.writtenAnswered - data.summary.pendingReview) / data.summary.writtenAnswered),
            const SizedBox(height: 16),
            if (data.summary.choiceTotal > 0) Text('${data.summary.choiceCorrect} de ${data.summary.choiceTotal} escolhas múltiplas corretas.'),
            Text('Abertas: ${data.summary.writtenCorrect} corretas • ${data.summary.writtenPartial} parcialmente corretas • ${data.summary.writtenIncorrect} incorretas.'),
            if (data.summary.unansweredTotal > 0) Text('${data.summary.unansweredTotal} perguntas sem resposta.'),
            const SizedBox(height: 12),
            const Text('Podes voltar mais tarde para alterar uma classificação. Cada alteração fica registada.'),
          ])),
        const SizedBox(height: 24),
        if (data.instructions.isNotEmpty || data.text.isNotEmpty || data.audioText.isNotEmpty) ...[
          AppCard(child: ExpansionTile(title: const Text('Contexto da ficha'), children: [
            Padding(padding: const EdgeInsets.all(12), child: SelectableText([
              data.instructions, data.text, data.audioText,
            ].where((item) => item.isNotEmpty).join('\n\n'))),
          ])), const SizedBox(height: 24),
        ],
        for (var i = 0; i < data.questions.length; i++) Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: AnswerReviewCard(question: data.questions[i], number: i + 1, childName: data.child.displayName,
            enabled: !blocked, saving: saving && unconfirmed?.answerId == data.questions[i].answerId,
            onClassify: (classification) => classify(data.questions[i], classification)),
        ),
        AppButton(label: data.summary.pendingReview == 0 ? 'Concluir e voltar ao painel' : 'Pausar revisão e voltar',
          icon: data.summary.pendingReview == 0 ? Icons.task_alt_rounded : Icons.pause_rounded,
          onPressed: saving || unconfirmed != null ? null : widget.onClose),
      ],
    ]);
  }
}
