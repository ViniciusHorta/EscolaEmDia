import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/parent_access_service.dart';

class ParentActivityBoundary extends StatefulWidget {
  const ParentActivityBoundary({super.key, required this.access, required this.child});
  final ParentAccessService access;
  final Widget child;
  @override
  State<ParentActivityBoundary> createState() => _ParentActivityBoundaryState();
}

class _ParentActivityBoundaryState extends State<ParentActivityBoundary> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(keyEvent);
  }
  bool keyEvent(KeyEvent event) {if (event is KeyDownEvent || event is KeyRepeatEvent) widget.access.activity(); return false;}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.access.check();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(keyEvent);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => MouseRegion(onHover: (_) => widget.access.activity(),
    child: Listener(onPointerDown: (_) => widget.access.activity(),
      onPointerSignal: (_) => widget.access.activity(), onPointerMove: (_) => widget.access.activity(), child: widget.child));
}
