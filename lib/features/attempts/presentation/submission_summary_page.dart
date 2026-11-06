import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../domain/submission_summary.dart';
import 'widgets/attempt_chrome.dart';

/// Stitch: 5. Ficha Concluída e Celebração.
class SubmissionSummaryPage extends StatelessWidget {
  const SubmissionSummaryPage({super.key,required this.summary,required this.onClose,required this.onParents,this.onViewLocalDraft,this.onRepeat,this.errorMessage,this.onViewFeedback,this.onRefreshResult,this.loadingResult=false,this.childName,this.childEmoji});
  final SubmissionSummary summary;
  final VoidCallback onClose,onParents;
  final VoidCallback? onViewLocalDraft,onRepeat,onViewFeedback,onRefreshResult;
  final bool loadingResult;
  final String? errorMessage;
  final String? childName;
  final String? childEmoji;

  @override
  Widget build(BuildContext context) {
    final gutter = MediaQuery.sizeOf(context).width < 640 ? 16.0 : 32.0;
    final reviewed = summary.writtenCorrect + summary.writtenPartial + summary.writtenIncorrect;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        AttemptTopBar(
          title: summary.status == 'completed' ? 'Ficha concluída' : 'Ficha entregue',
          leading: RoundActionButton(icon: Icons.home_rounded, tooltip: 'Voltar ao meu espaço', onPressed: onClose),
          trailing: RoundActionButton(icon: Icons.lock_outline_rounded, tooltip: 'Área do responsável', filled: true, onPressed: onParents),
        ),
        Expanded(child: SingleChildScrollView(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _CelebrationHero(summary: summary, childName: childName, childEmoji: childEmoji),
              const SizedBox(height: 28),
              AppCard(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const ExcludeSemantics(child: CircleAvatar(radius: 28, backgroundColor: AppColors.lavender,
                    child: Icon(Icons.task_alt_rounded, color: AppColors.primary, size: 30))),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Semantics(header: true, child: const Text('Resumo de Hoje',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text))),
                    const Text('Tudo feito ao teu ritmo e sem pressa',
                      style: TextStyle(color: AppColors.muted, fontSize: 15, fontWeight: FontWeight.w600)),
                  ])),
                ]),
                const SizedBox(height: 20),
                if (summary.choiceTotal > 0) _SummaryRow(
                  icon: Icons.checklist_rounded,
                  label: 'Perguntas de escolha múltipla:',
                  value: '${summary.choiceCorrect} ${summary.choiceCorrect == 1 ? 'certa' : 'certas'} em ${summary.choiceTotal}',
                ),
                if (reviewed > 0) _SummaryRow(
                  icon: Icons.rate_review_outlined,
                  label: 'Respostas abertas revistas:',
                  value: '${summary.writtenCorrect} certas'
                      '${summary.writtenPartial > 0 ? ', ${summary.writtenPartial} quase' : ''}'
                      '${summary.writtenIncorrect > 0 ? ', ${summary.writtenIncorrect} a melhorar' : ''}',
                ),
                if (summary.choiceTotal == 0 && reviewed == 0 && summary.pendingReview == 0)
                  const _SummaryRow(icon: Icons.save_outlined, label: 'O teu trabalho ficou guardado.', value: 'Sem nota automática'),
                if (summary.pendingReview > 0) _NoteRow(
                  color: const Color(0xFFFFF4E6),
                  iconBackground: const Color(0xFFFEA619),
                  icon: Icons.family_restroom_rounded,
                  child: Text.rich(TextSpan(style: const TextStyle(fontSize: 16, height: 1.45, color: AppColors.text), children: [
                    TextSpan(text: summary.pendingReview == 1
                        ? '1 resposta para o teu responsável ler no '
                        : '${summary.pendingReview} respostas para o teu responsável ler no '),
                    const TextSpan(text: 'Painel do Responsável', style: TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: ' 💛'),
                  ])),
                ),
                if (summary.unansweredTotal > 0) _NoteRow(
                  color: AppColors.softBlue,
                  iconBackground: AppColors.blueBorder,
                  icon: Icons.help_outline_rounded,
                  iconColor: AppColors.primary,
                  child: Text(summary.unansweredTotal == 1
                      ? '1 pergunta ficou sem resposta. Não faz mal!'
                      : '${summary.unansweredTotal} perguntas ficaram sem resposta. Não faz mal!',
                    style: const TextStyle(fontSize: 16, height: 1.45, color: AppColors.text)),
                ),
              ])),
              if (errorMessage != null) ...[
                const SizedBox(height: 16),
                AppCard(color: AppColors.coralSoft, child: Semantics(liveRegion: true, child: Text(errorMessage!))),
              ],
              if (onViewLocalDraft != null) ...[
                const SizedBox(height: 20),
                const AppCard(child: Text('Existem alterações neste dispositivo que não foram incluídas na entrega confirmada. Podes consultá-las sem alterar a ficha entregue.')),
                const SizedBox(height: 12),
                AppButton(label: 'Consultar alterações locais', variant: AppButtonVariant.secondary, onPressed: onViewLocalDraft),
              ],
              const SizedBox(height: 32),
              if (onViewFeedback != null) ...[
                AppButton(label: 'Ver a correção', icon: Icons.fact_check_outlined, variant: AppButtonVariant.success, onPressed: onViewFeedback),
                const SizedBox(height: 16),
              ] else if (summary.pendingReview > 0) ...[
                const Text('A correção detalhada fica disponível quando o teu responsável terminar a revisão.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 14)),
                const SizedBox(height: 12),
                AppButton(label: 'Atualizar resultado', variant: AppButtonVariant.secondary,
                  icon: Icons.refresh_rounded, loading: loadingResult, onPressed: onRefreshResult),
                const SizedBox(height: 16),
              ],
              AppButton(label: 'Voltar ao meu espaço', icon: Icons.home_rounded, onPressed: onClose),
              if (onRepeat != null) ...[
                const SizedBox(height: 16),
                AppButton(label: 'Fazer outra vez', icon: Icons.replay_rounded, variant: AppButtonVariant.neutral, onPressed: onRepeat),
              ],
            ]),
          ),
        )))),
      ]),
    );
  }
}

