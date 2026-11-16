import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/ui/vault_page_route.dart';
import 'package:securecalc/src/core/widgets/glass_kit.dart';
import 'package:securecalc/src/features/chat/domain/services/attachment_cache_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:securecalc/src/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:securecalc/src/features/chat/presentation/widgets/location_chat_bubble.dart';
import 'package:securecalc/src/features/chat/presentation/widgets/sticker_picker_panel.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../widgets/chat_wallpaper_widget.dart';

class MessageInfoPage extends StatelessWidget {
  final ChatMessage message;
  final ChatConversation conversation;

  const MessageInfoPage({
    super.key,
    required this.message,
    required this.conversation,
  });

  /// Pushes the MessageInfoPage with a native iOS interactive slide transition.
  static Future<void> open(
    BuildContext context, {
    required ChatMessage message,
    required ChatConversation conversation,
  }) {
    return Navigator.of(context).push(
      VaultPageRoute<void>(
        builder: (context) => MessageInfoPage(
          message: message,
          conversation: conversation,
        ),
      ),
    );
  }

  String _formatTimeOnly(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatDateAndFilter(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(dt.year, dt.month, dt.day);

    final timeStr = _formatTimeOnly(dt);

    if (msgDate == today) {
      return 'Today at $timeStr';
    } else if (msgDate == yesterday) {
      return 'Yesterday at $timeStr';
    } else {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $timeStr';
    }
  }

  String _formatDateChip(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(dt.year, dt.month, dt.day);

    if (msgDate == today) {
      return 'Today';
    } else if (msgDate == yesterday) {
      return 'Yesterday';
    } else {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    }
  }

  String _resolveRemoteMediaUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final baseUrl = ServerApiService.baseUrl;
    final cleanPath = url.startsWith('/') ? url.substring(1) : url;
    return '$baseUrl/$cleanPath';
  }

