import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/core/widgets/vault_edge_panel_wrapper.dart';
import 'package:securecalc/src/features/chat/domain/entities/chat_conversation.dart';
import 'package:securecalc/src/features/chat/domain/services/local_chat_storage.dart';

import '../../domain/models/server_models.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import 'chat_detail_page.dart';

class LockedChatsPage extends StatefulWidget {
  final bool isDuressMode;

  const LockedChatsPage({super.key, this.isDuressMode = false});

  @override
  State<LockedChatsPage> createState() => _LockedChatsPageState();
}

class _LockedChatsPageState extends State<LockedChatsPage> {
  final ScrollController _scrollController = ScrollController();
  final List<ServerChatModel> _lockedChats = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchLockedChats();
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
      _loadMoreLockedChats();
    }
  }

  Future<void> _fetchLockedChats() async {
    if (widget.isDuressMode) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _lockedChats.clear();
          _hasMore = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      _currentPage = 1;
      final res = await ServerApiService.instance.getLockedChats(
        page: 1,
        limit: 20,
      );
      if (mounted) {
        setState(() {
          _lockedChats.clear();
          _lockedChats.addAll(res.chats);
          _hasMore = res.hasMore;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[LockedChatsPage] Fetch error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppToast.show('Failed to load locked chats', isError: true);
      }
    }
  }

  Future<void> _loadMoreLockedChats() async {
    if (widget.isDuressMode || _isLoadingMore || !_hasMore) return;

    if (mounted) setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final res = await ServerApiService.instance.getLockedChats(
        page: nextPage,
        limit: 20,
      );
      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          _lockedChats.addAll(res.chats);
          _hasMore = res.hasMore;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('[LockedChatsPage] Load more error: $e');
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
        message: const Text('Choose an action for this locked conversation.'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.of(modalContext).pop();
              _unlockChat(chat);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.lock_open, size: 20),
                SizedBox(width: 8),
                Text('Unlock Chat'),
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

  Future<void> _unlockChat(ServerChatModel chat) async {
    final displayName = _getDisplayName(chat);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: CupertinoActivityIndicator(radius: 16),
      ),
    );

    try {
      final success = await ServerChatManager.instance.unlockChat(chat.id);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (success) {
        if (mounted) {
          setState(() {
            _lockedChats.removeWhere((c) => c.id == chat.id);
          });
        }
        AppToast.show('Chat with $displayName unlocked');
      } else {
        AppToast.show('Failed to unlock chat. Please try again.', isError: true);
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      AppToast.show('Error unlocking chat: $e', isError: true);
    }
  }

  void _openChatDetail(ServerChatModel chat) async {
    final list = LocalChatStorage.instance.conversationsNotifier.value;
    final conv = list.firstWhere(
      (c) => c.id == chat.id.toString(),
      orElse: () => ChatConversation(
        id: chat.id.toString(),
        name: _getDisplayName(chat),
        avatarUrl: _getDisplayAvatar(chat) ?? '',
        lastMessage: chat.lastMessage ?? '',
        lastMessageTime: '',
        isGroup: chat.isGroup,
        isLocked: true,
        messages: const [],
      ),
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VaultEdgePanelWrapper(
          isDuressMode: widget.isDuressMode,
          child: ChatDetailPage(conversation: conv),
        ),
      ),
    );

    _fetchLockedChats();
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.lock_fill, size: 18, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text(
              'Locked Chats',
              style: TextStyle(
                color: AppTheme.primaryText(isDark),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          : _lockedChats.isEmpty
              ? RefreshIndicator(
                  onRefresh: _fetchLockedChats,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  CupertinoIcons.lock_fill,
                                  size: 44,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Locked Chats',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.secondaryText(isDark),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Chats you lock will appear here.',
                                style: TextStyle(
                                  fontSize: 13.5,
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
                  onRefresh: _fetchLockedChats,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _lockedChats.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _lockedChats.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CupertinoActivityIndicator(radius: 12)),
                        );
                      }

                      final chat = _lockedChats[index];
                      final displayName = _getDisplayName(chat);
                      final avatarUrl = _getDisplayAvatar(chat);
                      final lastMsgText = chat.lastMessage?.isNotEmpty == true
                          ? chat.lastMessage!
                          : 'Locked Conversation';

                      return InkWell(
                        onLongPress: () => _showChatOptionsDialog(chat),
                        onTap: () => _openChatDetail(chat),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                                      lastMsgText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.secondaryText(isDark),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _unlockChat(chat),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(CupertinoIcons.lock_open,
                                          size: 14, color: AppTheme.primaryColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Unlock',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  CupertinoIcons.ellipsis,
                                  color: AppTheme.secondaryText(isDark),
                                  size: 20,
                                ),
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
