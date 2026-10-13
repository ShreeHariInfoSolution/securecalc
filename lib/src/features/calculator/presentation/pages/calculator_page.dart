import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/config/app_preferences.dart';
import '../../../auth/presentation/pages/privacy_consent_page.dart';
import '../../domain/calculator_logic.dart';
import '../widgets/calculator_button.dart';
import '../widgets/calculator_display.dart';
import '../../../chat/presentation/pages/vault_home_page.dart';

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  final CalculatorLogic _logic = CalculatorLogic();
  bool _isNavigating = false;

  void _handleButton(String symbol) {
    if (_isNavigating) return;

    final trigger = _logic.input(symbol);
    // Render the newly pressed digit on the display immediately
    setState(() {});

    if (trigger == CalculatorTrigger.vault) {
      _triggerSecretVaultTransition(isDuress: false);
    } else if (trigger == CalculatorTrigger.duress) {
      _triggerSecretVaultTransition(isDuress: true);
    }
  }

  void _triggerSecretVaultTransition({bool isDuress = false}) {
    if (_isNavigating) return;
    _isNavigating = true;

    _logic.clearAll();
    if (mounted) setState(() {});

    final hasConsented = AppPreferences.getHasConsented();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          if (!hasConsented) {
            return const PrivacyConsentPage();
          }
          return VaultHomePage(isDuressMode: isDuress);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Guard against uninitialized window metrics during app reopen
            if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
              return const SizedBox();
            }

            final maxWidth = constraints.maxWidth;
            final maxHeight = constraints.maxHeight;

            // Wide screen check (iPads, tablets, or desktop)
            final isWideScreen = maxWidth >= 600;

            // On wide screens / iPad, cap the max keypad container width so buttons remain clean and well-proportioned
            final maxKeypadWidth = isWideScreen
                ? min(maxWidth * 0.85, 500.0)
                : maxWidth;

            // Spacing & padding configuration
            const double gap = 12.0;
            const double horizontalPadding = 16.0;

            // 1) Width constraint on button size:
            // 4 columns of buttonSize + 3 gaps + 2 * horizontalPadding = keypadWidth
            final availableKeypadWidth = maxKeypadWidth - (horizontalPadding * 2);
            final maxButtonWidth = (availableKeypadWidth - (gap * 3)) / 4;

            // 2) Height constraint on button size:
            // Keypad must take at most ~65% of screen height to guarantee ample room for display
            final maxKeypadHeightAllowed = maxHeight * 0.65;
            final maxButtonHeight = (maxKeypadHeightAllowed - (gap * 4) - 16.0) / 5;

            // Final button size (width = height) strictly constrained by both width and height bounds
            double buttonSize = min(maxButtonWidth, maxButtonHeight);
            buttonSize = buttonSize.clamp(32.0, 100.0);

            // Re-calculate actual keypad width based on final buttonSize
            final keypadWidth = (buttonSize * 4) + (gap * 3) + (horizontalPadding * 2);

            return Center(
              child: SizedBox(
                width: isWideScreen ? keypadWidth : maxWidth,
                child: Column(
                  children: [
                    // Display Area
                    Expanded(
                      child: GestureDetector(
                        onLongPress: _triggerSecretVaultTransition,
                        child: CalculatorDisplay(
                          value: _logic.displayValue,
                          expression: _logic.expression,
                        ),
                      ),
                    ),

                    // Keypad Grid - Apple Calculator Responsive Layout
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildRow(
                            ['AC', '+/-', '%', '÷'],
                            [
                              CalculatorButtonType.function,
                              CalculatorButtonType.function,
                              CalculatorButtonType.function,
                              CalculatorButtonType.operator,
                            ],
                            buttonSize,
                            gap,
                          ),
                          SizedBox(height: gap),
                          _buildRow(
                            ['7', '8', '9', '×'],
                            [
                              CalculatorButtonType.digit,
                              CalculatorButtonType.digit,
                              CalculatorButtonType.digit,
                              CalculatorButtonType.operator,
                            ],
                            buttonSize,
                            gap,
                          ),
                          SizedBox(height: gap),
                          _buildRow(
                            ['4', '5', '6', '-'],
                            [
                              CalculatorButtonType.digit,
                              CalculatorButtonType.digit,
                              CalculatorButtonType.digit,
                              CalculatorButtonType.operator,
                            ],
                            buttonSize,
                            gap,
                          ),
                          SizedBox(height: gap),
                          _buildRow(
                            ['1', '2', '3', '+'],
                            [
                              CalculatorButtonType.digit,
                              CalculatorButtonType.digit,
                              CalculatorButtonType.digit,
                              CalculatorButtonType.operator,
                            ],
                            buttonSize,
                            gap,
                          ),
                          SizedBox(height: gap),
                          _buildBottomRow(buttonSize, gap),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRow(
    List<String> labels,
    List<CalculatorButtonType> types,
    double buttonSize,
    double gap,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(4, (index) {
        return SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: CalculatorButton(
            label: labels[index],
            type: types[index],
            buttonSize: buttonSize,
            onTap: () => _handleButton(labels[index]),
          ),
        );
      }),
    );
  }

  Widget _buildBottomRow(double buttonSize, double gap) {
    final zeroWidth = buttonSize * 2 + gap;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SizedBox(
          width: zeroWidth,
          height: buttonSize,
          child: CalculatorButton(
            label: '0',
            isZero: true,
            type: CalculatorButtonType.digit,
            buttonSize: buttonSize,
            onTap: () => _handleButton('0'),
          ),
        ),
        SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: CalculatorButton(
            label: '.',
            type: CalculatorButtonType.digit,
            buttonSize: buttonSize,
            onTap: () => _handleButton('.'),
          ),
        ),
        SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: CalculatorButton(
            label: '=',
            type: CalculatorButtonType.operator,
            buttonSize: buttonSize,
            onTap: () => _handleButton('='),
          ),
        ),
      ],
    );
  }
}
