import 'dart:io';

import 'package:flutter/material.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/features/chat/domain/services/attachment_cache_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

String? resolveBackgroundUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final trimmed = raw.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://'))
    return trimmed;

  final apiBase = ServerApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final origin = apiBase.replaceFirst(RegExp(r'/api$'), '');

  if (trimmed.startsWith('/api/')) return '$origin$trimmed';
  if (trimmed.startsWith('/files/')) return '$apiBase$trimmed';
  if (trimmed.startsWith('/uploads/')) return '$origin$trimmed';
  if (trimmed.startsWith('/')) {
    if (trimmed.contains('/data/') || trimmed.contains('/storage/'))
      return trimmed;
    return '$origin$trimmed';
  }

  final clean = trimmed.replaceFirst(RegExp(r'^/+'), '');
  if (clean.startsWith('api/')) return '$origin/$clean';
  if (clean.startsWith('files/')) return '$apiBase/$clean';
  if (clean.startsWith('uploads/')) return '$origin/$clean';

  if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed) ||
      trimmed.startsWith('/data/') ||
      trimmed.startsWith('/storage/') ||
      trimmed.startsWith('/Users/')) {
    return trimmed;
  }
  return '$apiBase/files/$clean';
}

class ChatWallpaperWidget extends StatelessWidget {
  final String? chatId;
  final bool isDark;
  final String? backgroundUrl;

  const ChatWallpaperWidget({
    super.key,
    this.chatId,
    required this.isDark,
    this.backgroundUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (backgroundUrl != null && backgroundUrl!.isNotEmpty) {
      final resolvedUrl = resolveBackgroundUrl(backgroundUrl)!;
      return Stack(
        fit: StackFit.expand,
        children: [
          _CachedBackground(url: resolvedUrl),
          // Slight overlay to ensure readability if server image is too bright
          Container(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1)),
        ],
      );
    }

    return ValueListenableBuilder<String>(
      valueListenable: AppPreferences.chatWallpaperNotifier,
      builder: (context, _, __) {
        final type = AppPreferences.getWallpaperType(chatId: chatId);
        final customPath = AppPreferences.getWallpaperPath(chatId: chatId);
        final dim = AppPreferences.getWallpaperDim(chatId: chatId);

        Widget content;

        if (type == 'custom' &&
            customPath != null &&
            customPath.isNotEmpty &&
            File(customPath).existsSync()) {
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
              Container(color: Colors.black.withValues(alpha: dim)),
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
              colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0284C7)],
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
              colors: [Color(0xFF064E3B), Color(0xFF022C22), Color(0xFF065F46)],
            ),
          ),
        );
      case 'preset_4': // Cyberpunk Neon
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2E0249), Color(0xFF570A57), Color(0xFFA91079)],
            ),
          ),
        );
      case 'preset_5': // Royal Velvet
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [Color(0xFF180036), Color(0xFF3B0066), Color(0xFF180036)],
            ),
          ),
        );
      default:
        return Container(color: AppTheme.chatCanvas(isDark));
    }
  }
}

class _CachedBackground extends StatefulWidget {
  final String url;

  const _CachedBackground({required this.url});

  @override
  State<_CachedBackground> createState() => _CachedBackgroundState();
}

class _CachedBackgroundState extends State<_CachedBackground> {
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _resolveBackground();
  }

  @override
  void didUpdateWidget(covariant _CachedBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _localPath = null;
      _resolveBackground();
    }
  }

  Future<void> _resolveBackground() async {
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

    try {
      final headers = ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : <String, String>{};
      final response = await http.get(Uri.parse(widget.url), headers: headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bytes = response.bodyBytes;
        final dir = await getApplicationDocumentsDirectory();
        final bgDir = Directory(
          '${dir.path}${Platform.pathSeparator}chat_wallpapers',
        );
        if (!bgDir.existsSync()) {
          await bgDir.create(recursive: true);
        }
        final safeName = widget.url
            .split('/')
            .last
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final file = File('${bgDir.path}${Platform.pathSeparator}$safeName');
        await file.writeAsBytes(bytes, flush: true);
        AttachmentCacheService.instance.updateCache(widget.url, file.path);
        if (mounted) setState(() => _localPath = file.path);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_localPath != null) {
      return Image.file(
        File(_localPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return const ColoredBox(color: Colors.transparent);
  }
}
