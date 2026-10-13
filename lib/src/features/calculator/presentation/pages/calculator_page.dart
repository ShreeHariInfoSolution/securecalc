import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // Render the newly pressed digit or operator state on display immediately
    setState(() {});

    if (trigger == CalculatorTrigger.vault) {
      _triggerSecretVaultTransition(isDuress: false);
    } else if (trigger == CalculatorTrigger.duress) {
      _triggerSecretVaultTransition(isDuress: true);
    }
  }

  void _handleSwipeDelete() {
    if (_isNavigating) return;
    HapticFeedback.lightImpact();
    _logic.backspace();
    setState(() {});
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

            final isWideScreen = maxWidth >= 600;

            // Scaled padding & gaps for iPad vs iPhone
            final double horizontalPadding = isWideScreen
                ? min(maxWidth * 0.05, 36.0)
                : 16.0;
            final double gap = isWideScreen
                ? min(maxWidth * 0.025, 20.0)
                : 12.0;

            // Maximum keypad width allowed
            final double maxKeypadWidth = isWideScreen
                ? min(maxWidth * 0.88, 720.0)
                : maxWidth;

            final double availableKeypadWidth = maxKeypadWidth - (horizontalPadding * 2);
            final double maxButtonWidth = (availableKeypadWidth - (gap * 3)) / 4;

            // Maximum keypad height allowed (max 65% of screen height)
            final double maxKeypadHeightAllowed = maxHeight * 0.65;
            final double maxButtonHeight = (maxKeypadHeightAllowed - (gap * 4) - 24.0) / 5;

            // Final button size (width = height) strictly bounded
            double buttonSize = min(maxButtonWidth, maxButtonHeight);
            buttonSize = buttonSize.clamp(32.0, 130.0);

            final double keypadWidth = (buttonSize * 4) + (gap * 3) + (horizontalPadding * 2);
            final String clearLabel = _logic.clearButtonLabel;
            final String? activeOp = _logic.activeOperator;

            return Center(
              child: SizedBox(
                width: isWideScreen ? keypadWidth : maxWidth,
                child: Column(
                  children: [
                    // Display Area with Swipe-to-Delete gesture
                    Expanded(
                      child: GestureDetector(
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity != 0) {
                            _handleSwipeDelete();
                          }
                        },
                        onLongPress: _triggerSecretVaultTransition,
                        child: CalculatorDisplay(
                          value: _logic.displayValue,
                          expression: _logic.expression,
                          isWideScreen: isWideScreen,
                        ),
                      ),
                    ),

                    // Keypad Grid - iPadOS / iOS Native Layout
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildRow(
                            [clearLabel, '+/-', '%', '÷'],
                            [
                              CalculatorButtonType.function,
                              CalculatorButtonType.function,
                              CalculatorButtonType.function,
                              CalculatorButtonType.operator,
                            ],
                            buttonSize,
                            gap,
                            activeOp,
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
                            activeOp,
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
                            activeOp,
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
                            activeOp,
                          ),
                          SizedBox(height: gap),
                          _buildBottomRow(buttonSize, gap, activeOp),
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
    String? activeOp,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(4, (index) {
        final label = labels[index];
        final isSelected = activeOp != null && activeOp == label;

        return SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: CalculatorButton(
            label: label,
            type: types[index],
            isSelected: isSelected,
            buttonSize: buttonSize,
            onTap: () => _handleButton(label),
          ),
        );
      }),
    );
  }

  Widget _buildBottomRow(double buttonSize, double gap, String? activeOp) {
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
            isSelected: activeOp == '=',
            buttonSize: buttonSize,
            onTap: () => _handleButton('='),
          ),
        ),
      ],
    );
  }
}
