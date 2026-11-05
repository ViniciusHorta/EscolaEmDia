import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// Botão redondo tátil (Stitch: pausa / perfil no topo das perguntas).
class RoundActionButton extends StatelessWidget {
  const RoundActionButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.filled = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: filled ? AppColors.primaryPressed : AppColors.blueBorder, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: filled ? AppColors.primary : AppColors.softBlue,
        shape: CircleBorder(side: filled ? BorderSide.none : const BorderSide(color: AppColors.blueBorder)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 52, height: 52, child: Icon(icon,
            semanticLabel: tooltip,
            color: filled ? Colors.white : AppColors.primary, size: 26)),
        ),
      ),
    ),
  );
}

/// Cabeçalho fixo: ação à esquerda, título com «Sem pressa, com calma», ação à direita.
class AttemptTopBar extends StatelessWidget {
  const AttemptTopBar({super.key, required this.title, this.subtitle = 'Sem pressa, com calma', this.leading, this.trailing});
  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppColors.background, boxShadow: [
      BoxShadow(color: AppColors.primary.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 6)),
    ]),
    child: SafeArea(bottom: false, child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(children: [
          leading ?? const SizedBox(width: 52),
          const SizedBox(width: 12),
          Expanded(child: Column(children: [
            Semantics(header: true, child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text))),
            const SizedBox(height: 2),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Flexible(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 15, fontWeight: FontWeight.w600))),
            ]),
          ])),
          const SizedBox(width: 12),
          trailing ?? const SizedBox(width: 52),
        ]),
      ),
    ))),
  );
}

/// Progresso por segmentos: respondidas a verde, atual a lilás, restantes em azul suave.
class SegmentedProgress extends StatelessWidget {
  const SegmentedProgress({super.key, required this.answered, required this.current});
  final List<bool> answered;
  final int current;

  @override
  Widget build(BuildContext context) {
    final count = answered.where((value) => value).length;
    return Semantics(
      label: 'Pergunta ${current + 1} de ${answered.length}. $count respondidas.',
      child: ExcludeSemantics(child: Row(children: [
        for (var i = 0; i < answered.length; i++) Expanded(child: Container(
          height: 10,
          margin: EdgeInsets.only(right: i == answered.length - 1 ? 0 : 6),
          decoration: BoxDecoration(
            color: i == current ? AppColors.primary : answered[i] ? const Color(0xFF10B981) : AppColors.blueBorder,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
        )),
      ])),
    );
  }
}

/// Enunciado em destaque; números (e a palavra seguinte) a lilás, como no Stitch.
class HighlightedPrompt extends StatelessWidget {
  const HighlightedPrompt(this.text, {super.key, this.fontSize = 26});
  final String text;
  final double fontSize;

  static final _number = RegExp(r'\d+(?:[.,/]\d+)?(?:\s+[A-Za-zÀ-ÿ]+)?');

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: fontSize, height: 1.35, fontWeight: FontWeight.w700, color: AppColors.text);
    final spans = <TextSpan>[];
    var last = 0;
    for (final match in _number.allMatches(text)) {
      if (match.start > last) spans.add(TextSpan(text: text.substring(last, match.start)));
      spans.add(TextSpan(text: match.group(0), style: const TextStyle(color: AppColors.primary)));
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}
