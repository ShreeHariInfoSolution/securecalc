import 'package:flutter/material.dart';

class CalculatorDisplay extends StatelessWidget {
  final String value;
  final String expression;
  final bool isWideScreen;

  const CalculatorDisplay({
    super.key,
    required this.value,
    required this.expression,
    this.isWideScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final double maxValFontSize = isWideScreen ? 108.0 : 80.0;
    final double midValFontSize = isWideScreen ? 84.0 : 64.0;
    final double minValFontSize = isWideScreen ? 60.0 : 46.0;
    final double exprFontSize = isWideScreen ? 28.0 : 22.0;

    final double fontSize = value.length > 9
        ? minValFontSize
        : value.length > 6
            ? midValFontSize
            : maxValFontSize;

    final double hPadding = isWideScreen ? 32.0 : 24.0;
    final double vPadding = isWideScreen ? 16.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
      alignment: Alignment.bottomRight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (expression.isNotEmpty)
            Flexible(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: 0.7,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    expression,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: exprFontSize,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
              ),
            ),
          if (expression.isNotEmpty) const SizedBox(height: 8),
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
