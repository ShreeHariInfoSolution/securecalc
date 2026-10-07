import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Highly reliable physical device accelerometer shake detector.
class ShakeDetector {
  final VoidCallback onShake;
  final double shakeThresholdGravity;
  final int shakeSlopTimeMs;

  StreamSubscription<AccelerometerEvent>? _subscription;
  int _lastShakeTime = 0;

  ShakeDetector({
    required this.onShake,
    this.shakeThresholdGravity = 2.0, // Sensitive gForce threshold
    this.shakeSlopTimeMs = 500,
  });

  /// Starts listening to physical device accelerometer sensor.
  void startListening() {
    stopListening();

    try {
      _subscription = accelerometerEventStream().listen(
        (AccelerometerEvent event) {
          final double x = event.x;
          final double y = event.y;
          final double z = event.z;

          // Calculate gForce magnitude relative to standard earth gravity (9.8 m/s²)
          final double gX = x / 9.80665;
          final double gY = y / 9.80665;
          final double gZ = z / 9.80665;

          final double gForce = sqrt(gX * gX + gY * gY + gZ * gZ);

          if (gForce > shakeThresholdGravity) {
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastShakeTime < shakeSlopTimeMs) {
              return;
            }
            _lastShakeTime = now;
            HapticFeedback.heavyImpact();
            onShake();
          }
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  /// Stops sensor subscription.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}
