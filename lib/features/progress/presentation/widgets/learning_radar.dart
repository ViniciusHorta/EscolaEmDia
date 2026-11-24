import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../domain/learning_models.dart';

/// Cores das séries. A forma também as distingue (RNF08): Prática = linha contínua com quadrados;
/// Desempenho = linha tracejada com círculos.
abstract final class LearningColors {
  static const practice = Color(0xFFEA580C);
  static const practiceSoft = Color(0xFFFFEDD5);
  static const performance = Color(0xFF0284C7);
  static const performanceSoft = Color(0xFFE0F2FE);
}

/// Radar de Prática vs. Desempenho (0–100). Precisa de 3+ eixos; tocar num eixo, ponto ou rótulo
/// chama [onSelect]. A leitura acessível dos valores é feita pela lista que acompanha o radar.
class LearningRadar extends StatelessWidget {
  const LearningRadar({super.key, required this.axes, required this.onSelect, this.selectedId});
  final List<LearningAxis> axes;
  final ValueChanged<LearningAxis> onSelect;
  final String? selectedId;

  static const _labelWidth = 92.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final width = math.min(constraints.maxWidth, 420.0);
    final radius = math.min(width, 360.0) / 2 - 44;
    final height = radius * 2 + 84;
    final center = Offset(width / 2, height / 2);
    Offset point(int i, double r) {
      final angle = -math.pi / 2 + 2 * math.pi * i / axes.length;
      return center + Offset(math.cos(angle), math.sin(angle)) * r;
    }
    return Center(child: SizedBox(width: width, height: height, child: Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: ExcludeSemantics(child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final d = details.localPosition - center;
          if (d.distance > radius + 24) return;
          final angle = (math.atan2(d.dy, d.dx) + math.pi / 2) % (2 * math.pi);
          onSelect(axes[(angle / (2 * math.pi / axes.length)).round() % axes.length]);
        },
        child: CustomPaint(painter: _RadarPainter(axes: axes, center: center, radius: radius, selectedId: selectedId)),
      ))),
      for (var i = 0; i < axes.length; i++) () {
        final p = point(i, radius + 26);
        final left = (p.dx - _labelWidth / 2).clamp(0.0, width - _labelWidth);
        final selected = axes[i].id == selectedId;
        return Positioned(left: left, top: p.dy - 16, width: _labelWidth, child: Center(child: Material(
          color: selected ? LearningColors.practiceSoft : AppColors.softBlue,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => onSelect(axes[i]),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(axes[i].name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700,
                  color: selected ? LearningColors.practice : AppColors.text))),
          ),
        )));
      }(),
    ])));
  });
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.axes, required this.center, required this.radius, this.selectedId});
  final List<LearningAxis> axes;
  final Offset center;
  final double radius;
  final String? selectedId;

  Offset _point(int i, double value) {
    final angle = -math.pi / 2 + 2 * math.pi * i / axes.length;
    return center + Offset(math.cos(angle), math.sin(angle)) * (radius * value.clamp(0, 100) / 100);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = axes.length;
    final grid = Paint()..style = PaintingStyle.stroke..color = AppColors.blueBorder..strokeWidth = 1;
    for (final level in [20, 40, 60, 80, 100]) {
      final path = Path()..addPolygon([for (var i = 0; i < n; i++) _point(i, level.toDouble())], true);
      canvas.drawPath(path, grid..strokeWidth = level == 100 ? 1.5 : 1);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(center, _point(i, 100), grid..strokeWidth = 1);
      if (axes[i].id == selectedId) {
        canvas.drawLine(center, _point(i, 100), Paint()..color = LearningColors.practice.withValues(alpha: 0.4)..strokeWidth = 2);
      }
    }
    // Referência de equilíbrio da prática (80%).
    _dashed(canvas, Path()..addPolygon([for (var i = 0; i < n; i++) _point(i, 80)], true),
        Paint()..style = PaintingStyle.stroke..color = AppColors.outline..strokeWidth = 1, dash: 3, gap: 4);

    // Prática: mantém os zeros (§13.4).
    final practice = [for (var i = 0; i < n; i++) _point(i, axes[i].practice)];
    final practicePath = Path()..addPolygon(practice, true);
    canvas.drawPath(practicePath, Paint()..color = LearningColors.practice.withValues(alpha: 0.14));
    canvas.drawPath(practicePath, Paint()..style = PaintingStyle.stroke..color = LearningColors.practice
      ..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);

    // Desempenho: interrompido nos eixos sem dados (nunca desenhado como 0%).
    final perf = [for (var i = 0; i < n; i++) axes[i].performance == null ? null : _point(i, axes[i].performance!)];
    final stroke = Paint()..style = PaintingStyle.stroke..color = LearningColors.performance..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    if (perf.every((p) => p != null)) {
      final path = Path()..addPolygon(perf.cast<Offset>(), true);
      canvas.drawPath(path, Paint()..color = LearningColors.performance.withValues(alpha: 0.12));
    }
    for (var i = 0; i < n; i++) {
      final a = perf[i], b = perf[(i + 1) % n];
      if (a != null && b != null) _dashed(canvas, Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy), stroke, dash: 7, gap: 4);
    }

    final white = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5;
    for (final p in practice) {
      final r = Rect.fromCenter(center: p, width: 9, height: 9);
      canvas.drawRect(r, Paint()..color = LearningColors.practice);
      canvas.drawRect(r, white);
    }
    for (final p in perf.whereType<Offset>()) {
      canvas.drawCircle(p, 5, Paint()..color = LearningColors.performance);
      canvas.drawCircle(p, 5, white);
    }
  }

  void _dashed(Canvas canvas, Path path, Paint paint, {required double dash, required double gap}) {
    for (final ui.PathMetric metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.axes != axes || old.radius != radius || old.center != center || old.selectedId != selectedId;
}
