import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/features/chat/domain/entities/chat_conversation.dart';
import 'package:securecalc/src/features/chat/domain/models/server_models.dart';
import 'package:securecalc/src/features/chat/domain/services/call_service.dart';
import 'package:securecalc/src/features/chat/domain/services/local_chat_storage.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';

enum CallHistoryFilter { all, missed }

class CallHistoryView extends StatefulWidget {
  final bool isDuressMode;

  const CallHistoryView({super.key, this.isDuressMode = false});

  @override
  State<CallHistoryView> createState() => CallHistoryViewState();
}

class CallHistoryViewState extends State<CallHistoryView> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<CallHistoryModel> _callLogs = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  CallHistoryFilter _filter = CallHistoryFilter.all;
  final Map<int, UserModel> _userCache = {};
  int? _currentUserId;

  // Multi-selection state
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = ServerApiService.instance.currentUserId;
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    loadCallHistory();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _scrollController.removeListener(_onScroll);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      if (maxScroll - currentScroll <= 200) {
        _loadMoreCallHistory();
      }
    }
  }

  Future<void> loadCallHistory() async {
    if (widget.isDuressMode) {
      if (mounted) {
        setState(() {
          _callLogs = [];
          _isLoading = false;
          _hasMore = false;
          _selectedIds.clear();
          _isSelectionMode = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _currentPage = 1;
        _hasMore = true;
      });
    }

    try {
      final res = await ServerApiService.instance.getCallHistoryPaginated(
        page: 1,
        limit: 20,
      );
      if (mounted) {
        setState(() {
          _callLogs = res.items;
          _hasMore = res.hasMore;
          _isLoading = false;
        });
      }
      unawaited(_resolvePeerUsers(res.items));
    } catch (e) {
      debugPrint('[CALL HISTORY] Failed to load call logs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreCallHistory() async {
    if (_isLoading || _isLoadingMore || !_hasMore || widget.isDuressMode) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    final nextPage = _currentPage + 1;
    try {
      final res = await ServerApiService.instance.getCallHistoryPaginated(
        page: nextPage,
        limit: 20,
      );
      if (mounted) {
        final existingIds = _callLogs.map((e) => e.id).toSet();
        final newItems = res.items.where((e) => !existingIds.contains(e.id)).toList();

        setState(() {
          _callLogs.addAll(newItems);
          _currentPage = nextPage;
          _hasMore = res.hasMore;
          _isLoadingMore = false;
        });

        unawaited(_resolvePeerUsers(newItems));
      }
    } catch (e) {
      debugPrint('[CALL HISTORY] Load more error: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _resolvePeerUsers(List<CallHistoryModel> logs) async {
    final myId = _currentUserId ?? ServerApiService.instance.currentUserId;
    final peerIdsToFetch = <int>{};

    for (final log in logs) {
      final peerId = log.getPeerUserId(myId);
      if (peerId > 0 && !_userCache.containsKey(peerId)) {
        peerIdsToFetch.add(peerId);
      }
    }

    for (final peerId in peerIdsToFetch) {
      try {
        final user = await ServerApiService.instance.getUser(peerId);
        if (user != null && mounted) {
          setState(() {
            _userCache[peerId] = user;
          });
        }
      } catch (_) {}
    }
  }

  String _getPeerName(CallHistoryModel log, List<ChatConversation> conversations) {
    final myId = _currentUserId ?? ServerApiService.instance.currentUserId;
    final peerId = log.getPeerUserId(myId);

    if (log.isOutgoing(myId) && log.calleeName?.isNotEmpty == true) {
      return log.calleeName!;
    }
    if (!log.isOutgoing(myId) && log.callerName?.isNotEmpty == true) {
      return log.callerName!;
    }

    final cachedUser = _userCache[peerId];
    if (cachedUser != null && cachedUser.name.isNotEmpty && !cachedUser.name.startsWith('User #')) {
      return cachedUser.name;
    }

    final convMatch = conversations.firstWhere(
      (c) => c.peerUserId == peerId || c.id == peerId.toString(),
      orElse: () => ChatConversation(
        id: '',
        name: '',
        avatarUrl: '',
        lastMessage: '',
        lastMessageTime: '',
        unreadCount: 0,
        messages: const [],
      ),
    );
    if (convMatch.name.isNotEmpty && !convMatch.name.startsWith('User #')) {
      return convMatch.name;
    }

    if (cachedUser != null) {
      if (cachedUser.phone?.isNotEmpty == true) return cachedUser.phone!;
      if (cachedUser.email?.isNotEmpty == true) return cachedUser.email!;
    }

    return peerId > 0 ? 'User #$peerId' : 'Unknown';
  }

  String _getPeerAvatar(CallHistoryModel log, List<ChatConversation> conversations) {
    final myId = _currentUserId ?? ServerApiService.instance.currentUserId;
    final peerId = log.getPeerUserId(myId);

    if (log.isOutgoing(myId) && log.calleeAvatar?.isNotEmpty == true) {
      return log.calleeAvatar!;
    }
    if (!log.isOutgoing(myId) && log.callerAvatar?.isNotEmpty == true) {
      return log.callerAvatar!;
    }

    final cachedUser = _userCache[peerId];
    if (cachedUser?.avatar?.isNotEmpty == true) {
      return cachedUser!.avatar!;
    }

    final convMatch = conversations.firstWhere(
      (c) => c.peerUserId == peerId || c.id == peerId.toString(),
      orElse: () => ChatConversation(
        id: '',
        name: '',
        avatarUrl: '',
        lastMessage: '',
        lastMessageTime: '',
        unreadCount: 0,
        messages: const [],
      ),
    );
    return convMatch.avatarUrl;
  }

  void _makeCall(CallHistoryModel log, List<ChatConversation> conversations, CallType type) {
    if (_isSelectionMode) {
      _toggleSelection(log.id);
      return;
    }

    final myId = _currentUserId ?? ServerApiService.instance.currentUserId;
    final peerId = log.getPeerUserId(myId);
    final peerName = _getPeerName(log, conversations);
    final peerAvatar = _getPeerAvatar(log, conversations);

    int chatHeadId = log.chatHeadId ?? 0;
    if (chatHeadId <= 0) {
      final convMatch = conversations.firstWhere(
        (c) => c.peerUserId == peerId || c.id == peerId.toString(),
        orElse: () => ChatConversation(
          id: '',
          name: '',
          avatarUrl: '',
          lastMessage: '',
          lastMessageTime: '',
          unreadCount: 0,
          messages: const [],
        ),
      );
      chatHeadId = int.tryParse(convMatch.id) ?? peerId;
    }

    if (chatHeadId <= 0) {
      AppToast.show('Unable to start call: Invalid chat ID', isError: true);
      return;
    }

    CallService.instance.startCall(
      chatHeadId: chatHeadId,
      type: type,
      name: peerName,
      avatar: peerAvatar,
      peerUserId: peerId,
    ).catchError((e) {
      if (mounted) {
        AppToast.show(AppToast.userFriendlyMessage('$e'), isError: true);
      }
    });
  }

  String _formatCallDate(DateTime date) {
    final now = DateTime.now();
    final localDate = date.toLocal();

    final hour12 = localDate.hour == 0
        ? 12
        : (localDate.hour > 12 ? localDate.hour - 12 : localDate.hour);
    final period = localDate.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = localDate.minute.toString().padLeft(2, '0');
    final timeStr = '$hour12:$minuteStr $period';

    if (localDate.year == now.year &&
        localDate.month == now.month &&
        localDate.day == now.day) {
      return timeStr;
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (localDate.year == yesterday.year &&
        localDate.month == yesterday.month &&
        localDate.day == yesterday.day) {
      return 'Yesterday, $timeStr';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[localDate.month - 1]} ${localDate.day}, $timeStr';
  }

  // ─── Selection Mode Handlers ────────────────────────────────────────────────

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<CallHistoryModel> currentFilteredLogs) {
    setState(() {
      final filteredIds = currentFilteredLogs.map((e) => e.id).toSet();
      if (_selectedIds.containsAll(filteredIds) && filteredIds.isNotEmpty) {
        _selectedIds.removeAll(filteredIds);
      } else {
        _selectedIds.addAll(filteredIds);
      }
    });
  }

  // ─── API Deletion Actions ───────────────────────────────────────────────────

  Future<void> _deleteSingleLog(CallHistoryModel log) async {
    final success = await ServerApiService.instance.deleteCallHistory(ids: [log.id]);
    if (success) {
      if (mounted) {
        setState(() {
          _callLogs.removeWhere((item) => item.id == log.id);
          _selectedIds.remove(log.id);
        });
      }
      AppToast.show('Call log deleted');
    } else {
      AppToast.show('Failed to delete call log', isError: true);
    }
  }

  Future<void> _deleteSelectedLogs() async {
    if (_selectedIds.isEmpty || _isDeleting) return;

    final count = _selectedIds.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Delete $count Call ${count == 1 ? 'Log' : 'Logs'}?'),
        content: Text(
          'Are you sure you want to delete ${count == 1 ? 'this call log' : 'the $count selected call logs'}? This action cannot be undone.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    final idsToDelete = _selectedIds.toList();
    final success = await ServerApiService.instance.deleteCallHistory(ids: idsToDelete);

    if (mounted) {
      setState(() => _isDeleting = false);
      if (success) {
        setState(() {
          _callLogs.removeWhere((item) => idsToDelete.contains(item.id));
          _selectedIds.clear();
          _isSelectionMode = false;
        });
        AppToast.show(count == 1 ? 'Call log deleted' : '$count call logs deleted');
      } else {
        AppToast.show('Failed to delete selected call logs', isError: true);
      }
    }
  }

  Future<void> _confirmClearAll() async {
    if (_callLogs.isEmpty || _isDeleting) return;

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Clear Call History?'),
        content: const Text(
          'Are you sure you want to clear all call history? This action cannot be undone.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Clear All'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    final success = await ServerApiService.instance.deleteCallHistory(clearAll: true);

    if (mounted) {
      setState(() => _isDeleting = false);
      if (success) {
        setState(() {
          _callLogs.clear();
          _selectedIds.clear();
          _isSelectionMode = false;
        });
        AppToast.show('Call history cleared');
      } else {
        AppToast.show('Failed to clear call history', isError: true);
      }
    }
  }

  void _showItemContextMenu(CallHistoryModel log, List<ChatConversation> conversations) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final myId = _currentUserId ?? ServerApiService.instance.currentUserId;
    final isVideo = log.callType.toLowerCase() == 'video';
    final peerName = _getPeerName(log, conversations);

    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(peerName),
        message: Text(_formatCallDate(log.createdDateTime)),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _makeCall(log, conversations, CallType.voice);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.phone_fill, size: 18),
                SizedBox(width: 8),
                Text('Voice Call'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _makeCall(log, conversations, CallType.video);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.videocam_fill, size: 18),
                SizedBox(width: 8),
                Text('Video Call'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isSelectionMode = true;
                _selectedIds.add(log.id);
              });
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.checkmark_circle, size: 18),
                SizedBox(width: 8),
                Text('Select'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              _deleteSingleLog(log);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.trash, size: 18),
                SizedBox(width: 8),
                Text('Delete Log'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  // ─── Call Log Tile Builder ──────────────────────────────────────────────────

  Widget _buildCallLogTile({
    required CallHistoryModel log,
    required List<ChatConversation> conversations,
    required bool isDark,
  }) {
    final myId = _currentUserId ?? ServerApiService.instance.currentUserId;
    final isOutgoing = log.isOutgoing(myId);
    final isVideo = log.callType.toLowerCase() == 'video';
    final isMissed = log.isMissed;
    final peerName = _getPeerName(log, conversations);
    final peerAvatar = _getPeerAvatar(log, conversations);

    final Color statusColor;
    final IconData directionIcon;

    if (isMissed) {
      statusColor = const Color(0xFFFF3B30);
      directionIcon = isVideo
          ? Icons.videocam_off_rounded
          : Icons.phone_missed_rounded;
    } else if (isOutgoing) {
      statusColor = const Color(0xFF34C759);
      directionIcon = isVideo
          ? Icons.videocam_rounded
          : Icons.call_made_rounded;
    } else {
      statusColor = const Color(0xFF34C759);
      directionIcon = isVideo
          ? Icons.videocam_rounded
          : Icons.call_received_rounded;
    }

    final directionText = isMissed
        ? (isVideo ? 'Missed video call' : 'Missed voice call')
        : (isOutgoing
            ? (isVideo ? 'Outgoing video call' : 'Outgoing voice call')
            : (isVideo ? 'Incoming video call' : 'Incoming voice call'));

    final durationStr = log.formattedDuration;
    final fullStatusText = (durationStr.isNotEmpty && durationStr != 'Ended' && durationStr != '0s' && !isMissed)
        ? '$directionText • $durationStr'
        : directionText;

    final isSelected = _selectedIds.contains(log.id);

    final tileContent = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5F0FF))
            : (isDark
                ? const Color(0x991C1C1E)
                : Colors.white.withValues(alpha: 0.82)),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected
              ? AppTheme.primaryColor
              : AppTheme.glassBorder(isDark),
          width: isSelected ? 1.5 : 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: isDark ? 0.25 : 0.04,
            ),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _makeCall(
            log,
            conversations,
            isVideo ? CallType.video : CallType.voice,
          ),
          onLongPress: () => _showItemContextMenu(log, conversations),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Selection Checkbox in Multi-Select Mode
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isSelectionMode ? 32 : 0,
                  child: _isSelectionMode
                      ? Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            isSelected
                                ? CupertinoIcons.checkmark_circle_fill
                                : CupertinoIcons.circle,
                            color: isSelected
                                ? AppTheme.primaryColor
                                : AppTheme.secondaryText(isDark),
                            size: 22,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                // User Avatar
                IosAvatar(
                  name: peerName,
                  imagePath: peerAvatar,
                  size: 48,
                ),
                const SizedBox(width: 14),

                // Peer Name & Call Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peerName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isMissed
                              ? const Color(0xFFFF3B30)
                              : AppTheme.primaryText(isDark),
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            directionIcon,
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              fullStatusText,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isMissed
                                    ? const Color(0xFFFF3B30).withValues(alpha: 0.9)
                                    : AppTheme.secondaryText(isDark),
                                fontWeight: isMissed
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Date/Time & Action Buttons
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatCallDate(log.createdDateTime),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.secondaryText(isDark),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (!_isSelectionMode)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => _makeCall(
                              log,
                              conversations,
                              CallType.voice,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.phone_rounded,
                                size: 17,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _makeCall(
                              log,
                              conversations,
                              CallType.video,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.videocam_rounded,
                                size: 17,
                                color: Color(0xFF34C759),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Swipe-to-delete widget when NOT in multi-selection mode
    if (_isSelectionMode) {
      return tileContent;
    }

    return Dismissible(
      key: ValueKey('call_log_${log.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B30),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(
              CupertinoIcons.trash,
              color: Colors.white,
              size: 22,
            ),
            SizedBox(width: 6),
            Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        return await showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Delete Call Log?'),
            content: const Text(
              'Are you sure you want to delete this call log?',
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context, false),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                child: const Text('Delete'),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        _deleteSingleLog(log);
      },
      child: tileContent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.paddingOf(context).top;

    return ValueListenableBuilder<List<ChatConversation>>(
      valueListenable: LocalChatStorage.instance.conversationsNotifier,
      builder: (context, rawConversations, _) {
        final conversations = widget.isDuressMode
            ? <ChatConversation>[]
            : rawConversations;

        final query = _searchController.text.trim().toLowerCase();

        final filteredLogs = _callLogs.where((log) {
          final peerName = _getPeerName(log, conversations).toLowerCase();
          final matchesQuery = query.isEmpty || peerName.contains(query);

          if (_filter == CallHistoryFilter.missed) {
            return matchesQuery && log.isMissed;
          }
          return matchesQuery;
        }).toList();

        final allFilteredSelected = filteredLogs.isNotEmpty &&
            _selectedIds.containsAll(filteredLogs.map((e) => e.id));

        return Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                // Glass persistent header with title, delete/multi-select actions & segment filter
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _CallHistoryHeaderDelegate(
                    topPadding: topPadding,
                    isDark: isDark,
                    filter: _filter,
                    searchController: _searchController,
                    isSelectionMode: _isSelectionMode,
                    selectedCount: _selectedIds.length,
                    totalCount: filteredLogs.length,
                    allFilteredSelected: allFilteredSelected,
                    onFilterChanged: (f) => setState(() => _filter = f),
                    onRefresh: loadCallHistory,
                    onToggleSelectionMode: _toggleSelectionMode,
                    onSelectAllToggle: () => _selectAll(filteredLogs),
                    onClearAllTap: _confirmClearAll,
                  ),
                ),

                // Pull to Refresh
                CupertinoSliverRefreshControl(onRefresh: loadCallHistory),

                // Call log items
                if (_isLoading)
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 8, bottom: 120),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => const CallHistoryShimmerTile(),
                        childCount: 8,
                      ),
                    ),
                  )
                else if (filteredLogs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF2C2C2E)
                                    : const Color(0xFFF2F2F7),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _filter == CallHistoryFilter.missed
                                    ? Icons.phone_missed_rounded
                                    : CupertinoIcons.phone_fill,
                                size: 34,
                                color: AppTheme.secondaryText(isDark),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _filter == CallHistoryFilter.missed
                                  ? 'No Missed Calls'
                                  : 'No Call History',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryText(isDark),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _filter == CallHistoryFilter.missed
                                  ? 'You have no missed voice or video calls.'
                                  : 'Voice and video calls you make or receive will appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.secondaryText(isDark),
                              ),
                            ),
                            const SizedBox(height: 70),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.only(
                      top: 8,
                      bottom: _isSelectionMode
                          ? (160 + (MediaQuery.paddingOf(context).bottom > 0 ? MediaQuery.paddingOf(context).bottom : 0))
                          : (100 + (MediaQuery.paddingOf(context).bottom > 0 ? MediaQuery.paddingOf(context).bottom : 0)),
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index < filteredLogs.length) {
                            final log = filteredLogs[index];
                            return _buildCallLogTile(
                              log: log,
                              conversations: conversations,
                              isDark: isDark,
                            );
                          }
                          return const CallHistoryShimmerTile();
                        },
                        childCount: filteredLogs.length + (_isLoadingMore ? 2 : 0),
                      ),
                    ),
                  ),
              ],
            ),

            // Selection Mode Bottom Floating Delete Action Bar
            if (_isSelectionMode)
              Positioned(
                left: 16,
                right: 16,
                bottom: (MediaQuery.paddingOf(context).bottom > 0
                        ? MediaQuery.paddingOf(context).bottom
                        : 10) +
                    84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xEE1C1C1E)
                            : Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppTheme.glassBorder(isDark),
                          width: 0.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${_selectedIds.length} Selected',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryText(isDark),
                            ),
                          ),
                          const Spacer(),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            color: const Color(0xFFFF3B30),
                            disabledColor: const Color(0xFFFF3B30).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(16),
                            onPressed: (_selectedIds.isNotEmpty && !_isDeleting)
                                ? _deleteSelectedLogs
                                : null,
                            child: _isDeleting
                                ? const CupertinoActivityIndicator(color: Colors.white)
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        CupertinoIcons.trash,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Delete (${_selectedIds.length})',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
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
}

