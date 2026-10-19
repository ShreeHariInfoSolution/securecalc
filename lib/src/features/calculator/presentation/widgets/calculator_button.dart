import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum CalculatorButtonType {
  digit,
  operator,
  function,
}

class CalculatorButton extends StatefulWidget {
  final String label;
  final CalculatorButtonType type;
  final VoidCallback onTap;
  final bool isZero;
  final bool isSelected;
  final double? buttonSize;
  final double? buttonHeight;
  final bool isTablet;

  const CalculatorButton({
    super.key,
    required this.label,
    required this.onTap,
    this.type = CalculatorButtonType.digit,
    this.isZero = false,
    this.isSelected = false,
    this.buttonSize,
    this.buttonHeight,
    this.isTablet = false,
  });

  @override
  State<CalculatorButton> createState() => _CalculatorButtonState();
}

class _CalculatorButtonState extends State<CalculatorButton> {
  bool _isPressed = false;

  Color get _backgroundColor {
    if (widget.isSelected) {
      return Colors.white;
    }
    switch (widget.type) {
      case CalculatorButtonType.function:
        if (widget.isTablet) {
          return _isPressed ? const Color(0xFF8E8E93) : const Color(0xFF636366);
        }
        return _isPressed ? const Color(0xFFD9D9D9) : const Color(0xFFA5A5A5);
      case CalculatorButtonType.operator:
        return _isPressed ? const Color(0xFFF2C078) : const Color(0xFFFF9F0A);
      case CalculatorButtonType.digit:
        if (widget.isTablet) {
          return _isPressed ? const Color(0xFF505054) : const Color(0xFF2C2C2E);
        }
        return _isPressed ? const Color(0xFF737373) : const Color(0xFF333333);
    }
  }

  Color get _textColor {
    if (widget.isSelected) {
      return const Color(0xFFFF9F0A);
    }
    switch (widget.type) {
      case CalculatorButtonType.function:
        return widget.isTablet ? Colors.white : Colors.black;
      case CalculatorButtonType.operator:
      case CalculatorButtonType.digit:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.buttonHeight ?? widget.buttonSize ?? 70.0;
    final fontScale = widget.type == CalculatorButtonType.function ? 0.36 : 0.42;
    final fontSize = (height * fontScale).clamp(16.0, 48.0);
    final zeroPadding = (widget.buttonSize ?? 70.0) * 0.32;

    Widget child;
    if (widget.label == '⌫' || widget.label == 'backspace') {
      child = Icon(
        CupertinoIcons.delete_left,
        color: _textColor,
        size: fontSize * 1.1,
      );
    } else {
      child = Text(
        widget.label,
        style: TextStyle(
          color: _textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w400,
        ),
      );
    }

    final borderRadius = widget.isTablet
        ? BorderRadius.circular(height * 0.42)
        : BorderRadius.circular(100);

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        alignment: widget.isZero ? Alignment.centerLeft : Alignment.center,
        padding: widget.isZero ? EdgeInsets.only(left: zeroPadding) : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: borderRadius,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: child,
        ),
      ),
    );
  }
}
