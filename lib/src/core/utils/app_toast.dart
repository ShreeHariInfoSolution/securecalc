import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class AppToast {
  /// Transforms raw technical exceptions, code errors, and status dumps
  /// into clean, user-friendly English messages.
  static String userFriendlyMessage(dynamic message) {
    if (message == null) return '';
    String text = message.toString().trim();
    if (text.isEmpty) return '';

    // Extract message if JSON string is present e.g. {"error":"..."} or {"message":"..."}
    if (text.contains('{') && text.contains('}')) {
      try {
        final startIndex = text.indexOf('{');
        final endIndex = text.lastIndexOf('}') + 1;
        final jsonStr = text.substring(startIndex, endIndex);
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map) {
          final extracted =
              decoded['message'] ?? decoded['error'] ?? decoded['msg'];
          if (extracted != null && extracted.toString().trim().isNotEmpty) {
            text = extracted.toString().trim();
          }
        }
      } catch (_) {}
    }

    // Strip standard exception class prefixes
    text = text.replaceAll(
      RegExp(
        r'^(Exception|StateError|ArgumentError|NetworkException|ApiException|FormatException|TypeError|RangeError|SocketException|HttpException|ClientException|HandshakeException|TimeoutException):\s*',
        caseSensitive: false,
      ),
      '',
    );

    // Strip common UI action prefix wrappers e.g. "Authentication failed: Exception: ..."
    text = text.replaceAll(
      RegExp(
        r'^(Authentication failed|Could not share message|Forwarding failed|Error saving cropped image|Error selecting image|Error selecting file|Upload error|Unable to pick image|Unable to pick video|Unable to attach file|Unable to start recording|Could not download attachment|Could not download photo|Could not open attachment|Could not play voice message|Could not add members|Could not open file|Failed to load uploads|Send Message REST Error|Create Direct Chat Error|Create Group Error|Get Chats Failed|Get User List Failed|Load Messages Failed):\s*',
        caseSensitive: false,
      ),
      '',
    );

    // Re-strip any nested Exception prefix that was behind a wrapper prefix
    text = text.replaceAll(
      RegExp(
        r'^(Exception|StateError|ArgumentError|NetworkException|ApiException|FormatException|TypeError|RangeError|SocketException|HttpException|ClientException|HandshakeException|TimeoutException):\s*',
        caseSensitive: false,
      ),
      '',
    );

    final lower = text.toLowerCase();

    // Map common raw patterns to clear user messages
    if (lower.contains('wrong credentials') ||
        lower.contains('invalid credentials') ||
        lower.contains('wrong password') ||
        lower.contains('unauthorized')) {
      return 'Invalid phone, email, or password. Please try again.';
    }

    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('no address associated') ||
        lower.contains('networkexception') ||
        lower.contains('no internet') ||
        lower.contains('clientexception')) {
      return 'Network connection error. Please check your internet connection.';
    }

    if (lower.contains('connection refused') ||
        lower.contains('connection timed out') ||
        lower.contains('timeoutexception') ||
        lower.contains('handshakeexception')) {
      return 'Server connection timeout. Please try again later.';
    }

    if (lower.contains('internal server error') ||
        lower.contains('500') ||
        lower.contains('502') ||
        lower.contains('503')) {
      return 'Server error occurred. Please try again in a moment.';
    }

    if (lower.contains('microphone permission is required') ||
        lower.contains('microphone permission')) {
      return 'Microphone access is required to record voice notes.';
    }

    // Strip technical status code annotations like (500): or [500]:
    text = text.replaceAll(RegExp(r'\(\d{3}\):\s*'), '');
    text = text.replaceAll(RegExp(r'\[\d{3}\]:\s*'), '');

    text = text.trim();

    if (text.isNotEmpty) {
      text = text[0].toUpperCase() + text.substring(1);
    }

    return text.isEmpty ? 'An unexpected error occurred. Please try again.' : text;
  }

  static void show(String message, {bool isError = false}) {
    final cleanMsg = userFriendlyMessage(message);
    if (cleanMsg.trim().isEmpty) return;
    Fluttertoast.cancel();
    Fluttertoast.showToast(
      msg: cleanMsg,
      toastLength: cleanMsg.length > 40 ? Toast.LENGTH_LONG : Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor:
          isError ? const Color(0xFFD32F2F) : const Color(0xFF2C2C2E),
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }
}
