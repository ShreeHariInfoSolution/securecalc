import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/core/widgets/vault_edge_panel_wrapper.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/models/server_models.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import '../widgets/conversation_tile.dart';
import 'chat_detail_page.dart';

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
  int _selectedTab = 0; // 0: All, 1: Unread
  bool _showSearchBar = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _refreshServerChats();
  }

  Future<void> _refreshServerChats() async {
    if (widget.isDuressMode) return;
    if (mounted) setState(() => _isSyncing = true);
    try {
      await ServerChatManager.instance.syncChats();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
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
                                      final serverChat = await ServerApiService
                                          .instance
                                          .createDirectChat(u.id);
                                      if (serverChat.id <= 0) {
                                        throw Exception(
                                          'The server did not return a valid chat ID.',
                                        );
                                      }
                                      await LocalChatStorage.instance
                                          .createOrGetConversation(
                                            deviceId: serverChat.id.toString(),
                                            displayName: u.name,
                                            avatarUrl: u.avatar,
                                            peerUserId: u.id,
                                          );
                                      final cachedChats = await LocalChatStorage
                                          .instance
                                          .loadConversations();
                                      ChatConversation? cachedConversation;
                                      for (final chat in cachedChats) {
                                        if (chat.id ==
                                            serverChat.id.toString()) {
                                          cachedConversation = chat;
                                          break;
                                        }
                                      }
                                      final conversation =
                                          cachedConversation ??
                                          ChatConversation(
                                            id: serverChat.id.toString(),
                                            name: u.name,
                                            avatarUrl: u.avatar ?? '',
                                            lastMessage: 'Tap to start thread',
                                            lastMessageTime: 'Just now',
                                            lastActivityAt: DateTime.now(),
                                            unreadCount: 0,
                                            isPinned: false,
                                            peerUserId: u.id,
                                            messages: [],
                                          );
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
        backgroundColor: isDark
            ? AppTheme.darkBackground
            : AppTheme.lightBackground,
        body: SafeArea(
          child: ValueListenableBuilder<List<ChatConversation>>(
            valueListenable: LocalChatStorage.instance.conversationsNotifier,
            builder: (context, rawConversations, _) {
              final conversations =
                  widget.isDuressMode ? <ChatConversation>[] : rawConversations;
              final query = _searchController.text.trim().toLowerCase();
              final filtered =
                  conversations.where((conv) {
                    final matchesQuery =
                        conv.name.toLowerCase().contains(query) ||
                        conv.lastMessage.toLowerCase().contains(query);

                    if (_selectedTab == 1) {
                      return matchesQuery && conv.unreadCount > 0;
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

              return RefreshIndicator(
                onRefresh: _refreshServerChats,
                color: AppTheme.primaryColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // iOS Header Row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              if (Navigator.canPop(context)) ...[
                                GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    margin: const EdgeInsets.only(right: 10),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      size: 16,
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                              Text(
                                'Messages',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              if (_isSyncing) ...[
                                const SizedBox(width: 8),
                                const SizedBox(
                                  width: 14,
                                  height: 14,
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
                          Row(
                            children: [
                              // Search Round Button
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _showSearchBar = !_showSearchBar;
                                  });
                                  if (_showSearchBar) {
                                    _searchFocusNode.requestFocus();
                                  }
                                },
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF2C2C2E)
                                        : Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.3 : 0.08,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.search_rounded,
                                    color: AppTheme.primaryColor,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              /*
                              // Create a group conversation.
                              GestureDetector(
                                onTap: () => _showCreateGroupSheet(context),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF2C2C2E)
                                        : Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.3 : 0.08,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.group_add_rounded,
                                    color: AppTheme.primaryColor,
                                    size: 19,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              */

                              // New Chat Server User Search Button
                              GestureDetector(
                                onTap: () => _showUserSearchSheet(context),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primaryColor.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.edit_note_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Search Bar
                    if (_showSearchBar)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 6.0,
                        ),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1C1C1E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.3 : 0.04,
                                ),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
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
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    hintText: 'Search server chats',
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    hintStyle: TextStyle(
                                      color: AppTheme.subtitleGrey,
                                      fontSize: 15,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ),
                              if (_searchController.text.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _searchController.clear();
                                    });
                                  },
                                  child: const Icon(
                                    Icons.cancel_rounded,
                                    color: AppTheme.subtitleGrey,
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                    // Filter Tabs Row
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        children: [
                          _buildFilterTab(0, 'All'),
                          const SizedBox(width: 8),
                          _buildFilterTab(
                            1,
                            unreadTotal > 0 ? 'Unread $unreadTotal' : 'Unread',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Server Chat Tile List
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.forum_outlined,
                                      size: 44,
                                      color: AppTheme.subtitleGrey,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _searchController.text.isNotEmpty
                                          ? 'No results for "${_searchController.text}"'
                                          : 'No Server Conversations Yet',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.subtitleGrey,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Tap the edit button above to search users and start messaging.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.subtitleGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(
                                bottom: 24,
                                top: 2,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final conv = filtered[index];
                                return GestureDetector(
                                  onLongPress: () =>
                                      _showChatOptionsSheet(context, conv),
                                  child: ConversationTile(
                                    conversation: conv,
                                    isTyping: conv.isTyping,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              VaultEdgePanelWrapper(
                                            isDuressMode: widget.isDuressMode,
                                            child: ChatDetailPage(
                                                conversation: conv),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
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

  Widget _buildFilterTab(int index, String label) {
    final isSelected = _selectedTab == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor
              : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.subtitleGrey,
          ),
        ),
      ),
    );
  }
}
