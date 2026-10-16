import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class ChatGlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double size;
  final EdgeInsetsGeometry padding;
  final String? tooltip;
  final Color? customColor;

  const ChatGlassButton({
    super.key,
    required this.child,
    required this.onTap,
    this.size = 36,
    this.padding = EdgeInsets.zero,
    this.tooltip,
    this.customColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget button = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: size,
          height: size,
          padding: padding,
          decoration: BoxDecoration(
            color:
                customColor ??
                (isDark
                    ? const Color(0xFF2C2C2E).withValues(alpha: 0.75)
                    : Colors.white.withValues(alpha: 0.82)),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.glassBorder(isDark), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(child: child),
        ),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: tooltip != null
          ? Tooltip(message: tooltip!, child: button)
          : button,
    );
  }
}
