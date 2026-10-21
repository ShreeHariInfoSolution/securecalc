import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/server_api_service.dart';

class ChatReplyBanner extends StatelessWidget {
  final ChatMessage replyingMessage;
  final ChatConversation conversation;
  final String chatName;
  final Map<int, String> groupMemberNames;
  final VoidCallback onCancel;

  const ChatReplyBanner({
    super.key,
    required this.replyingMessage,
    required this.conversation,
    required this.chatName,
    required this.groupMemberNames,
    required this.onCancel,
  });

  String _resolveRemoteUrl(String rawUrl) {
    if (rawUrl.isEmpty) return '';
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    final apiBase = ServerApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final clean = rawUrl.replaceFirst(RegExp(r'^/+'), '');
    if (clean.startsWith('api/files/')) {
      return '$apiBase/${clean.substring(10)}';
    }
    if (clean.startsWith('files/')) {
      return '$apiBase/$clean';
    }
    return '$apiBase/files/$clean';
  }

  Widget _buildMediaThumbnail(bool isDark) {
    final url = replyingMessage.mediaUrl;
    final type = replyingMessage.type.toLowerCase();

    final isImage = type.contains('image') ||
        type == 'photo' ||
        (url != null &&
            ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].any(
                (ext) => url.toLowerCase().split('?').first.endsWith('.$ext')));

    final isVideo = type.contains('video') ||
        (url != null &&
            ['mp4', 'mov', 'avi', 'mkv'].any(
                (ext) => url.toLowerCase().split('?').first.endsWith('.$ext')));

    final isAudio = type.contains('audio') ||
        type.contains('voice') ||
        (url != null &&
            ['m4a', 'mp3', 'wav', 'aac'].any(
                (ext) => url.toLowerCase().split('?').first.endsWith('.$ext')));

    if (isImage && url != null && url.isNotEmpty) {
      return FutureBuilder<String?>(
        future: AttachmentCacheService.instance.resolveLocalPath(url),
        builder: (context, snapshot) {
          final localPath = snapshot.data;
          if (localPath != null &&
              localPath.isNotEmpty &&
              File(localPath).existsSync()) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(localPath),
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            );
          }
          final resolved = _resolveRemoteUrl(url);
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Image.network(
                resolved,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.photo_rounded,
                    size: 18,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    if (isVideo) {
      return _buildIconBadge(Icons.play_circle_fill_rounded, isDark);
    }

    if (isAudio) {
      return _buildIconBadge(Icons.mic_rounded, isDark);
    }

    return _buildIconBadge(Icons.insert_drive_file_rounded, isDark);
  }

  Widget _buildIconBadge(IconData icon, bool isDark) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 20, color: AppTheme.primaryColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final msgType = replyingMessage.type.toLowerCase();
    final mediaUrl = replyingMessage.mediaUrl?.trim();
    final bool hasMediaUrl = mediaUrl != null && mediaUrl.isNotEmpty;
    final bool isTextMessage =
        msgType == 'text' || msgType.contains('text') || !hasMediaUrl;
    final bool hasMedia = hasMediaUrl && !isTextMessage;

    final displayContent = replyingMessage.previewText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      color: isDark ? AppTheme.darkSurface : Colors.white,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  replyingMessage.senderId == 'user'
                      ? 'Replying to You'
                      : conversation.isGroup
                          ? groupMemberNames[int.tryParse(
                                  replyingMessage.senderId,
                                )] ??
                              'Replying to member'
                          : 'Replying to $chatName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayContent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.subtitleGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (hasMedia) ...[
            const SizedBox(width: 8),
            _buildMediaThumbnail(isDark),
          ],
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onCancel,
            tooltip: 'Cancel reply',
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
