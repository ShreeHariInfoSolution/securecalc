import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/models/server_models.dart';
import '../../domain/services/e2e_crypto_service.dart';
import '../../domain/services/local_chat_storage.dart';
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
  final List<ServerMessageModel> _deletedMessages = [];

  int _selectedTabIndex = 0; // 0 = Chats, 1 = Messages
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreChats = true;
  bool _hasMoreMessages = true;
  int _currentPage = 1;
  int _retentionDays = 30;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchDeletedItems();
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
      _loadMoreDeletedItems();
    }
  }

  Future<void> _fetchDeletedItems() async {
    if (widget.isDuressMode) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _deletedChats.clear();
          _deletedMessages.clear();
          _hasMoreChats = false;
          _hasMoreMessages = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      _currentPage = 1;
      final res = await ServerApiService.instance.getDeletedItemsPage(
        page: 1,
        limit: 20,
      );
      if (mounted) {
        setState(() {
          _retentionDays = res.retentionDays;
          _deletedChats.clear();
          _deletedChats.addAll(res.chats);
          _hasMoreChats = res.chatsHasMore;

          _deletedMessages.clear();
          _deletedMessages.addAll(res.messages);
          _hasMoreMessages = res.messagesHasMore;

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[DeletedChatsPage] Fetch error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppToast.show('Failed to load deleted items', isError: true);
      }
    }
  }

  Future<void> _loadMoreDeletedItems() async {
    final hasMore = _selectedTabIndex == 0 ? _hasMoreChats : _hasMoreMessages;
    if (widget.isDuressMode || _isLoadingMore || !hasMore) return;

    if (mounted) setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final res = await ServerApiService.instance.getDeletedItemsPage(
        page: nextPage,
        limit: 20,
      );
      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          _retentionDays = res.retentionDays;

          _deletedChats.addAll(res.chats);
          _hasMoreChats = res.chatsHasMore;

          _deletedMessages.addAll(res.messages);
          _hasMoreMessages = res.messagesHasMore;

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

  String _getChatNameForMessage(ServerMessageModel msg) {
    final chatId = msg.chatHeadId;

    final chatMatch = _deletedChats.firstWhere(
      (c) => c.id == chatId,
      orElse: () => ServerChatModel(
        id: -1,
        members: const [],
      ),
    );
    if (chatMatch.id != -1) {
      return _getDisplayName(chatMatch);
    }

    final conversations = LocalChatStorage.instance.conversationsNotifier.value;
    final convMatch = conversations.firstWhere(
      (c) => c.id == chatId.toString() || c.peerUserId == chatId,
      orElse: () => ChatConversation(
        id: '',
        name: '',
        avatarUrl: '',
        lastMessage: '',
        lastMessageTime: '',
        unreadCount: 0,
        messages: const [],
      ),
    );
    if (convMatch.name.isNotEmpty) {
      return convMatch.name;
    }

    return 'Chat #$chatId';
  }

  String? _getChatAvatarForMessage(ServerMessageModel msg) {
    final chatId = msg.chatHeadId;

    final chatMatch = _deletedChats.firstWhere(
      (c) => c.id == chatId,
      orElse: () => ServerChatModel(
        id: -1,
        members: const [],
      ),
    );
    if (chatMatch.id != -1) {
      return _getDisplayAvatar(chatMatch);
    }

    final conversations = LocalChatStorage.instance.conversationsNotifier.value;
    final convMatch = conversations.firstWhere(
      (c) => c.id == chatId.toString() || c.peerUserId == chatId,
      orElse: () => ChatConversation(
        id: '',
        name: '',
        avatarUrl: '',
        lastMessage: '',
        lastMessageTime: '',
        unreadCount: 0,
        messages: const [],
      ),
    );
    if (convMatch.avatarUrl.isNotEmpty) {
      return convMatch.avatarUrl;
    }

    return null;
  }

  Map<int, List<ServerMessageModel>> _groupMessagesByChat() {
    final Map<int, List<ServerMessageModel>> grouped = {};
    for (final msg in _deletedMessages) {
      final chatId = msg.chatHeadId;
      grouped.putIfAbsent(chatId, () => []).add(msg);
    }
    return grouped;
  }

  void _openDeletedChatDetail(ServerChatModel chat) {
    final chatMessages = _deletedMessages.where((m) => m.chatHeadId == chat.id).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DeletedChatDetailPage(
          chat: chat,
          messages: chatMessages,
          retentionDays: _retentionDays,
          onChatRecovered: () {
            setState(() {
              _deletedChats.removeWhere((c) => c.id == chat.id);
              _deletedMessages.removeWhere((m) => m.chatHeadId == chat.id);
            });
          },
          onChatDeletedPermanently: () {
            setState(() {
              _deletedChats.removeWhere((c) => c.id == chat.id);
              _deletedMessages.removeWhere((m) => m.chatHeadId == chat.id);
            });
          },
          onMessageRecovered: (msgId) {
            setState(() {
              _deletedMessages.removeWhere((m) => m.id == msgId);
            });
          },
        ),
      ),
    );
  }

  void _openDeletedChatDetailForChatId(int chatId, List<ServerMessageModel> messages) {
    final chatMatch = _deletedChats.firstWhere(
      (c) => c.id == chatId,
      orElse: () => ServerChatModel(
        id: chatId,
        groupName: _getChatNameForMessage(messages.first),
        members: const [],
      ),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DeletedChatDetailPage(
          chat: chatMatch,
          messages: messages,
          retentionDays: _retentionDays,
          onChatRecovered: () {
            setState(() {
              _deletedChats.removeWhere((c) => c.id == chatId);
              _deletedMessages.removeWhere((m) => m.chatHeadId == chatId);
            });
          },
          onChatDeletedPermanently: () {
            setState(() {
              _deletedChats.removeWhere((c) => c.id == chatId);
              _deletedMessages.removeWhere((m) => m.chatHeadId == chatId);
            });
          },
          onMessageRecovered: (msgId) {
            setState(() {
              _deletedMessages.removeWhere((m) => m.id == msgId);
            });
          },
        ),
      ),
    );
  }

  // ─── CHAT ACTIONS ─────────────────────────────────────────────────────────

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
              _confirmPermanentDeleteChat(chat);
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

  void _confirmPermanentDeleteChat(ServerChatModel chat) {
    final displayName = _getDisplayName(chat);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        title: const Text('Delete Permanently?'),
        content: Text(
          'Are you sure you want to permanently delete chat with $displayName? This action cannot be undone.',
          style: TextStyle(color: AppTheme.primaryText(isDark)),
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: CupertinoActivityIndicator(radius: 16),
      ),
    );

    try {
      final success = await ServerApiService.instance.deleteChatPermanently(chat.id);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (success) {
        if (mounted) {
          setState(() {
            _deletedChats.removeWhere((c) => c.id == chat.id);
          });
        }
        AppToast.show('Chat with $displayName permanently deleted');
      } else {
        AppToast.show('Failed to permanently delete chat. Please try again.', isError: true);
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      AppToast.show('Error deleting chat: $e', isError: true);
    }
  }

  Future<void> _recoverChat(ServerChatModel chat) async {
    final displayName = _getDisplayName(chat);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: CupertinoActivityIndicator(radius: 16),
      ),
    );

    try {
      final success = await ServerApiService.instance.recoverChat(chat.id);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

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
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      AppToast.show('Error recovering chat: $e', isError: true);
    }
  }

  // ─── UI BUILDERS ──────────────────────────────────────────────────────────

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
          'Trash & Recovery',
          style: TextStyle(
            color: AppTheme.primaryText(isDark),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Segmented Control Tabs
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppTheme.glassSurface(isDark),
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _selectedTabIndex,
              backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              thumbColor: isDark ? const Color(0xFF636366) : Colors.white,
              children: {
                0: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Chats (${_deletedChats.length})',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryText(isDark),
                    ),
                  ),
                ),
                1: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Messages (${_deletedMessages.length})',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryText(isDark),
                    ),
                  ),
                ),
              },
              onValueChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedTabIndex = val;
                  });
                }
              },
            ),
          ),

          // Retention notice banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(CupertinoIcons.info, size: 14, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Deleted items are kept for $_retentionDays days before permanent removal.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondaryText(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content List
          Expanded(
            child: _isLoading
                ? const Center(child: CupertinoActivityIndicator(radius: 14))
                : _selectedTabIndex == 0
                    ? _buildChatsList(isDark)
                    : _buildMessagesList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildChatsList(bool isDark) {
    if (_deletedChats.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchDeletedItems,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.trash,
                      size: 50,
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
                      'Deleted conversations will appear here.',
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
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchDeletedItems,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _deletedChats.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _deletedChats.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CupertinoActivityIndicator(radius: 12)),
            );
          }

          final chat = _deletedChats[index];
          final displayName = _getDisplayName(chat);
          final avatarUrl = _getDisplayAvatar(chat);

          return InkWell(
            onLongPress: () => _showChatOptionsDialog(chat),
            onTap: () => _openDeletedChatDetail(chat),
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
                          chat.isGroup ? 'Deleted Group' : 'Deleted Conversation',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.secondaryText(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _recoverChat(chat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.arrow_counterclockwise,
                              size: 14, color: AppTheme.primaryColor),
                          const SizedBox(width: 4),
                          Text(
                            'Recover',
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
    );
  }

  Widget _buildMessagesList(bool isDark) {
    if (_deletedMessages.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchDeletedItems,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.chat_bubble_text,
                      size: 50,
                      color: AppTheme.secondaryText(isDark),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No Deleted Messages',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondaryText(isDark),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Deleted messages will appear here grouped by chat.',
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
      );
    }

    final groupedMessages = _groupMessagesByChat();
    final chatIds = groupedMessages.keys.toList();

    return RefreshIndicator(
      onRefresh: _fetchDeletedItems,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: chatIds.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == chatIds.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CupertinoActivityIndicator(radius: 12)),
            );
          }

          final chatId = chatIds[index];
          final messagesInChat = groupedMessages[chatId] ?? [];
          if (messagesInChat.isEmpty) return const SizedBox.shrink();

          final firstMsg = messagesInChat.first;
          final chatName = _getChatNameForMessage(firstMsg);
          final chatAvatar = _getChatAvatarForMessage(firstMsg);

          return InkWell(
            onTap: () => _openDeletedChatDetailForChatId(chatId, messagesInChat),
            onLongPress: () => _openDeletedChatDetailForChatId(chatId, messagesInChat),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  IosAvatar(
                    name: chatName,
                    imagePath: chatAvatar,
                    size: 48,
                    showOnline: false,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chatName,
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
                          '${messagesInChat.length} deleted ${messagesInChat.length == 1 ? 'message' : 'messages'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.secondaryText(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 18,
                    color: AppTheme.secondaryText(isDark),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen preview of a deleted chat with left/right chat bubbles.
class DeletedChatDetailPage extends StatefulWidget {
  final ServerChatModel chat;
  final List<ServerMessageModel> messages;
  final int retentionDays;
  final VoidCallback onChatRecovered;
  final VoidCallback onChatDeletedPermanently;
  final ValueChanged<int> onMessageRecovered;

  const DeletedChatDetailPage({
    super.key,
    required this.chat,
    required this.messages,
    required this.retentionDays,
    required this.onChatRecovered,
    required this.onChatDeletedPermanently,
    required this.onMessageRecovered,
  });

  @override
  State<DeletedChatDetailPage> createState() => _DeletedChatDetailPageState();
}

class _DeletedChatDetailPageState extends State<DeletedChatDetailPage> {
  late List<ServerMessageModel> _chatMessages;
  bool _isSelectionMode = false;
  final Set<int> _selectedMessageIds = {};

  @override
  void initState() {
    super.initState();
    _chatMessages = List.from(widget.messages);
    _chatMessages.sort((a, b) {
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  bool _isMe(ServerMessageModel msg) {
    final currentUserId = ServerApiService.instance.currentUserId;
    final senderStr = msg.senderId.toString();
    return senderStr == 'user' ||
        senderStr == 'me' ||
        (currentUserId != null && senderStr == '$currentUserId');
  }

  String _getChatName() {
    if (widget.chat.isGroup) {
      return (widget.chat.groupName?.isNotEmpty == true)
          ? widget.chat.groupName!
          : 'Group Chat';
    }
    final currentUserId = ServerApiService.instance.currentUserId;
    final peer = widget.chat.members.firstWhere(
      (m) => m.id != currentUserId,
      orElse: () => widget.chat.members.isNotEmpty
          ? widget.chat.members.first
          : UserModel(id: 0, name: widget.chat.groupName ?? 'Contact'),
    );
    return peer.name.isNotEmpty && !peer.name.startsWith('User #')
        ? peer.name
        : (peer.phone ?? peer.email ?? 'Contact');
  }

  String? _getChatAvatar() {
    if (widget.chat.isGroup) return widget.chat.groupAvatar;
    final currentUserId = ServerApiService.instance.currentUserId;
    final peer = widget.chat.members.firstWhere(
      (m) => m.id != currentUserId,
      orElse: () => widget.chat.members.isNotEmpty
          ? widget.chat.members.first
          : UserModel(id: 0, name: ''),
    );
    return peer.avatar;
  }

  String _getDecryptedMessageText(ServerMessageModel msg) {
    final chatId = msg.chatHeadId;
    final secretKey = 'chat_key_$chatId';

    String content = msg.decryptedContent(secretKey);

    if (content.isEmpty || content.startsWith('ENC:v1:')) {
      final raw = msg.message?.isNotEmpty == true
          ? msg.message!
          : (msg.ciphertext.isNotEmpty ? msg.ciphertext : '');
      if (raw.startsWith('ENC:v1:')) {
        final decrypted = E2eCryptoService.instance.decryptText(raw, secretKey);
        if (!decrypted.startsWith('ENC:v1:') && decrypted.isNotEmpty) {
          content = decrypted;
        }
      } else if (raw.isNotEmpty) {
        content = raw;
      }
    }

    if (content.isEmpty || content.startsWith('ENC:v1:')) {
      if (msg.fileName?.isNotEmpty == true) return msg.fileName!;
      final typeName = msg.msgType?.toLowerCase();
      if (typeName == 'image' || typeName == 'photo') return '📷 Photo';
      if (typeName == 'video') return '📹 Video';
      if (typeName == 'audio' || typeName == 'voice') return '🎵 Voice message';
      if (typeName == 'file' || typeName == 'document') return '📄 Attachment';
      if (typeName == 'call' || msg.callStatus != null || msg.callId != null) {
        final isVideo = (msg.callType ?? '').toLowerCase() == 'video';
        final isMissed = msg.callStatus == 'missed' || msg.callStatus == 'declined' || msg.callStatus == 'rejected';
        return isMissed
            ? (isVideo ? '📹 Missed video call' : '📞 Missed voice call')
            : (isVideo ? '📹 Video call' : '📞 Voice call');
      }
      return 'Encrypted Message';
    }

    return content;
  }

  String _formatMessageTime(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    final hour12 = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = local.minute.toString().padLeft(2, '0');
    return '$hour12:$minuteStr $period';
  }

  void _onMessageLongPress(ServerMessageModel message) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_isSelectionMode) {
        _isSelectionMode = true;
        _selectedMessageIds.add(message.id);
      } else {
        _toggleMessageSelection(message.id);
      }
    });
  }

  void _onMessageTap(ServerMessageModel message) {
    if (_isSelectionMode) {
      HapticFeedback.selectionClick();
      setState(() {
        _toggleMessageSelection(message.id);
      });
    } else {
      _showMessageOptionsSheet(message);
    }
  }

  void _toggleMessageSelection(int messageId) {
    if (_selectedMessageIds.contains(messageId)) {
      _selectedMessageIds.remove(messageId);
      if (_selectedMessageIds.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedMessageIds.add(messageId);
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedMessageIds.length == _chatMessages.length) {
        _selectedMessageIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedMessageIds.clear();
        _selectedMessageIds.addAll(_chatMessages.map((m) => m.id));
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _recoverChat() async {
    final displayName = _getChatName();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CupertinoActivityIndicator(radius: 16)),
    );

    try {
      final success = await ServerApiService.instance.recoverChat(widget.chat.id);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (success) {
        AppToast.show('Chat with $displayName recovered successfully');
        unawaited(ServerChatManager.instance.syncChats());
        widget.onChatRecovered();
        if (mounted) Navigator.of(context).pop();
      } else {
        AppToast.show('Failed to recover chat', isError: true);
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      AppToast.show('Error recovering chat: $e', isError: true);
    }
  }

  Future<void> _recoverSingleMessage(ServerMessageModel message) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CupertinoActivityIndicator(radius: 16)),
    );

    try {
      final success = await ServerApiService.instance.recoverMessage(message.id);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (success) {
        await LocalChatStorage.instance.clearClearedAt(message.chatHeadId.toString());
        setState(() {
          _chatMessages.removeWhere((m) => m.id == message.id);
        });
        widget.onMessageRecovered(message.id);
        AppToast.show('Message recovered successfully');
        unawaited(ServerChatManager.instance.syncChats());
      } else {
        AppToast.show('Failed to recover message', isError: true);
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      AppToast.show('Error recovering message: $e', isError: true);
    }
  }

  Future<void> _recoverSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;
    final idsToRecover = List<int>.from(_selectedMessageIds);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CupertinoActivityIndicator(radius: 16)),
    );

    int successCount = 0;
    try {
      for (final msgId in idsToRecover) {
        final success = await ServerApiService.instance.recoverMessage(msgId);
        if (success) {
          successCount++;
          setState(() {
            _chatMessages.removeWhere((m) => m.id == msgId);
          });
          widget.onMessageRecovered(msgId);
        }
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (successCount > 0) {
        AppToast.show('$successCount ${successCount == 1 ? "message" : "messages"} recovered successfully');
        unawaited(ServerChatManager.instance.syncChats());
      } else {
        AppToast.show('Failed to recover selected message(s)', isError: true);
      }

      if (_chatMessages.isEmpty && mounted) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _isSelectionMode = false;
          _selectedMessageIds.clear();
        });
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      AppToast.show('Error recovering messages: $e', isError: true);
    }
  }

  void _showMessageOptionsSheet(ServerMessageModel message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final msgPreview = _getDecryptedMessageText(message);

    showCupertinoModalPopup(
      context: context,
      builder: (modalContext) => CupertinoActionSheet(
        title: Text(
          msgPreview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryText(isDark),
          ),
        ),
        message: const Text('Choose an action for this deleted message.'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.of(modalContext).pop();
              _recoverSingleMessage(message);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.arrow_counterclockwise, size: 20),
                SizedBox(width: 8),
                Text('Recover Message'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(modalContext).pop();
              setState(() {
                _isSelectionMode = true;
                _selectedMessageIds.add(message.id);
              });
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.checkmark_circle, size: 20),
                SizedBox(width: 8),
                Text('Select Messages'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(modalContext).pop();
              _confirmPermanentDeleteMessage(message);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.trash, size: 20, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Delete Permanently', style: TextStyle(color: Colors.redAccent)),
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

  Future<void> _confirmPermanentDeleteMessage(ServerMessageModel message) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Permanently?'),
        content: const Text(
          'Are you sure you want to permanently delete this message?',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CupertinoActivityIndicator(radius: 16)),
      );

      try {
        final result = await ServerApiService.instance.deleteMessagesPermanently([message.id]);
        if (mounted) Navigator.of(context, rootNavigator: true).pop();

        if (result.success && result.deletedIds.contains(message.id)) {
          setState(() {
            _chatMessages.removeWhere((m) => m.id == message.id);
          });
          widget.onMessageRecovered(message.id);
          AppToast.show('Message permanently deleted');
          if (_chatMessages.isEmpty && mounted) {
            Navigator.of(context).pop();
          }
        } else if (result.errorMessages.isNotEmpty) {
          AppToast.show(result.errorMessages.first, isError: true);
        } else {
          AppToast.show('Failed to delete message permanently', isError: true);
        }
      } catch (e) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        AppToast.show('Error deleting message: $e', isError: true);
      }
    }
  }

  Future<void> _confirmPermanentDeleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;
    final idsToDelete = List<int>.from(_selectedMessageIds);
    final count = idsToDelete.length;

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Delete $count ${count == 1 ? "Message" : "Messages"} Permanently?'),
        content: const Text(
          'Are you sure you want to permanently delete the selected message(s)? This action cannot be undone.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CupertinoActivityIndicator(radius: 16)),
      );

      try {
        final result = await ServerApiService.instance.deleteMessagesPermanently(idsToDelete);
        if (mounted) Navigator.of(context, rootNavigator: true).pop();

        if (result.success && result.deletedIds.isNotEmpty) {
          setState(() {
            _chatMessages.removeWhere((m) => result.deletedIds.contains(m.id));
            _selectedMessageIds.removeAll(result.deletedIds);
            if (_selectedMessageIds.isEmpty) {
              _isSelectionMode = false;
            }
          });
          for (final id in result.deletedIds) {
            widget.onMessageRecovered(id);
          }
          AppToast.show('${result.deletedIds.length} ${result.deletedIds.length == 1 ? "message" : "messages"} permanently deleted');
        }

        if (result.errorMessages.isNotEmpty) {
          AppToast.show(result.errorMessages.first, isError: true);
        } else if (!result.success && result.deletedIds.isEmpty) {
          AppToast.show('Failed to delete message(s) permanently', isError: true);
        }

        if (_chatMessages.isEmpty && mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        AppToast.show('Error deleting message(s): $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatName = _getChatName();
    final chatAvatar = _getChatAvatar();

    return Scaffold(
      backgroundColor: AppTheme.chatCanvas(isDark),
      appBar: AppBar(
        backgroundColor: AppTheme.glassSurface(isDark),
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(
            _isSelectionMode ? CupertinoIcons.xmark : CupertinoIcons.chevron_left,
            color: AppTheme.primaryColor,
          ),
          onPressed: () {
            if (_isSelectionMode) {
              setState(() {
                _isSelectionMode = false;
                _selectedMessageIds.clear();
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: _isSelectionMode
            ? Text(
                '${_selectedMessageIds.length} Selected',
                style: TextStyle(
                  color: AppTheme.primaryText(isDark),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  inherit: true,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IosAvatar(
                    name: chatName,
                    imagePath: chatAvatar,
                    size: 36,
                    showOnline: false,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          chatName,
                          style: TextStyle(
                            color: AppTheme.primaryText(isDark),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            inherit: true,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Deleted Chat Preview',
                          style: TextStyle(
                            color: AppTheme.secondaryText(isDark),
                            fontSize: 11,
                            inherit: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (_isSelectionMode)
            CupertinoButton(
              key: const ValueKey('action_btn_select_all'),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: _toggleSelectAll,
              child: Text(
                _selectedMessageIds.length == _chatMessages.length
                    ? 'Deselect All'
                    : 'Select All',
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  inherit: true,
                ),
              ),
            )
          else
            CupertinoButton(
              key: const ValueKey('action_btn_recover_chat'),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: _recoverChat,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.arrow_counterclockwise,
                    size: 16,
                    color: Color(0xFF34C759),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Recover',
                    style: TextStyle(
                      color: Color(0xFF34C759),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      inherit: true,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Banner Notice
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.orange.withValues(alpha: 0.12),
            child: Row(
              children: [
                const Icon(CupertinoIcons.info, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isSelectionMode
                        ? 'Tap messages to toggle selection for bulk actions.'
                        : 'Tap or hold any message to select single or multiple messages to recover or delete permanently.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryText(isDark),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Left/Right Chat Messages Thread List
          Expanded(
            child: _chatMessages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.chat_bubble_text,
                          size: 48,
                          color: AppTheme.secondaryText(isDark),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No Deleted Messages for this Chat',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondaryText(isDark),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    itemCount: _chatMessages.length,
                    itemBuilder: (context, index) {
                      final msg = _chatMessages[index];
                      return _buildDeletedChatBubble(
                        context: context,
                        message: msg,
                        isDark: isDark,
                      );
                    },
                  ),
          ),

          // Bottom Bar in Selection Mode
          if (_isSelectionMode)
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.of(context).padding.bottom + 10,
              ),
              decoration: BoxDecoration(
                color: AppTheme.glassSurface(isDark),
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _selectedMessageIds.isEmpty
                          ? null
                          : _recoverSelectedMessages,
                      icon: const Icon(CupertinoIcons.arrow_counterclockwise, size: 18),
                      label: Text(
                        'Recover (${_selectedMessageIds.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF34C759),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _selectedMessageIds.isEmpty
                          ? null
                          : _confirmPermanentDeleteSelectedMessages,
                      icon: const Icon(CupertinoIcons.trash, size: 18),
                      label: Text(
                        'Delete (${_selectedMessageIds.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDeletedChatBubble({
    required BuildContext context,
    required ServerMessageModel message,
    required bool isDark,
  }) {
    final isMe = _isMe(message);
    final text = _getDecryptedMessageText(message);
    final dt = DateTime.tryParse(message.createdAt.toString());
    final timeStr = _formatMessageTime(dt);
    final isSelected = _selectedMessageIds.contains(message.id);

    final bubbleColor = isMe
        ? AppTheme.primaryColor
        : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA));

    final textColor = isMe
        ? Colors.white
        : AppTheme.primaryText(isDark);

    final subTextColor = isMe
        ? Colors.white.withValues(alpha: 0.75)
        : AppTheme.secondaryText(isDark);

    final bubbleWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timeStr,
                style: TextStyle(
                  color: subTextColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                CupertinoIcons.trash,
                size: 11,
                color: subTextColor,
              ),
            ],
          ),
        ],
      ),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isMe ? 48 : 12,
          right: isMe ? 12 : 48,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _onMessageTap(message),
            onLongPress: () => _onMessageLongPress(message),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      isSelected
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.secondaryText(isDark),
                      size: 22,
                    ),
                  ),
                Flexible(child: bubbleWidget),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
