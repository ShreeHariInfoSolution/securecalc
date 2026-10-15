import 'dart:io';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';

class ChatWallpaperWidget extends StatelessWidget {
  final String? chatId;
  final bool isDark;

  const ChatWallpaperWidget({
    super.key,
    this.chatId,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppPreferences.chatWallpaperNotifier,
      builder: (context, _, __) {
        final type = AppPreferences.getWallpaperType(chatId: chatId);
        final customPath = AppPreferences.getWallpaperPath(chatId: chatId);
        final dim = AppPreferences.getWallpaperDim(chatId: chatId);

        Widget content;

        if (type == 'custom' && customPath != null && customPath.isNotEmpty && File(customPath).existsSync()) {
          content = Image.file(
            File(customPath),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) =>
                Container(color: AppTheme.chatCanvas(isDark)),
          );
        } else if (type.startsWith('preset_')) {
          content = buildPresetWallpaper(type, isDark);
        } else {
          return Container(color: AppTheme.chatCanvas(isDark));
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            content,
            // Dimming overlay for optimal readability
            if (dim > 0.0)
              Container(
                color: Colors.black.withValues(alpha: dim),
              ),
          ],
        );
      },
    );
  }

  static Widget buildPresetWallpaper(String type, bool isDark) {
    switch (type) {
      case 'preset_1': // Midnight Mesh
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F172A),
                Color(0xFF1E1B4B),
                Color(0xFF0284C7),
              ],
            ),
          ),
        );
      case 'preset_2': // Sunset Glow
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF31103F),
                Color(0xFF801336),
                Color(0xFFC72C41),
                Color(0xFFEE6F57),
              ],
            ),
          ),
        );
      case 'preset_3': // Emerald Forest
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color(0xFF064E3B),
                Color(0xFF022C22),
                Color(0xFF065F46),
              ],
            ),
          ),
        );
      case 'preset_4': // Cyberpunk Neon
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2E0249),
                Color(0xFF570A57),
                Color(0xFFA91079),
              ],
            ),
          ),
        );
      case 'preset_5': // Royal Velvet
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [
                Color(0xFF180036),
                Color(0xFF3B0066),
                Color(0xFF180036),
              ],
            ),
          ),
        );
      default:
        return Container(color: AppTheme.chatCanvas(isDark));
    }
  }
}
