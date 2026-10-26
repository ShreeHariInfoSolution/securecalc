import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';

import '../../domain/models/server_models.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';

class DeletedChatsPage extends StatefulWidget {
  final bool isDuressMode;

  const DeletedChatsPage({super.key, this.isDuressMode = false});

  @override
  State<DeletedChatsPage> createState() => _DeletedChatsPageState();
}

class _DeletedChatsPageState extends State<DeletedChatsPage> {
  final ScrollController _scrollController = ScrollController();
  final List<ServerChatModel> _deletedChats = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchDeletedChats();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadMoreDeletedChats();
    }
  }

  Future<void> _fetchDeletedChats() async {
    if (widget.isDuressMode) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _deletedChats.clear();
          _hasMore = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      _currentPage = 1;
      final res = await ServerApiService.instance.getDeletedChatsPage(
        page: 1,
        limit: 20,
      );
      if (mounted) {
        setState(() {
          _deletedChats.clear();
          _deletedChats.addAll(res.chats);
          _hasMore = res.hasMore;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[DeletedChatsPage] Fetch error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppToast.show('Failed to load deleted chats', isError: true);
      }
    }
  }

  Future<void> _loadMoreDeletedChats() async {
    if (widget.isDuressMode || _isLoadingMore || !_hasMore) return;

    if (mounted) setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final res = await ServerApiService.instance.getDeletedChatsPage(
        page: nextPage,
        limit: 20,
      );
      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          _deletedChats.addAll(res.chats);
          _hasMore = res.hasMore;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('[DeletedChatsPage] Load more error: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  String _getDisplayName(ServerChatModel chat) {
    if (chat.isGroup) {
      return (chat.groupName != null && chat.groupName!.isNotEmpty)
          ? chat.groupName!
          : 'Group Chat';
    }

    final currentUserId = ServerApiService.instance.currentUserId;
    final peer = chat.members.firstWhere(
      (m) => m.id != currentUserId,
      orElse: () => chat.members.isNotEmpty ? chat.members.first : UserModel(id: 0, name: 'Contact'),
    );

    return peer.name.isNotEmpty && !peer.name.startsWith('User #')
        ? peer.name
        : (peer.phone ?? peer.email ?? 'Contact');
  }

  String? _getDisplayAvatar(ServerChatModel chat) {
    if (chat.isGroup) {
      return chat.groupAvatar;
    }
    final currentUserId = ServerApiService.instance.currentUserId;
    final peer = chat.members.firstWhere(
      (m) => m.id != currentUserId,
      orElse: () => chat.members.isNotEmpty ? chat.members.first : UserModel(id: 0, name: ''),
    );
    return peer.avatar;
  }

  void _showChatOptionsDialog(ServerChatModel chat) {
    final displayName = _getDisplayName(chat);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (modalContext) => CupertinoActionSheet(
        title: Text(
          displayName,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryText(isDark),
          ),
        ),
        message: const Text('Choose an action for this deleted conversation.'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.of(modalContext).pop();
              _recoverChat(chat);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.arrow_counterclockwise, size: 20),
                SizedBox(width: 8),
                Text('Recover Chat'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(modalContext).pop();
              _confirmPermanentDelete(chat);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.trash, size: 20, color: Colors.redAccent),
                SizedBox(width: 8),
                Text(
                  'Delete Permanently',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(modalContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _confirmPermanentDelete(ServerChatModel chat) {
    final displayName = _getDisplayName(chat);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        title: const Text('Delete Permanently?'),
        content: Text(
          'Are you sure you want to permanently delete chat with $displayName? This action cannot be undone.',
          style: TextStyle(
            color: AppTheme.primaryText(isDark),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deleteChatPermanently(chat);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteChatPermanently(ServerChatModel chat) async {
    final displayName = _getDisplayName(chat);

    // Show loading overlay dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: CupertinoActivityIndicator(radius: 16),
      ),
    );

    try {
      final success =
          await ServerApiService.instance.deleteChatPermanently(chat.id);

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading
      }

      if (success) {
        if (mounted) {
          setState(() {
            _deletedChats.removeWhere((c) => c.id == chat.id);
          });
        }
        AppToast.show('Chat with $displayName permanently deleted');
      } else {
        AppToast.show(
          'Failed to permanently delete chat. Please try again.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading
      }
      AppToast.show('Error deleting chat: $e', isError: true);
    }
  }

  Future<void> _recoverChat(ServerChatModel chat) async {
    final displayName = _getDisplayName(chat);

    // Show loading overlay dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: CupertinoActivityIndicator(radius: 16),
      ),
    );

    try {
      final success = await ServerApiService.instance.recoverChat(chat.id);

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading
      }

      if (success) {
        if (mounted) {
          setState(() {
            _deletedChats.removeWhere((c) => c.id == chat.id);
          });
        }
        AppToast.show('Chat with $displayName recovered successfully');
        unawaited(ServerChatManager.instance.syncChats());
      } else {
        AppToast.show('Failed to recover chat. Please try again.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading
      }
      AppToast.show('Error recovering chat: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.chatCanvas(isDark),
      appBar: AppBar(
        backgroundColor: AppTheme.glassSurface(isDark),
        elevation: 0,
        leading: IconButton(
          icon: Icon(CupertinoIcons.chevron_left, color: AppTheme.primaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Deleted Chats',
          style: TextStyle(
            color: AppTheme.primaryText(isDark),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          : _deletedChats.isEmpty
              ? RefreshIndicator(
                  onRefresh: _fetchDeletedChats,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.trash,
                                size: 54,
                                color: AppTheme.secondaryText(isDark),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'No Deleted Chats',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.secondaryText(isDark),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Deleted chats will appear here.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.secondaryText(isDark),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchDeletedChats,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _deletedChats.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _deletedChats.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: CupertinoActivityIndicator(radius: 12),
                          ),
                        );
                      }

                      final chat = _deletedChats[index];
                      final displayName = _getDisplayName(chat);
                      final avatarUrl = _getDisplayAvatar(chat);

                      return InkWell(
                        onLongPress: () => _showChatOptionsDialog(chat),
                        onTap: () => _showChatOptionsDialog(chat),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              IosAvatar(
                                name: displayName,
                                imagePath: avatarUrl,
                                size: 48,
                                showOnline: false,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primaryText(isDark),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      chat.isGroup
                                          ? 'Deleted Group'
                                          : 'Deleted Conversation',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.secondaryText(isDark),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  CupertinoIcons.ellipsis,
                                  color: AppTheme.secondaryText(isDark),
                                  size: 22,
                                ),
                                tooltip: 'Chat Options',
                                onPressed: () => _showChatOptionsDialog(chat),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
