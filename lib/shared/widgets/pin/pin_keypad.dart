import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

/// Teclado numérico tátil (Stitch: Seleção de Perfil e PIN Infantil).
/// Canto inferior esquerdo: «Apagar» (último dígito; pressão longa limpa tudo).
/// Canto inferior direito: ajuda, se [onHelp] existir; caso contrário, «Limpar».
class PinKeypad extends StatelessWidget {
  const PinKeypad(
      {super.key,
      required this.onDigit,
      required this.onDelete,
      required this.onClear,
      this.onHelp,
      this.enabled = true});
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final VoidCallback? onHelp;
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * 2) / 3;
        Widget key({
          required String semantics,
          required VoidCallback action,
          VoidCallback? longPress,
          Widget? child,
          Color fill = AppColors.softBlue,
          Color shadow = AppColors.blueBorder,
        }) =>
            _TactileKey(
              width: width,
              semantics: semantics,
              enabled: enabled,
              onTap: action,
              onLongPress: longPress,
              fill: fill,
              shadow: shadow,
              child: child!,
            );
        const digitStyle = TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.text);
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (var i = 1; i <= 9; i++)
            key(semantics: '$i', action: () => onDigit('$i'), child: Text('$i', style: digitStyle)),
          key(
            semantics: 'Apagar último dígito',
            action: onDelete,
            longPress: onClear,
            fill: AppColors.coralSoft,
            shadow: const Color(0xFFFFC2B3),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.backspace_outlined, color: Color(0xFFE5603E), size: 22),
              SizedBox(width: 6),
              Flexible(child: Text('Apagar', maxLines: 1, overflow: TextOverflow.fade, softWrap: false,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFFE5603E)))),
            ]),
          ),
          key(semantics: '0', action: () => onDigit('0'), child: const Text('0', style: digitStyle)),
          if (onHelp != null)
            key(
              semantics: 'Ajuda com o PIN',
              action: onHelp!,
              child: const CircleAvatar(radius: 15, backgroundColor: Color(0xFFFBBF24),
                child: Icon(Icons.question_mark_rounded, color: Colors.white, size: 20)),
            )
          else
            key(
              semantics: 'Limpar PIN',
              action: onClear,
              child: const Icon(Icons.clear_all_rounded, color: AppColors.muted),
            ),
        ]);
      });
}

class _TactileKey extends StatefulWidget {
  const _TactileKey({
    required this.width,
    required this.semantics,
    required this.enabled,
    required this.onTap,
    required this.fill,
    required this.shadow,
    required this.child,
    this.onLongPress,
  });
  final double width;
  final String semantics;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color fill;
  final Color shadow;
  final Widget child;

  @override
  State<_TactileKey> createState() => _TactileKeyState();
}

class _TactileKeyState extends State<_TactileKey> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final down = pressed && widget.enabled;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semantics,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 70),
        width: widget.width,
        height: 64,
        transform: Matrix4.translationValues(0, down ? 3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: [BoxShadow(color: widget.enabled ? widget.shadow : AppColors.outline, offset: Offset(0, down ? 1 : 4))],
        ),
        child: Material(
          color: widget.enabled ? widget.fill : AppColors.softBlue.withValues(alpha: 0.6),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            onLongPress: widget.enabled ? widget.onLongPress : null,
            onHighlightChanged: (value) => setState(() => pressed = value),
            child: Center(child: Opacity(opacity: widget.enabled ? 1 : 0.45, child: widget.child)),
          ),
        ),
      ),
    );
  }
}
