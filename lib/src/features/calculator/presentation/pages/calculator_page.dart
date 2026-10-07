import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/config/app_preferences.dart';
import '../../../auth/presentation/pages/privacy_consent_page.dart';
import '../../domain/calculator_logic.dart';
import '../widgets/calculator_button.dart';
import '../widgets/calculator_display.dart';
import '../../../chat/presentation/pages/vault_home_page.dart';
import 'fake_crash_page.dart';

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
      _triggerSecretVaultTransition();
    } else if (trigger == CalculatorTrigger.dummyCrash) {
      _triggerDummyCrashTransition();
    }
  }

  void _triggerSecretVaultTransition() {
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
          return const VaultHomePage();
        },
      ),
    );
  }

  void _triggerDummyCrashTransition() {
    if (_isNavigating) return;
    _isNavigating = true;

    _logic.clearAll();
    if (mounted) setState(() {});

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          return const FakeCrashPage();
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

            return Column(
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

                // Keypad Grid - Apple Calculator Pixel Perfect Layout
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildRow(['AC', '+/-', '%', '÷'], [
                        CalculatorButtonType.function,
                        CalculatorButtonType.function,
                        CalculatorButtonType.function,
                        CalculatorButtonType.operator,
                      ]),
                      const SizedBox(height: 12),
                      _buildRow(['7', '8', '9', '×'], [
                        CalculatorButtonType.digit,
                        CalculatorButtonType.digit,
                        CalculatorButtonType.digit,
                        CalculatorButtonType.operator,
                      ]),
                      const SizedBox(height: 12),
                      _buildRow(['4', '5', '6', '-'], [
                        CalculatorButtonType.digit,
                        CalculatorButtonType.digit,
                        CalculatorButtonType.digit,
                        CalculatorButtonType.operator,
                      ]),
                      const SizedBox(height: 12),
                      _buildRow(['1', '2', '3', '+'], [
                        CalculatorButtonType.digit,
                        CalculatorButtonType.digit,
                        CalculatorButtonType.digit,
                        CalculatorButtonType.operator,
                      ]),
                      const SizedBox(height: 12),
                      _buildBottomRow(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRow(List<String> labels, List<CalculatorButtonType> types) {
    final size = _buttonSize(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(4, (index) {
        return SizedBox(
          width: size,
          height: size,
          child: CalculatorButton(
            label: labels[index],
            type: types[index],
            onTap: () => _handleButton(labels[index]),
          ),
        );
      }),
    );
  }

  Widget _buildBottomRow() {
    final size = _buttonSize(context);
    final zeroWidth = size * 2 + 12;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SizedBox(
          width: zeroWidth,
          height: size,
          child: CalculatorButton(
            label: '0',
            isZero: true,
            type: CalculatorButtonType.digit,
            onTap: () => _handleButton('0'),
          ),
        ),
        SizedBox(
          width: size,
          height: size,
          child: CalculatorButton(
            label: '.',
            type: CalculatorButtonType.digit,
            onTap: () => _handleButton('.'),
          ),
        ),
        SizedBox(
          width: size,
          height: size,
          child: CalculatorButton(
            label: '=',
            type: CalculatorButtonType.operator,
            onTap: () => _handleButton('='),
          ),
        ),
      ],
    );
  }

  double _buttonSize(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;

    // Safety fallback against uninitialized 0 or negative metrics
    if (screenWidth <= 0 || screenHeight <= 0) {
      return 70.0;
    }

    final isLandscape = media.orientation == Orientation.landscape;

    if (isLandscape) {
      final availableHeight = screenHeight - 80;
      return max(35.0, (availableHeight - 48) / 5);
    } else {
      final computedSize = (screenWidth - 32 - 36) / 4;
      return max(35.0, computedSize);
    }
  }
}
