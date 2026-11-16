import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/glass_kit.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import 'chat_bubble.dart';
import 'chat_wallpaper_widget.dart';
import 'sticker_picker_panel.dart';

/// iOS WhatsApp-style frosted glass peek preview dialog on long press in chat list.
class ChatPeekPreviewDialog extends StatefulWidget {
  final ChatConversation conversation;
  final VoidCallback onOpenChat;
  final bool isDuressMode;
  final Rect? originRect;
  final BuildContext? hostContext;

  const ChatPeekPreviewDialog({
    super.key,
    required this.conversation,
    required this.onOpenChat,
    this.originRect,
    this.hostContext,
    this.isDuressMode = false,
  });

  @override
  State<ChatPeekPreviewDialog> createState() => _ChatPeekPreviewDialogState();
}

class _ChatPeekPreviewDialogState extends State<ChatPeekPreviewDialog>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );

  static const _dismissDistance = 110.0;
  static const _spring = SpringDescription(mass: 1, stiffness: 420, damping: 30);
  bool _closing = false;
  bool _pastThreshold = false;

  List<ChatMessage> _last = const []; // newest first

  @override
  void initState() {
    super.initState();
    _enter.animateTo(1.0, curve: Curves.easeOutCubic);
    _loadMessages();
  }

  @override
  void dispose() {
    _enter.dispose();
    _drag.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    if (widget.isDuressMode) {
      if (mounted) setState(() => _last = const []);
      return;
    }

    final id = widget.conversation.id;
    // 1. Load local cached messages first so preview shows immediately
    final localList = await LocalChatStorage.instance.loadMessages(id);
    if (mounted && localList.isNotEmpty) {
      final tail = localList.length > 8 ? localList.sublist(localList.length - 8) : localList;
      setState(() => _last = tail.reversed.toList());
    }

    // 2. Fetch fresh messages from server for preview WITHOUT calling read API
    try {
      final fresh = await ServerChatManager.instance.loadMessages(id);
      if (!mounted) return;
      if (fresh.isNotEmpty) {
        final tail = fresh.length > 8 ? fresh.sublist(fresh.length - 8) : fresh;
        setState(() => _last = tail.reversed.toList());
      }
    } catch (_) {}
  }

  // ---------- Gestures (zero setState) ----------
  void _onDragUpdate(DragUpdateDetails d) {
    if (_closing) return;
    final v = _drag.value;
    final resist = (v <= 0 && d.delta.dy < 0) ? 0.25 : 1.0; // rubber band upward
    _drag.value = (v + d.delta.dy * resist).clamp(-24.0, 600.0);
    final past = _drag.value > _dismissDistance;
    if (past != _pastThreshold) {
      _pastThreshold = past;
      HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_closing) return;
    final vy = d.velocity.pixelsPerSecond.dy;
    if (_drag.value > _dismissDistance || vy > 800) {
      _dismiss(slide: true);
    } else {
      _drag.animateWith(SpringSimulation(_spring, _drag.value, 0, vy));
    }
  }

  Future<void> _dismiss({bool slide = false}) async {
    if (_closing) return;
    _closing = true;
    final h = MediaQuery.sizeOf(context).height;
    if (slide) {
      await _drag.animateTo(
        h * 0.5,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeInCubic,
      );
    } else {
      await _enter.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeIn,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Run a menu action after the exit animation so it feels smooth.
  Future<void> _act(FutureOr<void> Function() fn) async {
    await _dismiss();
    await fn();
  }

  bool _isMe(ChatMessage msg) {
    final currentUserIdStr = ServerApiService.instance.currentUserId?.toString();
    return msg.senderId == 'user' ||
        msg.senderId == 'me' ||
        (currentUserIdStr != null && msg.senderId == currentUserIdStr);
  }

  String _formatTime(DateTime date) {
    final hour24 = date.hour;
    final hour = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
    final min = date.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour:$min $period';
  }

  String _resolveRemoteMediaUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    String cleanPath = path;
    if (path.contains('uploads/')) {
      cleanPath = 'uploads/${path.split('uploads/').last}';
    } else if (path.contains('files/')) {
      cleanPath = 'files/${path.split('files/').last}';
    } else {
      cleanPath = path.split(RegExp(r'[/\\]')).last;
    }
    final normalized = cleanPath.replaceFirst(RegExp(r'^/+'), '');
    final apiBase = ServerApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final filePath = normalized.startsWith('api/files/')
        ? normalized.substring('api/files/'.length)
        : normalized.startsWith('files/')
            ? normalized.substring('files/'.length)
            : normalized;
    final encodedPath = filePath.split('/').map(Uri.encodeComponent).join('/');
    return '$apiBase/files/$encodedPath';
  }

  Widget _buildImageWidget(ChatMessage msg) {
    final url = msg.mediaUrl ?? '';
    if (url.isEmpty) return const SizedBox.shrink();

    Widget imgWidget;
    if (!url.startsWith('http://') &&
        !url.startsWith('https://') &&
        File(url).existsSync()) {
      imgWidget = Image.file(
        File(url),
        fit: BoxFit.cover,
        width: double.infinity,
        height: 120,
        cacheWidth: 400,
        cacheHeight: 300,
      );
    } else {
      final cached = AttachmentCacheService.instance.resolveLocalPathSync(url);
      if (cached != null && File(cached).existsSync()) {
        imgWidget = Image.file(
          File(cached),
          fit: BoxFit.cover,
          width: double.infinity,
          height: 120,
          cacheWidth: 400,
          cacheHeight: 300,
        );
      } else {
        final remoteUrl = _resolveRemoteMediaUrl(url);
        imgWidget = Image.network(
          remoteUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 120,
          cacheWidth: 400,
          cacheHeight: 300,
          errorBuilder: (context, error, stackTrace) => Container(
            height: 90,
            color: Colors.black12,
            child: const Center(
              child: Icon(
                Icons.broken_image_rounded,
                color: Colors.grey,
                size: 26,
              ),
            ),
          ),
        );
      }
    }

    return ClipRRect(borderRadius: BorderRadius.circular(10), child: imgWidget);
  }

  Widget _previewCard(bool isDark, double w, double h) {
    final conv = widget.conversation;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.7),
              width: 0.8,
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            children: [
              // Glass header
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppTheme.glassSurface(isDark),
                  border: Border(
                    bottom: BorderSide(
                      color: AppTheme.glassBorder(isDark),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    IosAvatar(
                      name: conv.name,
                      imagePath: conv.avatarUrl,
                      size: 34,
                      showOnline: false,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        conv.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryText(isDark),
                        ),
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 15,
                      color: AppTheme.secondaryText(isDark),
                    ),
                  ],
                ),
              ),
              // Wallpaper and last messages
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ChatWallpaperWidget(
                      chatId: conv.id,
                      isDark: isDark,
                      backgroundUrl: conv.backgroundUrl,
                    ),
                    if (_last.isEmpty)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.black : Colors.white)
                                .withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'No messages yet',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.secondaryText(isDark),
                            ),
                          ),
                        ),
                      )
                    else
                      ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (r) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                          stops: [0.0, 0.12],
                        ).createShader(r),
                        child: ListView.builder(
                          reverse: true, // newest at the bottom, shows what fits
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(8, 18, 8, 10),
                          itemCount: _last.length,
                          itemBuilder: (_, i) {
                            final m = _last[i];
                            final showTail = i == 0 || _isMe(_last[i - 1]) != _isMe(m);
                            return _PeekBubble(
                              msg: m,
                              isMe: _isMe(m),
                              isDark: isDark,
                              showTail: showTail,
                              maxW: w * 0.74,
                              chatId: conv.id,
                              time: _formatTime(m.timestamp),
                              imageBuilder: _buildImageWidget,
                            );
                          },
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

  List<_MenuItem> _menuItems(bool isDark) {
    final c = widget.conversation;
    final me = ServerApiService.instance.currentUserId;
    final peer = c.peerUserId ?? (c.isGroup ? null : int.tryParse(c.id));
    final canHide = !c.isGroup && peer != null && peer > 0 && peer != me;

    return [
      _MenuItem(
        c.unreadCount > 0 ? 'Mark as read' : 'Mark as unread',
        c.unreadCount > 0
            ? CupertinoIcons.chat_bubble
            : CupertinoIcons.chat_bubble_text,
        () => _act(() => LocalChatStorage.instance.toggleUnreadConversation(c.id)),
      ),
      _MenuItem(
        c.isArchived ? 'Unarchive' : 'Archive',
        CupertinoIcons.archivebox,
        () => _act(() => LocalChatStorage.instance.toggleArchiveConversation(c.id)),
      ),
      _MenuItem(
        c.isMuted ? 'Unmute' : 'Mute',
        c.isMuted ? CupertinoIcons.bell : CupertinoIcons.bell_slash,
        () => _act(() => LocalChatStorage.instance.toggleMuteConversation(c.id)),
      ),
      if (canHide)
        _MenuItem(
          c.isProfileHidden ? 'Show My Profile' : 'Hide My Profile',
          c.isProfileHidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
          () => _act(() async {
            final hide = !c.isProfileHidden;
            final ok = await ServerChatManager.instance
                .toggleProfileVisibility(c.id, peer, hide);
            if (ok) {
              AppToast.show(
                hide ? 'Profile hidden from user' : 'Profile visible to user',
              );
            }
          }),
        ),
      _MenuItem(
        c.isLocked ? 'Unlock chat' : 'Lock chat',
        c.isLocked ? CupertinoIcons.lock_open : CupertinoIcons.lock,
        () => _act(() async {
          final id = int.tryParse(c.id);
          if (id == null || id <= 0) return;
          final ok = c.isLocked
              ? await ServerChatManager.instance.unlockChat(id)
              : await ServerChatManager.instance.lockChat(id);
          AppToast.show(
            ok
                ? (c.isLocked ? 'Chat unlocked' : 'Chat locked')
                : 'Failed to ${c.isLocked ? "unlock" : "lock"} chat',
            isError: !ok,
          );
        }),
      ),
      _MenuItem(
        'Delete Chat',
        CupertinoIcons.trash,
        () => _act(_confirmDelete),
        destructive: true,
      ),
    ];
  }

  Future<void> _confirmDelete() async {
    final targetCtx = widget.hostContext ?? context;
    final ok = await showCupertinoDialog<bool>(
      context: targetCtx,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Chat'),
        content: Text('Delete conversation with ${widget.conversation.name}?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = int.tryParse(widget.conversation.id);
    if (id != null && id > 0) {
      await ServerApiService.instance.deleteChatREST(id, deleteChat: true);
    }
    await LocalChatStorage.instance.deleteConversation(widget.conversation.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);

    final items = _menuItems(isDark);
    final menuH = items.length * 46.0;
    final previewW = (size.width - 28.0).clamp(300.0, 420.0);
    final available = size.height - safe.top - safe.bottom - 24.0;
    final previewH = (available - menuH - 12.0).clamp(220.0, 420.0);
    final menuW = (size.width * 0.68).clamp(230.0, 275.0);
    final top = safe.top + 12.0;

    // Center offset from origin tile rect
    final originCenter = (widget.originRect != null && widget.originRect != Rect.zero)
        ? widget.originRect!.center
        : Offset(size.width / 2, size.height / 2);

    final fromOffset = originCenter -
        Offset(size.width / 2, top + previewH / 2);

    final previewCard = RepaintBoundary(
      child: _previewCard(isDark, previewW, previewH),
    );
    final menu = _GlassMenu(items: items, width: menuW);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop: blur and dim follow enter and drag
            AnimatedBuilder(
              animation: Listenable.merge([_enter, _drag]),
              builder: (_, __) {
                final k = _enter.value *
                    (1 - (_drag.value.clamp(0.0, 400.0) / 500.0)).clamp(0.0, 1.0);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismiss,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18 * k, sigmaY: 18 * k),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.38 * k),
                    ),
                  ),
                );
              },
            ),

            Positioned(
              top: top,
              left: 0,
              right: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // PREVIEW CARD
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: _onDragUpdate,
                      onVerticalDragEnd: _onDragEnd,
                      onTap: widget.onOpenChat,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_enter, _drag]),
                        child: previewCard,
                        builder: (_, child) {
                          final t = Curves.easeOutBack.transform(_enter.value);
                          final d = _drag.value;
                          final shrink = (d.clamp(0.0, 600.0) / 900.0).clamp(0.0, 0.12);
                          final scale = lerpDouble(0.35, 1.0, t)! * (1 - shrink);
                          final off = Offset.lerp(fromOffset, Offset.zero, t)! +
                              Offset(0, d);
                          return Opacity(
                            opacity: (_enter.value *
                                    (1 - (d.clamp(0.0, 400.0) / 420.0)))
                                .clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: off,
                              child: Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // MENU: hides on drag, returns when stable
                  Padding(
                    padding: EdgeInsets.only(left: (size.width - previewW) / 2),
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_enter, _drag]),
                      child: menu,
                      builder: (_, child) {
                        final land = Curves.easeOut.transform(
                          ((_enter.value - 0.45) / 0.55).clamp(0.0, 1.0),
                        );
                        final dragFade = (1 - _drag.value.abs() / 60.0).clamp(0.0, 1.0);
                        final m = land * dragFade;
                        return IgnorePointer(
                          ignoring: m < 0.9,
                          child: Opacity(
                            opacity: m,
                            child: Transform.translate(
                              offset: Offset(0, _drag.value * 0.35 - (1 - m) * 12),
                              child: Transform.scale(
                                scale: 0.94 + 0.06 * m,
                                alignment: Alignment.topLeft,
                                child: child,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeekBubble extends StatelessWidget {
  const _PeekBubble({
    required this.msg,
    required this.isMe,
    required this.isDark,
    required this.showTail,
    required this.maxW,
    required this.chatId,
    required this.time,
    required this.imageBuilder,
  });

  final ChatMessage msg;
  final bool isMe, isDark, showTail;
  final double maxW;
  final String chatId, time;
  final Widget Function(ChatMessage) imageBuilder;

  bool get _isLocation =>
      msg.type == 'location' ||
      msg.type == 'live_location' ||
      msg.msgType == 'location' ||
      msg.msgType == 'live_location' ||
      (msg.content.trim().startsWith('{') &&
          (msg.content.contains('"latitude"') ||
              msg.content.contains('"location_id"')));

  @override
  Widget build(BuildContext context) {
    final color = isMe
        ? AppPreferences.getChatBubbleColor(chatId: chatId)
        : AppTheme.receivedBubble(isDark);
    final fg = isMe ? Colors.white : (isDark ? Colors.white : Colors.black87);
    final fg2 = isMe ? Colors.white70 : (isDark ? Colors.white54 : Colors.black45);
    final tail = showTail ? 6.0 : 0.0;

    Widget body;
    if (_isLocation) {
      final live = msg.msgType == 'live_location' ||
          msg.type == 'live_location' ||
          msg.content.contains('"is_live":true') ||
          msg.content.contains('"isLive":true');
      body = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            live ? Icons.sensors_rounded : Icons.location_on_rounded,
            size: 18,
            color: live ? const Color(0xFFFF9500) : const Color(0xFFEA4335),
          ),
          const SizedBox(width: 6),
          Text(
            live ? 'Live location' : 'Location',
            style: TextStyle(fontSize: 14.5, color: fg),
          ),
        ],
      );
    } else if (msg.type.toLowerCase().contains('image') ||
        msg.type.toLowerCase() == 'photo' ||
        (msg.mediaUrl != null &&
            ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].any(
              (ext) => msg.mediaUrl!.toLowerCase().contains('.$ext'),
            ))) {
      body = SizedBox(
        width: maxW - 20,
        height: 120,
        child: imageBuilder(msg),
      );
    } else {
      body = EmojiText(
        msg.previewText.isNotEmpty ? msg.previewText : msg.content,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14.5, height: 1.22, color: fg),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: showTail ? 8 : 2,
          left: isMe ? 0 : (showTail ? 0 : 6),
          right: isMe ? (showTail ? 0 : 6) : 0,
        ),
        child: CustomPaint(
          painter: IMessageBubblePainter(
            color: color,
            isOutgoing: isMe,
            showTail: showTail,
          ),
          child: Container(
            constraints: BoxConstraints(maxWidth: maxW),
            padding: EdgeInsets.fromLTRB(
              10 + (isMe ? 0 : tail),
              6,
              10 + (isMe ? tail : 0),
              5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                body,
                const SizedBox(height: 1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time, style: TextStyle(fontSize: 10, color: fg2)),
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      Icon(
                        msg.isRead ? Icons.done_all : Icons.done,
                        size: 12,
                        color: fg2,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.label, this.icon, this.onTap, {this.destructive = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
}

class _GlassMenu extends StatelessWidget {
  const _GlassMenu({required this.items, required this.width});
  final List<_MenuItem> items;
  final double width;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      child: GlassSurface(
        radius: 20,
        blur: 30,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              _MenuRow(item: items[i]),
              if (i < items.length - 1)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: (dark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.10),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.item});
  final _MenuItem item;
  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = widget.item.destructive
        ? const Color(0xFFFF453A)
        : (dark ? Colors.white : Colors.black87);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.item.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: _down
            ? (dark ? Colors.white : Colors.black).withValues(alpha: 0.10)
            : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 16,
                  color: c,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Icon(widget.item.icon, size: 19, color: c),
          ],
        ),
      ),
    );
  }
}
