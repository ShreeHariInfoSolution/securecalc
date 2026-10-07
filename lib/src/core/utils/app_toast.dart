import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class AppToast {
  static void show(String message, {bool isError = false}) {
    if (message.trim().isEmpty) return;
    Fluttertoast.cancel();
    Fluttertoast.showToast(
      msg: message,
      toastLength: message.length > 40 ? Toast.LENGTH_LONG : Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: isError ? const Color(0xFFD32F2F) : const Color(0xFF2C2C2E),
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }
}