  Widget _buildMessagePreview(
    BuildContext context,
    bool isDark,
    Color bubbleColor,
    DateTime createdTime,
  ) {
    final isRead = message.isRead;
    final isDelivered = message.isDelivered || isRead;

    final isLocation = message.type == 'location' ||
        message.type == 'live_location' ||
        message.msgType == 'location' ||
        message.msgType == 'live_location' ||
        (message.content.trim().startsWith('{') &&
            (message.content.contains('"latitude"') ||
                message.content.contains('"location_id"')));

    if (isLocation) {
      return LocationMessageBubble(
        rawMessage: message.content,
        messageId: message.id,
        isMe: true,
        isDark: isDark,
        chatHeadId: int.tryParse(conversation.id) ?? 0,
        timestamp: Text(
          _formatTimeOnly(createdTime),
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
      );
    }

    final url = (message.mediaUrl ?? '').trim();
    final attachmentType = message.type.toLowerCase().trim();
    final name = (message.fileName ?? '').toLowerCase().trim();

    final isImage = attachmentType.contains('image') ||
        attachmentType == 'photo' ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].any((ext) =>
            url.toLowerCase().contains('.$ext') || name.endsWith('.$ext'));

    final isVideo = attachmentType.contains('video') ||
        ['mp4', 'mov', 'avi', 'mkv', 'webm'].any((ext) =>
            url.toLowerCase().contains('.$ext') || name.endsWith('.$ext'));

    final isDarkBubble = bubbleColor.computeLuminance() < 0.5;
    final bubbleFg = isDarkBubble ? Colors.white : Colors.black87;
    final bubbleFg2 = isDarkBubble ? Colors.white70 : Colors.black54;

    if (isImage) {
      return _buildImageMediaPreview(
          context, url, isDark, bubbleColor, createdTime, isRead, isDelivered);
    }

    if (isVideo) {
      return _buildVideoMediaPreview(
          context, url, isDark, bubbleColor, createdTime, isRead, isDelivered);
    }

    // Standard Text Message Bubble with native tail painter
    return CustomPaint(
      painter: IMessageBubblePainter(
        color: bubbleColor,
        isOutgoing: true,
        showTail: true,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.fromLTRB(11, 7, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            EmojiText(
              message.content,
              style: TextStyle(
                fontSize: 15,
                color: bubbleFg,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTimeOnly(createdTime),
                  style: TextStyle(
                    fontSize: 10,
                    color: bubbleFg2,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  (isRead || isDelivered)
                      ? Icons.done_all_rounded
                      : Icons.done_rounded,
                  size: 13,
                  color: isRead ? const Color(0xFF53BDEB) : bubbleFg2,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageMediaPreview(
    BuildContext context,
    String url,
    bool isDark,
    Color bubbleColor,
    DateTime createdTime,
    bool isRead,
    bool isDelivered,
  ) {
    final isDarkBubble = bubbleColor.computeLuminance() < 0.5;
    final bubbleFg = isDarkBubble ? Colors.white : Colors.black87;
    final bubbleFg2 = isDarkBubble ? Colors.white70 : Colors.black54;

    Widget imgWidget;
    if (url.isNotEmpty &&
        !url.startsWith('http://') &&
        !url.startsWith('https://') &&
        File(url).existsSync()) {
      imgWidget = Image.file(
        File(url),
        fit: BoxFit.cover,
        width: double.infinity,
        height: 180,
      );
    } else if (url.isNotEmpty) {
      final cached = AttachmentCacheService.instance.resolveLocalPathSync(url);
      if (cached != null && File(cached).existsSync()) {
        imgWidget = Image.file(
          File(cached),
          fit: BoxFit.cover,
          width: double.infinity,
          height: 180,
        );
      } else {
        final remoteUrl = _resolveRemoteMediaUrl(url);
        imgWidget = Image.network(
          remoteUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 180,
          errorBuilder: (context, error, stackTrace) => Container(
            height: 120,
            color: Colors.black12,
            child: const Center(
              child: Icon(Icons.broken_image_rounded,
                  color: Colors.grey, size: 30),
            ),
          ),
        );
      }
    } else {
      imgWidget = Container(
        height: 120,
        color: Colors.black12,
        child: const Center(
            child: Icon(Icons.image_rounded, color: Colors.grey, size: 30)),
      );
    }

    final hasCaption = message.content.isNotEmpty &&
        message.content != 'Photo' &&
        message.content != '[Attachment]' &&
        !message.content.startsWith('http://') &&
        !message.content.startsWith('https://');

    return CustomPaint(
      painter: IMessageBubblePainter(
        color: bubbleColor,
        isOutgoing: true,
        showTail: true,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imgWidget,
            ),
            if (hasCaption) ...[
              const SizedBox(height: 5),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 14,
                      color: bubbleFg,
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 2, top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTimeOnly(createdTime),
                    style: TextStyle(
                      fontSize: 10,
                      color: bubbleFg2,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    (isRead || isDelivered)
                        ? Icons.done_all_rounded
                        : Icons.done_rounded,
                    size: 13,
                    color: isRead ? const Color(0xFF53BDEB) : bubbleFg2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoMediaPreview(
    BuildContext context,
    String url,
    bool isDark,
    Color bubbleColor,
    DateTime createdTime,
    bool isRead,
    bool isDelivered,
  ) {
    final isDarkBubble = bubbleColor.computeLuminance() < 0.5;
    final bubbleFg = isDarkBubble ? Colors.white : Colors.black87;
    final bubbleFg2 = isDarkBubble ? Colors.white70 : Colors.black54;

    return CustomPaint(
      painter: IMessageBubblePainter(
        color: bubbleColor,
        isOutgoing: true,
        showTail: true,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 180,
                width: double.infinity,
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (url.isNotEmpty && File(url).existsSync())
                      Image.file(File(url),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 180)
                    else
                      const Icon(Icons.movie_rounded,
                          color: Colors.white38, size: 48),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (message.content.isNotEmpty && message.content != 'Video') ...[
              const SizedBox(height: 5),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 14,
                      color: bubbleFg,
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 2, top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTimeOnly(createdTime),
                    style: TextStyle(
                      fontSize: 10,
                      color: bubbleFg2,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    (isRead || isDelivered)
                        ? Icons.done_all_rounded
                        : Icons.done_rounded,
                    size: 13,
                    color: isRead ? const Color(0xFF53BDEB) : bubbleFg2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? AppTheme.darkBackground : const Color(0xFFF2F2F7);
    final cardSurface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final primaryTextColor = AppTheme.primaryText(isDark);
    final secondaryTextColor = AppTheme.secondaryText(isDark);
    final dividerColor = AppTheme.listDivider(isDark);
    final bubbleColor = AppPreferences.getChatBubbleColor(chatId: conversation.id);

    final isRead = message.isRead;
    final isDelivered = message.isDelivered || isRead;

    final createdTime = message.timestamp.toLocal();
    final readTime = (message.updatedAt ?? message.timestamp).toLocal();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Material(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white,
            shape: const CircleBorder(),
            elevation: isDark ? 0 : 1,
            shadowColor: Colors.black12,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pop(),
              child: Center(
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: primaryTextColor,
                ),
              ),
            ),
          ),
        ),
        title: Column(
          children: [
            Text(
              'Message Info',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: primaryTextColor,
              ),
            ),
            Text(
              conversation.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // Top Preview Container with Wallpaper Background
            Container(
              constraints: const BoxConstraints(minHeight: 180),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white,
                  width: 0.8,
                ),
              ),
              child: Stack(
                children: [
                  // Wallpaper
                  Positioned.fill(
                    child: ChatWallpaperWidget(
                      chatId: conversation.id,
                      isDark: isDark,
                      backgroundUrl: conversation.backgroundUrl,
                    ),
                  ),

                  // Message Content Layer
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 152),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Date Chip
                          GlassSurface(
                            radius: 12,
                            blurEnabled: false,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            child: Text(
                              _formatDateChip(createdTime),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: primaryTextColor,
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Message Bubble / Media / Location Preview
                          Align(
                            alignment: Alignment.centerRight,
                            child: _buildMessagePreview(
                              context,
                              isDark,
                              bubbleColor,
                              createdTime,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // Read & Delivered Info Card
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: cardSurface,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Read Row
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF53BDEB).withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.done_all_rounded,
                          color: Color(0xFF53BDEB), // Official WhatsApp Blue
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Read',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                      ),
                      trailing: Text(
                        isRead ? _formatDateAndFilter(readTime) : '—',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: secondaryTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    Divider(
                      height: 0.5,
                      indent: 58,
                      endIndent: 16,
                      color: dividerColor,
                    ),

                    // Delivered Row
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.done_all_rounded,
                          color: isDark ? Colors.white60 : Colors.black45,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Delivered',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                      ),
                      trailing: Text(
                        isDelivered ? _formatDateAndFilter(createdTime) : '—',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: secondaryTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // End-to-End Encryption Badge
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.lock_shield_fill,
                    size: 14,
                    color: secondaryTextColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'End-to-end encrypted',
                    style: TextStyle(
                      fontSize: 12,
                      color: secondaryTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
