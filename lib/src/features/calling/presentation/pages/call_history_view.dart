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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0x991C1C1E)
            : Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.glassBorder(isDark),
          width: 0.6,
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
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

                // Date/Time & Call Button
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

        return CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // Glass persistent header with title & segment filter
            SliverPersistentHeader(
              pinned: true,
              delegate: _CallHistoryHeaderDelegate(
                topPadding: topPadding,
                isDark: isDark,
                filter: _filter,
                searchController: _searchController,
                onFilterChanged: (f) => setState(() => _filter = f),
                onRefresh: loadCallHistory,
              ),
            ),

            // Pull to Refresh
            CupertinoSliverRefreshControl(onRefresh: loadCallHistory),

            // Call log items
            if (_isLoading)
              SliverPadding(
                padding: const EdgeInsets.only(top: 8, bottom: 100),
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
                padding: const EdgeInsets.only(top: 8, bottom: 100),
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
  final ValueChanged<CallHistoryFilter> onFilterChanged;
  final Future<void> Function() onRefresh;

  _CallHistoryHeaderDelegate({
    required this.topPadding,
    required this.isDark,
    required this.filter,
    required this.searchController,
    required this.onFilterChanged,
    required this.onRefresh,
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
              // Header Title & Refresh Button
              Row(
                children: [
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
    return oldDelegate.filter != filter || oldDelegate.isDark != isDark;
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

