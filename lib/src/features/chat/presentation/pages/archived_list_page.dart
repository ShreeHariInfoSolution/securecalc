import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/vault_edge_panel_wrapper.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/services/local_chat_storage.dart';
import '../widgets/chat_peek_preview_dialog.dart';
import '../widgets/conversation_tile.dart';
import 'chat_detail_page.dart';

class ArchivedListPage extends StatelessWidget {
  final bool isDuressMode;

  const ArchivedListPage({super.key, this.isDuressMode = false});

  void _showPeekPreview(BuildContext context, ChatConversation conv, Rect origin) {
    showGeneralDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, _, __) {
        return ChatPeekPreviewDialog(
          conversation: conv,
          originRect: origin,
          hostContext: context,
          isDuressMode: isDuressMode,
          onOpenChat: () {
            Navigator.of(dialogContext).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VaultEdgePanelWrapper(
                  isDuressMode: isDuressMode,
                  child: ChatDetailPage(conversation: conv),
                ),
              ),
            );
          },
        );
      },
    );
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
          'Archived Chats',
          style: TextStyle(
            color: AppTheme.primaryText(isDark),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: ValueListenableBuilder<List<ChatConversation>>(
        valueListenable: LocalChatStorage.instance.conversationsNotifier,
        builder: (context, rawConversations, _) {
          final archived = isDuressMode
              ? <ChatConversation>[]
              : rawConversations.where((c) => c.isArchived).toList();

          if (archived.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.archivebox,
                    size: 54,
                    color: AppTheme.secondaryText(isDark),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'No Archived Chats',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondaryText(isDark),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Chats you archive will appear here.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.secondaryText(isDark),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: archived.length,
            itemBuilder: (context, index) {
              final conv = archived[index];
              return Builder(
                builder: (tileCtx) => GestureDetector(
                  onLongPress: () {
                    final box = tileCtx.findRenderObject() as RenderBox?;
                    final rect = box != null
                        ? (box.localToGlobal(Offset.zero) & box.size)
                        : Rect.zero;
                    _showPeekPreview(context, conv, rect);
                  },
                  child: ConversationTile(
                  conversation: conv,
                  isTyping: conv.isTyping,
                  showDivider: index < archived.length - 1,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => VaultEdgePanelWrapper(
                          isDuressMode: isDuressMode,
                          child: ChatDetailPage(conversation: conv),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
            },
          );
        },
      ),
    );
  }
}
