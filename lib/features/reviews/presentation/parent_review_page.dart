import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/request_id.dart';
import '../../../core/utils/subject_icons.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../family/domain/family_models.dart';
import '../data/pending_reviews_service.dart';
import '../domain/parent_review_models.dart';
import 'widgets/report_question_sheet.dart';
import 'widgets/review_classification_selector.dart';

enum _Stage { summary, review, finalize, result }

/// Revisão parental de uma ficha entregue (Stitch: 2. Resumo da Ficha Entregue,
/// 3. Revisão de Resposta Aberta, 4. Finalização da Revisão, 5. Resultado Final).
/// Cada classificação é gravada no servidor no momento em que é escolhida; a
/// ficha fica concluída quando não restam respostas por rever.
class ParentReviewPage extends StatefulWidget {
  const ParentReviewPage({super.key, required this.attemptId, required this.service, required this.onClose, this.onPrepareWorksheet});
  final String attemptId;
  final PendingReviewsService service;
  final VoidCallback onClose;
  final VoidCallback? onPrepareWorksheet;
  @override
  State<ParentReviewPage> createState() => _ParentReviewPageState();
}

class _ParentReviewPageState extends State<ParentReviewPage> {
  ParentAttemptReview? detail;
  ReviewChange? unconfirmed;
  bool loading = true, saving = false, needsRefresh = false;
  String? error;
  _Stage? stage;
  String? reviewingQuestionId;
  bool showChoices = false;
  /// Perguntas com problema reportado nesta sessão de revisão.
  final reported = <String>{};

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
      if (mounted) {
        setState(() {
          detail = result; unconfirmed = null; needsRefresh = false;
          stage ??= result.summary.pendingReview == 0 ? _Stage.result : _Stage.summary;
        });
      }
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
      setState(() { detail = result; unconfirmed = null; });
    } on PendingReviewsException catch (failure) {
      if (!mounted) return;
      setState(() {
        error = failure.message;
        if (!failure.uncertain) { unconfirmed = null; needsRefresh = true; }
      });
    } finally { if (mounted) setState(() => saving = false); }
  }

  Future<void> report(ParentReviewQuestion question) async {
    final data = detail;
    if (data == null) return;
    final sent = await showReportQuestionSheet(context, service: widget.service,
      attemptId: data.summary.attemptId, question: question, number: numberOf(question));
    if (!sent || !mounted) return;
    setState(() => reported.add(question.id));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Obrigado! O problema foi registado e vai ser analisado.')));
  }

  Widget reportButton(ParentReviewQuestion question) {
    final done = reported.contains(question.id);
    return Align(alignment: Alignment.centerRight, child: TextButton.icon(
      onPressed: () => report(question),
      iconAlignment: IconAlignment.end,
      icon: Icon(done ? Icons.check_circle_rounded : Icons.flag_outlined, size: 14),
      label: Text(done ? 'Reportado • reportar outro' : 'Reportar problema'),
      style: TextButton.styleFrom(
        // Discreto: ação secundária, não deve competir com a classificação.
        foregroundColor: (done ? AppColors.success : const Color(0xFFE5603E)).withValues(alpha: 0.55),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    ));
  }

  bool get blocked => loading || saving || needsRefresh || unconfirmed != null;
  List<ParentReviewQuestion> get openQuestions =>
      detail!.questions.where((q) => q.type != 'multiple-choice' && q.reviewable).toList();
  int numberOf(ParentReviewQuestion q) => detail!.questions.indexOf(q) + 1;

  void openReview(ParentReviewQuestion question) =>
      setState(() { stage = _Stage.review; reviewingQuestionId = question.id; });

  void startReview() {
    final open = openQuestions;
    if (open.isEmpty) return setState(() => stage = _Stage.finalize);
    final next = open.firstWhere((q) => q.review == null, orElse: () => open.first);
    openReview(next);
  }

  void nextAfter(ParentReviewQuestion current) {
    final open = openQuestions;
    final index = open.indexWhere((q) => q.id == current.id);
    // Próxima pendente depois desta; senão, qualquer pendente; senão, finalização.
    final after = [...open.skip(index + 1), ...open.take(index)].where((q) => q.review == null);
    if (after.isNotEmpty) return openReview(after.first);
    setState(() { stage = _Stage.finalize; reviewingQuestionId = null; });
  }

  @override
  Widget build(BuildContext context) {
    final data = detail;
    final current = stage ?? _Stage.summary;
    final (overline, title) = switch (current) {
      _Stage.summary => ('Revisão de ficha', 'Resumo da ficha'),
      _Stage.review => ('Revisão de ficha', 'Revisão da resposta'),
      _Stage.finalize => ('Revisão de ficha', 'Finalização'),
      _Stage.result => ('Revisão de ficha', 'Resultado final'),
    };
    final canLeave = !saving && unconfirmed == null;
    final bottom = data == null ? null : bottomBar(data, current);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop && canLeave) back(); },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(children: [
          _ReviewTopBar(overline: overline, title: title,
            onBack: canLeave ? back : null, onSaveAndExit: canLeave ? widget.onClose : null),
          Expanded(child: SingleChildScrollView(key: ValueKey('$current-$reviewingQuestionId'), child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (error != null) ...[errorBox(), const SizedBox(height: 20)],
                if (data == null || (loading && data.questions.isEmpty))
                  const Padding(padding: EdgeInsets.all(48), child: Center(
                    child: CircularProgressIndicator(semanticsLabel: 'A carregar a revisão')))
                else switch (current) {
                  _Stage.summary => summaryStage(data),
                  _Stage.review => reviewStage(data),
                  _Stage.finalize => finalizeStage(data),
                  _Stage.result => resultStage(data),
                },
              ]),
            ),
          )))),
          if (bottom != null) bottom,
        ]),
      ),
    );
  }

  double get gutter => MediaQuery.sizeOf(context).width < 640 ? 16 : 32;

  void back() {
    switch (stage) {
      case _Stage.review || _Stage.finalize:
        setState(() { stage = _Stage.summary; reviewingQuestionId = null; });
      case _Stage.result when detail?.summary.pendingReview != 0:
        setState(() => stage = _Stage.summary);
      default:
        widget.onClose();
    }
  }

  Widget errorBox() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
  ]);

  Widget? bottomBar(ParentAttemptReview data, _Stage current) {
    Widget bar(List<Widget> children) => Container(
      decoration: BoxDecoration(color: AppColors.background,
        border: const Border(top: BorderSide(color: AppColors.lavender)),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, -6))]),
      child: SafeArea(top: false, child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children))))),
    );
    switch (current) {
      case _Stage.summary:
        final pending = data.summary.pendingReview;
        return bar([AppButton(
          label: pending > 0 ? 'Rever respostas ($pending ${pending == 1 ? 'pendente' : 'pendentes'})'
            : openQuestions.isEmpty ? 'Ver resultado final' : 'Ver avaliações',
          icon: Icons.arrow_forward_rounded,
          onPressed: blocked ? null : (pending > 0 ? startReview : () => setState(() => stage = openQuestions.isEmpty ? _Stage.result : _Stage.finalize)),
        )]);
      case _Stage.review:
        final question = data.questions.where((q) => q.id == reviewingQuestionId).firstOrNull;
        if (question == null) return null;
        final open = openQuestions;
        final position = open.indexWhere((q) => q.id == question.id) + 1;
        final remaining = open.where((q) => q.review == null && q.id != question.id).length;
        return bar([
          AppButton(
            label: remaining > 0 ? 'Guardar e seguinte (${position < open.length ? position + 1 : 1} de ${open.length})' : 'Guardar e finalizar',
            icon: Icons.arrow_forward_rounded,
            onPressed: blocked || question.review == null ? null : () => nextAfter(question),
          ),
          TextButton(onPressed: blocked ? null : widget.onClose,
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            child: const Text('Pausar e guardar para mais tarde')),
        ]);
      case _Stage.finalize || _Stage.result:
        return null;
    }
  }

  // ---------- 2. Resumo da ficha entregue ----------
  Widget summaryStage(ParentAttemptReview data) {
    final s = data.summary;
    final choices = data.questions.where((q) => q.type == 'multiple-choice').toList();
    final written = data.questions.where((q) => q.type != 'multiple-choice').toList();
    final pending = s.pendingReview;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _WorksheetHeader(data: data),
      const SizedBox(height: 20),
      _Banner(
        color: pending > 0 ? const Color(0xFFFCE9DC) : AppColors.successSoft,
        iconBackground: pending > 0 ? const Color(0xFFFEA619) : AppColors.success,
        icon: pending > 0 ? Icons.pending_actions_rounded : Icons.task_alt_rounded,
        title: pending > 0 ? 'Ficha entregue' : 'Revisão concluída',
        badge: pending > 0 ? 'Aguarda revisão' : 'Concluída',
        badgeBackground: pending > 0 ? const Color(0xFFFFDDA8) : Colors.white,
        badgeColor: pending > 0 ? const Color(0xFF8A5300) : AppColors.success,
        text: pending > 0
            ? 'O resultado final só fica disponível depois de reveres ${pending == 1 ? 'a resposta aberta' : 'as $pending respostas abertas'} de ${data.child.displayName}.'
            : 'Todas as respostas abertas estão classificadas. Podes alterar uma classificação a qualquer momento.',
      ),
      const SizedBox(height: 20),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _StatTile(title: 'Escolha múltipla', icon: Icons.check_circle_outline_rounded, iconColor: const Color(0xFF10B981),
          value: '${s.choiceCorrect}', total: '/ ${s.choiceTotal}', badge: 'Corrigidas auto',
          badgeBackground: AppColors.successSoft, badgeColor: AppColors.success)),
        const SizedBox(width: 14),
        Expanded(child: _StatTile(title: 'Respostas abertas', icon: Icons.hourglass_bottom_rounded, iconColor: const Color(0xFFF59E0B),
          value: '${pending > 0 ? pending : s.writtenAnswered}', badge: pending > 0 ? 'Por rever' : 'Revistas',
          badgeBackground: pending > 0 ? AppColors.amberSoft : AppColors.successSoft, badgeColor: pending > 0 ? AppColors.amber : AppColors.success)),
      ]),
      Padding(padding: const EdgeInsets.fromLTRB(4, 28, 4, 12), child: Row(children: [
        const Expanded(child: Text('Estrutura das Perguntas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text))),
        Text('Total: ${data.questions.length} desafios', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
      ])),
      if (choices.isNotEmpty) _RowCard(
        leading: const CircleAvatar(radius: 26, backgroundColor: AppColors.softBlue,
          child: Icon(Icons.format_list_bulleted_rounded, color: AppColors.primary)),
        title: choices.length == 1 ? 'Pergunta ${numberOf(choices.first)}'
          : 'Perguntas ${numberOf(choices.first)} a ${numberOf(choices.last)}',
        subtitle: 'Escolha múltipla • correção automática',
        trailing: _PillButton(label: showChoices ? 'Ocultar' : 'Detalhes',
          icon: showChoices ? Icons.expand_less_rounded : Icons.expand_more_rounded,
          onPressed: () => setState(() => showChoices = !showChoices)),
        expanded: showChoices ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final q in choices) _ChoiceDetail(number: numberOf(q), question: q,
            reported: reported.contains(q.id), onReport: () => report(q)),
        ]) : null,
      ),
      for (final q in written) _RowCard(
        onTap: q.reviewable && !blocked ? () => openReview(q) : null,
        leading: CircleAvatar(radius: 26, backgroundColor: q.review == null && q.reviewable ? AppColors.amberSoft : AppColors.softBlue,
          child: Text('${numberOf(q)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text))),
        title: q.prompt,
        subtitleIcon: q.answerType == 'paper' ? Icons.menu_book_outlined : q.reviewable ? Icons.edit_note_rounded : Icons.remove_rounded,
        subtitle: q.answerType == 'paper' ? 'No caderno' : q.reviewable ? 'Resposta digital' : 'Sem resposta',
        trailing: !q.reviewable ? IconButton(tooltip: 'Reportar um problema nesta questão',
            onPressed: () => report(q), icon: Icon(reported.contains(q.id) ? Icons.flag_rounded : Icons.flag_outlined,
              color: reported.contains(q.id) ? AppColors.success : const Color(0xFFE5603E)))
          : q.review == null
          ? const AppBadge(label: 'Pendente', background: AppColors.amberSoft, color: AppColors.amber)
          : _ClassificationBadge(q.review!.classification),
      ),
      const SizedBox(height: 12),
      const _Tip(text: 'Dica: revê com calma para apoiar a aprendizagem, sem focar apenas na pontuação.'),
      if (s.unansweredTotal > 0) ...[
        const SizedBox(height: 10),
        _Tip(icon: Icons.info_outline_rounded,
          text: '${s.unansweredTotal} ${s.unansweredTotal == 1 ? 'pergunta ficou' : 'perguntas ficaram'} sem resposta e não precisam de revisão.'),
      ],
    ]);
  }

  // ---------- 3. Revisão de resposta aberta ----------
  Widget reviewStage(ParentAttemptReview data) {
    final question = data.questions.where((q) => q.id == reviewingQuestionId).firstOrNull;
    if (question == null) return const SizedBox.shrink();
    final open = openQuestions;
    final position = open.indexWhere((q) => q.id == question.id) + 1;
    final reviewed = open.where((q) => q.review != null).length;
    final percent = open.isEmpty ? 100 : (reviewed * 100 / open.length).round();
    final name = data.child.displayName;
    final saving = this.saving && unconfirmed?.answerId == question.answerId;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(28)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(radius: 15, backgroundColor: AppColors.lavender,
              child: Text('$position', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary))),
            const SizedBox(width: 10),
            Expanded(child: Text('Resposta aberta $position de ${open.length}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text))),
            AppBadge(label: 'Pergunta ${numberOf(question)} de ${data.questions.length}',
              background: AppColors.lavender, color: AppColors.text),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('Ficha de $name', style: const TextStyle(color: AppColors.muted))),
            Text('$percent% das abertas revistas', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(AppRadii.pill), child: LinearProgressIndicator(
            value: open.isEmpty ? 1 : reviewed / open.length, minHeight: 12,
            backgroundColor: AppColors.blueBorder, color: AppColors.primary)),
        ]),
      ),
      const SizedBox(height: 18),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.help_center_outlined, color: AppColors.primary, size: 20), SizedBox(width: 8),
          Text('ENUNCIADO DA PERGUNTA', style: TextStyle(fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppColors.primary)),
        ]),
        const SizedBox(height: 10),
        SelectableText('“${question.prompt}”', style: const TextStyle(fontSize: 22, height: 1.35, fontWeight: FontWeight.w700, color: AppColors.text)),
      ])),
      const SizedBox(height: 18),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('RESPOSTA DE ${name.toUpperCase()}',
            style: const TextStyle(fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppColors.muted))),
          AppBadge(label: question.answerType == 'paper' ? 'Respondido no caderno 📝' : 'Resposta digital',
            background: AppColors.lavender, color: AppColors.primary),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(18)),
          child: question.answerType == 'paper'
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const CircleAvatar(radius: 24, backgroundColor: AppColors.lavender,
                  child: Icon(Icons.menu_book_rounded, color: AppColors.primary)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Consulta o caderno de rascunho', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('$name indicou que resolveu no caderno. Espreita a folha para conferir a conta e a explicação antes de classificar.',
                    style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.muted)),
                ])),
              ])
            : SelectableText(question.text ?? '', style: const TextStyle(fontSize: 17, height: 1.5, color: AppColors.text)),
        ),
      ])),
      if (question.explanation.isNotEmpty) ...[
        const SizedBox(height: 14),
        _Expandable(icon: Icons.lightbulb_outline_rounded, iconColor: AppColors.amber,
          title: 'Ver sugestão de resposta e critérios', child: SelectableText(question.explanation,
            style: const TextStyle(fontSize: 15, height: 1.5))),
      ],
      Padding(padding: const EdgeInsets.fromLTRB(4, 24, 4, 12), child: Row(children: [
        const Expanded(child: Text('CLASSIFICAÇÃO RÁPIDA',
          style: TextStyle(fontSize: 14, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppColors.muted))),
        Text(saving ? 'A guardar…' : question.review != null ? 'Guardada ✓' : 'Toca para selecionar',
          style: TextStyle(color: question.review != null && !saving ? AppColors.success : AppColors.muted, fontWeight: FontWeight.w600)),
      ])),
      ReviewClassificationSelector(value: question.review?.classification, enabled: !blocked,
        onChanged: (classification) => classify(question, classification)),
      const SizedBox(height: 12),
      const Text('Cada escolha é guardada logo e podes alterá-la mais tarde.',
        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.muted)),
      const SizedBox(height: 6),
      reportButton(question),
    ]);
  }

  // ---------- 4. Finalização da revisão ----------
  Widget finalizeStage(ParentAttemptReview data) {
    final open = openQuestions;
    final reviewed = open.where((q) => q.review != null).length;
    final pending = data.summary.pendingReview;
    final total = data.questions.length;
    final done = total - pending;
    final name = data.child.displayName;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(32)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(radius: 32, backgroundColor: pending == 0 ? AppColors.success : AppColors.amber,
              child: Icon(pending == 0 ? Icons.verified_rounded : Icons.pending_actions_rounded, color: Colors.white, size: 34)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppBadge(label: pending == 0 ? 'Pronto a submeter' : 'Falta pouco', icon: Icons.done_all_rounded,
                background: pending == 0 ? const Color(0xFF87FE45) : AppColors.amberSoft,
                color: pending == 0 ? const Color(0xFF1F5100) : AppColors.amber),
              const SizedBox(height: 6),
              Text(pending == 0 ? 'Tudo revisto!' : 'Faltam $pending',
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.text)),
            ])),
          ]),
          const SizedBox(height: 12),
          Text(pending == 0 ? 'Confirma as tuas avaliações antes de fechar a ficha de $name.'
            : 'Ainda há respostas por classificar. Revê-as para concluir a ficha de $name.',
            style: const TextStyle(fontSize: 17, height: 1.45, color: AppColors.muted)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.lavender.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Icon(Icons.verified_outlined, color: pending == 0 ? AppColors.success : AppColors.amber),
              const SizedBox(width: 10),
              Expanded(child: Text(pending == 0 ? 'Todas as $total perguntas da ficha estão agora completas.'
                : '$done de $total perguntas completas.',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))),
            ]),
          ),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(4, 26, 4, 12), child: Row(children: [
        const Expanded(child: Text('RESPOSTAS ABERTAS REVISTAS',
          style: TextStyle(fontSize: 14, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppColors.muted))),
        Text('$reviewed de ${open.length} avaliadas', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
      ])),
      for (final q in open) Padding(padding: const EdgeInsets.only(bottom: 14), child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 20, backgroundColor: AppColors.softBlue,
              child: Text('${numberOf(q)}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q.prompt, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, height: 1.3, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 4),
              Text(q.answerType == 'paper' ? 'Pergunta aberta • resolvida no caderno' : 'Pergunta aberta • resposta digital',
                style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            ])),
            TextButton.icon(onPressed: blocked ? null : () => openReview(q), icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(q.review == null ? 'Rever' : 'Alterar')),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(AppRadii.pill)),
            child: q.review == null
              ? const Row(children: [Icon(Icons.hourglass_bottom_rounded, color: AppColors.amber), SizedBox(width: 10),
                  Text('Por classificar', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.amber))])
              : Builder(builder: (context) {
                  final style = classificationStyle(q.review!.classification);
                  return Row(children: [
                    CircleAvatar(radius: 14, backgroundColor: style.ink, child: Icon(style.icon, color: Colors.white, size: 18)),
                    const SizedBox(width: 10),
                    Text(q.review!.classification.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: style.ink)),
                  ]);
                }),
          ),
        ]),
      )),
      AppCard(padding: const EdgeInsets.all(20), child: Row(children: [
        SizedBox(width: 92, height: 92, child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(child: CircularProgressIndicator(value: total == 0 ? 1 : done / total, strokeWidth: 10,
            backgroundColor: AppColors.blueBorder, color: pending == 0 ? AppColors.success : AppColors.amber)),
          Text('$done/$total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
        ])),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pending == 0 ? 'Pronto para ver o resultado' : 'Quase pronto',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(pending == 0 ? 'A correção completa fica disponível no espaço de $name.'
            : 'A correção fica disponível para $name quando todas as respostas estiverem classificadas.',
            style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.muted)),
        ])),
      ])),
      const SizedBox(height: 28),
      AppButton(label: pending == 0 ? 'Concluir revisão' : 'Rever respostas em falta',
        icon: pending == 0 ? Icons.workspace_premium_rounded : Icons.arrow_forward_rounded,
        onPressed: blocked ? null : (pending == 0 ? () => setState(() => stage = _Stage.result) : startReview)),
      const SizedBox(height: 8),
      Center(child: TextButton.icon(onPressed: blocked ? null : widget.onClose,
        icon: const Icon(Icons.save_outlined), label: const Text('Guardar e voltar ao painel'),
        style: TextButton.styleFrom(foregroundColor: AppColors.muted))),
    ]);
  }

  // ---------- 5. Resultado final ----------
  Widget resultStage(ParentAttemptReview data) {
    final s = data.summary;
    final name = data.child.displayName;
    final total = data.questions.length;
    final achieved = s.choiceCorrect + s.writtenCorrect;
    final segments = <Color>[
      for (var i = 0; i < achieved; i++) const Color(0xFF10B981),
      for (var i = 0; i < s.writtenPartial; i++) const Color(0xFFF59E0B),
    ];
    while (segments.length < total) { segments.add(const Color(0xFFF1E4D3)); }
    final correct = data.questions.where(isCorrect).toList();
    final toPractise = data.questions.where((q) => !isCorrect(q)).toList();
    String shortList(List<ParentReviewQuestion> items) => items.take(2)
        .map((q) => '«${q.prompt.length > 60 ? '${q.prompt.substring(0, 57)}…' : q.prompt}»').join(' e ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(32),
          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.07), blurRadius: 20, offset: const Offset(0, 8))]),
        child: Column(children: [
          AppBadge(label: '$name • ${data.child.schoolYear}.º Ano', icon: Icons.face_rounded),
          const SizedBox(height: 14),
          Semantics(header: true, child: Text(s.pendingReview == 0 ? 'Ficha Concluída com Sucesso!' : 'Resultado provisório',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, height: 1.2, fontWeight: FontWeight.w800, color: AppColors.text))),
          const SizedBox(height: 6),
          Text('${s.subjectName} • ${s.title}', textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppColors.muted)),
          const SizedBox(height: 18),
          ExcludeSemantics(child: SizedBox(width: 128, height: 120, child: Stack(children: [
            Positioned(left: 0, top: 0, child: Container(width: 110, height: 110, alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.softBlue, shape: BoxShape.circle),
              child: Text(ChildAvatars.emoji(data.child.avatarId), style: const TextStyle(fontSize: 58)))),
            Positioned(right: 0, bottom: 0, child: Container(width: 44, height: 44,
              decoration: const BoxDecoration(color: Color(0xFFFBBF24), shape: BoxShape.circle),
              child: const Icon(Icons.star_rounded, color: Colors.white, size: 26))),
          ]))),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(20)),
            child: Column(children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '$achieved', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.primary)),
                TextSpan(text: ' de $total ', style: const TextStyle(fontSize: 20, color: AppColors.muted)),
                const TextSpan(text: 'conseguidas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text)),
              ]), semanticsLabel: '$achieved de $total conseguidas'),
              const SizedBox(height: 6),
              Text([
                if (s.choiceTotal > 0) '${s.choiceCorrect} ${s.choiceCorrect == 1 ? 'escolha múltipla certa' : 'escolhas múltiplas certas'}',
                if (s.writtenAnswered > 0) '${s.writtenCorrect} ${s.writtenCorrect == 1 ? 'aberta correta' : 'abertas corretas'}',
                if (s.writtenPartial > 0) '${s.writtenPartial} ${s.writtenPartial == 1 ? 'parcial' : 'parciais'}',
              ].join(' + '), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.muted)),
              const SizedBox(height: 14),
              ExcludeSemantics(child: Row(children: [
                for (var i = 0; i < segments.length; i++) Expanded(child: Container(height: 12,
                  margin: EdgeInsets.only(right: i == segments.length - 1 ? 0 : 5),
                  decoration: BoxDecoration(color: segments[i], borderRadius: BorderRadius.circular(AppRadii.pill)))),
              ])),
            ]),
          ),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(4, 28, 4, 12), child: Row(children: const [
        Expanded(child: Text('APRECIAÇÃO PEDAGÓGICA',
          style: TextStyle(fontSize: 15, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: AppColors.text))),
        Icon(Icons.visibility_outlined, color: AppColors.primary, size: 18), SizedBox(width: 6),
        Text('Para encarregados', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
      ])),
      _InsightCard(icon: Icons.check_circle_outline_rounded, iconBackground: const Color(0xFF87FE45), iconColor: AppColors.success,
        title: 'Ponto Forte', titleColor: AppColors.success,
        text: correct.isEmpty ? 'Completou a ficha até ao fim — o esforço também conta.'
          : 'Respondeu bem a ${correct.length} de $total perguntas, incluindo ${shortList(correct)}.'),
      const SizedBox(height: 12),
      _InsightCard(icon: Icons.lightbulb_outline_rounded, iconBackground: AppColors.amberSoft, iconColor: AppColors.amber,
        title: 'A Praticar Mais', titleColor: AppColors.amber,
        text: toPractise.isEmpty ? 'Nada a assinalar: todas as respostas estiveram corretas.'
          : 'Vale a pena rever ${shortList(toPractise)}${toPractise.length > 2 ? ' (e mais ${toPractise.length - 2})' : ''}.'),
      if (toPractise.isNotEmpty && widget.onPrepareWorksheet != null) ...[
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: const Color(0xFFFCE9EA), borderRadius: BorderRadius.circular(32)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.edit_note_rounded, color: Color(0xFF8A5300)), SizedBox(width: 8),
              Text('Sugestão de Continuidade', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF8A5300))),
            ]),
            const SizedBox(height: 10),
            const Text('Gostarias de reforçar este tema?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 8),
            Text('Uma nova ficha de ${s.subjectName} sobre os mesmos temas pode ajudar $name a consolidar o conceito, com tranquilidade e sem sobrecarga.',
              style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.muted)),
            const SizedBox(height: 18),
            AppButton(label: 'Preparar ficha de revisão ✏️', onPressed: widget.onPrepareWorksheet),
          ]),
        ),
      ],
      const SizedBox(height: 24),
      AppButton(label: 'Voltar ao Painel dos Pais', icon: Icons.dashboard_outlined, variant: AppButtonVariant.secondary,
        onPressed: blocked ? null : widget.onClose),
      const SizedBox(height: 8),
      Center(child: TextButton.icon(onPressed: () => setState(() { stage = _Stage.summary; showChoices = true; }),
        icon: const Icon(Icons.checklist_rtl_rounded), label: const Text('Ver todas as respostas e notas'))),
    ]);
  }

  bool isCorrect(ParentReviewQuestion q) => q.type == 'multiple-choice'
      ? q.answerType == 'multiple-choice' && q.selectedOptionId == q.correctOptionId
      : q.review?.classification == ReviewClassification.correct;
}

