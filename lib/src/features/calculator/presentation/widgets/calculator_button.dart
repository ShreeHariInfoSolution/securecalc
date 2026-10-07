import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  const CalculatorButton({
    super.key,
    required this.label,
    required this.onTap,
    this.type = CalculatorButtonType.digit,
    this.isZero = false,
    this.isSelected = false,
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
        return _isPressed ? const Color(0xFFD9D9D9) : const Color(0xFFA5A5A5);
      case CalculatorButtonType.operator:
        return _isPressed ? const Color(0xFFF2C078) : const Color(0xFFFF9F0A);
      case CalculatorButtonType.digit:
        return _isPressed ? const Color(0xFF737373) : const Color(0xFF333333);
    }
  }

  Color get _textColor {
    if (widget.isSelected) {
      return const Color(0xFFFF9F0A);
    }
    switch (widget.type) {
      case CalculatorButtonType.function:
        return Colors.black;
      case CalculatorButtonType.operator:
      case CalculatorButtonType.digit:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _isPressed = true);
      },
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        alignment: widget.isZero ? Alignment.centerLeft : Alignment.center,
        padding: widget.isZero ? const EdgeInsets.only(left: 28) : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: _textColor,
            fontSize: widget.type == CalculatorButtonType.function ? 26 : 34,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
