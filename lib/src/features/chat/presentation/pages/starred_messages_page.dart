import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/server_api_service.dart';
import '../widgets/photo_gallery_viewer.dart';

class StarredMessagesPage extends StatefulWidget {
  final ChatConversation conversation;

  const StarredMessagesPage({super.key, required this.conversation});

  @override
  State<StarredMessagesPage> createState() => _StarredMessagesPageState();
}

class _StarredMessagesPageState extends State<StarredMessagesPage> {
  bool _loading = true;
  List<ChatMessage> _starredMessages = [];
  String _searchQuery = '';
  String _activeFilter = 'All'; // 'All', 'Photos', 'Files'

  @override
  void initState() {
    super.initState();
    _loadStarredMessages();
  }

  Future<void> _loadStarredMessages() async {
    setState(() => _loading = true);
    try {
      // 1. Try loading local cached messages
      var localMsgs = await LocalChatStorage.instance.loadMessages(
        widget.conversation.id,
      );
      var starred = localMsgs.where((m) => m.reaction == 'star').toList();

      // 2. Fetch remote history REST to ensure sync
      final chatId = int.tryParse(widget.conversation.id);
      if (chatId != null) {
        final serverMsgs = await ServerApiService.instance.getMessages(
          chatId,
          limit: 100,
        );
        final converted = serverMsgs
            .map(
              (sm) => ChatMessage(
                id: sm.id.toString(),
                senderId: sm.senderId == ServerApiService.instance.currentUserId
                    ? 'user'
                    : sm.senderId.toString(),
                content: sm.decryptedContent('chat_key_$chatId'),
                timestamp:
                    DateTime.tryParse(sm.createdAt)?.toLocal() ??
                    DateTime.now(),
                type:
                    sm.fileType ??
                    (sm.filePath != null && sm.filePath!.trim().isNotEmpty
                        ? 'application/octet-stream'
                        : 'text'),
                mediaUrl:
                    (sm.filePath != null && sm.filePath!.trim().isNotEmpty)
                        ? sm.filePath
                        : null,
                fileName:
                    (sm.fileName != null && sm.fileName!.trim().isNotEmpty)
                        ? sm.fileName
                        : null,
                reaction: sm.chatReact,
                replyToId: sm.replyToId,
              ),
            )
            .toList();
        final remoteStarred = converted
            .where((m) => m.reaction == 'star')
            .toList();

        // Merge local and remote
        final map = <String, ChatMessage>{};
        for (final m in starred) {
          map[m.id] = m;
        }
        for (final m in remoteStarred) {
          map[m.id] = m;
        }
        starred = map.values.toList();
      }

      // Sort newest first
      starred.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        setState(() {
          _starredMessages = starred;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleStar(ChatMessage msg) async {
    final isStarred = msg.reaction == 'star';
    final newReaction = isStarred ? null : 'star';
    final updatedMsg = msg.copyWith(reaction: newReaction);

    HapticFeedback.lightImpact();

    // Optimistic state update
    setState(() {
      if (isStarred) {
        _starredMessages.removeWhere((m) => m.id == msg.id);
      } else {
        _starredMessages.add(updatedMsg);
        _starredMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
    });

    // Remote update
    final messageId = int.tryParse(msg.id);
    if (messageId != null) {
      await ServerApiService.instance.reactMessageREST(
        messageId: messageId,
        chatReact: newReaction ?? '',
      );
    }

    // Local storage update without reordering conversation list
    final cached = await LocalChatStorage.instance.loadMessages(
      widget.conversation.id,
    );
    final idx = cached.indexWhere((m) => m.id == msg.id);
    if (idx >= 0) {
      cached[idx] = updatedMsg;
      await LocalChatStorage.instance.cacheMessages(
        widget.conversation.id,
        cached,
      );
    }

    if (mounted && isStarred) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message unstarred'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          action: SnackBarAction(
            label: 'Undo',
            textColor: Colors.amber,
            onPressed: () => _toggleStar(msg),
          ),
        ),
      );
    }
  }

  bool _isImageMessage(ChatMessage msg) {
    final url = msg.mediaUrl;
    final fn = msg.fileName ?? '';
    final t = msg.type.toLowerCase();

    if (t.startsWith('image') || t == 'photo') return true;
    if (url != null && url.isNotEmpty) {
      final lowerUrl = url.toLowerCase();
      if (lowerUrl.endsWith('.jpg') ||
          lowerUrl.endsWith('.jpeg') ||
          lowerUrl.endsWith('.png') ||
          lowerUrl.endsWith('.webp') ||
          lowerUrl.endsWith('.gif') ||
          lowerUrl.endsWith('.heic')) {
        return true;
      }
    }
    if (fn.isNotEmpty) {
      final lowerFn = fn.toLowerCase();
      if (lowerFn.endsWith('.jpg') ||
          lowerFn.endsWith('.jpeg') ||
          lowerFn.endsWith('.png') ||
          lowerFn.endsWith('.webp') ||
          lowerFn.endsWith('.gif') ||
          lowerFn.endsWith('.heic')) {
        return true;
      }
    }
    return false;
  }

  bool _isFileMessage(ChatMessage msg) {
    if (_isImageMessage(msg)) return false;
    return (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) ||
        (msg.fileName != null && msg.fileName!.isNotEmpty);
  }

  List<ChatMessage> get _starredImageMessages {
    return _starredMessages.where(_isImageMessage).toList();
  }

  List<ChatMessage> get _filteredMessages {
    return _starredMessages.where((msg) {
      // Filter by category
      if (_activeFilter == 'Photos' && !_isImageMessage(msg)) return false;
      if (_activeFilter == 'Files' && !_isFileMessage(msg)) return false;

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final contentMatches = msg.content.toLowerCase().contains(query);
        final fileMatches =
            msg.fileName?.toLowerCase().contains(query) ?? false;
        final previewMatches = msg.previewText.toLowerCase().contains(query);
        return contentMatches || fileMatches || previewMatches;
      }

      return true;
    }).toList();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(date.year, date.month, date.day);

    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    if (msgDate == today) {
      return 'Today $timeStr';
    } else if (msgDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday $timeStr';
    } else {
      return '${date.day}/${date.month}/${date.year} $timeStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? AppTheme.darkBackground
        : AppTheme.lightBackground;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final cardBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.06);

    final imageMsgs = _starredImageMessages;
    final filtered = _filteredMessages;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Starred Messages',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${_starredMessages.length} starred in this chat',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.subtitleGrey,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Reload',
            onPressed: _loadStarredMessages,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _starredMessages.isEmpty
          ? _buildEmptyState(isDark)
          : Column(
              children: [
                // Filter Chips & Search Header
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  color: surface,
                  child: Column(
                    children: [
                      // Search field
                      TextField(
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim()),
                        decoration: InputDecoration(
                          hintText: 'Search starred messages...',
                          hintStyle: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.subtitleGrey,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: AppTheme.subtitleGrey,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () =>
                                      setState(() => _searchQuery = ''),
                                )
                              : null,
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.grey.withValues(alpha: 0.1),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Category Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(
                              label: 'All (${_starredMessages.length})',
                              filterKey: 'All',
                              isDark: isDark,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              label: 'Photos (${imageMsgs.length})',
                              filterKey: 'Photos',
                              icon: Icons.image_rounded,
                              isDark: isDark,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              label:
                                  'Files (${_starredMessages.where(_isFileMessage).length})',
                              filterKey: 'Files',
                              icon: Icons.insert_drive_file_rounded,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),

                // Starred Messages List
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: AppTheme.subtitleGrey.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No matching starred messages found',
                                style: TextStyle(
                                  color: AppTheme.subtitleGrey,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final msg = filtered[index];
                            final isMine = msg.senderId == 'user';
                            final isImage = _isImageMessage(msg);
                            final isFile = _isFileMessage(msg);

                            // Find image index in all starred images
                            int imgIndex = -1;
                            if (isImage) {
                              imgIndex = imageMsgs.indexWhere(
                                (m) => m.id == msg.id,
                              );
                            }

                            return Container(
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: cardBorderColor),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    // Jump directly to this message in chat
                                    Navigator.pop(context, msg.id);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Header: Sender Avatar, Name, Date & Unstar
                                        Row(
                                          children: [
                                            IosAvatar(
                                              name: isMine
                                                  ? 'You'
                                                  : widget.conversation.name,
                                              imagePath: isMine
                                                  ? null
                                                  : widget
                                                        .conversation
                                                        .avatarUrl,
                                              size: 36,
                                              showOnline: false,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    isMine
                                                        ? 'You'
                                                        : widget
                                                              .conversation
                                                              .name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    _formatDate(msg.timestamp),
                                                    style: const TextStyle(
                                                      color:
                                                          AppTheme.subtitleGrey,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Unstar Button
                                            IconButton(
                                              icon: const Icon(
                                                Icons.star_rounded,
                                                color: Colors.amber,
                                                size: 22,
                                              ),
                                              tooltip: 'Unstar',
                                              constraints:
                                                  const BoxConstraints(),
                                              padding: const EdgeInsets.all(6),
                                              onPressed: () => _toggleStar(msg),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        // Text Content
                                        if (msg.content.trim().isNotEmpty) ...[
                                          Text(
                                            msg.content,
                                            style: TextStyle(
                                              fontSize: 14,
                                              height: 1.35,
                                              color: isDark
                                                  ? Colors.white.withValues(
                                                      alpha: 0.9,
                                                    )
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                        ],

                                        // Image Attachment Preview
                                        if (isImage) ...[
                                          _StarredImagePreview(
                                            msg: msg,
                                            isDark: isDark,
                                            onTapImage: () {
                                              if (imageMsgs.isNotEmpty &&
                                                  imgIndex >= 0) {
                                                PhotoGalleryViewer.open(
                                                  context,
                                                  photos: imageMsgs,
                                                  initialIndex: imgIndex,
                                                );
                                              }
                                            },
                                          ),
                                          const SizedBox(height: 10),
                                        ] else if (isFile) ...[
                                          // Document / Other File Attachment
                                          _buildFileAttachmentTile(msg, isDark),
                                          const SizedBox(height: 10),
                                        ],

                                        // Card Footer: Jump to Message indicator
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Text(
                                              'Jump to message',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.primaryColor
                                                    .withValues(alpha: 0.9),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              size: 11,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String filterKey,
    IconData? icon,
    required bool isDark,
  }) {
    final isSelected = _activeFilter == filterKey;
    final activeBg = AppTheme.primaryColor;
    final inactiveBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.grey.withValues(alpha: 0.12);

    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: icon != null
          ? Icon(
              icon,
              size: 16,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black87),
            )
          : null,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? Colors.white
              : (isDark ? Colors.white70 : Colors.black87),
        ),
      ),
      backgroundColor: inactiveBg,
      selectedColor: activeBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide.none,
      onSelected: (_) {
        setState(() => _activeFilter = filterKey);
      },
    );
  }

  Widget _buildFileAttachmentTile(ChatMessage msg, bool isDark) {
    final fileName = msg.fileName ?? 'Attachment';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.insert_drive_file_rounded,
              color: AppTheme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  msg.type.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.subtitleGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.star_rounded,
                size: 64,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Starred Messages',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Long press any message in this chat and select "Star" to keep important messages saved here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.subtitleGrey,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper widget to resolve local/remote image paths and render proper image preview
class _StarredImagePreview extends StatefulWidget {
  final ChatMessage msg;
  final bool isDark;
  final VoidCallback onTapImage;

  const _StarredImagePreview({
    required this.msg,
    required this.isDark,
    required this.onTapImage,
  });

  @override
  State<_StarredImagePreview> createState() => _StarredImagePreviewState();
}

class _StarredImagePreviewState extends State<_StarredImagePreview> {
  String? _resolvedPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolveImagePath();
  }

  Future<void> _resolveImagePath() async {
    final rawUrl = widget.msg.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 1. Direct local file check
    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      if (File(rawUrl).existsSync()) {
        if (mounted) {
          setState(() {
            _resolvedPath = rawUrl;
            _isLoading = false;
          });
        }
        return;
      }
    }

    // 2. Local cached attachment check
    final cached = await AttachmentCacheService.instance.resolveLocalPath(
      rawUrl,
    );
    if (cached != null && File(cached).existsSync()) {
      if (mounted) {
        setState(() {
          _resolvedPath = cached;
          _isLoading = false;
        });
      }
      return;
    }

    // 3. Fallback to network URL resolution
    final networkUrl = resolveAvatarUrl(rawUrl);
    if (mounted) {
      setState(() {
        _resolvedPath = networkUrl;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: widget.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final path = _resolvedPath;
    if (path == null) {
      return Container(
        height: 100,
        width: double.infinity,
        decoration: BoxDecoration(
          color: widget.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_rounded, color: AppTheme.subtitleGrey),
            SizedBox(width: 8),
            Text(
              'Image unavailable',
              style: TextStyle(color: AppTheme.subtitleGrey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final isLocal = !path.startsWith('http://') && !path.startsWith('https://');

    Widget imageWidget;
    if (isLocal) {
      imageWidget = Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: 200,
        errorBuilder: (context, error, stackTrace) => _buildErrorWidget(),
      );
    } else {
      final headers = ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : null;

      imageWidget = Image.network(
        path,
        headers: headers,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 200,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            height: 200,
            width: double.infinity,
            color: widget.isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.04),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildErrorWidget(),
      );
    }

    return GestureDetector(
      onTap: widget.onTapImage,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            imageWidget,
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fullscreen_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Preview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      height: 120,
      width: double.infinity,
      color: widget.isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_rounded,
            color: AppTheme.subtitleGrey,
            size: 32,
          ),
          SizedBox(height: 6),
          Text(
            'Failed to load image preview',
            style: TextStyle(color: AppTheme.subtitleGrey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
