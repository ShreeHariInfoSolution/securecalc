import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/core/widgets/typing_dots.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/models/server_models.dart';
import '../../domain/services/e2e_crypto_service.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import '../../domain/services/socket_chat_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_detail_header.dart';
import '../widgets/chat_message_list.dart';
import 'chat_info_page.dart';

class ChatDetailPage extends StatefulWidget {
  final ChatConversation conversation;
  final String? peerIp;

  const ChatDetailPage({super.key, required this.conversation, this.peerIp});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  late List<ChatMessage> _messages;
  late String _chatName;
  late String _chatAvatar;
  bool _isLoadingMessages = true;
  bool _isRefreshingAfterIncoming = false;
  bool _refreshAfterIncomingAgain = false;
  int _historyLoadGeneration = 0;
  final Map<String, ChatMessage> _messagesReceivedWhileLoading = {};
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMorePages = true;
  bool _isLoadingMore = false;
  bool _isSending = false;
  ChatMessage? _editingMessage;
  ChatMessage? _replyingMessage;
  String? _historyError;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<int, String> _groupMemberNames = {};
  bool _showJumpToLatest = false;
  int _newMessagesWhileAway = 0;
  final ValueNotifier<bool> _isPeerTyping = ValueNotifier(false);
  final ValueNotifier<bool> _isPeerOnline = ValueNotifier(false);
  Timer? _peerTypingTimer;
  StreamSubscription<ServerMessageModel>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;
  StreamSubscription<Map<String, dynamic>>? _presenceSubscription;
  StreamSubscription<Map<String, dynamic>>? _readSubscription;
  StreamSubscription<Map<String, dynamic>>? _editedSubscription;
  StreamSubscription<Map<String, dynamic>>? _deletedSubscription;
  StreamSubscription<Map<String, dynamic>>? _reactionSubscription;

