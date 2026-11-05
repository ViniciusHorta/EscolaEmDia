import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.onChanged,
    this.errorText,
    this.enabled = true,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.obscureText = false,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final bool enabled;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    onChanged: onChanged,
    enabled: enabled,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    validator: validator,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    obscureText: obscureText,
    autocorrect: !obscureText && keyboardType != TextInputType.emailAddress && keyboardType != TextInputType.visiblePassword,
    enableSuggestions: !obscureText && keyboardType != TextInputType.visiblePassword,
    autofillHints: autofillHints,
    textInputAction: textInputAction,
    onFieldSubmitted: onSubmitted,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      errorMaxLines: 3,
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      suffixIcon: suffixIcon,
    ),
  );
}
