import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/core/widgets/vault_edge_panel_wrapper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:securecalc/src/features/chat/domain/entities/chat_conversation.dart';
import 'package:securecalc/src/features/chat/domain/models/server_models.dart';
import 'package:securecalc/src/features/chat/domain/services/call_service.dart';
import 'package:securecalc/src/features/chat/domain/services/local_chat_storage.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:securecalc/src/features/chat/presentation/pages/chat_detail_page.dart';

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
  int? _activeSwipedLogId;

  static final ValueNotifier<int> missedCallsNotifier = ValueNotifier<int>(0);
  static DateTime? _lastSeenMissedCallTime;
  static const String _prefLastSeenMissedKey = 'PREF_LAST_SEEN_MISSED_CALL_TIME';

  static Future<void> markMissedCallsAsSeen() async {
    _lastSeenMissedCallTime = DateTime.now();
    missedCallsNotifier.value = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _prefLastSeenMissedKey,
        _lastSeenMissedCallTime!.millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<void> initLastSeenTime() async {
    if (_lastSeenMissedCallTime != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_prefLastSeenMissedKey);
      if (ms != null && ms > 0) {
        _lastSeenMissedCallTime = DateTime.fromMillisecondsSinceEpoch(ms);
      } else {
        _lastSeenMissedCallTime = DateTime.now();
        await prefs.setInt(
          _prefLastSeenMissedKey,
          _lastSeenMissedCallTime!.millisecondsSinceEpoch,
        );
      }
    } catch (_) {}
  }

  static void onNewMissedCallReceived() {
    missedCallsNotifier.value = missedCallsNotifier.value + 1;
  }

  void _updateMissedCountNotifier() async {
    await initLastSeenTime();
    if (_lastSeenMissedCallTime == null) {
      missedCallsNotifier.value = 0;
      return;
    }
    final count = _callLogs.where((l) {
      if (!l.isMissed) return false;
      return l.createdDateTime.isAfter(_lastSeenMissedCallTime!);
    }).length;
    missedCallsNotifier.value = count;
  }

  @override
  void initState() {
    super.initState();
    _currentUserId = ServerApiService.instance.currentUserId;
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    markMissedCallsAsSeen();
    loadCallHistory();
  }

  @override
  void dispose() {
    _closeGlassMenu();
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
        _updateMissedCountNotifier();
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
        _updateMissedCountNotifier();

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
        _updateMissedCountNotifier();
      }
      AppToast.show('Call log deleted');
    } else {
      AppToast.show('Failed to delete call log', isError: true);
    }
  }

  Future<void> _deleteSelectedLogs() async {
    if (_selectedIds.isEmpty || _isDeleting) return;

    final count = _selectedIds.length;

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
        _updateMissedCountNotifier();
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
        _updateMissedCountNotifier();
        AppToast.show('Call history cleared');
      } else {
        AppToast.show('Failed to clear call history', isError: true);
      }
    }
  }

  Future<void> _confirmDeleteSingle(CallHistoryModel log) async {
    final confirm = await showCupertinoDialog<bool>(
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

    if (confirm == true) {
      await _deleteSingleLog(log);
    }
  }

  void _openMessageThread(CallHistoryModel log, List<ChatConversation> conversations) {
    final myId = _currentUserId ?? ServerApiService.instance.currentUserId;
    final peerId = log.getPeerUserId(myId);
    final peerName = _getPeerName(log, conversations);
    final peerAvatar = _getPeerAvatar(log, conversations);

    final convMatch = conversations.firstWhere(
      (c) => c.peerUserId == peerId || c.id == peerId.toString() || c.id == log.chatHeadId?.toString(),
      orElse: () => ChatConversation(
        id: (log.chatHeadId ?? peerId).toString(),
        name: peerName,
        avatarUrl: peerAvatar,
        lastMessage: '',
        lastMessageTime: '',
        unreadCount: 0,
        messages: const [],
      ),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VaultEdgePanelWrapper(
          isDuressMode: widget.isDuressMode,
          child: ChatDetailPage(conversation: convMatch),
        ),
      ),
    );
  }

  OverlayEntry? _currentMenuOverlay;

  void _closeGlassMenu() {
    _currentMenuOverlay?.remove();
    _currentMenuOverlay = null;
  }

  void _showGlassPopupMenu(BuildContext tileContext, CallHistoryModel log, List<ChatConversation> conversations) {
    _closeGlassMenu();

    final renderBox = tileContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _currentMenuOverlay = OverlayEntry(
      builder: (overlayContext) => _GlassPopupMenuOverlay(
        targetOffset: offset,
        targetSize: size,
        isDark: isDark,
        onDismiss: () {
          _closeGlassMenu();
        },
        children: [
          // 1. Message
          _buildGlassMenuItem(
            context: overlayContext,
            icon: CupertinoIcons.chat_bubble_fill,
            label: 'Message',
            showChevron: true,
            isDark: isDark,
            onTap: () {
              _closeGlassMenu();
              _openMessageThread(log, conversations);
            },
          ),

          Divider(
            height: 1,
            thickness: 0.6,
            color: AppTheme.glassBorder(isDark),
          ),

          // 2. Call
          _buildGlassMenuItem(
            context: overlayContext,
            icon: CupertinoIcons.phone_fill,
            label: 'Call',
            showChevron: true,
            isDark: isDark,
            onTap: () {
              _closeGlassMenu();
              _makeCall(log, conversations, CallType.voice);
            },
          ),

          Divider(
            height: 1,
            thickness: 0.6,
            color: AppTheme.glassBorder(isDark),
          ),

          // 3. Video
          _buildGlassMenuItem(
            context: overlayContext,
            icon: CupertinoIcons.videocam_fill,
            label: 'Video',
            showChevron: true,
            isDark: isDark,
            onTap: () {
              _closeGlassMenu();
              _makeCall(log, conversations, CallType.video);
            },
          ),

          Divider(
            height: 1,
            thickness: 0.6,
            color: AppTheme.glassBorder(isDark),
          ),

          // 4. Select
          _buildGlassMenuItem(
            context: overlayContext,
            icon: CupertinoIcons.checkmark_circle_fill,
            label: 'Select',
            showChevron: true,
            isDark: isDark,
            onTap: () {
              _closeGlassMenu();
              setState(() {
                _isSelectionMode = true;
                _selectedIds.add(log.id);
              });
            },
          ),

          Divider(
            height: 1,
            thickness: 0.6,
            color: AppTheme.glassBorder(isDark),
          ),

          // 5. Delete
          _buildGlassMenuItem(
            context: overlayContext,
            icon: CupertinoIcons.trash,
            iconColor: const Color(0xFFFF3B30),
            label: 'Delete',
            isDestructive: true,
            isDark: isDark,
            onTap: () {
              _closeGlassMenu();
              _confirmDeleteSingle(log);
            },
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_currentMenuOverlay!);
  }

  Widget _buildGlassMenuItem({
    required BuildContext context,
    required IconData icon,
    Color? iconColor,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
    bool showChevron = false,
    bool isDestructive = false,
  }) {
    final effectiveIconColor = iconColor ??
        (isDestructive
            ? const Color(0xFFFF3B30)
            : AppTheme.primaryText(isDark));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: effectiveIconColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: isDestructive
                      ? const Color(0xFFFF3B30)
                      : AppTheme.primaryText(isDark),
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (showChevron)
              Icon(
                CupertinoIcons.chevron_right,
                size: 12,
                color: AppTheme.secondaryText(isDark).withValues(alpha: 0.5),
              ),
          ],
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
        child: Builder(
          builder: (tileContext) {
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _makeCall(
                log,
                conversations,
                isVideo ? CallType.video : CallType.voice,
              ),
              onLongPress: () => _showGlassPopupMenu(tileContext, log, conversations),
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

                // Date/Time & Call Icon Button (matching call type)
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
                      GestureDetector(
                        onTap: () => _makeCall(
                          log,
                          conversations,
                          isVideo ? CallType.video : CallType.voice,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isVideo
                                ? const Color(0xFF34C759).withValues(alpha: 0.12)
                                : AppTheme.primaryColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                            size: 18,
                            color: isVideo
                                ? const Color(0xFF34C759)
                                : AppTheme.primaryColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  ),
);

    // Swipe-to-delete widget when NOT in multi-selection mode
    if (_isSelectionMode) {
      return tileContent;
    }

    return AppleSlideToDelete(
      key: ValueKey('call_log_${log.id}'),
      id: log.id,
      activeSwipedId: _activeSwipedLogId,
      onSwipeStarted: () {
        if (_activeSwipedLogId != log.id) {
          setState(() {
            _activeSwipedLogId = log.id;
          });
        }
      },
      enabled: !_isSelectionMode,
      onConfirmDelete: () async {
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
      onDelete: () {
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

        final missedCount = _callLogs.where((l) => l.isMissed).length;

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
                    missedCount: missedCount,
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
  final int missedCount;
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
    required this.missedCount,
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
                    if (totalCount > 0)
                      _GlassPill(
                        tint: const Color(0xFFFF3B30),
                        isDark: isDark,
                        onTap: onClearAllTap,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.trash, size: 14, color: Color(0xFFFF3B30)),
                            SizedBox(width: 5),
                            Text(
                              'Clear All',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF3B30),
                              ),
                            ),
                          ],
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
                        badgeCount: missedCount,
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
    int? badgeCount,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppTheme.primaryText(isDark)
                      : AppTheme.secondaryText(isDark),
                ),
              ),
              if (badgeCount != null && badgeCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
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
        oldDelegate.missedCount != missedCount ||
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

/// Apple/iOS style swipable tile that reveals a rounded stretching delete pill button.
class AppleSlideToDelete extends StatefulWidget {
  final int id;
  final int? activeSwipedId;
  final VoidCallback onSwipeStarted;
  final Widget child;
  final Future<bool?> Function() onConfirmDelete;
  final VoidCallback onDelete;
  final bool enabled;

  const AppleSlideToDelete({
    super.key,
    required this.id,
    required this.activeSwipedId,
    required this.onSwipeStarted,
    required this.child,
    required this.onConfirmDelete,
    required this.onDelete,
    this.enabled = true,
  });

  @override
  State<AppleSlideToDelete> createState() => _AppleSlideToDeleteState();
}

class _AppleSlideToDeleteState extends State<AppleSlideToDelete>
    with SingleTickerProviderStateMixin {
  static const double _bubble = 56.0;
  static const double _gap = 8.0;
  static const double _openOffset = _bubble + _gap;

  late final AnimationController _c; // value = how far the row is dragged (px)
  bool _isDeleting = false;
  bool _pastFull = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController.unbounded(vsync: this, value: 0);
  }

  @override
  void didUpdateWidget(AppleSlideToDelete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeSwipedId != widget.id &&
        oldWidget.activeSwipedId == widget.id &&
        _c.value > 0 &&
        !_isDeleting) {
      _springTo(0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  TickerFuture _springTo(double target, {double velocity = 0}) {
    return _c.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 380, damping: 32),
        _c.value,
        target,
        velocity,
      ),
    );
  }

  Future<void> _triggerDelete() async {
    if (_isDeleting) return;
    _isDeleting = true;
    _springTo(_openOffset);

    final confirm = await widget.onConfirmDelete();
    if (!mounted) return;

    if (confirm == true) {
      final w = MediaQuery.sizeOf(context).width;
      await _springTo(w);
      if (mounted) widget.onDelete();
    } else {
      _isDeleting = false;
      _springTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final w = MediaQuery.sizeOf(context).width;
    final fullThreshold = w * 0.5;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _c.stop(),
      onHorizontalDragUpdate: (d) {
        if (_isDeleting) return;
        if (_c.value <= 0 && d.delta.dx < 0) widget.onSwipeStarted();

        final v = math.max(0.0, _c.value - d.delta.dx);
        _c.value = v;

        final past = v >= fullThreshold;
        if (past != _pastFull) {
          _pastFull = past;
          HapticFeedback.mediumImpact();
        }
      },
      onHorizontalDragEnd: (d) {
        if (_isDeleting) return;
        final vel = -(d.primaryVelocity ?? 0); // + = moving left (opening)

        if (_c.value >= fullThreshold || vel > 1400) {
          _pastFull = false;
          _triggerDelete();
        } else if (_c.value > _openOffset / 2 || vel > 300) {
          _springTo(_openOffset, velocity: vel);
        } else {
          _springTo(0, velocity: vel);
        }
      },
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final o = math.max(0.0, _c.value);
          final progress = (o / _openOffset).clamp(0.0, 1.0);
          // Circle at rest, stretches into a pill on long swipe
          final bubbleWidth = o <= _openOffset
              ? _bubble
              : (o - _gap).clamp(_bubble, w - 32);
          final isOpen = o > 1;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (o > 0)
                Positioned(
                  right: 16, // same as tile's horizontal margin
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Opacity(
                      opacity: progress,
                      child: Transform.scale(
                        scale: 0.6 + 0.4 * progress,
                        alignment: Alignment.centerRight,
                        child: _GlassDeleteBubble(
                          width: bubbleWidth,
                          height: _bubble,
                          showLabel: bubbleWidth > 130,
                          onTap: _triggerDelete,
                        ),
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(-o, 0),
                child: isOpen
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _springTo(0), // tap row = close, no call
                        child: AbsorbPointer(child: child),
                      )
                    : child,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Red liquid-glass delete bubble
class _GlassDeleteBubble extends StatelessWidget {
  final double width;
  final double height;
  final bool showLabel;
  final VoidCallback onTap;

  const _GlassDeleteBubble({
    required this.width,
    required this.height,
    required this.showLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF3B30);
    final radius = BorderRadius.circular(height / 2);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: red.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    red.withValues(alpha: 0.88),
                    const Color(0xFFD70015).withValues(alpha: 0.78),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
              child: Stack(
                children: [
                  // glossy highlight on the top half
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: height * 0.5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.35),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.trash_fill,
                            color: Colors.white, size: 22),
                        if (showLabel) ...[
                          const SizedBox(width: 8),
                          const Text(
                            'Delete',
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Proper Apple Liquid Glass pill button with frosted blur & liquid specular highlights
class _GlassPill extends StatefulWidget {
  final Color tint;
  final bool isDark;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsets padding;

  const _GlassPill({
    required this.tint,
    required this.isDark,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
  });

  @override
  State<_GlassPill> createState() => _GlassPillState();
}

class _GlassPillState extends State<_GlassPill> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: widget.isDark ? 0.25 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: widget.isDark ? 0.16 : 0.55),
                      widget.tint.withValues(alpha: widget.isDark ? 0.12 : 0.08),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: widget.isDark ? 0.22 : 0.65),
                    width: 0.7,
                  ),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated position-anchored Glass Popup Menu Overlay
class _GlassPopupMenuOverlay extends StatefulWidget {
  final Offset targetOffset;
  final Size targetSize;
  final bool isDark;
  final VoidCallback onDismiss;
  final List<Widget> children;

  const _GlassPopupMenuOverlay({
    required this.targetOffset,
    required this.targetSize,
    required this.isDark,
    required this.onDismiss,
    required this.children,
  });

  @override
  State<_GlassPopupMenuOverlay> createState() => _GlassPopupMenuOverlayState();
}

class _GlassPopupMenuOverlayState extends State<_GlassPopupMenuOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _dismiss() async {
    await _animController.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const menuWidth = 195.0;
    const estimatedMenuHeight = 200.0;

    bool positionBelow = true;
    double top = widget.targetOffset.dy + widget.targetSize.height + 4;
    if (top + estimatedMenuHeight > screenSize.height - 80) {
      top = widget.targetOffset.dy - estimatedMenuHeight - 4;
      positionBelow = false;
    }

    // Position on the left side (aligned with left margin of the held item)
    double left = widget.targetOffset.dx + 16;
    if (left + menuWidth > screenSize.width - 16) {
      left = screenSize.width - menuWidth - 16;
    }
    if (left < 16) left = 16;

    return Stack(
      children: [
        // Transparent Barrier - Tap anywhere outside to dismiss cleanly
        Positioned.fill(
          child: GestureDetector(
            onTap: _dismiss,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),

        // Pop Menu anchored on the left side directly under the held item
        Positioned(
          top: top,
          left: left,
          width: menuWidth,
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              return Transform.scale(
                scale: 0.85 + (0.15 * _scaleAnim.value),
                alignment: positionBelow ? Alignment.topLeft : Alignment.bottomLeft,
                child: Opacity(
                  opacity: _fadeAnim.value,
                  child: Material(
                    color: Colors.transparent,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                        child: Container(
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? const Color(0xD9252528)
                                : Colors.white.withValues(alpha: 0.86),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: widget.isDark
                                  ? const Color(0x33FFFFFF)
                                  : const Color(0x22000000),
                              width: 0.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: widget.isDark ? 0.30 : 0.10,
                                ),
                                blurRadius: 16,
                                spreadRadius: 0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: widget.children,
                          ),
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
    );
  }
}
