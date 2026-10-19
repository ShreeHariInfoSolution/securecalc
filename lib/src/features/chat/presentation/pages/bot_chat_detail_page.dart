import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/vault_page_route.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/bot_assistant_service.dart';
import '../../domain/services/local_chat_storage.dart';
import '../widgets/chat_wallpaper_widget.dart';

class BotChatDetailPage extends StatefulWidget {
  final ChatConversation conversation;

  const BotChatDetailPage({
    super.key,
    required this.conversation,
  });

  static Future<void> open(
    BuildContext context, {
    required ChatConversation conversation,
  }) {
    return Navigator.of(context).push(
      VaultPageRoute<void>(
        builder: (context) => BotChatDetailPage(conversation: conversation),
      ),
    );
  }

  @override
  State<BotChatDetailPage> createState() => _BotChatDetailPageState();
}

class _BotChatDetailPageState extends State<BotChatDetailPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  bool _isBotTyping = false;

  @override
  void initState() {
    super.initState();
    _messages = List<ChatMessage>.from(widget.conversation.messages);
    _loadStoredMessages();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadStoredMessages() async {
    final loaded = await LocalChatStorage.instance.loadMessages(
      BotAssistantService.botId,
    );
    if (loaded.isNotEmpty) {
      if (mounted) {
        setState(() {
          _messages = loaded;
        });
      }
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _handleUserSend(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    _inputController.clear();

    final userMessage = ChatMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'user',
      content: query,
      timestamp: DateTime.now(),
      isRead: true,
      isDelivered: true,
    );

    setState(() {
      _messages.add(userMessage);
      _isBotTyping = true;
    });

    _scrollToBottom();

    await LocalChatStorage.instance.saveMessage(
      deviceId: BotAssistantService.botId,
      peerName: BotAssistantService.botName,
      message: userMessage,
      markUnread: false,
    );

    // Simulate natural AI thinking delay
    await Future.delayed(const Duration(milliseconds: 650));

    final botAnswer = BotAssistantService.instance.getBotResponse(query);

    final botMessage = ChatMessage(
      id: 'bot_${DateTime.now().millisecondsSinceEpoch}',
      senderId: BotAssistantService.botId,
      content: botAnswer,
      timestamp: DateTime.now(),
      isRead: true,
      isDelivered: true,
    );

    if (mounted) {
      setState(() {
        _messages.add(botMessage);
        _isBotTyping = false;
      });
      _scrollToBottom();
    }

    await LocalChatStorage.instance.saveMessage(
      deviceId: BotAssistantService.botId,
      peerName: BotAssistantService.botName,
      message: botMessage,
      markUnread: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? AppTheme.darkBackground
        : const Color(0xFFF6F5F0);
    final cardSurface = isDark
        ? const Color(0xFF2C2C2E)
        : Colors.white;
    final userBubbleColor = isDark
        ? const Color(0xFF1E3A2B)
        : const Color(0xFFDCF8C6);
    final botBubbleColor = isDark
        ? const Color(0xFF1C1C1E)
        : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: isDark
            ? AppTheme.darkBackground.withValues(alpha: 0.95)
            : const Color(0xFFF6F5F0).withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        leadingWidth: 70,
        leading: Row(
          children: [
            const SizedBox(width: 8),
            Material(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                ),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.3),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: const Icon(
                CupertinoIcons.sparkles,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        BotAssistantService.botName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryText(isDark),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'AI BOT',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Online • Instant Support',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.secondaryText(isDark),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Background Wallpaper
          ChatWallpaperWidget(
            chatId: BotAssistantService.botId,
            isDark: isDark,
          ),

          // Main Column: Messages + Suggested Chips + Input Composer
          Column(
            children: [
              // Messages List
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  itemCount: _messages.length + (_isBotTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length && _isBotTyping) {
                      return _buildBotTypingBubble(isDark, botBubbleColor);
                    }

                    final msg = _messages[index];
                    final isUser = msg.senderId == 'user';

                    return _buildMessageBubble(
                      context: context,
                      msg: msg,
                      isUser: isUser,
                      isDark: isDark,
                      userBubbleColor: userBubbleColor,
                      botBubbleColor: botBubbleColor,
                    );
                  },
                ),
              ),

              // Suggested Question Chips Bar
              _buildSuggestedChipsBar(isDark, cardSurface),

              // Bottom Input Composer Bar
              _buildInputComposer(isDark, cardSurface),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestedChipsBar(bool isDark, Color cardSurface) {
    return Container(
      width: double.infinity,
      color: isDark
          ? Colors.black.withValues(alpha: 0.4)
          : Colors.white.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.lightbulb_fill,
                  size: 13,
                  color: Color(0xFFFFCC00),
                ),
                const SizedBox(width: 5),
                Text(
                  'Suggested Questions',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppTheme.secondaryText(isDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: BotAssistantService.suggestedQuestions.length,
              itemBuilder: (context, index) {
                final item = BotAssistantService.suggestedQuestions[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: isDark
                        ? const Color(0xFF2C2C2E)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(17),
                      onTap: () => _handleUserSend(item.question),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : const Color(0xFF007AFF).withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          item.shortChipText,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF007AFF),
                          ),
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

  Widget _buildInputComposer(bool isDark, Color cardSurface) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.primaryText(isDark),
                ),
                decoration: InputDecoration(
                  hintText: 'Ask Calnox AI anything...',
                  hintStyle: TextStyle(
                    fontSize: 14.5,
                    color: AppTheme.secondaryText(isDark),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: _handleUserSend,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _handleUserSend(_inputController.text),
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: Color(0xFF007AFF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.arrow_up_circle_fill,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotTypingBubble(bool isDark, Color botBubbleColor) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: botBubbleColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF007AFF)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Calnox AI is thinking...',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: AppTheme.secondaryText(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required BuildContext context,
    required ChatMessage msg,
    required bool isUser,
    required bool isDark,
    required Color userBubbleColor,
    required Color botBubbleColor,
  }) {
    final timeStr =
        '${msg.timestamp.hour > 12 ? msg.timestamp.hour - 12 : (msg.timestamp.hour == 0 ? 12 : msg.timestamp.hour)}:${msg.timestamp.minute.toString().padLeft(2, '0')} ${msg.timestamp.hour >= 12 ? 'PM' : 'AM'}';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? userBubbleColor : botBubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.sparkles,
                    size: 13,
                    color: Color(0xFF007AFF),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Calnox AI',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF007AFF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            SelectableText(
              msg.content,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
