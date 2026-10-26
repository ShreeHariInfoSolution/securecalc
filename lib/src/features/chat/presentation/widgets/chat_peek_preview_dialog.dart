import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import 'chat_wallpaper_widget.dart';

/// iOS WhatsApp-style frosted glass peek preview dialog on long press in chat list.
class ChatPeekPreviewDialog extends StatefulWidget {
  final ChatConversation conversation;
  final VoidCallback onOpenChat;
  final bool isDuressMode;

  const ChatPeekPreviewDialog({
    super.key,
    required this.conversation,
    required this.onOpenChat,
    this.isDuressMode = false,
  });

  @override
  State<ChatPeekPreviewDialog> createState() => _ChatPeekPreviewDialogState();
}

class _ChatPeekPreviewDialogState extends State<ChatPeekPreviewDialog> {
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isDragging = false;
  double _dragOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    // 1. Load cached local messages first
    final cached = await LocalChatStorage.instance.loadMessages(
      widget.conversation.id,
    );
    if (mounted) {
      setState(() {
        _messages = cached;
        _isLoading = cached.isEmpty;
      });
      _scrollToBottom();
    }

    // 2. Fetch fresh messages from server
    try {
      final fresh = await ServerChatManager.instance.loadMessages(
        widget.conversation.id,
      );
      if (mounted) {
        setState(() {
          _messages = fresh;
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  bool _isMe(ChatMessage msg) {
    final currentUserIdStr = ServerApiService.instance.currentUserId
        ?.toString();
    return msg.senderId == 'user' ||
        msg.senderId == 'me' ||
        (currentUserIdStr != null && msg.senderId == currentUserIdStr);
  }

  String _formatTime(DateTime date) {
    final hour24 = date.hour;
    final hour = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
    final min = date.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour:$min $period';
  }

  bool _isSingleEmoji(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final regex = RegExp(
      r'^(?:[\u2700-\u27BF]|[\uE000-\uF8FF]|\uD83C[\uDC00-\uDFFF]|\uD83D[\uDC00-\uDFFF]|[\u2011-\u26FF]|\uD83E[\uDD10-\uDDFF])+$',
    );
    return regex.hasMatch(trimmed) && trimmed.runes.length <= 3;
  }

  bool _isImageMessage(ChatMessage msg) {
    if (msg.isDeleted) return false;
    final type = msg.type.toLowerCase();
    if (type.startsWith('image/') || type == 'image') return true;
    if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) {
      final ext = msg.mediaUrl!.split('.').last.split('?').first.toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext) ||
          msg.previewText == 'Photo') {
        return true;
      }
    }
    return false;
  }

  String _resolveRemoteMediaUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    String cleanPath = path;
    if (path.contains('uploads/')) {
      cleanPath = 'uploads/${path.split('uploads/').last}';
    } else if (path.contains('files/')) {
      cleanPath = 'files/${path.split('files/').last}';
    } else {
      cleanPath = path.split(RegExp(r'[/\\]')).last;
    }
    final normalized = cleanPath.replaceFirst(RegExp(r'^/+'), '');
    final apiBase = ServerApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final filePath = normalized.startsWith('api/files/')
        ? normalized.substring('api/files/'.length)
        : normalized.startsWith('files/')
        ? normalized.substring('files/'.length)
        : normalized;
    final encodedPath = filePath.split('/').map(Uri.encodeComponent).join('/');
    return '$apiBase/files/$encodedPath';
  }

  Widget _buildImageWidget(ChatMessage msg) {
    final url = msg.mediaUrl ?? '';
    if (url.isEmpty) return const SizedBox.shrink();

    Widget imgWidget;
    if (!url.startsWith('http://') &&
        !url.startsWith('https://') &&
        File(url).existsSync()) {
      imgWidget = Image.file(
        File(url),
        fit: BoxFit.cover,
        width: double.infinity,
        height: 140,
      );
    } else {
      final cached = AttachmentCacheService.instance.resolveLocalPathSync(url);
      if (cached != null && File(cached).existsSync()) {
        imgWidget = Image.file(
          File(cached),
          fit: BoxFit.cover,
          width: double.infinity,
          height: 140,
        );
      } else {
        final remoteUrl = _resolveRemoteMediaUrl(url);
        imgWidget = Image.network(
          remoteUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 140,
          errorBuilder: (context, error, stackTrace) => Container(
            height: 90,
            color: Colors.black12,
            child: const Center(
              child: Icon(
                Icons.broken_image_rounded,
                color: Colors.grey,
                size: 26,
              ),
            ),
          ),
        );
      }
    }

    return ClipRRect(borderRadius: BorderRadius.circular(10), child: imgWidget);
  }

