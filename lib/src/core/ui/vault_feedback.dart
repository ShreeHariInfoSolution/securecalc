import 'package:flutter/services.dart';

class VaultFeedback {
  static void selectionClick() {
    HapticFeedback.selectionClick();
  }

  static void lightImpact() {
    HapticFeedback.lightImpact();
  }

  static void mediumImpact() {
    HapticFeedback.mediumImpact();
  }
}
