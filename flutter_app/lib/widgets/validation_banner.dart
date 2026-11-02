import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/exercise.dart';

class ValidationBanner extends StatefulWidget {
  const ValidationBanner({
    super.key,
    required this.exercise,
    required this.answers,
  });
  final Exercise exercise;
  final Map<String, String> answers;
  @override
  State<ValidationBanner> createState() => _ValidationBannerState();
}

class _ValidationBannerState extends State<ValidationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      animation.stop();
      animation.value = 1;
    } else if (animation.value == 0) {
      animation.forward();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    final celebrates = exercise.celebrates(widget.answers);
    final percent = exercise.percentage(widget.answers);
    final title = percent == null
        ? 'As tuas ideias merecem ser partilhadas!'
        : celebrates
        ? 'Boa! Estás a brilhar!'
        : 'Cada tentativa faz-te crescer!';
    final message = percent == null
        ? 'Revê as respostas escritas com um adulto e descobre o que já fizeste bem.'
        : celebrates
        ? 'O teu esforço está a dar frutos. Celebra esta conquista e continua a descobrir!'
        : 'Lê as explicações com calma e tenta outra vez. Os erros ajudam-nos a aprender. Tu consegues!';
    return Semantics(
      liveRegion: true,
      child: Container(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: celebrates ? const Color(0xfff1f5da) : const Color(0xffedf4ec),
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) => CustomPaint(
            foregroundPainter: celebrates && animation.value < 1
                ? _Confetti(animation.value)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  ExcludeSemantics(
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        animation.value < 1
                            ? -8 * math.sin(animation.value * math.pi * 10)
                            : 0,
                      ),
                      child: Text(
                        percent == null
                            ? '✏️'
                            : celebrates
                            ? '🌟'
                            : '🌱',
                        style: const TextStyle(fontSize: 56),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(message, textAlign: TextAlign.center),
                  if (percent != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '$percent% de acertos · ${exercise.correctCount(widget.answers)} de ${exercise.choices.length} perguntas de escolha múltipla',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Confetti extends CustomPainter {
  _Confetti(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    const colors = [
      Color(0xffe1ac3c),
      Color(0xff3a9071),
      Color(0xffdc7b68),
      Color(0xff8c86c0),
    ];
    for (var i = 0; i < 28; i++) {
      final phase = (progress * 2 + i / 28) % 1;
      final x = ((i * 37 + 5) % 100) / 100 * size.width;
      final y = phase * size.height;
      final paint = Paint()
        ..color = colors[i % colors.length].withAlpha(
          ((1 - phase) * 210).round(),
        );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(i + progress * math.pi * 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-3, -5, 6, 10),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Confetti oldDelegate) => oldDelegate.progress != progress;
}
