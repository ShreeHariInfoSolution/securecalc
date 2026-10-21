import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/features/chat/domain/services/attachment_cache_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';

/// Opens a full screen profile picture viewer showing the full square/rectangular image with zoom.
void showFullProfilePictureDialog(
  BuildContext context, {
  required String name,
  required String? imagePath,
  VoidCallback? onChangePhoto,
}) {
  HapticFeedback.lightImpact();

  final resolvedImage = resolveAvatarUrl(imagePath);
  final hasNetworkImage = resolvedImage != null &&
      (resolvedImage.startsWith('http://') ||
          resolvedImage.startsWith('https://'));
  final hasLocalImage = resolvedImage != null && !hasNetworkImage;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'ViewProfilePic',
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (dialogContext, anim1, anim2) {
      final screenSize = MediaQuery.of(dialogContext).size;

      Widget imageWidget;
      if (hasLocalImage) {
        imageWidget = Image.file(
          File(resolvedImage),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              _buildFallbackInitials(name, 260),
        );
      } else if (hasNetworkImage) {
        imageWidget = _FullNetworkImage(
          url: resolvedImage,
          name: name,
        );
      } else {
        imageWidget = _buildFallbackInitials(name, 260);
      }

      return Material(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              // Full Screen Zoomable Image (Unclipped Square/Original Aspect)
              Center(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 5.0,
                  clipBehavior: Clip.none,
                  child: SizedBox(
                    width: screenSize.width,
                    height: screenSize.height * 0.78,
                    child: Center(
                      child: imageWidget,
                    ),
                  ),
                ),
              ),

              // Top Header Bar: Name & Close Button
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white24,
                        shape: const CircleBorder(),
                      ),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
              ),

              // Bottom Action Bar: Change Photo
              if (onChangePhoto != null)
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: Center(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text(
                        'Change Photo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        onChangePhoto();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (context, anim1, anim2, child) {
      return FadeTransition(
        opacity: anim1,
        child: child,
      );
    },
  );
}

Widget _buildFallbackInitials(String name, double size) {
  final baseColor = _getDeterministicColor(name);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: baseColor.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(16),
    ),
    alignment: Alignment.center,
    child: Text(
      _getInitials(name),
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: size * 0.36,
        decoration: TextDecoration.none,
      ),
    ),
  );
}

Color _getDeterministicColor(String text) {
  const avatarColors = [
    Color(0xFFFF6B6B),
    Color(0xFF4ECDC4),
    Color(0xFFA78BFA),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFFF472B6),
    Color(0xFF60A5FA),
    Color(0xFFFB7185),
  ];
  if (text.isEmpty) return avatarColors[0];
  int hash = 0;
  for (int i = 0; i < text.length; i++) {
    hash = text.codeUnitAt(i) + ((hash << 5) - hash);
  }
  return avatarColors[hash.abs() % avatarColors.length];
}

String _getInitials(String text) {
  if (text.trim().isEmpty) return '?';
  final parts = text.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return parts[0][0].toUpperCase();
}

class _FullNetworkImage extends StatefulWidget {
  final String url;
  final String name;

  const _FullNetworkImage({
    required this.url,
    required this.name,
  });

  @override
  State<_FullNetworkImage> createState() => _FullNetworkImageState();
}

class _FullNetworkImageState extends State<_FullNetworkImage> {
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final cached = AttachmentCacheService.instance.resolveLocalPathSync(
      widget.url,
    );
    if (cached != null) {
      if (mounted) setState(() => _localPath = cached);
      return;
    }
    final resolved = await AttachmentCacheService.instance.resolveLocalPath(
      widget.url,
    );
    if (resolved != null) {
      if (mounted) setState(() => _localPath = resolved);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_localPath != null) {
      return Image.file(
        File(_localPath!),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _buildFallbackInitials(widget.name, 260),
      );
    }

    return Image.network(
      widget.url,
      fit: BoxFit.contain,
      headers: ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : null,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
      errorBuilder: (context, error, stackTrace) =>
          _buildFallbackInitials(widget.name, 260),
    );
  }
}

String? resolveAvatarUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  final trimmed = raw.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final badgeSize = size > 44 ? 14.0 : 10.0;

    final resolvedImage = resolveAvatarUrl(imagePath);
    final hasNetworkImage = resolvedImage != null &&
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
          decoration: TextDecoration.none,
        ),
      ),
    );

    final isBot = name.contains('Calnox AI') || name.contains('AI Assistant');

    Widget avatarWidget;

    if (isBot && !hasLocalImage && !hasNetworkImage) {
      avatarWidget = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF007AFF).withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.smart_toy_rounded,
          color: Colors.white,
          size: size * 0.52,
        ),
      );
    } else if (hasLocalImage) {
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

    return widget.fallback;
  }
}