class _CelebrationHero extends StatelessWidget {
  const _CelebrationHero({required this.summary, this.childName, this.childEmoji});
  final SubmissionSummary summary;
  final String? childName;
  final String? childEmoji;

  @override
  Widget build(BuildContext context) {
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFFE5DEFF), Color(0xFFF7F5FF)]),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Stack(children: [
        Positioned.fill(child: ExcludeSemantics(child: TweenAnimationBuilder<double>(
          tween: Tween(begin: animate ? 0 : 1, end: 1),
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => CustomPaint(painter: _ConfettiPainter(t)),
        ))),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 36),
          child: Column(children: [
            ExcludeSemantics(child: TweenAnimationBuilder<double>(
              tween: Tween(begin: animate ? 0.6 : 1, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: SizedBox(width: 168, height: 160, child: Stack(children: [
                Positioned(left: 0, top: 0, child: Container(
                  width: 150, height: 150,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 6),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.12), blurRadius: 18)],
                  ),
                  alignment: Alignment.center,
                  child: Text(childEmoji ?? '🎉', style: const TextStyle(fontSize: 76)),
                )),
                Positioned(right: 0, bottom: 0, child: Container(
                  width: 56, height: 56,
                  decoration: const BoxDecoration(color: Color(0xFFFBBF24), shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Color(0xFFD97706), offset: Offset(0, 3))]),
                  child: const Icon(Icons.star_rounded, color: Colors.white, size: 34),
                )),
              ])),
            )),
            const SizedBox(height: 20),
            const AppBadge(label: 'Tudo pronto e entregue', icon: Icons.circle,
              color: AppColors.success, background: AppColors.successSoft),
            const SizedBox(height: 14),
            Semantics(header: true, child: Text(
              childName == null ? 'Muito bem! 🎉' : 'Muito bem, $childName! 🎉',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 34, height: 1.2, fontWeight: FontWeight.w800, color: AppColors.primary),
            )),
            const SizedBox(height: 16),
            const Text('A tua ficha foi entregue!', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 8),
            Text(summary.title, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.primary)),
            const SizedBox(height: 10),
            const Text('Fizeste um excelente esforço hoje. Desafios completados com calma e dedicação!',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 17, height: 1.5, color: AppColors.muted)),
            if (summary.attemptNumber > 1) ...[
              const SizedBox(height: 14),
              AppBadge(label: 'Tentativa ${summary.attemptNumber}', icon: Icons.history_rounded),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Confetes decorativos fixos (semente constante), concentrados nas margens
/// para não tapar o texto. [progress] faz uma queda curta de entrada.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress);
  final double progress;

  static const colors = [Color(0xFF7C6BF0), Color(0xFF10B981), Color(0xFF1CB0F6), Color(0xFFFBBF24), Color(0xFFFF7A59)];
  static final pieces = () {
    final random = Random(7);
    return List.generate(34, (i) {
      // Metade nas margens laterais, metade no topo.
      final side = i.isEven;
      final x = side ? (random.nextBool() ? random.nextDouble() * 0.07 : 0.93 + random.nextDouble() * 0.07) : random.nextDouble();
      final y = side ? random.nextDouble() : random.nextDouble() * 0.16;
      return (x: x, y: y, size: 6 + random.nextDouble() * 10, angle: random.nextDouble() * pi,
        color: colors[random.nextInt(colors.length)], round: random.nextInt(3) == 0);
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final piece in pieces) {
      final dy = (1 - progress) * -60;
      final center = Offset(piece.x * size.width, piece.y * size.height + dy);
      paint.color = piece.color.withValues(alpha: 0.85 * progress.clamp(0, 1));
      if (piece.round) {
        canvas.drawCircle(center, piece.size / 2, paint);
      } else {
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(piece.angle + (1 - progress) * 2);
        canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: piece.size * 1.6, height: piece.size), const Radius.circular(3)), paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => oldDelegate.progress != progress;
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(20)),
    child: Row(children: [
      Icon(icon, color: AppColors.primary),
      const SizedBox(width: 12),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
      const SizedBox(width: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(AppRadii.pill)),
        child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
      ),
    ]),
  );
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.color, required this.iconBackground, required this.icon, required this.child, this.iconColor = Colors.white});
  final Color color;
  final Color iconBackground;
  final Color iconColor;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
    child: Row(children: [
      ExcludeSemantics(child: CircleAvatar(radius: 26, backgroundColor: iconBackground, child: Icon(icon, color: iconColor))),
      const SizedBox(width: 16),
      Expanded(child: child),
    ]),
  );
}
