import 'package:flutter/widgets.dart';

class VaultMotion {
  static const Duration pressDuration = Duration(milliseconds: 100);
  static const Duration selectionDuration = Duration(milliseconds: 180);
  static const Duration pageTransitionDuration = Duration(milliseconds: 280);
  static const Duration sheetTransitionDuration = Duration(milliseconds: 320);

  static const Curve entryCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
}
