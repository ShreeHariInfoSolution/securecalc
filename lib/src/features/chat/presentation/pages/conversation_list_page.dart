import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/core/widgets/vault_edge_panel_wrapper.dart';
import 'package:securecalc/src/features/calculator/presentation/pages/calculator_page.dart';
import 'package:securecalc/src/features/private_folder/presentation/pages/private_folder_page.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/models/server_models.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import '../../domain/services/chat_invite_service.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/chat_peek_preview_dialog.dart';
import '../../domain/services/bot_assistant_service.dart';
import 'archived_list_page.dart';
import 'bot_chat_detail_page.dart';
import 'chat_detail_page.dart';
import 'secret_settings_page.dart';
import 'share/scan_qr_page.dart';
import 'share/share_qr_page.dart';

enum ConversationFilter { all, unread, favourites, groups }

class ConversationListPage extends StatefulWidget {
  final bool isDuressMode;

  const ConversationListPage({super.key, this.isDuressMode = false});

  @override
  State<ConversationListPage> createState() => _ConversationListPageState();
}

class _ConversationListPageState extends State<ConversationListPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  ConversationFilter _filter = ConversationFilter.all;
  bool _showFilterChips = false;
  bool _isSyncing = false;

  int _currentChatPage = 1;
  bool _hasMoreChats = true;
  bool _isLoadingMoreChats = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _warmAttachmentCache();
    _refreshServerChats();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  void _onSearchFocusChanged() {
    setState(() {});
  }

  Future<void> _warmAttachmentCache() async {
    await AttachmentCacheService.instance.warmUp();
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final offset = _scrollController.offset;
      if (offset < -10) {
        if (!_showFilterChips) {
          setState(() => _showFilterChips = true);
        }
      } else if (offset > 40 &&
          _filter == ConversationFilter.all &&
          _searchController.text.isEmpty &&
          !_searchFocusNode.hasFocus) {
        if (_showFilterChips) {
          setState(() => _showFilterChips = false);
        }
      }

      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMoreChats();
      }
    }
  }

  Future<void> _refreshServerChats() async {
    if (widget.isDuressMode) return;
    if (mounted) setState(() => _isSyncing = true);
    try {
      _currentChatPage = 1;
      _hasMoreChats = true;
      final chats = await ServerChatManager.instance.syncChats(
        page: 1,
        limit: 20,
      );
      if (mounted) {
        setState(() {
          _hasMoreChats = chats.length >= 20;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _loadMoreChats() async {
    if (widget.isDuressMode || _isLoadingMoreChats || !_hasMoreChats) return;
    if (mounted) setState(() => _isLoadingMoreChats = true);
    try {
      final nextPage = _currentChatPage + 1;
      final chats = await ServerChatManager.instance.syncChats(
        page: nextPage,
        limit: 20,
        append: true,
      );
      if (mounted) {
        setState(() {
          _currentChatPage = nextPage;
          _hasMoreChats = chats.length >= 20;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoadingMoreChats = false);
      }
    }
  }

  void _showMoreOptionsMenu(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, anim1, anim2) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final topPadding = MediaQuery.paddingOf(context).top;

        return Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(dialogContext).pop(),
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
            Positioned(
              left: 14,
              top: topPadding + 48,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                    child: Container(
                      width: 210,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xDD2C2C2E)
                            : const Color(0xEEF8F8F8),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Option 1: Calculator
                          InkWell(
                            onTap: () {
                              Navigator.of(dialogContext).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const CalculatorPage(),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.number,
                                    size: 18,
                                    color: AppTheme.primaryText(isDark),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Calculator',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.primaryText(isDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.08),
                          ),

                          // Option 2: Private Vault
                          InkWell(
                            onTap: () {
                              Navigator.of(dialogContext).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const PrivateFolderPage(),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.folder,
                                    size: 18,
                                    color: AppTheme.primaryText(isDark),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Private Vault',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.primaryText(isDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.08),
                          ),

                          // Option 3: Secret Settings
                          InkWell(
                            onTap: () {
                              Navigator.of(dialogContext).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const SecretSettingsPage(),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.lock_shield,
                                    size: 18,
                                    color: AppTheme.primaryText(isDark),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Secret Settings',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.primaryText(isDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startChatFromCode(String value) async {
    final targetId = ChatInvite.targetUserIdFrom(value);
    if (targetId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid code or link')));
      return;
    }
    try {
      final conv = await DirectChatStarter.instance.start(targetId);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VaultEdgePanelWrapper(
              isDuressMode: widget.isDuressMode,
              child: ChatDetailPage(conversation: conv),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _showPasteCodeSheet() {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste profile code',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter code or user ID...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final text = controller.text.trim();
                  Navigator.pop(sheetContext);
                  if (text.isNotEmpty) _startChatFromCode(text);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                ),
                child: const Text(
                  'Start Chat',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewChatActionsSheet() {
    final userId = ServerApiService.instance.currentUserId;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.subtitleGrey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'New chat',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // ListTile(
                //   leading: const Icon(
                //     CupertinoIcons.person_crop_circle_badge_plus,
                //   ),
                //   title: const Text('Find a user'),
                //   subtitle: const Text('Search registered SecureCalc users'),
                //   onTap: () {
                //     Navigator.of(sheetContext).pop();
                //     _showUserSearchSheet(context);
                //   },
                // ),
                // ListTile(leading: const Icon(CupertinoIcons.person_3), title: const Text('New group'), subtitle: const Text('Create a secure group chat'), onTap: () { Navigator.of(sheetContext).pop(); _showCreateGroupSheet(context); }),
                ListTile(
                  leading: const Icon(CupertinoIcons.qrcode_viewfinder),
                  title: const Text('Scan QR code'),
                  subtitle: const Text('Scan someone’s SecureCalc profile'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final value = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => const ScanQrPage()),
                    );
                    if (value != null && mounted) _startChatFromCode(value);
                  },
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.doc_on_clipboard),
                  title: const Text('Paste profile code'),
                  subtitle: const Text('Paste a code or numeric user ID'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showPasteCodeSheet();
                  },
                ),
                if (userId != null)
                  ListTile(
                    leading: const Icon(CupertinoIcons.qrcode),
                    title: const Text('Share my profile'),
                    subtitle: const Text(
                      'Show QR code, copy code, or share link',
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShareQrPage(
                            title: 'My profile QR',
                            subtitle: 'Let someone scan this code to start a secure chat with you.',
                            shareLink: ChatInvite.forUser(userId),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateGroupSheet(BuildContext context) {
    final groupNameController = TextEditingController();
    final selectedUserIds = <int>{};
    List<UserModel> users = [];
    bool loadingUsers = true;
    bool submitting = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> loadUsers() async {
            try {
              final result = await ServerApiService.instance.getUsersPage(
                page: 1,
                limit: 50,
              );
              final meId = ServerApiService.instance.currentUserId;
              if (sheetContext.mounted) {
                setSheetState(() {
                  users = result.users.where((u) => u.id != meId).toList();
                  loadingUsers = false;
                });
              }
            } catch (_) {
              if (sheetContext.mounted) {
                setSheetState(() => loadingUsers = false);
              }
            }
          }

          if (loadingUsers && users.isEmpty) {
            unawaited(loadUsers());
          }

          Future<void> createGroup() async {
            final nav = Navigator.of(context);
            final name = groupNameController.text.trim();
            if (name.isEmpty || selectedUserIds.isEmpty || submitting) return;
            setSheetState(() => submitting = true);
            try {
              final serverChat = await ServerApiService.instance.createGroup(
                groupName: name,
                memberIds: selectedUserIds.toList(),
              );
              if (serverChat.id <= 0) {
                throw Exception('Invalid group ID');
              }
              await LocalChatStorage.instance.createOrGetConversation(
                deviceId: serverChat.id.toString(),
                displayName: name,
              );
              if (mounted) {
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                final currentConv =
                    LocalChatStorage.instance.getConversationSync(
                      serverChat.id.toString(),
                    ) ??
                    ChatConversation(
                      id: serverChat.id.toString(),
                      name: name,
                      avatarUrl: '',
                      lastMessage: 'Group created',
                      lastMessageTime: 'Just now',
                      unreadCount: 0,
                      isGroup: true,
                      messages: const [],
                    );
                nav.push(
                  MaterialPageRoute(
                    builder: (context) => VaultEdgePanelWrapper(
                      isDuressMode: widget.isDuressMode,
                      child: ChatDetailPage(conversation: currentConv),
                    ),
                  ),
                );
              }
            } catch (err) {
              setSheetState(() => submitting = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              top: 16,
              left: 16,
              right: 16,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Create Group',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.xmark_circle_fill),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: groupNameController,
                    decoration: InputDecoration(
                      hintText: 'Group Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Select Members:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: loadingUsers
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final u = users[index];
                              final selected = selectedUserIds.contains(u.id);
                              return CheckboxListTile(
                                value: selected,
                                title: Text(u.name),
                                secondary: IosAvatar(
                                  name: u.name,
                                  imagePath: u.avatarUrl,
                                  size: 36,
                                ),
                                onChanged: (val) {
                                  setSheetState(() {
                                    if (val == true) {
                                      selectedUserIds.add(u.id);
                                    } else {
                                      selectedUserIds.remove(u.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: submitting ? null : createGroup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Create Group',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showUserSearchSheet(BuildContext context) {
    final searchUserCtrl = TextEditingController();
    List<UserModel> userList = [];
    bool loading = true;
    String query = '';
    Timer? searchTimer;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> fetchUsers() async {
            setSheetState(() => loading = true);
            try {
              final result = await ServerApiService.instance.getUsersPage(
                page: 1,
                limit: 30,
                query: query,
              );
              final meId = ServerApiService.instance.currentUserId;
              if (sheetContext.mounted) {
                setSheetState(() {
                  userList = result.users.where((u) => u.id != meId).toList();
                  loading = false;
                });
              }
            } catch (_) {
              if (sheetContext.mounted) {
                setSheetState(() => loading = false);
              }
            }
          }

          if (loading && userList.isEmpty) {
            unawaited(fetchUsers());
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            builder: (context, scrollCtrl) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'New Chat',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(CupertinoIcons.xmark_circle_fill),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1C1E)
                            : const Color(0xFFF0F0F2),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.search,
                            size: 18,
                            color: AppTheme.secondaryText(isDark),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: searchUserCtrl,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.search,
                              keyboardType: TextInputType.text,
                              onSubmitted: (_) => FocusScope.of(context).unfocus(),
                              onChanged: (val) {
                                searchTimer?.cancel();
                                searchTimer = Timer(
                                  const Duration(milliseconds: 300),
                                  () {
                                    query = val.trim();
                                    fetchUsers();
                                  },
                                );
                              },
                              style: TextStyle(
                                fontSize: 15,
                                color: AppTheme.primaryText(isDark),
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Search user...',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : userList.isEmpty
                          ? const Center(child: Text('No users found'))
                          : ListView.builder(
                              controller: scrollCtrl,
                              itemCount: userList.length,
                              itemBuilder: (context, index) {
                                final u = userList[index];
                                return ListTile(
                                  leading: IosAvatar(
                                    name: u.name,
                                    imagePath: u.avatarUrl,
                                    size: 42,
                                  ),
                                  title: Text(
                                    u.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    u.isOnline ? 'Online' : 'Last seen recently',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: u.isOnline
                                          ? Colors.green
                                          : Colors.grey,
                                    ),
                                  ),
                                  onTap: () async {
                                    final nav = Navigator.of(context);
                                    Navigator.pop(sheetContext);
                                    try {
                                      final directChat = await ServerApiService
                                          .instance
                                          .createDirectChat(u.id);
                                      await LocalChatStorage.instance
                                          .createOrGetConversation(
                                            deviceId: directChat.id.toString(),
                                            displayName: u.name,
                                            avatarUrl: u.avatarUrl,
                                            peerUserId: u.id,
                                          );
                                      if (mounted) {
                                        final currentConv =
                                            LocalChatStorage.instance
                                                .getConversationSync(
                                                  directChat.id.toString(),
                                                ) ??
                                            ChatConversation(
                                              id: directChat.id.toString(),
                                              name: u.name,
                                              avatarUrl: u.avatarUrl,
                                              lastMessage: '',
                                              lastMessageTime: 'Just now',
                                              unreadCount: 0,
                                              peerUserId: u.id,
                                              messages: const [],
                                            );
                                        nav.push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                VaultEdgePanelWrapper(
                                                  isDuressMode:
                                                      widget.isDuressMode,
                                                  child: ChatDetailPage(
                                                    conversation: currentConv,
                                                  ),
                                                ),
                                          ),
                                        );
                                      }
                                    } catch (_) {}
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showChatPeekPreview(BuildContext context, ChatConversation conv) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (dialogContext, anim1, anim2) {
        return ChatPeekPreviewDialog(
          conversation: conv,
          isDuressMode: widget.isDuressMode,
          onOpenChat: () {
            Navigator.of(dialogContext).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => VaultEdgePanelWrapper(
                  isDuressMode: widget.isDuressMode,
                  child: ChatDetailPage(conversation: conv),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = CurvedAnimation(
          parent: anim1,
          curve: Curves.easeOutCubic,
        );
        return Transform.scale(
          scale: 0.88 + (0.12 * curve.value),
          child: FadeTransition(opacity: curve, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor: AppTheme.chatCanvas(isDark),
        body: ValueListenableBuilder<List<ChatConversation>>(
          valueListenable: LocalChatStorage.instance.conversationsNotifier,
          builder: (context, rawConversations, _) {
            final conversations = widget.isDuressMode
                ? <ChatConversation>[]
                : rawConversations;

            final activeConversations = conversations
                .where((c) => !c.isArchived)
                .toList();
            final archivedTotal = conversations
                .where((c) => c.isArchived)
                .length;
            final archivedUnreadChatsCount = conversations
                .where((c) => c.isArchived && c.unreadCount > 0)
                .length;

            final query = _searchController.text.trim().toLowerCase();
            final filtered =
                activeConversations.where((conv) {
                  final matchesQuery =
                      conv.name.toLowerCase().contains(query) ||
                      conv.lastMessage.toLowerCase().contains(query);

                  if (_filter == ConversationFilter.unread) {
                    return matchesQuery && conv.unreadCount > 0;
                  } else if (_filter == ConversationFilter.favourites) {
                    return matchesQuery && conv.isPinned;
                  } else if (_filter == ConversationFilter.groups) {
                    return matchesQuery && conv.isGroup;
                  }
                  return matchesQuery;
                }).toList()..sort((a, b) {
                  if (a.isPinned != b.isPinned) {
                    return a.isPinned ? -1 : 1;
                  }
                  final aTime = a.lastActivityAt?.millisecondsSinceEpoch ?? 0;
                  final bTime = b.lastActivityAt?.millisecondsSinceEpoch ?? 0;
                  return bTime.compareTo(aTime);
                });

            final unreadTotal = conversations.fold<int>(
              0,
              (sum, c) => sum + c.unreadCount,
            );
            final groupTotal = conversations
                .where((c) => c.isGroup && !c.isArchived)
                .length;

            final showFilterChips =
                _showFilterChips ||
                _filter != ConversationFilter.all ||
                _searchFocusNode.hasFocus ||
                _searchController.text.isNotEmpty;

            return CustomScrollView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                // iOS Collapsing Large Title Header & Search/Filters
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _IosMessagesHeaderDelegate(
                    topPadding: MediaQuery.paddingOf(context).top,
                    isDark: isDark,
                    isSyncing: _isSyncing,
                    unreadTotal: unreadTotal,
                    groupTotal: groupTotal,
                    filter: _filter,
                    showFilterChips: showFilterChips,
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    onFilterSelected: (f) => setState(() => _filter = f),
                    onMoreTap: () => _showMoreOptionsMenu(context),
                    onNewChatTap: () => _showNewChatActionsSheet(),
                  ),
                ),

                // Cupertino Pull-to-Refresh
                CupertinoSliverRefreshControl(onRefresh: _refreshServerChats),

                // Conversation Tiles List + Archived Row
                if (filtered.isEmpty && archivedTotal == 0)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.chat_bubble_2,
                              size: 48,
                              color: AppTheme.secondaryText(isDark),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No results for "${_searchController.text}"'
                                  : 'No Conversations Yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondaryText(isDark),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap the + button above to search users and start messaging.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.secondaryText(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        // Index 0: Archived Row
                        if (index == 0) {
                          return Column(
                            children: [
                              InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => ArchivedListPage(
                                        isDuressMode: widget.isDuressMode,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 12.0,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.archivebox,
                                        size: 22,
                                        color: AppTheme.secondaryText(isDark),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        'Archived',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryText(isDark),
                                        ),
                                      ),
                                      const Spacer(),
                                      if (archivedUnreadChatsCount > 0) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '$archivedUnreadChatsCount',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ] else if (archivedTotal > 0) ...[
                                        Text(
                                          '$archivedTotal',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: AppTheme.secondaryText(
                                              isDark,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              Divider(
                                height: 0.5,
                                thickness: 0.5,
                                color: AppTheme.listDivider(isDark),
                                indent: 54,
                              ),
                            ],
                          );
                        }

                        final convIndex = index - 1;
                        if (convIndex == filtered.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        final conv = filtered[convIndex];
                        return GestureDetector(
                          onLongPress: () =>
                              _showChatPeekPreview(context, conv),
                          child: ConversationTile(
                            conversation: conv,
                            isTyping: conv.isTyping,
                            showDivider: convIndex < filtered.length - 1,
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              if (conv.id == BotAssistantService.botId) {
                                BotChatDetailPage.open(
                                  context,
                                  conversation: conv,
                                );
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => VaultEdgePanelWrapper(
                                    isDuressMode: widget.isDuressMode,
                                    child: ChatDetailPage(conversation: conv),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                      childCount:
                          1 + filtered.length + (_isLoadingMoreChats ? 1 : 0),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IosMessagesHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double topPadding;
  final bool isDark;
  final bool isSyncing;
  final int unreadTotal;
  final int groupTotal;
  final ConversationFilter filter;
  final bool showFilterChips;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final Function(ConversationFilter) onFilterSelected;
  final VoidCallback onMoreTap;
  final VoidCallback onNewChatTap;

  _IosMessagesHeaderDelegate({
    required this.topPadding,
    required this.isDark,
    required this.isSyncing,
    required this.unreadTotal,
    required this.groupTotal,
    required this.filter,
    required this.showFilterChips,
    required this.searchController,
    required this.searchFocusNode,
    required this.onFilterSelected,
    required this.onMoreTap,
    required this.onNewChatTap,
  });

  @override
  double get minExtent => 56.0 + topPadding;

  @override
  double get maxExtent => (showFilterChips ? 208.0 : 160.0) + topPadding;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final maxScroll = maxExtent - minExtent;
    final progress = (shrinkOffset / maxScroll).clamp(0.0, 1.0);

    final largeTitleOpacity = (1.0 - (shrinkOffset / 48.0)).clamp(0.0, 1.0);
    final smallTitleOpacity = ((shrinkOffset - 34.0) / 26.0).clamp(0.0, 1.0);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: AppTheme.glassSurface(isDark),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.glassBorder(isDark)
                      .withValues(alpha: progress * 0.8),
                  width: 0.5,
                ),
              ),
            ),
            padding: EdgeInsets.only(top: topPadding),
            child: Stack(
              children: [
                // Top Action Bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left: More actions button
                        GestureDetector(
                          onTap: onMoreTap,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : const Color(0xFFE9E9EF),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.ellipsis,
                              size: 21,
                              color: AppTheme.primaryText(isDark),
                            ),
                          ),
                        ),

                        // Centered Small Title "Chats" (Fades in on scroll)
                        Opacity(
                          opacity: smallTitleOpacity,
                          child: Text(
                            'Chats',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryText(isDark),
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),

                        // Right: Compose button
                        GestureDetector(
                          onTap: onNewChatTap,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              CupertinoIcons.add,
                              size: 23,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Collapsing Section: Large Title "Chats", Search Bar & Filter Chips
                Positioned(
                  top: 56,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: largeTitleOpacity,
                    child: Transform.translate(
                      offset: Offset(0, -shrinkOffset * 0.4),
                      child: ClipRect(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Large Title "Chats"
                                Text(
                                  'Chats',
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.9,
                                    color: AppTheme.primaryText(isDark),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Search bar
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF2C2C2E)
                                        : const Color(0xFFE9E9EF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.search,
                                        size: 18,
                                        color: AppTheme.secondaryText(isDark),
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: TextField(
                                          controller: searchController,
                                          focusNode: searchFocusNode,
                                          textCapitalization: TextCapitalization.sentences,
                                          textInputAction: TextInputAction.search,
                                          keyboardType: TextInputType.text,
                                          onSubmitted: (_) => searchFocusNode.unfocus(),
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: AppTheme.primaryText(isDark),
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Search conversations',
                                            hintStyle: TextStyle(
                                              fontSize: 15,
                                              color: AppTheme.secondaryText(
                                                isDark,
                                              ),
                                            ),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Horizontal Filter Chips
                                if (showFilterChips) ...[
                                  const SizedBox(height: 10),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    child: Row(
                                      children: [
                                        _buildFilterPill(
                                          context: context,
                                          isDark: isDark,
                                          label: 'All',
                                          isSelected:
                                              filter == ConversationFilter.all,
                                          onTap: () => onFilterSelected(
                                            ConversationFilter.all,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildFilterPill(
                                          context: context,
                                          isDark: isDark,
                                          label: unreadTotal > 0
                                              ? 'Unread $unreadTotal'
                                              : 'Unread',
                                          isSelected:
                                              filter ==
                                              ConversationFilter.unread,
                                          onTap: () => onFilterSelected(
                                            ConversationFilter.unread,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildFilterPill(
                                          context: context,
                                          isDark: isDark,
                                          label: 'Favourites',
                                          isSelected:
                                              filter ==
                                              ConversationFilter.favourites,
                                          onTap: () => onFilterSelected(
                                            ConversationFilter.favourites,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildFilterPill(
                                          context: context,
                                          isDark: isDark,
                                          label: groupTotal > 0
                                              ? 'Groups $groupTotal'
                                              : 'Groups',
                                          isSelected:
                                              filter ==
                                              ConversationFilter.groups,
                                          onTap: () => onFilterSelected(
                                            ConversationFilter.groups,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildFilterPill(
                                          context: context,
                                          isDark: isDark,
                                          label: 'Communities',
                                          isSelected: false,
                                          onTap: () {},
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required BuildContext context,
    required bool isDark,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final activeBg = isDark ? const Color(0xFF105E4E) : const Color(0xFFD8FDD2);
    final activeTextColor = isDark
        ? const Color(0xFF25D366)
        : const Color(0xFF075E54);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeBg
              : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? activeTextColor.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? activeTextColor
                : AppTheme.secondaryText(isDark),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_IosMessagesHeaderDelegate oldDelegate) {
    return oldDelegate.topPadding != topPadding ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isSyncing != isSyncing ||
        oldDelegate.unreadTotal != unreadTotal ||
        oldDelegate.groupTotal != groupTotal ||
        oldDelegate.filter != filter ||
        oldDelegate.showFilterChips != showFilterChips;
  }
}