class _ReviewTopBar extends StatelessWidget {
  const _ReviewTopBar({required this.overline, required this.title, required this.onBack, required this.onSaveAndExit});
  final String overline, title;
  final VoidCallback? onBack, onSaveAndExit;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppColors.background, boxShadow: [
      BoxShadow(color: AppColors.primary.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 6))]),
    child: SafeArea(bottom: false, child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760),
      child: Padding(padding: const EdgeInsets.fromLTRB(8, 8, 16, 10), child: Row(children: [
        IconButton(onPressed: onBack, tooltip: 'Voltar', iconSize: 28, icon: const Icon(Icons.arrow_back_rounded)),
        const SizedBox(width: 4),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(overline.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, letterSpacing: 1.3, fontWeight: FontWeight.w700, color: AppColors.primary)),
          Semantics(header: true, child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.text))),
        ])),
        const SizedBox(width: 8),
        DecoratedBox(
          decoration: const BoxDecoration(borderRadius: BorderRadius.all(Radius.circular(AppRadii.pill)),
            boxShadow: [BoxShadow(color: AppColors.blueBorder, offset: Offset(0, 3))]),
          child: TextButton.icon(
            onPressed: onSaveAndExit,
            icon: const Icon(Icons.bookmark_border_rounded, size: 20),
            label: const Text('Guardar e sair'),
            style: TextButton.styleFrom(backgroundColor: AppColors.softBlue, foregroundColor: AppColors.text,
              minimumSize: const Size(48, 46), padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const StadiumBorder(side: BorderSide(color: AppColors.blueBorder)),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14)),
          ),
        ),
      ]))))),
  );
}