  Widget _buildMessageBubble(
    BuildContext context,
    ChatMessage msg,
    bool isDark,
    double previewWidth,
  ) {
    final isMe = _isMe(msg);
    final isEmoji = _isSingleEmoji(msg.content);
    final isImage = _isImageMessage(msg);

    if (isEmoji) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(msg.content.trim(), style: const TextStyle(fontSize: 48)),
              Text(
                _formatTime(msg.timestamp),
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppTheme.secondaryText(isDark),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: previewWidth * 0.72),
        margin: const EdgeInsets.symmetric(vertical: 3.5),
        padding: isImage
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isMe
              ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFDCF8C6))
              : (isDark ? const Color(0xFF1F2C34) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMe ? 14 : 2),
            bottomRight: Radius.circular(isMe ? 2 : 14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isImage) ...[
              _buildImageWidget(msg),
              if (msg.content.isNotEmpty && msg.content != 'Photo') ...[
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  child: Text(
                    msg.content,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ] else ...[
              Text(
                msg.content.isNotEmpty ? msg.content : msg.previewText,
                style: TextStyle(
                  fontSize: 14.5,
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.25,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _formatTime(msg.timestamp),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isMe
                        ? (isDark ? Colors.white70 : Colors.black54)
                        : (isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 3),
                  Icon(
                    msg.isRead ? Icons.done_all : Icons.done,
                    size: 13,
                    color: msg.isRead
                        ? (isDark ? const Color(0xFF53B147) : Colors.blue)
                        : (isDark ? Colors.white54 : Colors.black45),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Keep the preview at the same in-list position shown by WhatsApp.
    final previewWidth = (screenWidth - 28.0).clamp(300.0, 420.0);
    final preferredPreviewHeight = (screenHeight * 0.43).clamp(220.0, 390.0);
    // Reserve space for the action sheet. On compact screens the preview
    // shrinks instead of allowing the Column to overflow below the viewport.
    final previewHeight =
        (screenHeight - MediaQuery.paddingOf(context).vertical - 28.0 - 300.0)
            .clamp(120.0, preferredPreviewHeight)
            .toDouble();

    // Options Menu Card: Aligned to Left, compact glass design (~68% width)
    final optionsWidth = (screenWidth * 0.68).clamp(230.0, 275.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dismiss on tap outside
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.black.withValues(alpha: 0.42)),
            ),
          ),

          // A short drag springs back; a decisive downward drag dismisses.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 14.0,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: (_) =>
                      setState(() => _isDragging = true),
                  onVerticalDragUpdate: (details) {
                    if (details.delta.dy > 0 || _dragOffset > 0) {
                      setState(() {
                        _dragOffset = (_dragOffset + details.delta.dy).clamp(
                          0.0,
                          260.0,
                        );
                      });
                    }
                  },
                  onVerticalDragEnd: (details) {
                    final shouldDismiss =
                        _dragOffset > 72 ||
                        (details.primaryVelocity ?? 0) > 650;
                    if (shouldDismiss) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() {
                        _isDragging = false;
                        _dragOffset = 0.0;
                      });
                    }
                  },
                  onVerticalDragCancel: () => setState(() {
                    _isDragging = false;
                    _dragOffset = 0.0;
                  }),
                  child: AnimatedSlide(
                    duration: _isDragging
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    offset: Offset(0, _dragOffset / previewHeight),
                    child: AnimatedOpacity(
                      duration: _isDragging
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      opacity: (1.0 - (_dragOffset / 260.0)).clamp(0.2, 1.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top Box: Full Chat Preview Window
                          GestureDetector(
                            onTap: widget.onOpenChat,
                            child: Container(
                              height: previewHeight,
                              width: previewWidth,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    blurRadius: 22,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: Column(
                                  children: [
                                    // Chat Header Bar
                                    Container(
                                      height: 48,
                                      width: double.infinity,
                                      color: isDark
                                          ? const Color(0xFF2C2C2E)
                                          : const Color(0xFFF6F6F8),
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Text(
                                        widget.conversation.name,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryText(isDark),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Chat Messages Area
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          // Wallpaper background
                                          ChatWallpaperWidget(
                                            chatId: widget.conversation.id,
                                            isDark: isDark,
                                            backgroundUrl: widget
                                                .conversation
                                                .backgroundUrl,
                                          ),

                                          if (_isLoading)
                                            const Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(AppTheme.primaryColor),
                                              ),
                                            )
                                          else if (_messages.isEmpty)
                                            Center(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      (isDark
                                                              ? Colors.black
                                                              : Colors.white)
                                                          .withValues(
                                                            alpha: 0.7,
                                                          ),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Text(
                                                  'No messages yet',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color:
                                                        AppTheme.secondaryText(
                                                          isDark,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            )
                                          else
                                            ListView.builder(
                                              controller: _scrollController,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              itemCount: _messages.length,
                                              itemBuilder: (context, index) =>
                                                  _buildMessageBubble(
                                                    context,
                                                    _messages[index],
                                                    isDark,
                                                    previewWidth,
                                                  ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Bottom Box: Frosted Glass Options Action Menu (Left Aligned)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                              child: Container(
                                width: optionsWidth,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.black.withValues(alpha: 0.45)
                                      : Colors.white.withValues(alpha: 0.68),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.15)
                                        : Colors.white.withValues(alpha: 0.6),
                                    width: 0.8,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.18,
                                      ),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 1. Mark as unread / read
                                    _buildActionTile(
                                      context: context,
                                      isDark: isDark,
                                      icon: widget.conversation.unreadCount > 0
                                          ? CupertinoIcons.chat_bubble
                                          : CupertinoIcons.chat_bubble_text,
                                      label: widget.conversation.unreadCount > 0
                                          ? 'Mark as read'
                                          : 'Mark as unread',
                                      onTap: () async {
                                        Navigator.pop(context);
                                        await LocalChatStorage.instance
                                            .toggleUnreadConversation(
                                              widget.conversation.id,
                                            );
                                      },
                                    ),
                                    _buildDivider(isDark),

                                    // 2. Archive
                                    _buildActionTile(
                                      context: context,
                                      isDark: isDark,
                                      icon: CupertinoIcons.archivebox,
                                      label: widget.conversation.isArchived
                                          ? 'Unarchive'
                                          : 'Archive',
                                      onTap: () async {
                                        Navigator.pop(context);
                                        await LocalChatStorage.instance
                                            .toggleArchiveConversation(
                                              widget.conversation.id,
                                            );
                                      },
                                    ),
                                    _buildDivider(isDark),

                                    // 3. Mute
                                    _buildActionTile(
                                      context: context,
                                      isDark: isDark,
                                      icon: widget.conversation.isMuted
                                          ? CupertinoIcons.bell
                                          : CupertinoIcons.bell_slash,
                                      label: widget.conversation.isMuted
                                          ? 'Unmute'
                                          : 'Mute',
                                      onTap: () async {
                                        Navigator.pop(context);
                                        await LocalChatStorage.instance
                                            .toggleMuteConversation(
                                              widget.conversation.id,
                                            );
                                      },
                                    ),
                                    _buildDivider(isDark),

                                    // 4. Lock chat
                                    _buildActionTile(
                                      context: context,
                                      isDark: isDark,
                                      icon: CupertinoIcons.lock,
                                      label: 'Lock chat',
                                      onTap: () {
                                        Navigator.pop(context);
                                        widget.onOpenChat();
                                      },
                                    ),
                                    _buildDivider(isDark),

                                    // 5. Add to Favourites
                                    _buildActionTile(
                                      context: context,
                                      isDark: isDark,
                                      icon: CupertinoIcons.heart,
                                      label: 'Add to Favourites',
                                      onTap: () {
                                        Navigator.pop(context);
                                      },
                                    ),
                                    _buildDivider(isDark),

                                    // 6. Add to list
                                    _buildActionTile(
                                      context: context,
                                      isDark: isDark,
                                      icon: CupertinoIcons.person_crop_square,
                                      label: 'Add to list',
                                      onTap: () {
                                        Navigator.pop(context);
                                      },
                                    ),
                                    _buildDivider(isDark),

                                    // 7. Block / Delete
                                    _buildActionTile(
                                      context: context,
                                      isDark: isDark,
                                      icon: CupertinoIcons.trash,
                                      label: 'Delete Chat',
                                      isDestructive: true,
                                      onTap: () async {
                                        Navigator.pop(context);
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Delete Chat'),
                                            content: Text(
                                              'Delete conversation with ${widget.conversation.name}?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.redAccent,
                                                ),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          final chatId = int.tryParse(
                                            widget.conversation.id,
                                          );
                                          if (chatId != null && chatId > 0) {
                                            await ServerApiService.instance
                                                .deleteChatREST(
                                                  chatId,
                                                  deleteChat: true,
                                                );
                                          }
                                          await LocalChatStorage.instance
                                              .deleteConversation(
                                                widget.conversation.id,
                                              );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required bool isDark,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final textColor = isDestructive
        ? Colors.redAccent
        : AppTheme.primaryText(isDark);
    final iconColor = isDestructive ? Colors.redAccent : textColor;

    return InkWell(
      onTap: onTap,
      splashColor: isDestructive
          ? Colors.red.withValues(alpha: 0.1)
          : AppTheme.primaryColor.withValues(alpha: 0.08),
      highlightColor: Colors.black.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.5),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      color: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.black.withValues(alpha: 0.06),
    );
  }
}
