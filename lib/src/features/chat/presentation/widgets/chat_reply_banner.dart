import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/attachment_cache_service.dart';

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

  Widget _buildMediaThumbnail(bool isDark) {
    final url = replyingMessage.mediaUrl;
    final type = replyingMessage.type.toLowerCase();

    if (type.startsWith('image/') ||
        type == 'image' ||
        (url != null &&
            ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic']
                .contains(url.split('.').last.split('?').first.toLowerCase()))) {
      if (url != null && url.isNotEmpty) {
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
            if (url.startsWith('http://') ||
                url.startsWith('https://') ||
                url.startsWith('uploads/')) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Image.network(
                    url,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF3F51B5), Color(0xFF7E57C2)],
                        ),
                      ),
                      child: const Icon(
                        Icons.image_outlined,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              );
            }
            return Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(
                  colors: [Color(0xFF3F51B5), Color(0xFF7E57C2)],
                ),
              ),
              child: const Icon(
                Icons.image_outlined,
                size: 18,
                color: Colors.white70,
              ),
            );
          },
        );
      }
      return _buildIconBadge(Icons.image_rounded, isDark);
    }

    if (type.startsWith('video/') || type == 'video') {
      return _buildIconBadge(Icons.play_circle_fill_rounded, isDark);
    }

    if (type.startsWith('audio/') || type == 'audio') {
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
      child: Icon(
        icon,
        size: 20,
        color: AppTheme.primaryColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasMedia = replyingMessage.mediaUrl?.isNotEmpty == true ||
        replyingMessage.type != 'text';

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
                          ? groupMemberNames[int.tryParse(replyingMessage.senderId)] ?? 'Replying to member'
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
                Row(
                  children: [
                    if (hasMedia) ...[
                      Icon(
                        replyingMessage.type.startsWith('image')
                            ? Icons.photo_camera_rounded
                            : replyingMessage.type.startsWith('video')
                                ? Icons.videocam_rounded
                                : replyingMessage.type.startsWith('audio')
                                    ? Icons.mic_rounded
                                    : Icons.attach_file_rounded,
                        size: 13,
                        color: AppTheme.subtitleGrey,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        replyingMessage.previewText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.subtitleGrey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
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