class _WorksheetHeader extends StatelessWidget {
  const _WorksheetHeader({required this.data});
  final ParentAttemptReview data;
  @override
  Widget build(BuildContext context) => AppCard(padding: const EdgeInsets.all(20), child: Row(children: [
    ExcludeSemantics(child: CircleAvatar(radius: 34, backgroundColor: AppColors.lavender,
      child: Icon(subjectIcon(data.summary.subjectName), color: AppColors.primary, size: 32))),
    const SizedBox(width: 16),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('FICHA DE ${data.summary.subjectName.toUpperCase()}', maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppColors.primary)),
      const SizedBox(height: 2),
      Text('${data.child.displayName} (${data.child.schoolYear}.º Ano)${data.summary.attemptNumber > 1 ? ' • Tentativa ${data.summary.attemptNumber}' : ''}',
        style: const TextStyle(fontSize: 14, color: AppColors.muted)),
      const SizedBox(height: 2),
      Text(data.summary.title, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 22, height: 1.25, fontWeight: FontWeight.w700, color: AppColors.text)),
    ])),
  ]));
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.iconBackground, required this.icon, required this.title,
    required this.badge, required this.badgeBackground, required this.badgeColor, required this.text});
  final Color color, iconBackground, badgeBackground, badgeColor;
  final IconData icon;
  final String title, badge, text;
  @override
  Widget build(BuildContext context) => Semantics(liveRegion: true, child: Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(32)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ExcludeSemantics(child: CircleAvatar(radius: 26, backgroundColor: iconBackground, child: Icon(icon, color: Colors.white))),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.text)),
          AppBadge(label: badge, background: badgeBackground, color: badgeColor),
        ]),
        const SizedBox(height: 6),
        Text(text, style: const TextStyle(fontSize: 16, height: 1.45, color: AppColors.text)),
      ])),
    ]),
  ));
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.title, required this.icon, required this.iconColor, required this.value,
    required this.badge, required this.badgeBackground, required this.badgeColor, this.total});
  final String title, value, badge;
  final String? total;
  final IconData icon;
  final Color iconColor, badgeBackground, badgeColor;
  @override
  Widget build(BuildContext context) => AppCard(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 15, color: AppColors.muted))),
      Icon(icon, color: iconColor),
    ]),
    const SizedBox(height: 10),
    Text.rich(TextSpan(children: [
      TextSpan(text: value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.text)),
      if (total != null) TextSpan(text: ' $total', style: const TextStyle(fontSize: 20, color: AppColors.muted)),
    ])),
    const SizedBox(height: 8),
    AppBadge(label: badge, background: badgeBackground, color: badgeColor),
  ]));
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.leading, required this.title, required this.subtitle, this.subtitleIcon,
    this.trailing, this.onTap, this.expanded});
  final Widget leading;
  final String title, subtitle;
  final IconData? subtitleIcon;
  final Widget? trailing, expanded;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12), child: AppCard(
    padding: const EdgeInsets.all(16), onTap: onTap,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        leading,
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 2),
          Row(children: [
            if (subtitleIcon != null) ...[Icon(subtitleIcon, size: 18, color: AppColors.muted), const SizedBox(width: 6)],
            Flexible(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: AppColors.muted))),
          ]),
        ])),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
      if (expanded != null) ...[const SizedBox(height: 12), expanded!],
    ]),
  ));
}

