import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/request_id.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../data/pending_reviews_service.dart';
import '../../domain/parent_review_models.dart';

/// Abre a folha para reportar um problema numa pergunta. Devolve `true` se o
/// relato ficou gravado na base de dados.
Future<bool> showReportQuestionSheet(BuildContext context, {required PendingReviewsService service,
    required String attemptId, required ParentReviewQuestion question, required int number}) async =>
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (_) => _ReportQuestionSheet(service: service, attemptId: attemptId, question: question, number: number),
  ) ?? false;

class _ReportQuestionSheet extends StatefulWidget {
  const _ReportQuestionSheet({required this.service, required this.attemptId, required this.question, required this.number});
  final PendingReviewsService service;
  final String attemptId;
  final ParentReviewQuestion question;
  final int number;
  @override
  State<_ReportQuestionSheet> createState() => _ReportQuestionSheetState();
}

class _ReportQuestionSheetState extends State<_ReportQuestionSheet> {
  static const minLength = 5, maxLength = 1000;
  final message = TextEditingController();
  // Um identificador por relato: repetir após falha de rede não duplica o registo.
  final requestId = newRequestId();
  QuestionReportReason? reason;
  bool sending = false;
  String? error;

  bool get valid => reason != null && message.text.trim().length >= minLength;

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (sending || !valid) return;
    FocusScope.of(context).unfocus();
    setState(() { sending = true; error = null; });
    try {
      await widget.service.reportQuestion(attemptId: widget.attemptId, questionId: widget.question.id,
        reason: reason!, message: message.text, requestId: requestId);
      if (mounted) Navigator.of(context).pop(true);
    } on PendingReviewsException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível enviar o relato. Tenta novamente.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(top: false, child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const CircleAvatar(radius: 22, backgroundColor: AppColors.coralSoft,
            child: Icon(Icons.flag_outlined, color: Color(0xFFE5603E))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: const Text('Reportar um problema',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.text))),
            Text('Pergunta ${widget.number}', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          ])),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(18)),
          child: Text(widget.question.prompt, maxLines: 4, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.text)),
        ),
        const SizedBox(height: 18),
        const Text('O que aconteceu?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final item in QuestionReportReason.values) ChoiceChip(
            label: Text(item.label),
            selected: reason == item,
            selectedColor: AppColors.lavender,
            onSelected: sending ? null : (_) => setState(() { reason = item; error = null; }),
          ),
        ]),
        const SizedBox(height: 18),
        const Text('Descreve o problema', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 10),
        TextField(
          controller: message,
          enabled: !sending,
          minLines: 4,
          maxLines: 8,
          maxLength: maxLength,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => error = null),
          decoration: InputDecoration(
            hintText: 'Ex.: a resposta indicada como correta é a 2/4, mas devia ser 1/4.',
            filled: true,
            fillColor: AppColors.softBlue,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: AppColors.primary, width: 2)),
            helperText: 'Mínimo de $minLength caracteres. Não incluas dados pessoais da criança.',
            helperMaxLines: 2,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(error!, style: const TextStyle(color: AppColors.error))),
        ],
        const SizedBox(height: 16),
        AppButton(label: 'Enviar relato', icon: Icons.send_rounded, loading: sending, onPressed: valid && !sending ? send : null),
        const SizedBox(height: 4),
        TextButton(onPressed: sending ? null : () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
      ]),
    )),
  );
}
