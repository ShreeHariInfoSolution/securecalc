import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_preferences.dart';
import '../utils/shake_detector.dart';
import '../../features/calculator/presentation/pages/calculator_page.dart';

/// Wraps secret vault pages to listen for real device shakes and instantly pop back to Calculator.
class ShakePanicWrapper extends StatefulWidget {
  final Widget child;

  const ShakePanicWrapper({
    super.key,
    required this.child,
  });

  @override
  State<ShakePanicWrapper> createState() => _ShakePanicWrapperState();
}

class _ShakePanicWrapperState extends State<ShakePanicWrapper> {
  ShakeDetector? _shakeDetector;

  @override
  void initState() {
    super.initState();
    _shakeDetector = ShakeDetector(
      onShake: _triggerInstantPanicLock,
    );
    _shakeDetector?.startListening();
  }

  void _triggerInstantPanicLock() {
    if (!mounted) return;
    if (!AppPreferences.getPanicShake()) return; // Respect saved setting

    HapticFeedback.heavyImpact();

    // Instantly navigate back to CalculatorPage clearing route history
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          return const CalculatorPage();
        },
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _shakeDetector?.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