class _ChoiceDetail extends StatelessWidget {
  const _ChoiceDetail({required this.number, required this.question, required this.onReport, this.reported = false});
  final int number;
  final ParentReviewQuestion question;
  final VoidCallback onReport;
  final bool reported;
  @override
  Widget build(BuildContext context) {
    final answered = question.answerType == 'multiple-choice';
    final right = answered && question.selectedOptionId == question.correctOptionId;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(!answered ? Icons.remove_circle_outline_rounded : right ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: !answered ? AppColors.muted : right ? AppColors.success : AppColors.error),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$number. ${question.prompt}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Resposta: ${question.optionText(question.selectedOptionId)}', style: const TextStyle(fontSize: 13)),
          if (!right) Text('Correta: ${question.optionText(question.correctOptionId)}',
            style: const TextStyle(fontSize: 13, color: AppColors.success)),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: onReport,
            iconAlignment: IconAlignment.end,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              foregroundColor: (reported ? AppColors.success : const Color(0xFFE5603E)).withValues(alpha: 0.55)),
            icon: Icon(reported ? Icons.flag_rounded : Icons.flag_outlined, size: 14),
            label: Text(reported ? 'Problema reportado' : 'Reportar problema'))),
        ])),
      ]),
    );
  }
}

class _ClassificationBadge extends StatelessWidget {
  const _ClassificationBadge(this.value);
  final ReviewClassification value;
  @override
  Widget build(BuildContext context) {
    final style = classificationStyle(value);
    return AppBadge(label: value == ReviewClassification.partiallyCorrect ? 'Parcial' : value.label,
      icon: style.icon, background: style.soft, color: style.ink);
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(borderRadius: BorderRadius.all(Radius.circular(AppRadii.pill)),
      boxShadow: [BoxShadow(color: AppColors.blueBorder, offset: Offset(0, 3))]),
    child: TextButton.icon(onPressed: onPressed, iconAlignment: IconAlignment.end, icon: Icon(icon, size: 20), label: Text(label),
      style: TextButton.styleFrom(backgroundColor: AppColors.softBlue, foregroundColor: AppColors.primary,
        minimumSize: const Size(48, 44), padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: const StadiumBorder(side: BorderSide(color: AppColors.blueBorder)),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14))),
  );
}

class _Tip extends StatelessWidget {
  const _Tip({required this.text, this.icon = Icons.lightbulb_outline_rounded});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(24)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppColors.primary), const SizedBox(width: 12),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.muted))),
    ]),
  );
}

class _Expandable extends StatelessWidget {
  const _Expandable({required this.icon, required this.iconColor, required this.title, required this.child});
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => AppCard(padding: EdgeInsets.zero, child: Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [child],
    ),
  ));
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.icon, required this.iconBackground, required this.iconColor,
    required this.title, required this.titleColor, required this.text});
  final IconData icon;
  final Color iconBackground, iconColor, titleColor;
  final String title, text;
  @override
  Widget build(BuildContext context) => AppCard(padding: const EdgeInsets.all(20), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    ExcludeSemantics(child: CircleAvatar(radius: 26, backgroundColor: iconBackground, child: Icon(icon, color: iconColor))),
    const SizedBox(width: 14),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: titleColor)),
      const SizedBox(height: 4),
      Text(text, style: const TextStyle(fontSize: 16, height: 1.45, color: AppColors.text)),
    ])),
  ]));
}
