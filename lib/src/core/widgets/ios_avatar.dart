import 'dart:io';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';

String? resolveAvatarUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (File(raw).existsSync()) return raw;

  final apiBase = ServerApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final origin = apiBase.replaceFirst(RegExp(r'/api$'), '');
  final clean = raw.replaceFirst(RegExp(r'^/+'), '');

  if (clean.startsWith('api/')) {
    return '$origin/$clean';
  }
  if (clean.startsWith('files/')) {
    return '$apiBase/$clean';
  }
  return '$apiBase/files/$clean';
}

class IosAvatar extends StatelessWidget {
  final String name;
  final String? imagePath;
  final bool isOnline;
  final double size;
  final bool showOnline;

  const IosAvatar({
    super.key,
    required this.name,
    this.imagePath,
    this.isOnline = false,
    this.size = 52,
    this.showOnline = true,
  });

  static const List<Color> _avatarColors = [
    Color(0xFFFF6B6B),
    Color(0xFF4ECDC4),
    Color(0xFFA78BFA),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFFF472B6),
    Color(0xFF60A5FA),
    Color(0xFFFB7185),
  ];

  Color _getDeterministicColor(String text) {
    if (text.isEmpty) return _avatarColors[0];
    int hash = 0;
    for (int i = 0; i < text.length; i++) {
      hash = text.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return _avatarColors[hash.abs() % _avatarColors.length];
  }

  String _getInitials(String text) {
    if (text.trim().isEmpty) return '?';
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final badgeSize = size > 44 ? 14.0 : 10.0;

    final resolvedImage = resolveAvatarUrl(imagePath);
    final hasLocalImage = resolvedImage != null &&
        !resolvedImage.startsWith('http') &&
        File(resolvedImage).existsSync();
    final hasNetworkImage = resolvedImage != null &&
        (resolvedImage.startsWith('http://') || resolvedImage.startsWith('https://'));

    final baseColor = _getDeterministicColor(name);

    Widget avatarWidget;

    if (hasLocalImage) {
      avatarWidget = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: FileImage(File(resolvedImage)),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else if (hasNetworkImage) {
      avatarWidget = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: NetworkImage(resolvedImage),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      avatarWidget = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              baseColor.withValues(alpha: 0.95),
              baseColor.withValues(alpha: 0.65),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: baseColor.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          _getInitials(name),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.36,
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatarWidget,
          if (showOnline && isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: AppTheme.onlineGreen,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
                    width: 2.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
