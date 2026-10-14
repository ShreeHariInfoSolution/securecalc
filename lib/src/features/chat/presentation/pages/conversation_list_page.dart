import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/core/widgets/vault_edge_panel_wrapper.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/models/server_models.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/chat_invite_service.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/conversation_list_bottom_rail.dart';
import 'package:securecalc/src/features/calculator/presentation/pages/calculator_page.dart';
import 'package:securecalc/src/features/private_folder/presentation/pages/private_folder_page.dart';
import 'chat_detail_page.dart';
import 'secret_settings_page.dart';
import 'share/scan_qr_page.dart';
import 'share/share_qr_page.dart';

enum ConversationFilter { all, unread, read }

class ConversationListPage extends StatefulWidget {
  final bool isDuressMode;

  const ConversationListPage({
    super.key,
    this.isDuressMode = false,
  });

  @override
  State<ConversationListPage> createState() => _ConversationListPageState();
}

class _ConversationListPageState extends State<ConversationListPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  ConversationFilter _filter = ConversationFilter.all;
  bool _isSyncing = false;

  int _currentChatPage = 1;
  bool _hasMoreChats = true;
  bool _isLoadingMoreChats = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _refreshServerChats();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadMoreChats();
    }
  }

  Future<void> _refreshServerChats() async {
    if (widget.isDuressMode) return;
    if (mounted) setState(() => _isSyncing = true);
    try {
      _currentChatPage = 1;
      _hasMoreChats = true;
      final chats = await ServerChatManager.instance.syncChats(page: 1, limit: 20);
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

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : null),
    );
  }

  void _showVaultOptionsSheet(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text(
          'Secret Vault Options',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        message: const Text('Access private files, settings, or lock calculator'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
              Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => const PrivateFolderPage(),
                ),
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.folder_fill_badge_person_crop,
                  color: Color(0xFFAF52DE),
                  size: 22,
                ),
                SizedBox(width: 10),
                Text(
                  'Private Vault',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
              Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => const SecretSettingsPage(),
                ),
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.gear_alt_fill,
                  color: Color(0xFFFF9500),
                  size: 22,
                ),
                SizedBox(width: 10),
                Text(
                  'Settings',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(sheetContext);
              Navigator.of(context).pushAndRemoveUntil(
                PageRouteBuilder(
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  pageBuilder: (context, a1, a2) => const CalculatorPage(),
                ),
                (route) => false,
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.lock_fill,
                  color: Color(0xFFFF3B30),
                  size: 20,
                ),
                SizedBox(width: 10),
                Text(
                  'Lock Calculator',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _startChatFromCode(String value) async {
    final targetId = ChatInvite.targetUserIdFrom(value);
    if (targetId == null) {
      _showMessage('Paste a valid SecureCalc profile code or user ID.', isError: true);
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final conversation = await DirectChatStarter.instance.start(targetId);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatDetailPage(conversation: conversation)),
      );
    } catch (error) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showMessage('Could not start chat: $error', isError: true);
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
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Paste profile code', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Paste a copied SecureCalc profile code or a user ID.'),
          const SizedBox(height: 18),
          TextField(controller: controller, autofocus: true, minLines: 1, maxLines: 3, decoration: const InputDecoration(hintText: 'securecalc://chat?target_id=…', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            icon: const Icon(CupertinoIcons.chat_bubble_2_fill), label: const Text('Start chat'),
            onPressed: () { final value = controller.text; Navigator.of(sheetContext).pop(); _startChatFromCode(value); },
          )),
        ]),
      ),
    ).whenComplete(controller.dispose);
  }

  void _showNewChatActionsSheet() {
    final userId = ServerApiService.instance.currentUserId;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 38, height: 4, decoration: BoxDecoration(color: AppTheme.subtitleGrey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 16),
              const Text('New chat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ListTile(leading: const Icon(CupertinoIcons.person_crop_circle_badge_plus), title: const Text('Find a user'), subtitle: const Text('Search registered SecureCalc users'), onTap: () { Navigator.of(sheetContext).pop(); _showUserSearchSheet(context); }),
              // ListTile(leading: const Icon(CupertinoIcons.person_3), title: const Text('New group'), subtitle: const Text('Create a secure group chat'), onTap: () { Navigator.of(sheetContext).pop(); _showCreateGroupSheet(context); }),
              ListTile(leading: const Icon(CupertinoIcons.qrcode_viewfinder), title: const Text('Scan QR code'), subtitle: const Text('Scan someone’s SecureCalc profile'), onTap: () async { Navigator.of(sheetContext).pop(); final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanQrPage())); if (value != null && mounted) _startChatFromCode(value); }),
              ListTile(leading: const Icon(CupertinoIcons.doc_on_clipboard), title: const Text('Paste profile code'), subtitle: const Text('Paste a code or numeric user ID'), onTap: () { Navigator.of(sheetContext).pop(); _showPasteCodeSheet(); }),
              if (userId != null) ListTile(leading: const Icon(CupertinoIcons.qrcode), title: const Text('Share my profile'), subtitle: const Text('Show QR code, copy code, or share link'), onTap: () { Navigator.of(sheetContext).pop(); Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShareQrPage(title: 'My profile QR', subtitle: 'Let someone scan this code to start a secure chat with you.', shareLink: ChatInvite.forUser(userId)))); }),
            ]),
          ),
        ),
      ),
    );
  }

  void _showUserSearchSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searchUserCtrl = TextEditingController();
    List<UserModel> searchResults = [];
    bool searching = false;
    int searchGeneration = 0;
    int? openingChatForUserId;
    Timer? searchDebounce;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> doSearch(String query) async {
              final generation = ++searchGeneration;
              if (query.trim().length < 2) {
                searchDebounce?.cancel();
                setSheetState(() {
                  searchResults = [];
                  searching = false;
                });
                return;
              }
              setSheetState(() => searching = true);
              try {
                final results = await ServerApiService.instance.searchUsers(
                  query.trim(),
                );
                if (!context.mounted || generation != searchGeneration) return;
                setSheetState(() {
                  searchResults = results
                      .where(
                        (user) =>
                            user.id != ServerApiService.instance.currentUserId,
                      )
                      .toList();
                  searching = false;
                });
              } catch (_) {
                if (context.mounted && generation == searchGeneration) {
                  setSheetState(() => searching = false);
                }
              }
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.person_search_rounded,
                            color: AppTheme.primaryColor,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'New Chat — Search Server Users',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search_rounded,
                              color: AppTheme.subtitleGrey,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: searchUserCtrl,
                                onChanged: (val) {
                                  searchDebounce?.cancel();
                                  if (val.trim().length < 2) {
                                    doSearch(val);
                                  } else {
                                    searchDebounce = Timer(
                                      const Duration(milliseconds: 300),
                                      () => doSearch(val),
                                    );
                                  }
                                },
                                decoration: const InputDecoration(
                                  hintText: 'Search by name, phone or email...',
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintStyle: TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.subtitleGrey,
                                  ),
                                ),
                                style: TextStyle(
                                  fontSize: 15,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: searching
                          ? const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.primaryColor,
                                ),
                              ),
                            )
                          : searchResults.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(
                                      Icons.search_rounded,
                                      size: 40,
                                      color: AppTheme.subtitleGrey,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Type 2+ characters to search registered server users',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.subtitleGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: searchResults.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                indent: 68,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.06),
                              ),
                              itemBuilder: (context, index) {
                                final u = searchResults[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  leading: IosAvatar(
                                    name: u.name,
                                    imagePath: u.avatar,
                                    isOnline: u.isOnline,
                                    size: 46,
                                  ),
                                  title: Text(
                                    u.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    u.phone ?? u.email ?? 'Server User',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.subtitleGrey,
                                    ),
                                  ),
                                  trailing: openingChatForUserId == u.id
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.chat_bubble_rounded,
                                          color: AppTheme.primaryColor,
                                          size: 20,
                                        ),
                                  onTap: () async {
                                    if (openingChatForUserId != null) return;
                                    setSheetState(
                                      () => openingChatForUserId = u.id,
                                    );
                                    try {
                                      final conversation =
                                          await DirectChatStarter.instance
                                              .start(u.id);
                                      if (!context.mounted) return;
                                      Navigator.of(context).pop();
                                      if (mounted) {
                                        Navigator.of(this.context).push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                ChatDetailPage(
                                                  conversation: conversation,
                                                ),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      debugPrint('[API DIRECT CHAT ERROR] $e');
                                      if (context.mounted) {
                                        setSheetState(
                                          () => openingChatForUserId = null,
                                        );
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Could not start chat: $e',
                                                ),
                                              ),
                                            );
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    ).whenComplete(() {
      searchDebounce?.cancel();
    });
  }

  void _showCreateGroupSheet(BuildContext context) {
    final groupNameController = TextEditingController();
    final selectedUserIds = <int>{};
    List<UserModel> users = [];
    bool loadingUsers = true;
    bool loadingMoreUsers = false;
    bool submitting = false;
    bool loadingStarted = false;
    Object? loadError;
    int currentPage = 1;
    int totalPages = 1;
    int userRequestGeneration = 0;
    String userQuery = '';
    Timer? userSearchDebounce;

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
          Future<void> loadUsers({bool append = false}) async {
            final generation = ++userRequestGeneration;
            final requestedPage = append ? currentPage + 1 : 1;
            if (append) {
              setSheetState(() => loadingMoreUsers = true);
            } else if (!loadingUsers) {
              setSheetState(() {
                loadingUsers = true;
                loadingMoreUsers = false;
                loadError = null;
              });
            }
            try {
              final result = await ServerApiService.instance.getUsersPage(
                page: requestedPage,
                limit: 20,
                query: userQuery,
              );
              if (!sheetContext.mounted ||
                  generation != userRequestGeneration) {
                return;
              }
              final fetchedUsers = result.users.where(
                (user) => user.id != ServerApiService.instance.currentUserId,
              );
              setSheetState(() {
                if (append) {
                  final existingIds = users.map((user) => user.id).toSet();
                  users.addAll(
                    fetchedUsers.where(
                      (user) => !existingIds.contains(user.id),
                    ),
                  );
                } else {
                  users = fetchedUsers.toList();
                }
                currentPage = result.page;
                totalPages = result.totalPages;
                loadingUsers = false;
                loadingMoreUsers = false;
                loadError = null;
              });
            } catch (error) {
              if (!sheetContext.mounted ||
                  generation != userRequestGeneration) {
                return;
              }
              setSheetState(() {
                loadingUsers = false;
                loadingMoreUsers = false;
                loadError = error;
              });
            }
          }

          if (!loadingStarted) {
            loadingStarted = true;
            unawaited(loadUsers());
          }

          Future<void> createGroup() async {
            final name = groupNameController.text.trim();
            if (name.isEmpty || selectedUserIds.isEmpty || submitting) return;
            setSheetState(() => submitting = true);
            try {
              final serverChat = await ServerApiService.instance.createGroup(
                groupName: name,
                memberIds: selectedUserIds.toList(),
              );
              if (serverChat.id <= 0) {
                throw Exception('The server did not return a valid chat ID.');
              }
              await LocalChatStorage.instance.createOrGetConversation(
                deviceId: serverChat.id.toString(),
                displayName: name,
              );
              final conversation = ChatConversation(
                id: serverChat.id.toString(),
                name: name,
                avatarUrl: '',
                lastMessage: 'No messages yet',
                lastMessageTime: '',
                lastActivityAt: DateTime.now(),
                unreadCount: 0,
                isGroup: true,
                memberNames: {
                  for (final user in users)
                    if (selectedUserIds.contains(user.id)) user.id: user.name,
                },
                messages: const [],
              );
              if (!sheetContext.mounted) return;
              Navigator.of(sheetContext).pop();
              if (mounted) {
                Navigator.of(this.context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatDetailPage(conversation: conversation),
                  ),
                );
                unawaited(() async {
                  try {
                    await ServerChatManager.instance.syncChats();
                  } catch (_) {}
                }());
              }
            } catch (error) {
              if (!sheetContext.mounted) return;
              setSheetState(() => submitting = false);
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text('Could not create group: $error')),
              );
            }
          }

          final isDark = Theme.of(context).brightness == Brightness.dark;
          final screenHeight = MediaQuery.sizeOf(context).height;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: screenHeight * 0.82),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Create group',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: submitting
                              ? null
                              : () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: TextField(
                      textInputAction: TextInputAction.search,
                      onChanged: (value) {
                        userSearchDebounce?.cancel();
                        userQuery = value.trim();
                        userRequestGeneration++;
                        setSheetState(() {
                          users = [];
                          currentPage = 1;
                          totalPages = 1;
                          loadingUsers = true;
                          loadingMoreUsers = false;
                          loadError = null;
                        });
                        userSearchDebounce = Timer(
                          const Duration(milliseconds: 300),
                          () => unawaited(loadUsers()),
                        );
                      },
                      decoration: InputDecoration(
                        hintText: 'Search people',
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFFF2F2F7),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: TextField(
                      controller: groupNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Group name',
                        prefixIcon: const Icon(Icons.groups_2_outlined),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFFF2F2F7),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Choose people · ${selectedUserIds.length} selected',
                            style: const TextStyle(
                              color: AppTheme.subtitleGrey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed:
                              submitting ||
                                  groupNameController.text.trim().isEmpty ||
                                  selectedUserIds.isEmpty
                              ? null
                              : createGroup,
                          child: submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Create'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: loadingUsers
                        ? const Center(child: CircularProgressIndicator())
                        : loadError != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Could not load users.'),
                                TextButton.icon(
                                  onPressed: () {
                                    setSheetState(() {
                                      loadingUsers = true;
                                      loadError = null;
                                      loadingStarted = false;
                                    });
                                  },
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Try again'),
                                ),
                              ],
                            ),
                          )
                        : users.isEmpty
                        ? const Center(child: Text('No other users found.'))
                        : ListView.builder(
                            itemCount:
                                users.length +
                                (currentPage < totalPages ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == users.length) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: TextButton.icon(
                                      onPressed: loadingMoreUsers
                                          ? null
                                          : () => unawaited(
                                              loadUsers(append: true),
                                            ),
                                      icon: loadingMoreUsers
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.expand_more_rounded,
                                            ),
                                      label: Text(
                                        loadingMoreUsers
                                            ? 'Loading people…'
                                            : 'Load more people',
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final user = users[index];
                              final selected = selectedUserIds.contains(
                                user.id,
                              );
                              return CheckboxListTile(
                                value: selected,
                                secondary: IosAvatar(
                                  name: user.name,
                                  imagePath: user.avatar,
                                  isOnline: user.isOnline,
                                  size: 42,
                                ),
                                title: Text(user.name),
                                subtitle: Text(
                                  user.phone ?? user.email ?? 'Member',
                                ),
                                onChanged: submitting
                                    ? null
                                    : (checked) => setSheetState(() {
                                        if (checked == true) {
                                          selectedUserIds.add(user.id);
                                        } else {
                                          selectedUserIds.remove(user.id);
                                        }
                                      }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor: AppTheme.chatCanvas(isDark),
        body: ValueListenableBuilder<List<ChatConversation>>(
          valueListenable: LocalChatStorage.instance.conversationsNotifier,
          builder: (context, rawConversations, _) {
            final conversations =
                widget.isDuressMode ? <ChatConversation>[] : rawConversations;
            final query = _searchController.text.trim().toLowerCase();
            final filtered = conversations.where((conv) {
              final matchesQuery =
                  conv.name.toLowerCase().contains(query) ||
                  conv.lastMessage.toLowerCase().contains(query);

              if (_filter == ConversationFilter.unread) {
                return matchesQuery && conv.unreadCount > 0;
              } else if (_filter == ConversationFilter.read) {
                return matchesQuery && conv.unreadCount == 0;
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

            return Stack(
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    // iOS Collapsing Large Title Header
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _IosMessagesHeaderDelegate(
                        topPadding: MediaQuery.paddingOf(context).top,
                        isDark: isDark,
                        isSyncing: _isSyncing,
                        unreadTotal: unreadTotal,
                        filter: _filter,
                        onEditTap: () {
                          if (Navigator.canPop(context)) {
                            Navigator.of(context).pop();
                          } else {
                            _showVaultOptionsSheet(context);
                          }
                        },
                        onFilterTap: () => _showFilterMenu(context),
                      ),
                    ),

                    // Cupertino Pull-to-Refresh
                    CupertinoSliverRefreshControl(
                      onRefresh: _refreshServerChats,
                    ),

                    // Conversation Tiles List
                    if (filtered.isEmpty)
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
                                  'Tap the compose button below to search users and start messaging.',
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
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index == filtered.length) {
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
                              final conv = filtered[index];
                              return GestureDetector(
                                onLongPress: () => _showChatOptionsSheet(context, conv),
                                child: ConversationTile(
                                  conversation: conv,
                                  isTyping: conv.isTyping,
                                  showDivider: index < filtered.length - 1,
                                  onTap: () {
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
                            childCount: filtered.length + (_isLoadingMoreChats ? 1 : 0),
                          ),
                        ),
                      ),
                  ],
                ),

                // Floating Bottom Rail Search / New Chat Bar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ConversationListBottomRail(
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    onChanged: (_) => setState(() {}),
                    onNewChatTap: _showNewChatActionsSheet,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showFilterMenu(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Filter Messages'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
              setState(() => _filter = ConversationFilter.all);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_filter == ConversationFilter.all)
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: Icon(CupertinoIcons.checkmark, size: 18),
                  ),
                const Text('All Messages'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
              setState(() => _filter = ConversationFilter.unread);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_filter == ConversationFilter.unread)
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: Icon(CupertinoIcons.checkmark, size: 18),
                  ),
                const Text('Unread Messages'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
              setState(() => _filter = ConversationFilter.read);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_filter == ConversationFilter.read)
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: Icon(CupertinoIcons.checkmark, size: 18),
                  ),
                const Text('Read Messages'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showChatOptionsSheet(BuildContext context, ChatConversation conv) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(conv.name),
        message: Text(conv.isPinned
            ? 'Currently pinned to top & Edge Panel'
            : 'Pin to top & Edge Panel for 1-tap quick access'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              LocalChatStorage.instance.togglePinConversation(conv.id);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  conv.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(conv.isPinned
                    ? 'Unpin Conversation'
                    : 'Pin Conversation'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => VaultEdgePanelWrapper(
                    isDuressMode: widget.isDuressMode,
                    child: ChatDetailPage(conversation: conv),
                  ),
                ),
              );
            },
            child: const Text('Open Secret Thread'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
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
  final ConversationFilter filter;
  final VoidCallback onEditTap;
  final VoidCallback onFilterTap;

  _IosMessagesHeaderDelegate({
    required this.topPadding,
    required this.isDark,
    required this.isSyncing,
    required this.unreadTotal,
    required this.filter,
    required this.onEditTap,
    required this.onFilterTap,
  });

  @override
  double get minExtent => 52.0 + topPadding;

  @override
  double get maxExtent => 104.0 + topPadding;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final maxScroll = maxExtent - minExtent;
    final progress = (shrinkOffset / maxScroll).clamp(0.0, 1.0);

    final largeTitleOpacity = (1.0 - (shrinkOffset / 32.0)).clamp(0.0, 1.0);
    final smallTitleOpacity = ((shrinkOffset - 22.0) / 22.0).clamp(0.0, 1.0);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: AppTheme.glassSurface(isDark),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.glassBorder(isDark).withValues(
                    alpha: progress * 0.8,
                  ),
                  width: 0.5,
                ),
              ),
            ),
            padding: EdgeInsets.only(top: topPadding),
            child: Stack(
              children: [
                // Top Action Bar (Edit, Centered Small Title, Filter)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Edit Button
                        GestureDetector(
                          onTap: onEditTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C2C2E)
                                      .withValues(alpha: 0.75)
                                  : Colors.white.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: AppTheme.glassBorder(isDark),
                                width: 0.8,
                              ),
                            ),
                            child: const Text(
                              'More',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                        ),

                        // Centered Small Title (Fades in when collapsed)
                        Opacity(
                          opacity: smallTitleOpacity,
                          child: Text(
                            'Messages',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryText(isDark),
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),

                        // Filter Button
                        GestureDetector(
                          onTap: onFilterTap,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2C2C2E)
                                          .withValues(alpha: 0.75)
                                      : Colors.white.withValues(alpha: 0.85),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.glassBorder(isDark),
                                    width: 0.8,
                                  ),
                                ),
                                child: Icon(
                                  CupertinoIcons.slider_horizontal_3,
                                  size: 18,
                                  color: AppTheme.primaryText(isDark),
                                ),
                              ),
                              if (unreadTotal > 0 || filter != ConversationFilter.all)
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppTheme.primaryColor,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Center(
                                      child: Text(
                                        unreadTotal > 0 ? '$unreadTotal' : '!',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
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

                // Large Title "Messages" (Fades out and moves slightly on scroll)
                Positioned(
                  left: 16,
                  bottom: 6,
                  child: Opacity(
                    opacity: largeTitleOpacity,
                    child: Transform.translate(
                      offset: Offset(0, -shrinkOffset * 0.25),
                      child: Row(
                        children: [
                          Text(
                            'Messages',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.8,
                              color: AppTheme.primaryText(isDark),
                            ),
                          ),
                          if (isSyncing) ...[
                            const SizedBox(width: 10),
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ],
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

  @override
  bool shouldRebuild(_IosMessagesHeaderDelegate oldDelegate) {
    return oldDelegate.topPadding != topPadding ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isSyncing != isSyncing ||
        oldDelegate.unreadTotal != unreadTotal ||
        oldDelegate.filter != filter;
  }
}
