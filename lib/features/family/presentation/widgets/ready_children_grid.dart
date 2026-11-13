import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/family_models.dart';

/// Grelha do ecrã «Tudo a postos»: um cartão por criança (lado a lado) e, no fim,
/// um espaço tracejado para adicionar outra criança.
class ReadyChildrenGrid extends StatelessWidget {
  const ReadyChildrenGrid({
    super.key,
    required this.children,
    required this.onEnterChild,
    required this.onPrepareWorksheet,
    required this.onAddChild,
    this.highlightedChildId,
    this.busy = false,
  });

  final List<ChildProfile> children;
  final ValueChanged<String> onEnterChild;
  final ValueChanged<String> onPrepareWorksheet;
  final VoidCallback onAddChild;
  /// Criança acabada de guardar, assinalada com «Novo».
  final String? highlightedChildId;
  final bool busy;

  /// Altura mínima comum, para o espaço tracejado alinhar com os cartões.
  static const tileMinHeight = 300.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    const gap = 20.0;
    final columns = constraints.maxWidth >= 900 ? 3 : constraints.maxWidth >= 560 ? 2 : 1;
    final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
    return Wrap(spacing: gap, runSpacing: gap, children: [
      for (final child in children) SizedBox(width: width, child: _ChildTile(
        child: child,
        isNew: child.id == highlightedChildId,
        busy: busy,
        onEnter: () => onEnterChild(child.id),
        onPrepare: () => onPrepareWorksheet(child.id),
      )),
      SizedBox(width: width, child: _AddChildTile(onTap: busy ? null : onAddChild)),
    ]);
  });
}

class _ChildTile extends StatelessWidget {
  const _ChildTile({required this.child, required this.isNew, required this.busy, required this.onEnter, required this.onPrepare});
  final ChildProfile child;
  final bool isNew;
  final bool busy;
  final VoidCallback onEnter;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: ReadyChildrenGrid.tileMinHeight),
    child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 64, height: 64, alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.lavender, shape: BoxShape.circle),
          child: ExcludeSemantics(child: Text(ChildAvatars.emoji(child.avatarId), style: const TextStyle(fontSize: 36)))),
        const Spacer(),
        if (isNew) Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(AppRadii.pill)),
          child: const Text('Novo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
        ),
      ]),
      const SizedBox(height: 14),
      Text(child.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text('${child.schoolYear}.º Ano • ${ChildAvatars.label(child.avatarId)}',
        style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 20),
      AppButton(label: 'Entrar na área da criança', icon: Icons.rocket_launch_rounded,
        variant: AppButtonVariant.success, onPressed: busy ? null : onEnter),
      const SizedBox(height: 12),
      AppButton(label: 'Preparar uma ficha', icon: Icons.auto_stories_rounded,
        variant: AppButtonVariant.secondary, onPressed: busy ? null : onPrepare),
    ])),
  );
}

class _AddChildTile extends StatelessWidget {
  const _AddChildTile({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Adicionar criança',
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: CustomPaint(
          painter: const _DashedBorderPainter(color: AppColors.outline, radius: AppRadii.card),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: ReadyChildrenGrid.tileMinHeight),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: ExcludeSemantics(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                CircleAvatar(radius: 28, backgroundColor: AppColors.lavender,
                  child: Icon(Icons.add_rounded, size: 32, color: AppColors.primary)),
                SizedBox(height: 14),
                Text('Adicionar criança', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primary)),
                SizedBox(height: 4),
                Text('Cria o perfil de outro educando', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.muted)),
              ])),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 8.0, gap = 6.0, stroke = 2.0;
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = stroke;
    final rect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(stroke / 2), Radius.circular(radius));
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color || old.radius != radius;
}
