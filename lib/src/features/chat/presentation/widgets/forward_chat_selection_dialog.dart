import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/features/chat/domain/entities/chat_conversation.dart';
import 'package:securecalc/src/features/chat/domain/entities/chat_message.dart';
import 'package:securecalc/src/features/chat/domain/services/local_chat_storage.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_chat_manager.dart';

class ForwardChatSelectionDialog extends StatefulWidget {
  final List<ChatMessage> selectedMessages;

  const ForwardChatSelectionDialog({
    super.key,
    required this.selectedMessages,
  });

  static Future<void> show(
    BuildContext context, {
    required List<ChatMessage> selectedMessages,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ForwardChatSelectionDialog(
        selectedMessages: selectedMessages,
      ),
    );
  }

  @override
  State<ForwardChatSelectionDialog> createState() =>
      _ForwardChatSelectionDialogState();
}

class _ForwardChatSelectionDialogState
    extends State<ForwardChatSelectionDialog> {
  final Set<String> _selectedChatIds = {};
  String _searchQuery = '';
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ValueListenableBuilder<List<ChatConversation>>(
      valueListenable: LocalChatStorage.instance.conversationsNotifier,
      builder: (context, conversations, _) {
        final filteredChats = conversations.where((c) {
          if (_searchQuery.trim().isEmpty) return true;
          return c.name.toLowerCase().contains(_searchQuery.trim().toLowerCase());
        }).toList();

        return Container(
          height: MediaQuery.sizeOf(context).height * 0.75,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header Drag Handle
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white30 : Colors.black26,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 12),

              // Title & Send Action
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Text(
                      'Forward ${widget.selectedMessages.length} message(s)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedChatIds.isNotEmpty)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          elevation: 0,
                        ),
                        onPressed: _isSending ? null : () => _performForward(conversations),
                        child: _isSending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Send (${_selectedChatIds.length})',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Search Box
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search chats…',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      CupertinoIcons.search,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFF2F2F7),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Chat List
              Expanded(
                child: filteredChats.isEmpty
                    ? Center(
                        child: Text(
                          'No chats found',
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredChats.length,
                        itemBuilder: (context, index) {
                          final chat = filteredChats[index];
                          final isSelected = _selectedChatIds.contains(chat.id);

                          return ListTile(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedChatIds.remove(chat.id);
                                } else {
                                  _selectedChatIds.add(chat.id);
                                }
                              });
                            },
                            leading: IosAvatar(
                              name: chat.name,
                              imagePath: chat.avatarUrl,
                              size: 44,
                              showOnline: false,
                            ),
                            title: Text(
                              chat.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            subtitle: Text(
                              chat.lastMessage.isNotEmpty
                                  ? chat.lastMessage
                                  : 'Tap to select',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                            trailing: Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: isSelected
                                  ? const Color(0xFF007AFF)
                                  : (isDark ? Colors.white38 : Colors.black26),
                              size: 22,
                            ),
                          );
                        },
                      ),
              ),

              SizedBox(height: bottomInset + 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _performForward(List<ChatConversation> allChats) async {
    if (_selectedChatIds.isEmpty || _isSending) return;
    setState(() => _isSending = true);

    try {
      final targets = allChats.where((c) => _selectedChatIds.contains(c.id)).toList();

      for (final targetChat in targets) {
        final existingMsgs = await LocalChatStorage.instance.loadMessages(targetChat.id);
        final updatedMsgs = List<ChatMessage>.from(existingMsgs);

        String lastText = '';

        for (final origMsg in widget.selectedMessages) {
          final now = DateTime.now();
          final forwardedMsg = ChatMessage(
            id: now.millisecondsSinceEpoch.toString(),
            senderId: 'user',
            content: origMsg.content,
            timestamp: now,
            type: origMsg.type,
            mediaUrl: origMsg.mediaUrl,
            fileName: origMsg.fileName,
            isRead: true,
            isDelivered: true,
            isForwarded: true,
          );

          updatedMsgs.add(forwardedMsg);
          lastText = forwardedMsg.previewText;

          // Attempt socket / REST send if online
          if (ServerApiService.instance.authToken != null) {
            unawaited(
              ServerChatManager.instance.sendMessage(
                chatId: targetChat.id,
                peerName: targetChat.name,
                text: origMsg.content,
                filePath: origMsg.mediaUrl,
                fileName: origMsg.fileName,
                fileType: origMsg.type,
                peerUserId: targetChat.peerUserId,
              ),
            );
          }
        }

        await LocalChatStorage.instance.cacheMessages(targetChat.id, updatedMsgs);

        // Update conversation tile info and move target chat to top
        final nowStr = '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}';
        await LocalChatStorage.instance.updateConversation(
          targetChat.id,
          (c) => c.copyWith(
            lastMessage: lastText,
            lastMessageTime: nowStr,
            messages: updatedMsgs,
          ),
        );
      }

      await ServerChatManager.instance.syncChats();

      if (mounted) {
        Navigator.pop(context);
        AppToast.show('Forwarded to ${_selectedChatIds.length} chat(s)');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show('Forwarding failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }
}
