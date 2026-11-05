import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';

/// neutral: botão branco com contorno lavanda (DESIGN.md «Ghost / Neutral Button»).
enum AppButtonVariant { primary, secondary, success, neutral }

class AppButton extends StatefulWidget {
  const AppButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.icon,
      this.variant = AppButtonVariant.primary,
      this.loading = false,
      this.expand = true});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool loading;
  final bool expand;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  final states = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    states.addListener(_stateChanged);
  }

  void _stateChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    states.removeListener(_stateChanged);
    states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressed = states.value.contains(WidgetState.pressed);
    final enabled = widget.onPressed != null && !widget.loading;
    final secondary = widget.variant == AppButtonVariant.secondary;
    final neutral = widget.variant == AppButtonVariant.neutral;
    final (fill, shadow, foreground) = switch (widget.variant) {
      AppButtonVariant.primary => (
          AppColors.primary,
          AppColors.primaryPressed,
          Colors.white
        ),
      AppButtonVariant.secondary => (
          AppColors.softBlue,
          AppColors.blueBorder,
          AppColors.primary
        ),
      AppButtonVariant.success => (
          AppColors.success,
          AppColors.successPressed,
          Colors.white
        ),
      AppButtonVariant.neutral => (
          AppColors.surface,
          AppColors.blueBorder,
          AppColors.text
        ),
    };
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 90);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: AnimatedContainer(
        duration: duration,
        transform: Matrix4.translationValues(0, pressed && enabled ? 4 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: [
            BoxShadow(
                color: enabled ? shadow : AppColors.outline,
                offset: Offset(0, pressed && enabled ? 1 : 5))
          ],
        ),
        child: FilledButton(
          onPressed: enabled ? widget.onPressed : null,
          statesController: states,
          style: FilledButton.styleFrom(
            backgroundColor: fill,
            foregroundColor: foreground,
            disabledBackgroundColor: AppColors.softBlue,
            disabledForegroundColor: AppColors.muted,
            minimumSize: const Size(48, 56),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
            shape: StadiumBorder(
                side: secondary
                    ? const BorderSide(color: AppColors.blueBorder)
                    : neutral
                        ? const BorderSide(color: AppColors.lavender, width: 2)
                        : BorderSide.none),
            textStyle: Theme.of(context).textTheme.labelLarge,
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading) ...[
                SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.muted,
                        semanticsLabel: 'A carregar')),
                const SizedBox(width: 10),
              ] else if (widget.icon != null) ...[
                Icon(widget.icon, size: 22),
                const SizedBox(width: 10),
              ],
              Flexible(child: Text(widget.label, textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    );
  }
}
