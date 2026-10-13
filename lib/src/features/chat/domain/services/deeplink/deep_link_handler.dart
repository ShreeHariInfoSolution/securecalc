import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import '../server_api_service.dart';
import '../server_chat_manager.dart';
import '../chat_invite_service.dart';
import '../../../presentation/pages/chat_detail_page.dart';
import '../../../../../core/ui/vault_page_route.dart';
import '../../entities/chat_conversation.dart';

class DeepLinkHandler {
  DeepLinkHandler._();
  static final instance = DeepLinkHandler._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  
  Uri? _pendingUri;
  bool _isVaultReady = false;
  BuildContext? _vaultContext;

  /// Call this early in main.dart to ensure we don't miss warm-start intents
  void startListening() {
    _handleInitialLink();
    
    _linkSubscription?.cancel();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (_isVaultReady && _vaultContext != null && _vaultContext!.mounted) {
        _processLink(_vaultContext!, uri);
      } else {
        _pendingUri = uri; // queue it until vault is ready
      }
    });
  }

  Future<void> _handleInitialLink() async {
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        if (_isVaultReady && _vaultContext != null && _vaultContext!.mounted) {
          _processLink(_vaultContext!, initialLink);
        } else {
          _pendingUri = initialLink;
        }
      }
    } catch (e) {
      debugPrint('[DeepLink] Failed to get initial link: $e');
    }
  }

  /// Call this when the vault is fully unlocked and authenticated.
  void init(BuildContext context) {
    _isVaultReady = true;
    _vaultContext = context;
    
    if (_pendingUri != null) {
      _processLink(context, _pendingUri!);
      _pendingUri = null;
    }
  }

  void dispose() {
    _isVaultReady = false;
    _vaultContext = null;
  }

  Future<void> _processLink(BuildContext context, Uri uri) async {
    // Support both custom scheme and standard HTTPS fallback
    if (uri.scheme != 'securecalc' && uri.scheme != 'https') return;
    if (uri.scheme == 'https' && uri.host != 'realragnardev-dotcom.github.io') return;

    // In https mode, the action is passed in query parameters via the redirect page
    // In securecalc:// mode, the action is the host (e.g. securecalc://chat)
    final isHttps = uri.scheme == 'https';

    if ((isHttps && uri.queryParameters.containsKey('target_id')) || (!isHttps && uri.host == 'chat')) {
      final targetIdStr = uri.queryParameters['target_id'];
      if (targetIdStr != null) {
        final targetId = int.tryParse(targetIdStr);
        if (targetId != null) {
          if (context.mounted) _joinDirectChat(context, targetId);
        }
      }
    } else if ((isHttps && uri.queryParameters.containsKey('group_id')) || (!isHttps && uri.host == 'join')) {
      final groupIdStr = uri.queryParameters['group_id'];
      if (groupIdStr != null) {
        final groupId = int.tryParse(groupIdStr);
        if (groupId != null) {
          if (context.mounted) _joinGroup(context, groupId);
        }
      }
    }
  }

  Future<void> _joinDirectChat(BuildContext context, int targetId) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final conversation = await DirectChatStarter.instance.start(targetId);
      
      if (!context.mounted) return;
      Navigator.pop(context); // close loader

      Navigator.of(context).push(
        VaultPageRoute(
          builder: (_) => ChatDetailPage(
            conversation: conversation,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // close loader
      debugPrint('[DeepLink] Direct Chat Error: $e');
    }
  }

  Future<void> _joinGroup(BuildContext context, int groupId) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final currentUserId = ServerApiService.instance.currentUserId;
      if (currentUserId != null) {
        await ServerApiService.instance.addGroupMembers(
          chatId: groupId,
          userIds: [currentUserId],
        );
      }
      
      final chat = await ServerApiService.instance.getChatDetails(groupId);
      await ServerChatManager.instance.syncChats();

      if (!context.mounted) return;
      Navigator.pop(context); // close loader

      if (chat != null) {
        Navigator.of(context).push(
          VaultPageRoute(
            builder: (_) => ChatDetailPage(
              conversation: ChatConversation(
                id: chat.id.toString(),
                name: chat.groupName ?? 'Group',
                avatarUrl: chat.groupAvatar ?? '',
                lastMessage: '',
                lastMessageTime: '',
                unreadCount: 0,
                isOnline: false,
                messages: const [],
                isGroup: chat.isGroup,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // close loader
      debugPrint('[DeepLink] Join Group Error: $e');
    }
  }
}
