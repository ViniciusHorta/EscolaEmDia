import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/subject_icons.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../domain/worksheet_models.dart';

enum AssignmentStage { todo, paused, delivered }

extension AssignmentStageOf on AssignedWorksheet {
  AssignmentStage get stage => activeAttemptId != null
      ? AssignmentStage.paused
      : latestAttemptId == null ? AssignmentStage.todo : AssignmentStage.delivered;
}

/// Ficha nova em destaque (Stitch: O Meu Espaço de Estudo).
class AssignedWorksheetCard extends StatelessWidget {
  const AssignedWorksheetCard({super.key,required this.assignment,this.onStart,this.onRepeat,this.onViewFeedback});
  final AssignedWorksheet assignment;
  final VoidCallback? onStart,onRepeat,onViewFeedback;

  @override
  Widget build(BuildContext context) {
    final item = assignment.worksheet;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: AppColors.lavender, width: 2),
        boxShadow: [
          const BoxShadow(color: AppColors.blueBorder, offset: Offset(0, 5)),
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          const AppBadge(label: 'Preparada pelos teus pais', icon: Icons.favorite_border_rounded,
            background: AppColors.coralSoft, color: Color(0xFFE5603E)),
          AppBadge(label: '${item.questionCount} perguntas', icon: Icons.quiz_outlined),
          if (item.isSample) const AppBadge(label: 'Ficha de exemplo', background: AppColors.amberSoft, color: AppColors.amber),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          ExcludeSemantics(child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(22)),
            child: Icon(subjectIcon(item.subjectName), color: AppColors.amber, size: 38),
          )),
          const SizedBox(width: 18),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item.subjectName}: ${item.title}',
              style: const TextStyle(fontSize: 21, height: 1.3, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 4),
            Text(item.topicNames.isEmpty ? 'Desafio divertido e sem pressa' : item.topicNames.join(' • '),
              style: const TextStyle(fontSize: 15, color: AppColors.muted)),
          ])),
        ]),
        const SizedBox(height: 24),
        AppButton(label: 'Começar ✏️', onPressed: onStart),
      ]),
    );
  }
}

/// Linha compacta para fichas em pausa ou já entregues.
class AssignedWorksheetTile extends StatelessWidget {
  const AssignedWorksheetTile({super.key,required this.assignment,this.onStart,this.onRepeat,this.onViewFeedback});
  final AssignedWorksheet assignment;
  final VoidCallback? onStart,onRepeat,onViewFeedback;

  @override
  Widget build(BuildContext context) {
    final item = assignment.worksheet;
    final paused = assignment.stage == AssignmentStage.paused;
    final status = paused
        ? 'Progresso guardado'
        : assignment.latestAttemptStatus == 'pending_review'
            ? 'Entregue • os teus pais vão rever'
            : assignment.latestAttemptStatus == 'completed' ? 'Concluída' : 'Entregue';
    final attempt = assignment.latestAttemptNumber;
    final actions = <Widget>[
      if (paused)
        _PillAction(label: 'Continuar', icon: Icons.arrow_forward_rounded, onPressed: onStart)
      else if (assignment.latestCompletedAttemptId != null)
        _PillAction(label: 'Ver correção', icon: Icons.fact_check_outlined, onPressed: onViewFeedback)
      else
        _PillAction(label: 'Ver entrega', icon: Icons.arrow_forward_rounded, onPressed: onStart),
      if (assignment.canRepeat) _PillAction(label: 'Outra vez', icon: Icons.replay_rounded, onPressed: onRepeat),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.lavender, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ExcludeSemantics(child: CircleAvatar(radius: 28, backgroundColor: AppColors.lavender,
            child: Icon(subjectIcon(item.subjectName), color: AppColors.primary))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item.subjectName}: ${item.title}', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 2),
            Text(attempt != null && attempt > 1 ? '$status • Tentativa $attempt' : status,
              style: TextStyle(fontSize: 14, color: assignment.latestAttemptStatus == 'completed' && !paused
                ? AppColors.success : AppColors.muted, fontWeight: FontWeight.w600)),
          ])),
          if (actions.length == 1) ...[const SizedBox(width: 8), actions.single],
        ]),
        if (actions.length > 1) ...[
          const SizedBox(height: 14),
          Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: actions),
        ],
      ]),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      borderRadius: BorderRadius.all(Radius.circular(AppRadii.pill)),
      boxShadow: [BoxShadow(color: AppColors.blueBorder, offset: Offset(0, 3))],
    ),
    child: TextButton.icon(
      onPressed: onPressed,
      iconAlignment: IconAlignment.end,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: TextButton.styleFrom(
        backgroundColor: AppColors.softBlue,
        foregroundColor: AppColors.primary,
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const StadiumBorder(side: BorderSide(color: AppColors.blueBorder)),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 15),
      ),
    ),
  );
}
