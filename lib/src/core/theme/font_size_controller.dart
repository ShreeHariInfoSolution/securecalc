import 'package:flutter/material.dart';

/// Reactive Controller managing text size scale (Small: 0.9x, Medium: 1.0x, Large: 1.15x).
class FontSizeController extends ValueNotifier<double> {
  static final FontSizeController instance = FontSizeController._();

  FontSizeController._() : super(1.0);

  void setScale(double scale) {
    value = scale;
  }

  String get currentLabel {
    if (value <= 0.92) return 'Small';
    if (value >= 1.1) return 'Large';
    return 'Medium (Default)';
  }
}