  @override
  void initState() {
    super.initState();
    ServerChatManager.instance.activeChatId = widget.conversation.id;
    _chatName = widget.conversation.name;
    _chatAvatar = widget.conversation.avatarUrl;
    _isPeerOnline.value = widget.conversation.isOnline;
    _groupMemberNames.addAll(widget.conversation.memberNames);
    _scrollController.addListener(_handleScrollChanged);
    _messages = List.from(widget.conversation.messages);
    if (widget.conversation.isGroup) unawaited(_loadGroupMemberNames());
    _loadInitialMessages();
    _messageSubscription = SocketChatService.instance.onNewMessage.listen(
      _handleIncomingMessage,
    );
    _typingSubscription = SocketChatService.instance.onTyping.listen(
      _handleTypingEvent,
    );
    _presenceSubscription = SocketChatService.instance.onPresence.listen(
      _handlePresenceEvent,
    );
    _readSubscription = SocketChatService.instance.onRead.listen(
      _handleReadEvent,
    );
    _editedSubscription = SocketChatService.instance.onMessageEdited.listen(
      _handleEditedMessage,
    );
    _deletedSubscription = SocketChatService.instance.onMessageDeleted.listen(
      _handleDeletedMessage,
    );
    _reactionSubscription = SocketChatService.instance.onMessageReaction.listen(
      _handleReactionMessage,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _markChatRead();
      }
    });
  }

  Future<void> _loadGroupMemberNames() async {
    final id = int.tryParse(widget.conversation.id);
    if (id == null) return;
    final details = await ServerApiService.instance.getChatDetails(id);
    if (!mounted || details == null) return;
    setState(() {
      for (final member in details.members) {
        _groupMemberNames[member.id] = member.name;
      }
    });
  }

  void _handleScrollChanged() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.position.pixels > 180;
    if (show != _showJumpToLatest) setState(() => _showJumpToLatest = show);
    if (!show) _newMessagesWhileAway = 0;

    // Trigger pagination when scrolling UP near top of chat history
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 250) {
      if (!_isLoadingMore && _hasMorePages && !_isLoadingMessages) {
        _loadOlderMessages();
      }
    }
  }

  void _beginReply(ChatMessage message) {
    if (int.tryParse(message.id) == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _editingMessage = null;
      _replyingMessage = message;
    });
    _inputFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingMessage = null);
  }

  void _handleIncomingMessage(ServerMessageModel serverMessage) {
    if (!mounted ||
        serverMessage.chatHeadId.toString() != widget.conversation.id) {
      return;
    }
    final wasNearLatest =
        !_scrollController.hasClients ||
        _scrollController.position.pixels < 180;
    final currentUserId = ServerApiService.instance.currentUserId;
    final plaintext = serverMessage.decryptedContent(
      'chat_key_${serverMessage.chatHeadId}',
    );
    DateTime timestamp;
    try {
      timestamp = DateTime.parse(serverMessage.createdAt).toLocal();
    } catch (_) {
      timestamp = DateTime.now();
    }
    final incoming = ChatMessage(
      id: serverMessage.id.toString(),
      senderId: serverMessage.senderId == currentUserId
          ? 'user'
          : serverMessage.senderId.toString(),
      content: serverMessage.isDeleted ? 'This message was deleted' : plaintext,
      timestamp: timestamp,
      type:
          inferAttachmentType(
            fileType: serverMessage.fileType,
            fileName: serverMessage.fileName,
            filePath: serverMessage.filePath,
          ) ??
          (serverMessage.filePath != null
              ? 'application/octet-stream'
              : 'text'),
      mediaUrl: serverMessage.filePath,
      fileName: serverMessage.fileName,
      isRead: true,
      isEdited: serverMessage.isEdited,
      isDeleted: serverMessage.isDeleted,
      reaction: serverMessage.chatReact,
      replyToId: serverMessage.replyToId,
    );
    if (_isLoadingMessages) {
      _messagesReceivedWhileLoading[incoming.id] = incoming;
    }
    if (_messages.any((message) => message.id == incoming.id)) return;
    setState(() {
      _messages = [..._messages, incoming]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (!wasNearLatest && incoming.senderId != 'user') {
        _newMessagesWhileAway++;
      }
    });
    if (incoming.senderId != 'user') {
      unawaited(
        ServerChatManager.instance.markChatRead(widget.conversation.id),
      );
    }
    if (wasNearLatest || incoming.senderId == 'user') _scrollToBottom();
  }

  void _handleTypingEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final event = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;
    final eventChatId = (event['chat_head_id'] ?? event['chat_id'])?.toString();
    if (eventChatId == widget.conversation.id) {
      final eventUserId = int.tryParse(
        (event['user_id'] ?? event['userId'])?.toString() ?? '',
      );
      if (eventUserId != null &&
          eventUserId == ServerApiService.instance.currentUserId) {
        return;
      }
      final rawTyping = event['is_typing'] ?? event['typing'];
      final isTyping =
          rawTyping == true ||
          rawTyping == 1 ||
          rawTyping?.toString().toLowerCase() == 'true';
      _peerTypingTimer?.cancel();
      _isPeerTyping.value = isTyping;
      if (isTyping) {
        _peerTypingTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) _isPeerTyping.value = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _handlePresenceEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : event;
    final peerId = widget.conversation.peerUserId;
    final userId = int.tryParse(
      (data['user_id'] ?? data['userId'] ?? data['id'])?.toString() ?? '',
    );
    if (peerId == null || userId != peerId) return;
    final online = data['is_online'] ?? data['online'] ?? data['status'];
    final isOnline =
        online == true ||
        online == 1 ||
        online?.toString().toLowerCase() == 'online' ||
        online?.toString().toLowerCase() == 'true';
    _isPeerOnline.value = isOnline;
  }

  void _handleReadEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final eventChatId = (data['chat_head_id'] ?? data['chat_id'])?.toString();
    if (eventChatId == widget.conversation.id) {
      setState(() {
        _messages = _messages.map((m) {
          if (m.senderId == 'user') {
            return m.copyWith(isRead: true);
          }
          return m;
        }).toList();
      });
    }
  }

  void _onTypingChanged(bool isTyping) {
    final numericId = int.tryParse(widget.conversation.id);
    if (numericId == null) return;

    SocketChatService.instance.sendTyping(
      chatHeadId: numericId,
      isTyping: isTyping,
    );
  }

  Future<void> _markChatRead() async {
    await ServerChatManager.instance.markChatRead(widget.conversation.id);
  }

  Future<void> _reloadMessages() async {
    final generation = ++_historyLoadGeneration;
    if (mounted) {
      setState(() {
        _isLoadingMessages = true;
        _historyError = null;
      });
    }

    try {
      final res = await ServerChatManager.instance.loadMessagesPage(
        widget.conversation.id,
        page: 1,
        limit: 20,
      );

      if (!mounted || generation != _historyLoadGeneration) return;

      final mergedById = <String, ChatMessage>{
        for (final message in res.messages) message.id: message,
      };
      mergedById.addAll(_messagesReceivedWhileLoading);
      final merged = mergedById.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      setState(() {
        _messages = merged;
        _currentPage = res.page;
        _totalPages = res.totalPages;
        _hasMorePages = res.hasMore;
        _historyError = null;
        _isLoadingMessages = false;
      });
      _messagesReceivedWhileLoading.clear();
      _scrollToBottom();
    } catch (error) {
      debugPrint('[CHAT] Failed to load server history: $error');
      final cached = await LocalChatStorage.instance.loadMessages(
        widget.conversation.id,
      );
      if (mounted && generation == _historyLoadGeneration) {
        setState(() {
          _messages = cached;
          _isLoadingMessages = false;
        });
      }
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingMore || !_hasMorePages) return;

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final res = await ServerChatManager.instance.loadMessagesPage(
        widget.conversation.id,
        page: nextPage,
        limit: 20,
      );

      if (mounted) {
        final existingById = {for (final m in _messages) m.id: m};
        for (final m in res.messages) {
          existingById[m.id] = m;
        }
        final merged = existingById.values.toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        setState(() {
          _messages = merged;
          _currentPage = res.page;
          _totalPages = res.totalPages;
          _hasMorePages = res.hasMore;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('[CHAT] Error loading older messages page ${_currentPage + 1}: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Widget _buildTopLoadingShimmer(bool isDark) {
    return const SizedBox.shrink(); // Moved to chat_message_list.dart
  }

  Future<void> _loadInitialMessages() async {
    final cached = await LocalChatStorage.instance.loadMessages(
      widget.conversation.id,
    );
    if (!mounted) return;
    if (cached.isEmpty) {
      await _reloadMessages();
      return;
    }

    final byId = {for (final message in cached) message.id: message};
    byId.addAll(_messagesReceivedWhileLoading);
    final messages = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    setState(() {
      _messages = messages;
      _isLoadingMessages = false;
      _historyError = null;
    });
    _messagesReceivedWhileLoading.clear();
    _scrollToBottom();
    final historyComplete = await LocalChatStorage.instance.hasCompleteHistory(
      widget.conversation.id,
    );
    if (mounted && !historyComplete) {
      unawaited(_refreshMessagesAfterIncoming());
    }
  }

  Future<void> _refreshMessagesAfterIncoming() async {
    if (_isRefreshingAfterIncoming) {
      _refreshAfterIncomingAgain = true;
      return;
    }
    _isRefreshingAfterIncoming = true;
    do {
      _refreshAfterIncomingAgain = false;
      try {
        final fetched = await ServerChatManager.instance.loadMessages(
          widget.conversation.id,
        );
        if (!mounted) return;
        final byId = {for (final message in _messages) message.id: message};
        for (final message in fetched) {
          byId[message.id] = message;
        }
        final merged = byId.values.toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        setState(() => _messages = merged);
      } catch (error) {
        debugPrint('[CHAT] Could not refresh incoming message: $error');
      }
    } while (_refreshAfterIncomingAgain && mounted);
    _isRefreshingAfterIncoming = false;
  }

  Future<void> _showCachedMessages() async {
    final cached = await LocalChatStorage.instance.loadMessages(
      widget.conversation.id,
    );
    if (!mounted) return;
    final messagesById = <String, ChatMessage>{
      for (final message in _messages) message.id: message,
      for (final message in cached) message.id: message,
    };
    final messages = messagesById.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    setState(() => _messages = messages);
    _scrollToBottom();
  }

  void _handleEditedMessage(Map<String, dynamic> event) {
    var data = event;
    if (event['data'] is Map) {
      data = Map<String, dynamic>.from(event['data'] as Map);
    }
    if (data['message'] is Map) {
      data = Map<String, dynamic>.from(data['message'] as Map);
    }
    final messageId = (data['id'] ?? data['message_id'])?.toString();
    final updatedText = data['message']?.toString();
    if (messageId == null || updatedText == null || !mounted) return;

    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    setState(() {
      _messages[index] = _messages[index].copyWith(
        content: updatedText,
        isEdited: true,
      );
    });
  }

  void _handleDeletedMessage(Map<String, dynamic> event) {
    var data = event;
    if (event['data'] is Map) {
      data = Map<String, dynamic>.from(event['data'] as Map);
    }
    if (data['message'] is Map) {
      data = Map<String, dynamic>.from(data['message'] as Map);
    }
    final messageId = (data['id'] ?? data['message_id'])?.toString();
    if (messageId == null || !mounted) return;
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    setState(() {
      _messages[index] = _messages[index].copyWith(
        content: 'This message was deleted',
        isDeleted: true,
      );
    });
  }

  void _handleReactionMessage(Map<String, dynamic> event) {
    var data = event;
    if (event['data'] is Map) {
      data = Map<String, dynamic>.from(event['data'] as Map);
    }
    if (data['message'] is Map) {
      data = Map<String, dynamic>.from(data['message'] as Map);
    }
    final messageId = (data['id'] ?? data['message_id'])?.toString();
    final reaction = normalizeChatReaction(
      data['chat_react'] ?? data['reaction'],
    );
    if (messageId == null || reaction == null || !mounted) return;
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    setState(() {
      _messages[index] = _messages[index].copyWith(reaction: reaction);
    });
  }

  Future<void> _shareMessage(ChatMessage message) async {
    try {
      final mediaUrl = message.mediaUrl;
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        AppToast.show('Sharing file...');
        final localFilePath = await _downloadOrResolveFile(message);
        if (localFilePath != null && await File(localFilePath).exists()) {
          final xFile = XFile(localFilePath);
          final caption = message.content.isNotEmpty &&
                  message.content != 'Sent a photo' &&
                  message.content != 'Sent an attachment'
              ? message.content
              : null;
          await SharePlus.instance.share(
            ShareParams(files: [xFile], text: caption),
          );
          return;
        }
      }

      if (message.content.isNotEmpty) {
        AppToast.show('Sharing message...');
        await SharePlus.instance.share(
          ShareParams(text: message.content),
        );
      }
    } catch (e) {
      AppToast.show('Could not share message: $e', isError: true);
    }
  }

  Future<String?> _downloadOrResolveFile(ChatMessage message) async {
    final mediaUrl = message.mediaUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) return null;

    final file = File(mediaUrl);
    if (!mediaUrl.startsWith('http://') &&
        !mediaUrl.startsWith('https://') &&
        file.existsSync()) {
      return file.path;
    }

    final documents = await getApplicationDocumentsDirectory();
    final filename = message.fileName?.isNotEmpty == true
        ? message.fileName!
        : (Uri.tryParse(mediaUrl)?.pathSegments.last ?? 'attachment');
    final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final cachedFile = File(
      '${documents.path}${Platform.pathSeparator}chat_attachments${Platform.pathSeparator}${message.timestamp.millisecondsSinceEpoch}_$safeName',
    );

    if (cachedFile.existsSync()) {
      return cachedFile.path;
    }

    try {
      String downloadUrl = mediaUrl;
      if (!downloadUrl.startsWith('http://') && !downloadUrl.startsWith('https://')) {
        String cleanPath = mediaUrl;
        if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(mediaUrl) ||
            RegExp(r'^/(?:data|storage|private|var|tmp|Users)/').hasMatch(mediaUrl)) {
          if (mediaUrl.contains('uploads/')) {
            cleanPath = 'uploads/${mediaUrl.split('uploads/').last}';
          } else if (mediaUrl.contains('files/')) {
            cleanPath = 'files/${mediaUrl.split('files/').last}';
          } else {
            cleanPath = message.fileName?.trim().isNotEmpty == true
                ? message.fileName!
                : mediaUrl.split(RegExp(r'[/\\]')).last;
          }
        }
        final normalized = cleanPath.replaceFirst(RegExp(r'^/+'), '');
        final apiBase = ServerApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
        final filePath = normalized.startsWith('api/files/')
            ? normalized.substring('api/files/'.length)
            : normalized.startsWith('files/')
                ? normalized.substring('files/'.length)
                : normalized;
        final encodedPath = filePath.split('/').map(Uri.encodeComponent).join('/');
        downloadUrl = '$apiBase/files/$encodedPath';
      }

      final headers = ServerApiService.instance.authToken == null
          ? <String, String>{}
          : {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'};

      final response = await http.get(Uri.parse(downloadUrl), headers: headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await cachedFile.parent.create(recursive: true);
        await cachedFile.writeAsBytes(response.bodyBytes, flush: true);
        return cachedFile.path;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _showMessageActions(
    ChatMessage message,
    Offset globalPosition,
  ) async {
    if (message.isDeleted) return;
    final messageId = int.tryParse(message.id);
    final isMine = message.senderId == 'user';
    final screen = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    const menuWidth = 236.0;
    final rows =
        3 + (isMine ? 1 : 0) + (isMine && message.type == 'text' ? 1 : 0);
    final menuHeight = rows * 50.0 + 8;
    final minTop = safePadding.top + 76.0;
    final maxTop = math.max(
      minTop,
      screen.height - menuHeight - safePadding.bottom - 12,
    );
    final left = (globalPosition.dx - menuWidth / 2)
        .clamp(12.0, math.max(12.0, screen.width - menuWidth - 12))
        .toDouble();
    final top = (globalPosition.dy + 20).clamp(minTop, maxTop).toDouble();
    final reactionTop = math.max(safePadding.top + 8, top - 64.0).toDouble();
    final reactionWidth = math.min(screen.width - 24, 360.0).toDouble();
    final reactionLeft = (globalPosition.dx - reactionWidth / 2)
        .clamp(12.0, math.max(12.0, screen.width - reactionWidth - 12))
        .toDouble();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Message actions',
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogContext, animation1, animation2) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final menuColor = isDark ? AppTheme.darkSurface : Colors.white;
        final primaryText = isDark ? Colors.white : Colors.black87;
        final emojiItems = ['👍', '❤️', '😂', '😮', '😢', '🙏', '👻'];

        Widget actionRow({
          required IconData icon,
          required String label,
          required VoidCallback onTap,
          Color? color,
        }) => InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 50,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: color ?? primaryText),
                  const SizedBox(width: 14),
                  Text(
                    label,
                    style: TextStyle(
                      color: color ?? primaryText,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        return Stack(
          children: [
            Positioned(
              left: reactionLeft,
              top: reactionTop,
              width: reactionWidth,
              child: Material(
                color: menuColor,
                elevation: 14,
                borderRadius: BorderRadius.circular(30),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...emojiItems.map(
                        (emoji) => IconButton(
                          tooltip: emoji,
                          constraints: const BoxConstraints(
                            minWidth: 42,
                            minHeight: 54,
                          ),
                          onPressed: messageId == null
                              ? null
                              : () {
                                  Navigator.pop(dialogContext);
                                  _reactToMessage(message, emoji);
                                },
                          icon: Text(
                            emoji,
                            style: const TextStyle(fontSize: 25),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'More reactions',
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _showMoreReactions(message);
                        },
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 28,
                          color: AppTheme.subtitleGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: Material(
                color: menuColor,
                elevation: 16,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    actionRow(
                      icon: Icons.copy_rounded,
                      label: 'Copy',
                      onTap: () {
                        Navigator.pop(dialogContext);
                        Clipboard.setData(ClipboardData(text: message.content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Message copied')),
                        );
                      },
                    ),
                    actionRow(
                      icon: Icons.info_outline_rounded,
                      label: 'Info',
                      onTap: () {
                        Navigator.pop(dialogContext);
                        _showMessageInfo(message);
                      },
                    ),
                    actionRow(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      onTap: () {
                        Navigator.pop(dialogContext);
                        _shareMessage(message);
                      },
                    ),
                    if (isMine && messageId != null && message.type == 'text')
                      actionRow(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _beginEditingMessage(message);
                        },
                      ),
                    if (isMine && messageId != null)
                      actionRow(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        color: Colors.red,
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _deleteMessage(message);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMoreReactions(ChatMessage message) async {
    const emojis = [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🙂',
      '😊',
      '😍',
      '🥰',
      '😘',
      '😎',
      '🤔',
      '😮',
      '😢',
      '😭',
      '😡',
      '👍',
      '👎',
      '👏',
      '🙌',
      '🙏',
      '❤️',
      '🔥',
      '🎉',
      '💯',
      '👻',
      '🤝',
      '💪',
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 310,
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: emojis.length,
            itemBuilder: (context, index) => InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.pop(sheetContext);
                _reactToMessage(message, emojis[index]);
              },
              child: Center(
                child: Text(
                  emojis[index],
                  style: const TextStyle(fontSize: 27),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMessageInfo(ChatMessage message) async {
    final isMine = message.senderId == 'user';
    final created = message.timestamp.toLocal();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Message info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isMine ? 'Sent by you' : 'Sent by $_chatName'),
            const SizedBox(height: 8),
            Text(
              '${created.day}/${created.month}/${created.year}  '
              '${created.hour > 12 ? created.hour - 12 : (created.hour == 0 ? 12 : created.hour)}:'
              '${created.minute.toString().padLeft(2, '0')} '
              '${created.hour >= 12 ? 'PM' : 'AM'}',
            ),
            if (message.isEdited) ...[
              const SizedBox(height: 8),
              const Text('Edited'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _reactToMessage(ChatMessage message, String emoji) async {
    final messageId = int.tryParse(message.id);
    if (messageId == null) return;
    final saved = await ServerApiService.instance.reactMessageREST(
      messageId: messageId,
      chatReact: emoji,
    );
    if (!saved) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reaction could not be saved.')),
        );
      }
      return;
    }
    final updated = message.copyWith(reaction: emoji);
    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((item) => item.id == message.id);
        if (index >= 0) _messages[index] = updated;
      });
    }
    await LocalChatStorage.instance.saveMessage(
      deviceId: widget.conversation.id,
      peerName: _chatName,
      message: updated,
      markUnread: false,
      peerUserId: widget.conversation.peerUserId,
    );
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messageId = int.tryParse(message.id);
    if (messageId == null) return;
    final deleted = await ServerApiService.instance.deleteMessageREST(
      messageId,
    );
    if (!deleted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message could not be deleted.')),
        );
      }
      return;
    }
    final updated = message.copyWith(
      content: 'This message was deleted',
      isDeleted: true,
    );
    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((item) => item.id == message.id);
        if (index >= 0) _messages[index] = updated;
        if (_editingMessage?.id == message.id) _editingMessage = null;
      });
    }
    await LocalChatStorage.instance.saveMessage(
      deviceId: widget.conversation.id,
      peerName: _chatName,
      message: updated,
      markUnread: false,
      peerUserId: widget.conversation.peerUserId,
    );
  }

  void _beginEditingMessage(ChatMessage message) {
    setState(() {
      _editingMessage = message;
      _replyingMessage = null;
      _inputController.text = message.content;
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
    });
    _inputFocusNode.requestFocus();
  }

  void _cancelEditingMessage() {
    setState(() {
      _editingMessage = null;
      _inputController.clear();
    });
  }

  Future<void> _saveEditedMessage() async {
    final message = _editingMessage;
    if (message == null || _isSending) return;
    final messageId = int.tryParse(message.id);
    if (messageId == null) return;
    final text = _inputController.text.trim();
    if (text.isEmpty || text == message.content) {
      _cancelEditingMessage();
      return;
    }

    setState(() => _isSending = true);
    final encryptedText = E2eCryptoService.instance.encryptText(
      text,
      'chat_key_${widget.conversation.id}',
    );
    final saved = await ServerApiService.instance.editMessageREST(
      messageId: messageId,
      message: encryptedText,
    );
    if (!mounted) return;
    setState(() => _isSending = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message could not be edited.')),
      );
      return;
    }

    final updated = message.copyWith(content: text, isEdited: true);
    setState(() {
      final index = _messages.indexWhere((item) => item.id == message.id);
      if (index >= 0) _messages[index] = updated;
      _editingMessage = null;
      _inputController.clear();
    });
    await LocalChatStorage.instance.saveMessage(
      deviceId: widget.conversation.id,
      peerName: _chatName,
      message: updated,
      markUnread: false,
    );
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  Widget _buildEmptyHistory(bool isDark) {
    return const SizedBox.shrink(); // Moved to chat_message_list.dart
  }

  Future<void> _sendMessage() async {
    if (_editingMessage != null) {
      await _saveEditedMessage();
      return;
    }
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    final localMsgId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMsg = ChatMessage(
      id: localMsgId,
      senderId: 'user',
      content: text,
      timestamp: DateTime.now(),
      type: 'text',
      isRead: false,
      replyToId: _replyingMessage == null
          ? null
          : int.tryParse(_replyingMessage!.id),
    );
    final replyToId = _replyingMessage == null
        ? null
        : int.tryParse(_replyingMessage!.id);

    _inputController.clear();
    setState(() {
      _messages = [..._messages, optimisticMsg];
      _isSending = true;
    });
    _scrollToBottom();

    // Reset typing indicator
    final numericId = int.tryParse(widget.conversation.id);
    if (numericId != null) {
      SocketChatService.instance.sendTyping(
        chatHeadId: numericId,
        isTyping: false,
      );
    }

    try {
      final sent = await ServerChatManager.instance.sendMessage(
        chatId: widget.conversation.id,
        peerName: _chatName,
        text: text,
        peerUserId: widget.conversation.peerUserId,
        replyToId: replyToId,
      );
      if (!sent) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message could not be sent. Please try again.'),
            ),
          );
          setState(() {
            _messages = _messages.where((m) => m.id != localMsgId).toList();
            _inputController.text = text;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _messages = _messages.where((m) => m.id != localMsgId).toList();
          _replyingMessage = null;
        });
      }
      await _showCachedMessages();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _uploadAndSendAttachment({
    required File file,
    required String fileName,
    required String fileType,
  }) async {
    if (_isSending) return;
    if (mounted) setState(() => _isSending = true);
    try {
      final secretKey = 'chat_key_${widget.conversation.id}';

      // 1. Encrypt file bytes before uploading to server
      final rawBytes = await file.readAsBytes();
      final encryptedBytes = E2eCryptoService.instance.encryptFileBytes(
        rawBytes,
        secretKey,
      );

      final tempDir = await getTemporaryDirectory();
      final tempEncFile = File(
        '${tempDir.path}${Platform.pathSeparator}enc_upload_${DateTime.now().millisecondsSinceEpoch}.tmp',
      );
      await tempEncFile.writeAsBytes(encryptedBytes, flush: true);

      // 2. Upload encrypted file to server
      final uploadedPath = await ServerApiService.instance.uploadFile(
        tempEncFile,
        filename: fileName,
      );
      try {
        await tempEncFile.delete();
      } catch (_) {}

      if (uploadedPath == null || uploadedPath.isEmpty) {
        throw Exception('The file could not be uploaded. Please try again.');
      }

      // 3. Save unencrypted original file copy in local chat_attachments
      // under standardized key so sender's device already has the local file!
      final documents = await getApplicationDocumentsDirectory();
      final attachmentDirectory = Directory(
        '${documents.path}${Platform.pathSeparator}chat_attachments',
      );
      await attachmentDirectory.create(recursive: true);
      final mediaKey = uploadedPath
          .split('/')
          .last
          .split('\\')
          .last
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final localCopyPath =
          '${attachmentDirectory.path}${Platform.pathSeparator}${mediaKey}_$safeName';
      final localCopy = File(localCopyPath);
      await file.copy(localCopy.path);

      final sent = await ServerChatManager.instance.sendMessage(
        chatId: widget.conversation.id,
        peerName: _chatName,
        text: fileType.startsWith('image/')
            ? 'Photo'
            : fileType.startsWith('video/')
            ? 'Video'
            : fileType.startsWith('audio/')
            ? 'Voice message'
            : fileName,
        filePath: uploadedPath,
        fileName: fileName,
        fileType: fileType,
        peerUserId: widget.conversation.peerUserId,
        replyToId: _replyingMessage == null
            ? null
            : int.tryParse(_replyingMessage!.id),
      );
      if (!sent) throw Exception('The file message could not be sent.');
      if (mounted) setState(() => _replyingMessage = null);
      await _showCachedMessages();
    } catch (error) {
      debugPrint('[ATTACHMENT SEND ERROR] $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to send attachment: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openChatInfo() async {
    final cleared = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatInfoPage(conversation: widget.conversation),
      ),
    );
    if (cleared == true && mounted) {
      setState(() {
        _historyLoadGeneration++;
        _isLoadingMessages = false;
        _historyError = null;
        _messages.clear();
        _messagesReceivedWhileLoading.clear();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Chat cleared.')));
    }
  }

  void _jumpToLatest() {
    _newMessagesWhileAway = 0;
    _scrollToBottom();
  }

  @override
  void dispose() {
    if (ServerChatManager.instance.activeChatId == widget.conversation.id) {
      ServerChatManager.instance.activeChatId = null;
    }
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _presenceSubscription?.cancel();
    _readSubscription?.cancel();
    _editedSubscription?.cancel();
    _deletedSubscription?.cancel();
    _reactionSubscription?.cancel();
    _peerTypingTimer?.cancel();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _isPeerOnline.dispose();
    _isPeerTyping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor: isDark
            ? AppTheme.darkBackground
            : AppTheme.lightBackground,
        body: SafeArea(
          child: Column(
            children: [
              ChatDetailHeader(
                conversation: widget.conversation,
                chatName: _chatName,
                chatAvatar: _chatAvatar,
                isPeerOnline: _isPeerOnline,
                isPeerTyping: _isPeerTyping,
                onOpenChatInfo: _openChatInfo,
              ),

              // Messages List
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isPeerTyping,
                  builder: (context, isTyping, _) {
                    return ChatMessageList(
                      messages: _messages,
                      isLoadingMessages: _isLoadingMessages,
                      isLoadingMore: _isLoadingMore,
                      isPeerTyping: isTyping,
                      showJumpToLatest: _showJumpToLatest,
                      newMessagesWhileAway: _newMessagesWhileAway,
                      historyError: _historyError,
                      scrollController: _scrollController,
                      conversation: widget.conversation,
                      groupMemberNames: _groupMemberNames,
                      chatName: _chatName,
                      chatAvatar: _chatAvatar,
                      onShowMessageActions: _showMessageActions,
                      onBeginReply: _beginReply,
                      onJumpToLatest: _jumpToLatest,
                      onReloadMessages: _reloadMessages,
                    );
                  }
                ),
              ),

              // Bottom Input Bar
              ChatComposer(
                inputController: _inputController,
                inputFocusNode: _inputFocusNode,
                editingMessage: _editingMessage,
                replyingMessage: _replyingMessage,
                conversation: widget.conversation,
                chatName: _chatName,
                groupMemberNames: _groupMemberNames,
                isSending: _isSending,
                onCancelEditing: _cancelEditingMessage,
                onCancelReply: _cancelReply,
                onTypingChanged: _onTypingChanged,
                onSendText: _sendMessage,
                onSendAttachment: _uploadAndSendAttachment,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
