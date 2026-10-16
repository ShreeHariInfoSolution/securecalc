import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';

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

  /// Pushes the MessageInfoPage with a smooth right-to-left slide transition.
  static Future<void> open(
    BuildContext context, {
    required ChatMessage message,
    required ChatConversation conversation,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) {
          return MessageInfoPage(message: message, conversation: conversation);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final tween = Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
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
      return 'today $timeStr';
    } else if (msgDate == yesterday) {
      return 'yesterday $timeStr';
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
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $timeStr';
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? AppTheme.darkBackground
        : const Color(0xFFF6F5F0);
    final cardSurface = isDark ? AppTheme.darkSurface : Colors.white;
    final bubbleColor = isDark
        ? const Color(0xFF1E3A2B)
        : const Color(0xFFDCF8C6);

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
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pop(),
              child: const Center(
                child: Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              ),
            ),
          ),
        ),
        title: const Text(
          'Message info',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Top Preview Card with Wallpaper Background
            Container(
              height: 160,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white12
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Wallpaper
                  ChatWallpaperWidget(
                    chatId: conversation.id,
                    isDark: isDark,
                    backgroundUrl: conversation.backgroundUrl,
                  ),

                  // Message Content Layer
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Date Chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.black87
                                : Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Text(
                            _formatDateChip(createdTime),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),

                        // Message Bubble
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.72,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: bubbleColor,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(4),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    message.content,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatTimeOnly(createdTime),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(
                                      (isRead || isDelivered)
                                          ? Icons.done_all_rounded
                                          : Icons.done_rounded,
                                      size: 14,
                                      color: isRead
                                          ? const Color(0xFF53BDEB)
                                          : (isDark
                                                ? Colors.white60
                                                : Colors.black45),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Read & Delivered Info Card
            Container(
              decoration: BoxDecoration(
                color: cardSurface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Read Row
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: const Icon(
                      Icons.done_all_rounded,
                      color: Color(0xFF53BDEB), // WhatsApp Blue
                      size: 22,
                    ),
                    title: const Text(
                      'Read',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Text(
                      isRead ? _formatDateAndFilter(readTime) : '-',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  Divider(
                    height: 1,
                    indent: 52,
                    endIndent: 16,
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),

                  // Delivered Row
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Icon(
                      Icons.done_all_rounded,
                      color: isDark ? Colors.white60 : Colors.black45,
                      size: 22,
                    ),
                    title: const Text(
                      'Delivered',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Text(
                      isDelivered ? _formatDateAndFilter(createdTime) : '-',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
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
