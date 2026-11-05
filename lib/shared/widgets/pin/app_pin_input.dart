import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_tokens.dart';
import 'pin_indicators.dart';
import 'pin_keypad.dart';

class AppPinInput extends StatefulWidget {
  const AppPinInput(
      {super.key,
      required this.label,
      required this.onChanged,
      this.onCompleted,
      this.errorText,
      this.length = 4,
      this.enabled = true})
      : assert(length > 0);
  final String label;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final String? errorText;
  final int length;
  final bool enabled;

  @override
  State<AppPinInput> createState() => _AppPinInputState();
}

class _AppPinInputState extends State<AppPinInput> {
  final controller = TextEditingController();
  final focus = FocusNode();

  void update(String value) {
    if (!widget.enabled || value == controller.text) return;
    controller.value = TextEditingValue(
        text: value, selection: TextSelection.collapsed(offset: value.length));
    notify(value);
  }

  void notify(String value) {
    setState(() {});
    widget.onChanged(value);
    if (value.length == widget.length) widget.onCompleted?.call(value);
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          SizedBox(
              height: 64,
              child: Stack(children: [
                Positioned.fill(
                    child: IgnorePointer(
                        child: PinIndicators(
                            filled: controller.text.length,
                            length: widget.length,
                            hasError: widget.errorText != null,
                            enabled: widget.enabled))),
                Positioned.fill(
                    child: Semantics(
                        label: widget.label,
                        child: TextField(
                          controller: controller,
                          focusNode: focus,
                          enabled: widget.enabled,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          enableInteractiveSelection: false,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(widget.length)
                          ],
                          style: const TextStyle(color: Colors.transparent),
                          showCursor: false,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(
                                    color: AppColors.primary, width: 2)),
                            disabledBorder: InputBorder.none,
                            filled: false,
                            labelText: null,
                            hintText: null,
                            counterText: '',
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: notify,
                        ))),
              ])),
          if (widget.errorText != null) ...[
            const SizedBox(height: 10),
            Semantics(
                liveRegion: true,
                child: Text(widget.errorText!,
                    style: const TextStyle(color: AppColors.error))),
          ],
          const SizedBox(height: 20),
          PinKeypad(
            enabled: widget.enabled,
            onDigit: (digit) {
              if (controller.text.length < widget.length) {
                update(controller.text + digit);
              }
            },
            onDelete: () {
              if (controller.text.isNotEmpty) {
                update(
                    controller.text.substring(0, controller.text.length - 1));
              }
            },
            onClear: () => update(''),
          ),
        ]),
      );
}
