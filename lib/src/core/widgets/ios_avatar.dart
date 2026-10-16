import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/features/chat/domain/services/attachment_cache_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';

String? resolveAvatarUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final trimmed = raw.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://'))
    return trimmed;

  final apiBase = ServerApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final origin = apiBase.replaceFirst(RegExp(r'/api$'), '');

  if (trimmed.startsWith('/api/')) {
    return '$origin$trimmed';
  }
  if (trimmed.startsWith('/files/')) {
    return '$apiBase$trimmed';
  }
  if (trimmed.startsWith('/uploads/')) {
    return '$origin$trimmed';
  }
  if (trimmed.startsWith('/')) {
    // Check if it's an absolute local path (e.g. /data/user/0/...)
    if (trimmed.contains('/data/') || trimmed.contains('/storage/')) {
      return trimmed;
    }
    return '$origin$trimmed';
  }

  final clean = trimmed.replaceFirst(RegExp(r'^/+'), '');

  if (clean.startsWith('api/')) {
    return '$origin/$clean';
  }
  if (clean.startsWith('files/')) {
    return '$apiBase/$clean';
  }
  if (clean.startsWith('uploads/')) {
    return '$origin/$clean';
  }

  // If it's a typical local Windows or Android path like C:\ or /data/user/...
  if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed) ||
      trimmed.startsWith('/data/') ||
      trimmed.startsWith('/storage/') ||
      trimmed.startsWith('/Users/')) {
    return trimmed;
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
    final hasNetworkImage =
        resolvedImage != null &&
        (resolvedImage.startsWith('http://') ||
            resolvedImage.startsWith('https://'));
    final hasLocalImage = resolvedImage != null && !hasNetworkImage;

    final baseColor = _getDeterministicColor(name);

    final fallbackInitials = Container(
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

    Widget avatarWidget;

    if (hasLocalImage) {
      avatarWidget = ClipOval(
        child: Image.file(
          File(resolvedImage),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallbackInitials,
        ),
      );
    } else if (hasNetworkImage) {
      avatarWidget = _CachedNetworkAvatar(
        url: resolvedImage,
        size: size,
        fallback: fallbackInitials,
      );
    } else {
      avatarWidget = fallbackInitials;
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
                    color: isDark
                        ? AppTheme.darkBackground
                        : AppTheme.lightSurface,
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

class _CachedNetworkAvatar extends StatefulWidget {
  final String url;
  final double size;
  final Widget fallback;

  const _CachedNetworkAvatar({
    required this.url,
    required this.size,
    required this.fallback,
  });

  @override
  State<_CachedNetworkAvatar> createState() => _CachedNetworkAvatarState();
}

class _CachedNetworkAvatarState extends State<_CachedNetworkAvatar> {
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _resolveAvatar();
  }

  @override
  void didUpdateWidget(covariant _CachedNetworkAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _localPath = null;
      _resolveAvatar();
    }
  }

  Future<void> _resolveAvatar() async {
    final cached = AttachmentCacheService.instance.resolveLocalPathSync(
      widget.url,
    );
    if (cached != null) {
      if (mounted) {
        setState(() {
          _localPath = cached;
        });
      }
      return;
    }
    final resolved = await AttachmentCacheService.instance.resolveLocalPath(
      widget.url,
    );
    if (resolved != null) {
      if (mounted) {
        setState(() {
          _localPath = resolved;
        });
      }
      return;
    }

    // Download and cache locally
    try {
      final headers = ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : <String, String>{};
      final response = await http.get(Uri.parse(widget.url), headers: headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bytes = response.bodyBytes;
        final dir = await getApplicationDocumentsDirectory();
        final avatarsDir = Directory(
          '${dir.path}${Platform.pathSeparator}avatars',
        );
        if (!avatarsDir.existsSync()) {
          await avatarsDir.create(recursive: true);
        }
        final safeName = widget.url
            .split('/')
            .last
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final file = File(
          '${avatarsDir.path}${Platform.pathSeparator}$safeName',
        );
        await file.writeAsBytes(bytes, flush: true);
        AttachmentCacheService.instance.updateCache(widget.url, file.path);
        if (mounted) {
          setState(() {
            _localPath = file.path;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_localPath != null) {
      return ClipOval(
        child: Image.file(
          File(_localPath!),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => widget.fallback,
        ),
      );
    }

    // Avoid briefly starting a second network image on every list rebuild.
    // The resolver above writes the avatar to local storage once, then this
    // widget uses that local file on subsequent app launches.
    return widget.fallback;
  }
}
