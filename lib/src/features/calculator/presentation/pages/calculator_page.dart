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

            final String clearLabel = _logic.clearButtonLabel;
            final String? activeOp = _logic.activeOperator;

            if (isWideScreen) {
              // ─── iPad / Tablet Full-Screen Native Layout (Matching iPadOS Calculator) ───
              const double horizontalPadding = 20.0;
              const double bottomPadding = 20.0;
              const double gap = 14.0;

              final double availableWidth = maxWidth - (horizontalPadding * 2);
              final double buttonWidth = (availableWidth - (gap * 3)) / 4;

              final double maxKeypadHeightAllowed = maxHeight * 0.58;
              final double calculatedHeight =
                  (maxKeypadHeightAllowed - (gap * 4) - bottomPadding) / 5;
              final double buttonHeight = calculatedHeight.clamp(48.0, 120.0);

              return Column(
                children: [
                  // Display Area
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
                        isWideScreen: true,
                      ),
                    ),
                  ),

                  // Full-width Tablet Keypad Grid
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      horizontalPadding,
                      0,
                      horizontalPadding,
                      bottomPadding,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildTabletRow(
                          ['⌫', clearLabel, '%', '÷'],
                          [
                            CalculatorButtonType.function,
                            CalculatorButtonType.function,
                            CalculatorButtonType.function,
                            CalculatorButtonType.operator,
                          ],
                          buttonWidth,
                          buttonHeight,
                          gap,
                          activeOp,
                        ),
                        SizedBox(height: gap),
                        _buildTabletRow(
                          ['7', '8', '9', '×'],
                          [
                            CalculatorButtonType.digit,
                            CalculatorButtonType.digit,
                            CalculatorButtonType.digit,
                            CalculatorButtonType.operator,
                          ],
                          buttonWidth,
                          buttonHeight,
                          gap,
                          activeOp,
                        ),
                        SizedBox(height: gap),
                        _buildTabletRow(
                          ['4', '5', '6', '-'],
                          [
                            CalculatorButtonType.digit,
                            CalculatorButtonType.digit,
                            CalculatorButtonType.digit,
                            CalculatorButtonType.operator,
                          ],
                          buttonWidth,
                          buttonHeight,
                          gap,
                          activeOp,
                        ),
                        SizedBox(height: gap),
                        _buildTabletRow(
                          ['1', '2', '3', '+'],
                          [
                            CalculatorButtonType.digit,
                            CalculatorButtonType.digit,
                            CalculatorButtonType.digit,
                            CalculatorButtonType.operator,
                          ],
                          buttonWidth,
                          buttonHeight,
                          gap,
                          activeOp,
                        ),
                        SizedBox(height: gap),
                        _buildTabletRow(
                          ['+/-', '0', '.', '='],
                          [
                            CalculatorButtonType.function,
                            CalculatorButtonType.digit,
                            CalculatorButtonType.digit,
                            CalculatorButtonType.operator,
                          ],
                          buttonWidth,
                          buttonHeight,
                          gap,
                          activeOp,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            } else {
              // ─── iPhone / Mobile Classic Calculator Layout ───
              const double horizontalPadding = 16.0;
              const double gap = 12.0;

              final double availableKeypadWidth =
                  maxWidth - (horizontalPadding * 2);
              final double maxButtonWidth =
                  (availableKeypadWidth - (gap * 3)) / 4;

              final double maxKeypadHeightAllowed = maxHeight * 0.65;
              final double maxButtonHeight =
                  (maxKeypadHeightAllowed - (gap * 4) - 16.0) / 5;

              double buttonSize = min(maxButtonWidth, maxButtonHeight);
              buttonSize = buttonSize.clamp(32.0, 95.0);

              return Center(
                child: SizedBox(
                  width: maxWidth,
                  child: Column(
                    children: [
                      // Display Area
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
                            isWideScreen: false,
                          ),
                        ),
                      ),

                      // Mobile Keypad Grid
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
                            _buildPhoneRow(
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
                            _buildPhoneRow(
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
                            _buildPhoneRow(
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
                            _buildPhoneRow(
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
                            _buildPhoneBottomRow(buttonSize, gap, activeOp),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildTabletRow(
    List<String> labels,
    List<CalculatorButtonType> types,
    double buttonWidth,
    double buttonHeight,
    double gap,
    String? activeOp,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(4, (index) {
        final label = labels[index];
        final isSelected = activeOp != null && activeOp == label;

        return SizedBox(
          width: buttonWidth,
          height: buttonHeight,
          child: CalculatorButton(
            label: label,
            type: types[index],
            isSelected: isSelected,
            buttonSize: buttonWidth,
            buttonHeight: buttonHeight,
            isTablet: true,
            onTap: () => _handleButton(label),
          ),
        );
      }),
    );
  }

  Widget _buildPhoneRow(
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
            isTablet: false,
            onTap: () => _handleButton(label),
          ),
        );
      }),
    );
  }

  Widget _buildPhoneBottomRow(double buttonSize, double gap, String? activeOp) {
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
            isTablet: false,
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
            isTablet: false,
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
            isTablet: false,
            onTap: () => _handleButton('='),
          ),
        ),
      ],
    );
  }
}
