import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/features/chat/domain/entities/chat_conversation.dart';
import 'package:securecalc/src/features/chat/domain/entities/chat_message.dart';
import 'package:securecalc/src/features/chat/domain/services/forward_service.dart';
import 'package:securecalc/src/features/chat/domain/services/local_chat_storage.dart';

class ForwardChatSelectionDialog extends StatefulWidget {
  final List<ChatMessage> selectedMessages;
  final String sourceChatId;

  const ForwardChatSelectionDialog({
    super.key,
    required this.selectedMessages,
    required this.sourceChatId,
  });

  static Future<void> show(
    BuildContext context, {
    required List<ChatMessage> selectedMessages,
    required String sourceChatId,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ForwardChatSelectionDialog(
        selectedMessages: selectedMessages,
        sourceChatId: sourceChatId,
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

  Future<void> _performForward(List<ChatConversation> allChats) async {
    if (_selectedChatIds.isEmpty || _isSending) return;
    setState(() => _isSending = true);

    final targets =
        allChats.where((c) => _selectedChatIds.contains(c.id)).toList();
    final count = _selectedChatIds.length;

    Navigator.pop(context);
    AppToast.show(
      count == 1 ? 'Forwarding message...' : 'Forwarding to $count chats...',
    );

    unawaited(
      ForwardService.forward(
        messages: widget.selectedMessages,
        sourceChatId: widget.sourceChatId,
        targets: targets,
      ).then((failures) {
        if (failures > 0) {
          AppToast.show('Some messages could not be forwarded.', isError: true);
        } else {
          AppToast.show(
            count == 1
                ? 'Message forwarded successfully.'
                : 'Forwarded to $count chats successfully.',
          );
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ValueListenableBuilder<List<ChatConversation>>(
      valueListenable: LocalChatStorage.instance.conversationsNotifier,
      builder: (context, conversations, _) {
        final filtered = conversations.where((c) {
          if (_searchQuery.trim().isEmpty) return true;
          final query = _searchQuery.trim().toLowerCase();
          return c.name.toLowerCase().contains(query);
        }).toList();

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      'Forward ${widget.selectedMessages.length} message(s)',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: CupertinoSearchTextField(
                  placeholder: 'Search chats...',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No chats found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final chat = filtered[index];
                          final isSelected =
                              _selectedChatIds.contains(chat.id);
                          return ListTile(
                            leading: IosAvatar(
                              imagePath: chat.avatarUrl,
                              name: chat.name,
                              size: 40,
                            ),
                            title: Text(
                              chat.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: Checkbox(
                              value: isSelected,
                              activeColor: AppTheme.primaryColor,
                              onChanged: (_) {
                                setState(() {
                                  if (isSelected) {
                                    _selectedChatIds.remove(chat.id);
                                  } else {
                                    _selectedChatIds.add(chat.id);
                                  }
                                });
                              },
                            ),
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedChatIds.remove(chat.id);
                                } else {
                                  _selectedChatIds.add(chat.id);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _selectedChatIds.isEmpty || _isSending
                        ? null
                        : () => _performForward(conversations),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSending
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'Send to ${_selectedChatIds.length} chat(s)',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
              SizedBox(height: bottomInset + 10),
            ],
          ),
        );
      },
    );
  }
}
