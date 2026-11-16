import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_preferences.dart';
import '../utils/shake_detector.dart';
import '../../features/calculator/presentation/pages/calculator_page.dart';
import '../../features/chat/domain/services/call_service.dart';
import '../../features/calling/domain/p2p_call_service.dart' as p2p;

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

    // Disable shake panic gesture while in an active or ringing call (voice/video)
    if (CallService.instance.state != CallState.idle ||
        p2p.P2pCallService.instance.callStateNotifier.value != p2p.CallState.idle) {
      debugPrint('[ShakePanic] Suppressing shake panic lock because call is in progress.');
      return;
    }

    HapticFeedback.heavyImpact();

    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');

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
