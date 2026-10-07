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
  bool _isSending = false;
  ChatMessage? _editingMessage;
  ChatMessage? _replyingMessage;
  double _horizontalDragDistance = 0;
  String? _historyError;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<int, String> _groupMemberNames = {};
  bool _showJumpToLatest = false;
  int _newMessagesWhileAway = 0;
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isPeerTyping = false;
  bool _isPeerOnline = false;
  bool _isRecordingVoice = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _typingDebounce;
  Timer? _peerTypingTimer;
  Timer? _recordingTimer;
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
    _isPeerOnline = widget.conversation.isOnline;
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
      setState(() {
        _isPeerTyping = isTyping;
      });
      if (isTyping) {
        _peerTypingTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _isPeerTyping = false);
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
    setState(() => _isPeerOnline = isOnline);
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

  void _onInputChanged(String val) {
    setState(() {});
    final numericId = int.tryParse(widget.conversation.id);
    if (numericId == null) return;

    if (_typingDebounce?.isActive ?? false) _typingDebounce!.cancel();
    if (val.trim().isNotEmpty) {
      SocketChatService.instance.sendTyping(
        chatHeadId: numericId,
        isTyping: true,
      );
      _typingDebounce = Timer(const Duration(seconds: 3), () {
        SocketChatService.instance.sendTyping(
          chatHeadId: numericId,
          isTyping: false,
        );
      });
    } else {
      SocketChatService.instance.sendTyping(
        chatHeadId: numericId,
        isTyping: false,
      );
    }
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

    var loaded = <ChatMessage>[];
    String? loadError;
    var serverHistoryFailed = false;
    try {
      loaded = await ServerChatManager.instance.loadMessages(
        widget.conversation.id,
      );
    } catch (error) {
      debugPrint('[CHAT] Failed to load server history: $error');
      serverHistoryFailed = true;
      loadError =
          'Could not load chat history. Check your connection and retry.';
    }
    if (serverHistoryFailed) {
      final cached = await LocalChatStorage.instance.loadMessages(
        widget.conversation.id,
      );
      loaded = cached;
    }
    if (!mounted || generation != _historyLoadGeneration) return;
    if (mounted) {
      final mergedById = <String, ChatMessage>{
        for (final message in loaded) message.id: message,
      };
      // Keep realtime events that arrived after the history request began.
      // This prevents the response from overwriting a newly received message.
      mergedById.addAll(_messagesReceivedWhileLoading);
      final merged = mergedById.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      setState(() {
        _messages = merged;
        _historyError = merged.isEmpty ? loadError : null;
        _isLoadingMessages = false;
      });
      _messagesReceivedWhileLoading.clear();
      _scrollToBottom();
    }
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
    final error = _historyError;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error == null
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.cloud_off_rounded,
              size: 42,
              color: AppTheme.subtitleGrey,
            ),
            const SizedBox(height: 12),
            Text(
              error ?? 'No messages yet. Start the conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : AppTheme.subtitleGrey,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _reloadMessages,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
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

  String _attachmentType(String fileName) =>
      inferAttachmentType(fileName: fileName) ?? 'application/octet-stream';

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

  Future<void> _pickAndSendImage(ImageSource source) async {
    AppPreferences.isPickerActive = true;
    try {
      if (source == ImageSource.camera &&
          !(await Permission.camera.request()).isGranted) {
        throw Exception('Camera permission is required.');
      }
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      await _uploadAndSendAttachment(
        file: File(picked.path),
        fileName: picked.name,
        fileType: _attachmentType(picked.name),
      );
    } catch (error) {
      debugPrint('[IMAGE PICK ERROR] $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to pick image: $error')));
      }
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _pickAndSendVideo() async {
    AppPreferences.isPickerActive = true;
    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      await _uploadAndSendAttachment(
        file: File(picked.path),
        fileName: picked.name,
        fileType: _attachmentType(picked.name),
      );
    } catch (error) {
      debugPrint('[VIDEO PICK ERROR] $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to pick video: $error')));
      }
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _pickAndSendFile() async {
    AppPreferences.isPickerActive = true;
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final picked = files.first;
      var path = picked.path;
      if (path == null || path.isEmpty) {
        final temporaryDirectory = await getTemporaryDirectory();
        final safeName = picked.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        path =
            '${temporaryDirectory.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
        await File(path).writeAsBytes(await picked.readAsBytes(), flush: true);
      }
      await _uploadAndSendAttachment(
        file: File(path),
        fileName: picked.name,
        fileType: _attachmentType(picked.name),
      );
    } catch (error) {
      debugPrint('[FILE PICK ERROR] $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to attach file: $error')),
        );
      }
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isSending) return;
    if (_isRecordingVoice) {
      await _finishVoiceRecording(send: true);
      return;
    }
    try {
      if (!await _audioRecorder.hasPermission()) {
        throw Exception('Microphone permission is required.');
      }
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = true;
        _recordingDuration = Duration.zero;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordingDuration += const Duration(seconds: 1));
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to start recording: $error')),
        );
      }
    }
  }

  Future<void> _finishVoiceRecording({required bool send}) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final path = await _audioRecorder.stop();
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingDuration = Duration.zero;
      });
    }
    if (!send || path == null || path.isEmpty) return;
    await _uploadAndSendAttachment(
      file: File(path),
      fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      fileType: 'audio/mp4',
    );
  }

  Future<void> _cancelVoiceRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _audioRecorder.cancel();
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingDuration = Duration.zero;
      });
    }
  }

  String _formatRecordingDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
    _typingDebounce?.cancel();
    _peerTypingTimer?.cancel();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final messagesById = {for (final message in _messages) message.id: message};

    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor: isDark
            ? AppTheme.darkBackground
            : AppTheme.lightBackground,
        body: SafeArea(
          child: Column(
            children: [
              // iOS Glassmorphic Frosted Header Bar
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1C1C1E).withValues(alpha: 0.82)
                          : Colors.white.withValues(alpha: 0.85),
                      border: Border(
                        bottom: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: ValueListenableBuilder<List<ChatConversation>>(
                      valueListenable: LocalChatStorage.instance.conversationsNotifier,
                      builder: (context, conversations, _) {
                        final unreadTotal = conversations.fold<int>(
                          0,
                          (sum, c) => sum + c.unreadCount,
                        );

                        return Row(
                          children: [
                            // Glassmorphic Back Button Pill with Dynamic Unread Count
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.pop(context);
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: unreadTotal > 0 ? 12 : 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2C2C2E).withValues(alpha: 0.85)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.18)
                                        : Colors.black.withValues(alpha: 0.08),
                                    width: 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: isDark ? 0.3 : 0.06,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      size: 18,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                    if (unreadTotal > 0) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '$unreadTotal',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : Colors.black87,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Profile Avatar & Contact Name Row
                            Expanded(
                              child: InkWell(
                                onTap: _openChatInfo,
                                borderRadius: BorderRadius.circular(16),
                                child: Row(
                                  children: [
                                    IosAvatar(
                                      name: _chatName,
                                      imagePath: _chatAvatar,
                                      isOnline: _isPeerOnline,
                                      size: 38,
                                      showOnline: true,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _chatName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : Colors.black87,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          Text(
                                            _isPeerTyping
                                                ? 'typing…'
                                                : _isPeerOnline
                                                ? 'online'
                                                : 'Tap for info',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _isPeerTyping || _isPeerOnline
                                                  ? AppTheme.primaryColor
                                                  : AppTheme.subtitleGrey,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Right Detail Glass Icon Button
                            GestureDetector(
                              onTap: _openChatInfo,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2C2C2E).withValues(alpha: 0.85)
                                      : Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.18)
                                        : Colors.black.withValues(alpha: 0.08),
                                    width: 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: isDark ? 0.3 : 0.06,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.info_outline_rounded,
                                  size: 20,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Messages List
              Expanded(
                child: _isLoadingMessages && _messages.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                    ? _buildEmptyHistory(isDark)
                    : Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            itemCount:
                                _messages.length + (_isPeerTyping ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_isPeerTyping && index == 0) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      IosAvatar(
                                        name: _chatName,
                                        imagePath: _chatAvatar,
                                        size: 28,
                                        showOnline: false,
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? AppTheme.darkBubbleOther
                                              : AppTheme.lightBubbleOther,
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: const TypingDots(
                                          color: AppTheme.subtitleGrey,
                                          dotSize: 5,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final messageIndex =
                                  _messages.length -
                                  1 -
                                  (index - (_isPeerTyping ? 1 : 0));
                              final msg = _messages[messageIndex];
                              final showDateHeader =
                                  messageIndex == 0 ||
                                  !_sameDay(
                                    _messages[messageIndex - 1].timestamp,
                                    msg.timestamp,
                                  );
                              final previousSender = messageIndex > 0
                                  ? _messages[messageIndex - 1].senderId
                                  : null;
                              final showGroupSender =
                                  widget.conversation.isGroup &&
                                  msg.senderId != previousSender;
                              final senderId = msg.senderId == 'user'
                                  ? ServerApiService.instance.currentUserId
                                  : int.tryParse(msg.senderId);
                              final repliedMessage = msg.replyToId == null
                                  ? null
                                  : messagesById[msg.replyToId.toString()];

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (showDateHeader)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.08,
                                                  )
                                                : Colors.black.withValues(
                                                    alpha: 0.055,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Text(
                                            _dateLabel(msg.timestamp),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.subtitleGrey,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  GestureDetector(
                                    onLongPressStart:
                                        int.tryParse(msg.id) != null
                                        ? (details) => _showMessageActions(
                                            msg,
                                            details.globalPosition,
                                          )
                                        : null,
                                    onHorizontalDragStart: (_) {
                                      _horizontalDragDistance = 0;
                                    },
                                    onHorizontalDragUpdate: (details) {
                                      _horizontalDragDistance +=
                                          details.delta.dx;
                                    },
                                    onHorizontalDragEnd: (_) {
                                      if (_horizontalDragDistance.abs() > 42) {
                                        _beginReply(msg);
                                      }
                                      _horizontalDragDistance = 0;
                                    },
                                    child: ChatBubble(
                                      key: ValueKey(msg.id),
                                      chatId: widget.conversation.id,
                                      message: msg.content,
                                      isMe: msg.senderId == 'user',
                                      timestamp: msg.timestamp,
                                      type: msg.type,
                                      mediaUrl: msg.mediaUrl,
                                      fileName: msg.fileName,
                                      isRead: msg.isRead,
                                      isEdited: msg.isEdited,
                                      isDeleted: msg.isDeleted,
                                      senderName:
                                          showGroupSender && senderId != null
                                          ? _groupMemberNames[senderId] ??
                                                'Member'
                                          : null,
                                      replySender: repliedMessage == null
                                          ? null
                                          : repliedMessage.senderId == 'user'
                                          ? 'You'
                                          : widget.conversation.isGroup
                                          ? _groupMemberNames[int.tryParse(
                                                  repliedMessage.senderId,
                                                )] ??
                                                'Member'
                                          : _chatName,
                                      replyText: repliedMessage?.previewText,
                                      reactions: msg.reaction == null
                                          ? null
                                          : [msg.reaction!],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          if (_showJumpToLatest)
                            Positioned(
                              right: 14,
                              bottom: 18,
                              child: Material(
                                color: isDark
                                    ? AppTheme.darkSurface
                                    : Colors.white,
                                elevation: 4,
                                shape: const CircleBorder(),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    IconButton(
                                      onPressed: _jumpToLatest,
                                      tooltip: 'Jump to latest',
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                      ),
                                      color: AppTheme.primaryColor,
                                    ),
                                    if (_newMessagesWhileAway > 0)
                                      Positioned(
                                        right: -2,
                                        top: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: AppTheme.primaryColor,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            '$_newMessagesWhileAway',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),

              // Bottom Input Bar
              if (_editingMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
                  color: isDark ? AppTheme.darkSurface : Colors.white,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Editing message',
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: _cancelEditingMessage,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Cancel edit',
                      ),
                    ],
                  ),
                ),
              if (_replyingMessage != null)
                Container(
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
                              _replyingMessage!.senderId == 'user'
                                  ? 'Replying to You'
                                  : widget.conversation.isGroup
                                  ? _groupMemberNames[int.tryParse(
                                          _replyingMessage!.senderId,
                                        )] ??
                                        'Replying to member'
                                  : 'Replying to $_chatName',
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
                              _replyingMessage!.previewText,
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
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: _cancelReply,
                        tooltip: 'Cancel reply',
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.darkBackground
                      : AppTheme.lightSurface,
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Attachment '+' Plus Button
                    GestureDetector(
                      onTap: () => _showAttachmentOptions(context),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFF2F2F7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          size: 20,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Input Text Pill Field
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            if (_isRecordingVoice)
                              Expanded(
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.fiber_manual_record_rounded,
                                      color: Colors.redAccent,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatRecordingDuration(
                                        _recordingDuration,
                                      ),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'Recording voice message…',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppTheme.subtitleGrey,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      onPressed: _cancelVoiceRecording,
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: AppTheme.subtitleGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              Expanded(
                                child: TextField(
                                  controller: _inputController,
                                  focusNode: _inputFocusNode,
                                  onChanged: _onInputChanged,
                                  decoration: InputDecoration(
                                    hintText: _editingMessage == null
                                        ? 'iMessage'
                                        : 'Edit message',
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    hintStyle: const TextStyle(
                                      color: AppTheme.subtitleGrey,
                                      fontSize: 15,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    _pickAndSendImage(ImageSource.camera),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 18,
                                  color: AppTheme.subtitleGrey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Send / Mic Circle Button
                    GestureDetector(
                      onTap: _isSending
                          ? null
                          : (_editingMessage != null ||
                                    _inputController.text.trim().isNotEmpty
                                ? _sendMessage
                                : _toggleVoiceRecording),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color:
                              _editingMessage != null ||
                                  _isRecordingVoice ||
                                  _inputController.text.trim().isNotEmpty
                              ? AppTheme.primaryColor
                              : (isDark
                                    ? const Color(0xFF2C2C2E)
                                    : const Color(0xFFF2F2F7)),
                          shape: BoxShape.circle,
                          boxShadow:
                              _editingMessage != null ||
                                  _isRecordingVoice ||
                                  _inputController.text.trim().isNotEmpty
                              ? [
                                  BoxShadow(
                                    color: AppTheme.primaryColor.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: _isSending
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _editingMessage != null
                                    ? Icons.check_rounded
                                    : _inputController.text.trim().isNotEmpty
                                    ? Icons.arrow_upward_rounded
                                    : _isRecordingVoice
                                    ? Icons.send_rounded
                                    : Icons.mic_rounded,
                                size: 18,
                                color:
                                    _editingMessage != null ||
                                        _isRecordingVoice ||
                                        _inputController.text.trim().isNotEmpty
                                    ? Colors.white
                                    : AppTheme.primaryColor,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAttachmentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildOptionItem(
                  Icons.image_rounded,
                  'Photo',
                  Colors.purple,
                  () {
                    Navigator.pop(context);
                    _pickAndSendImage(ImageSource.gallery);
                  },
                ),
                _buildOptionItem(
                  Icons.camera_alt_rounded,
                  'Camera',
                  Colors.blue,
                  () {
                    Navigator.pop(context);
                    _pickAndSendImage(ImageSource.camera);
                  },
                ),
                _buildOptionItem(
                  Icons.videocam_rounded,
                  'Video',
                  Colors.teal,
                  () {
                    Navigator.pop(context);
                    _pickAndSendVideo();
                  },
                ),
                _buildOptionItem(
                  Icons.insert_drive_file_rounded,
                  'File',
                  Colors.orange,
                  () {
                    Navigator.pop(context);
                    _pickAndSendFile();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionItem(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
