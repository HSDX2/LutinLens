import 'package:flutter/material.dart';

// Compatibility shim for Flutter versions prior to Color.withValues.
// If the SDK already provides withValues, the instance member is used and
// this extension is ignored. We only support the 'alpha' named argument here
// because the codebase only uses it.
extension ColorWithValuesCompat on Color {
  Color withValues({double? alpha, double? red, double? green, double? blue}) {
    final int curA = (value >> 24) & 0xFF;
    final int curR = (value >> 16) & 0xFF;
    final int curG = (value >> 8) & 0xFF;
    final int curB = value & 0xFF;
    final int ai = ((alpha != null ? alpha.clamp(0.0, 1.0) as double : curA / 255.0) * 255.0).round();
    final int r = ((red != null ? red.clamp(0.0, 1.0) as double : curR / 255.0) * 255.0).round();
    final int g = ((green != null ? green.clamp(0.0, 1.0) as double : curG / 255.0) * 255.0).round();
    final int b = ((blue != null ? blue.clamp(0.0, 1.0) as double : curB / 255.0) * 255.0).round();
    return Color.fromARGB(ai, r, g, b);
  }
}
