/// Trigger action resulting from calculator passcode evaluation.
enum CalculatorTrigger { none, vault, duress }

/// Core mathematical and passcode evaluation engine for the calculator.
class CalculatorLogic {
  String _displayValue = '0';
  String _expression = '';
  double? _firstOperand;
  String? _operator;
  bool _shouldResetDisplayOnNextInput = false;

  // Secret passcode storage (default "1234")
  static String secretPasscode = '1234';
  // Duress passcode storage (default "4321")
  static String duressPasscode = '4321';

  String get displayValue => _displayValue;
  String get expression => _expression;

  /// Processes button presses and returns the `CalculatorTrigger` action.
  CalculatorTrigger input(String symbol) {
    if (symbol == 'AC') {
      clearAll();
      return CalculatorTrigger.none;
    } else if (symbol == 'C') {
      _clearEntry();
      return CalculatorTrigger.none;
    } else if (symbol == '=') {
      if (secretPasscode.isNotEmpty && _displayValue == secretPasscode) {
        return CalculatorTrigger.vault;
      }
      if (duressPasscode.isNotEmpty && _displayValue == duressPasscode) {
        return CalculatorTrigger.duress;
      }
      _calculateResult();
      return CalculatorTrigger.none;
    } else if (['+', '-', '×', '÷'].contains(symbol)) {
      _setOperator(symbol);
      return CalculatorTrigger.none;
    } else if (symbol == '%') {
      _applyPercentage();
      return CalculatorTrigger.none;
    } else if (symbol == '+/-') {
      _toggleSign();
      return CalculatorTrigger.none;
    } else if (symbol == '.') {
      _appendDecimal();
      return CalculatorTrigger.none;
    } else {
      // Digit key input
      _appendDigit(symbol);
      if (secretPasscode.isNotEmpty && _displayValue == secretPasscode) {
        return CalculatorTrigger.vault;
      }
      if (duressPasscode.isNotEmpty && _displayValue == duressPasscode) {
        return CalculatorTrigger.duress;
      }
      return CalculatorTrigger.none;
    }
  }

  void clearAll() {
    _displayValue = '0';
    _expression = '';
    _firstOperand = null;
    _operator = null;
    _shouldResetDisplayOnNextInput = false;
  }

  void _clearEntry() {
    _displayValue = '0';
  }

  void _appendDigit(String digit) {
    if (_shouldResetDisplayOnNextInput || _displayValue == '0') {
      _displayValue = digit;
      _shouldResetDisplayOnNextInput = false;
    } else {
      if (_displayValue.length < 12) {
        _displayValue += digit;
      }
    }
  }

  void _appendDecimal() {
    if (_shouldResetDisplayOnNextInput) {
      _displayValue = '0.';
      _shouldResetDisplayOnNextInput = false;
      return;
    }
    if (!_displayValue.contains('.')) {
      _displayValue += '.';
    }
  }

  void _toggleSign() {
    if (_displayValue == '0') return;
    if (_displayValue.startsWith('-')) {
      _displayValue = _displayValue.substring(1);
    } else {
      _displayValue = '-$_displayValue';
    }
  }

  void _applyPercentage() {
    final val = double.tryParse(_displayValue);
    if (val != null) {
      _displayValue = _formatNumber(val / 100);
    }
  }

  void _setOperator(String op) {
    final currentVal = double.tryParse(_displayValue);
    if (currentVal != null) {
      if (_firstOperand != null && _operator != null && !_shouldResetDisplayOnNextInput) {
        _calculateResult();
        _firstOperand = double.tryParse(_displayValue);
      } else {
        _firstOperand = currentVal;
      }
    }
    _operator = op;
    _expression = '${_formatNumber(_firstOperand ?? 0)} $op';
    _shouldResetDisplayOnNextInput = true;
  }

  void _calculateResult() {
    if (_firstOperand == null || _operator == null) return;
    final secondOperand = double.tryParse(_displayValue);
    if (secondOperand == null) return;

    double result = 0;
    switch (_operator) {
      case '+':
        result = _firstOperand! + secondOperand;
        break;
      case '-':
        result = _firstOperand! - secondOperand;
        break;
      case '×':
        result = _firstOperand! * secondOperand;
        break;
      case '÷':
        if (secondOperand == 0) {
          _displayValue = 'Error';
          _expression = '';
          _firstOperand = null;
          _operator = null;
          _shouldResetDisplayOnNextInput = true;
          return;
        }
        result = _firstOperand! / secondOperand;
        break;
    }

    _expression = '${_formatNumber(_firstOperand!)} $_operator ${_formatNumber(secondOperand)} =';
    _displayValue = _formatNumber(result);
    _firstOperand = null;
    _operator = null;
    _shouldResetDisplayOnNextInput = true;
  }

  String _formatNumber(double number) {
    if (number.isInfinite || number.isNaN) return 'Error';
    if (number == number.roundToDouble()) {
      return number.toInt().toString();
    }
    String str = number.toStringAsFixed(6);
    while (str.contains('.') && (str.endsWith('0') || str.endsWith('.'))) {
      str = str.substring(0, str.length - 1);
    }
    return str;
  }
}
