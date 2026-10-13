import 'package:flutter/material.dart';

class CalculatorDisplay extends StatelessWidget {
  final String value;
  final String expression;

  const CalculatorDisplay({
    super.key,
    required this.value,
    required this.expression,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = value.length > 9
        ? 46.0
        : value.length > 6
            ? 64.0
            : 80.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
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
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 24,
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