class _CallHistoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double topPadding;
  final bool isDark;
  final CallHistoryFilter filter;
  final TextEditingController searchController;
  final bool isSelectionMode;
  final int selectedCount;
  final int totalCount;
  final bool allFilteredSelected;
  final ValueChanged<CallHistoryFilter> onFilterChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback onToggleSelectionMode;
  final VoidCallback onSelectAllToggle;
  final VoidCallback onClearAllTap;

  _CallHistoryHeaderDelegate({
    required this.topPadding,
    required this.isDark,
    required this.filter,
    required this.searchController,
    required this.isSelectionMode,
    required this.selectedCount,
    required this.totalCount,
    required this.allFilteredSelected,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onToggleSelectionMode,
    required this.onSelectAllToggle,
    required this.onClearAllTap,
  });

  @override
  double get minExtent => 104.0 + topPadding;

  @override
  double get maxExtent => 104.0 + topPadding;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: topPadding, left: 16, right: 16, bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.glassSurface(isDark),
            border: Border(
              bottom: BorderSide(
                color: AppTheme.glassBorder(isDark),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Header Title & Action Bar
              Row(
                children: [
                  if (isSelectionMode) ...[
                    // Select All Action
                    GestureDetector(
                      onTap: onSelectAllToggle,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE9E9EF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              allFilteredSelected
                                  ? CupertinoIcons.checkmark_square_fill
                                  : CupertinoIcons.square,
                              size: 16,
                              color: AppTheme.primaryColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              allFilteredSelected ? 'Deselect All' : 'Select All',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$selectedCount Selected',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryText(isDark),
                      ),
                    ),
                    const Spacer(),
                    // Cancel Selection Mode
                    GestureDetector(
                      onTap: onToggleSelectionMode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Calls',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryText(isDark),
                        letterSpacing: -0.6,
                      ),
                    ),
                    const Spacer(),
                    // Refresh Button
                    GestureDetector(
                      onTap: () => onRefresh(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFE9E9EF),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.arrow_clockwise,
                          size: 18,
                          color: AppTheme.primaryText(isDark),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Multi-select Edit Button
                    GestureDetector(
                      onTap: onToggleSelectionMode,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFE9E9EF),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.checkmark_circle,
                          size: 18,
                          color: AppTheme.primaryText(isDark),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Clear All Trash Button
                    GestureDetector(
                      onTap: onClearAllTap,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.trash,
                          size: 18,
                          color: Color(0xFFFF3B30),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),

              // Segmented Pill Filter (All | Missed)
              Container(
                height: 34,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildFilterTab(
                        title: 'All',
                        isSelected: filter == CallHistoryFilter.all,
                        onTap: () => onFilterChanged(CallHistoryFilter.all),
                      ),
                    ),
                    Expanded(
                      child: _buildFilterTab(
                        title: 'Missed',
                        isSelected: filter == CallHistoryFilter.missed,
                        onTap: () => onFilterChanged(CallHistoryFilter.missed),
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

  Widget _buildFilterTab({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? AppTheme.primaryText(isDark)
                  : AppTheme.secondaryText(isDark),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CallHistoryHeaderDelegate oldDelegate) {
    return oldDelegate.filter != filter ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isSelectionMode != isSelectionMode ||
        oldDelegate.selectedCount != selectedCount ||
        oldDelegate.totalCount != totalCount ||
        oldDelegate.allFilteredSelected != allFilteredSelected;
  }
}

class CallHistoryShimmerTile extends StatefulWidget {
  const CallHistoryShimmerTile({super.key});

  @override
  State<CallHistoryShimmerTile> createState() => _CallHistoryShimmerTileState();
}

class _CallHistoryShimmerTileState extends State<CallHistoryShimmerTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFE5E5EA);
    final highlightColor = isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFF2F2F7);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x991C1C1E) : Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppTheme.glassBorder(isDark),
              width: 0.6,
            ),
          ),
          child: Row(
            children: [
              _buildShimmerBox(
                width: 48,
                height: 48,
                borderRadius: 24,
                baseColor: baseColor,
                highlightColor: highlightColor,
              ),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildShimmerBox(
                      width: 120,
                      height: 16,
                      borderRadius: 8,
                      baseColor: baseColor,
                      highlightColor: highlightColor,
                    ),
                    const SizedBox(height: 8),
                    _buildShimmerBox(
                      width: 160,
                      height: 12,
                      borderRadius: 6,
                      baseColor: baseColor,
                      highlightColor: highlightColor,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildShimmerBox(
                    width: 55,
                    height: 12,
                    borderRadius: 6,
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildShimmerBox(
                        width: 30,
                        height: 30,
                        borderRadius: 15,
                        baseColor: baseColor,
                        highlightColor: highlightColor,
                      ),
                      const SizedBox(width: 8),
                      _buildShimmerBox(
                        width: 30,
                        height: 30,
                        borderRadius: 15,
                        baseColor: baseColor,
                        highlightColor: highlightColor,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    required double borderRadius,
    required Color baseColor,
    required Color highlightColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1.8 + (_controller.value * 3.6), 0),
            end: Alignment(-0.8 + (_controller.value * 3.6), 0),
            colors: [
              baseColor,
              highlightColor,
              baseColor,
            ],
            stops: const [0.2, 0.5, 0.8],
          ),
        ),
      ),
    );
  }
}
