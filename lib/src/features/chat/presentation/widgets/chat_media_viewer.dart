import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../../core/utils/app_toast.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/chat_media_downloader.dart';

// ─────────────────────────── controller + scope ───────────────────────────

bool _isVideoMsg(ChatMessage m) =>
    ChatMediaDownloader.kindOf(type: m.type, name: m.fileName, url: m.mediaUrl) ==
    MediaKind.video;

class ChatMediaController extends ChangeNotifier {
  String chatId = '';
  String chatName = '';
  void Function(ChatMessage)? onReply, onForward, onDelete;
  void Function(ChatMessage, String)? onReact;
  Future<bool> Function(ChatMessage)? onToggleStar;

  List<ChatMessage> _all = const [];
  String _sig = '';
  bool _disposed = false;

  static bool isMedia(ChatMessage m) {
    if (m.isDeleted || m.type == 'sticker') return false;
    final u = m.mediaUrl;
    if (u == null || u.isEmpty) return false;
    final k = ChatMediaDownloader.kindOf(type: m.type, name: m.fileName, url: u);
    return k == MediaKind.image || k == MediaKind.video;
  }

  List<ChatMessage> get media => _all.where(isMedia).toList();

  ChatMessage? byId(String id) {
    for (final m in _all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Called from ChatDetailPage.build(). Notifies only when something the viewer shows changed.
  void attach(List<ChatMessage> msgs) {
    _all = msgs;
    final b = StringBuffer();
    for (final m in msgs) {
      if (isMedia(m)) {
        b
          ..write(m.id)
          ..write(':')
          ..write(m.reaction)
          ..write(m.isSaved)
          ..write(m.status)
          ..write(m.mediaUrl)
          ..write(';');
      }
    }
    final s = b.toString();
    if (s == _sig) return;
    _sig = s;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  void react(ChatMessage m, String e) => onReact?.call(m, m.reaction == e ? '' : e);

  bool Function()? hasMore;
  Future<void> Function()? onLoadOlder;
  bool loadingOlder = false;

  Future<void> loadOlder() async {
    if (loadingOlder || onLoadOlder == null || hasMore?.call() != true) return;
    loadingOlder = true;
    if (!_disposed) notifyListeners();
    try {
      final before = media.length;
      var n = 0;
      // keep paging until at least one new media item shows up (older pages may be text-only)
      while (hasMore?.call() == true && n < 6) {
        n++;
        await onLoadOlder!();
        await WidgetsBinding.instance.endOfFrame;
        if (media.length > before) break;
      }
    } finally {
      loadingOlder = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ChatMediaScope extends InheritedWidget {
  final ChatMediaController controller;
  const ChatMediaScope({super.key, required this.controller, required super.child});

  static ChatMediaController? maybeOf(BuildContext c) =>
      c.getInheritedWidgetOfExactType<ChatMediaScope>()?.controller;

  @override
  bool updateShouldNotify(ChatMediaScope o) => controller != o.controller;
}

class _MediaRoute<T> extends PageRouteBuilder<T> {
  _MediaRoute(Widget page)
      : super(
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, a, __, child) {
            final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: c,
              child: ScaleTransition(
                scale: Tween(begin: 0.94, end: 1.0).animate(c),
                child: child,
              ),
            );
          },
        );
}

class ChatMediaViewer {
  static Future<void> openPager(
          BuildContext c, ChatMediaController ctl, ChatMessage m) =>
      Navigator.of(c).push(_MediaRoute(MediaPagerViewer(ctl: ctl, initialId: m.id)));

  static Future<void> openAlbum(
          BuildContext c, ChatMediaController ctl, List<ChatMessage> album) =>
      Navigator.of(c).push(
          _MediaRoute(MediaAlbumViewer(ctl: ctl, ids: album.map((e) => e.id).toList())));
}

// ─────────────────────────── helpers ───────────────────────────

class _Gate {
  static int _active = 0;
  static const _max = 3;
  static final _q = <Completer<void>>[];

  static Future<void> acquire() async {
    if (_active < _max) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _q.add(c);
    await c.future;
  }

  static void release() {
    if (_q.isNotEmpty) {
      _q.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}

class _MediaResolver {
  static final _futures = <String, Future<String?>>{};
  static final _memCache = <String, String>{};

  static String? localSync(ChatMessage m) {
    final url = m.mediaUrl ?? '';
    if (url.isEmpty) return null;
    final key = '${m.id}|$url';
    final mem = _memCache[key];
    if (mem != null && File(mem).existsSync()) return mem;

    if (!url.startsWith('http') && File(url).existsSync()) {
      _memCache[key] = url;
      return url;
    }
    final s = AttachmentCacheService.instance.resolveLocalPathSync(url);
    if (s != null && File(s).existsSync()) {
      _memCache[key] = s;
      return s;
    }
    return null;
  }

  static Future<String?> local(ChatMessage m) async {
    final syncP = localSync(m);
    if (syncP != null) return syncP;
    final url = m.mediaUrl ?? '';
    if (url.isEmpty) return null;
    final c = await AttachmentCacheService.instance.resolveLocalPath(url);
    if (c != null && File(c).existsSync()) {
      _memCache['${m.id}|$url'] = c;
      return c;
    }
    return null;
  }

  static Future<String?> resolve(String chatId, ChatMessage m) async {
    final syncP = localSync(m);
    if (syncP != null) return syncP;

    final key = '${m.id}|${m.mediaUrl}';
    return _futures[key] ??= _go(chatId, m).then((p) {
      if (p != null && File(p).existsSync()) {
        _memCache[key] = p;
        if (m.mediaUrl?.isNotEmpty == true) {
          AttachmentCacheService.instance.updateCache(m.mediaUrl!, p);
        }
        return p;
      } else {
        _futures.remove(key);
        return null;
      }
    });
  }

  static void invalidate(ChatMessage m) {
    final key = '${m.id}|${m.mediaUrl}';
    _futures.remove(key);
    _memCache.remove(key);
  }

  static Future<String?> _go(String chatId, ChatMessage m) async {
    final l = await local(m);
    if (l != null) return l;
    final url = m.mediaUrl ?? '';
    if (url.isEmpty) return null;
    final name = (m.fileName?.isNotEmpty == true) ? m.fileName! : url.split('/').last;

    await _Gate.acquire();
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final p = await ChatMediaDownloader.instance.fetch(
            mediaUrl: url,
            chatId: chatId,
            fileName: name,
            kind: _isVideoMsg(m) ? MediaKind.video : MediaKind.image,
          );
          if (File(p).existsSync()) {
            if (m.mediaUrl?.isNotEmpty == true) {
              AttachmentCacheService.instance.updateCache(m.mediaUrl!, p);
            }
            return p;
          }
        } catch (e) {
          debugPrint('[MEDIA VIEWER FETCH ERROR] attempt=$attempt $e');
        }
        await Future.delayed(const Duration(milliseconds: 600));
      }
      return null;
    } finally {
      _Gate.release();
    }
  }
}

class _Poster {
  static final _mem = <String, Future<Uint8List?>>{};
  static Future<Uint8List?> of(String path, {int w = 640}) =>
      _mem.putIfAbsent('$path@$w', () async {
        try {
          return await VideoThumbnail.thumbnailData(
              video: path, imageFormat: ImageFormat.JPEG, maxWidth: w, quality: 70);
        } catch (_) {
          return null;
        }
      });
}

String _fmtDate(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = t.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '${two(l.day)}/${two(l.month)}/${two(l.year % 100)}, $h:${two(l.minute)} ${l.hour >= 12 ? 'PM' : 'AM'}';
}

String _fmtTime(DateTime t) {
  final l = t.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour >= 12 ? 'PM' : 'AM'}';
}

String? _captionOf(ChatMessage m) {
  final c = m.content.trim();
  const generic = {'photo', 'video', 'sent a photo', 'sent a video', '[attachment]', 'gif'};
  if (c.isEmpty || generic.contains(c.toLowerCase())) return null;
  if (c.toLowerCase() == (m.fileName ?? '').toLowerCase()) return null;
  return c;
}

bool _hasReaction(ChatMessage m) =>
    m.reaction != null && m.reaction!.isNotEmpty && m.reaction != 'star';

void _replyFromViewer(BuildContext context, ChatMediaController ctl, ChatMessage m) {
  HapticFeedback.selectionClick();
  Navigator.of(context).popUntil((r) => r is! _MediaRoute);
  WidgetsBinding.instance.addPostFrameCallback((_) => ctl.onReply?.call(m));
}

Future<void> _shareMedia(ChatMediaController ctl, ChatMessage m) async {
  HapticFeedback.mediumImpact();
  final p = await _MediaResolver.resolve(ctl.chatId, m);
  if (p == null || !File(p).existsSync()) {
    AppToast.show('Media is not downloaded yet', isError: true);
    return;
  }
  await SharePlus.instance.share(ShareParams(files: [XFile(p)], text: _captionOf(m)));
}

// ─────────────────────────── small UI pieces ───────────────────────────

class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets? padding;
  const _Glass({required this.child, this.radius = 28, this.padding});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: child,
          ),
        ),
      );
}

class _GlassBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  const _GlassBtn(this.icon, this.onTap, {this.size = 46});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: _Glass(
          radius: size / 2,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: 22, color: onTap == null ? Colors.white30 : Colors.white),
          ),
        ),
      );
}

class _Pop extends StatelessWidget {
  final Widget child;
  final Alignment alignment;
  const _Pop({required this.child, this.alignment = Alignment.center});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutBack,
        child: child,
        builder: (_, v, c) => Opacity(
          opacity: v.clamp(0.0, 1.0).toDouble(),
          child: Transform.scale(scale: v, alignment: alignment, child: c),
        ),
      );
}

class _EmojiBar extends StatelessWidget {
  final String? current;
  final ValueChanged<String> onPick;
  const _EmojiBar({required this.current, required this.onPick});
  static const emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  @override
  Widget build(BuildContext context) => _Glass(
        radius: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in emojis)
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onPick(e);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: current == e ? Colors.white24 : Colors.transparent,
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 28)),
                ),
              ),
          ],
        ),
      );
}

class _Shimmer extends StatefulWidget {
  final double? height;
  final double? width;
  final double borderRadius;
  const _Shimmer({this.height, this.width, this.borderRadius = 0});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius > 0 ? BorderRadius.circular(widget.borderRadius) : null,
            gradient: LinearGradient(
              begin: Alignment(-2.0 + _c.value * 4, -0.2),
              end: Alignment(-0.5 + _c.value * 4, 0.2),
              colors: const [
                Color(0xFF1E1E20),
                Color(0xFF2C2C2E),
                Color(0xFF3B3B3E),
                Color(0xFF2C2C2E),
                Color(0xFF1E1E20),
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
            ),
          ),
        ),
      );
}

class _Thumb extends StatefulWidget {
  final ChatMessage msg;
  final String chatId;
  const _Thumb(this.msg, this.chatId);
  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late final bool _vid = _isVideoMsg(widget.msg);
  String? _path;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final syncP = _MediaResolver.localSync(widget.msg);
    if (syncP != null) {
      _path = syncP;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(_Thumb old) {
    super.didUpdateWidget(old);
    if (old.msg.id != widget.msg.id || old.msg.mediaUrl != widget.msg.mediaUrl) {
      final syncP = _MediaResolver.localSync(widget.msg);
      if (syncP != null) {
        setState(() {
          _path = syncP;
          _loading = false;
        });
      } else {
        _load();
      }
    }
  }

  Future<void> _load() async {
    final p = _vid
        ? await _MediaResolver.local(widget.msg)
        : await _MediaResolver.resolve(widget.chatId, widget.msg);
    if (!mounted) return;
    setState(() {
      _path = p;
      _loading = false;
    });
  }

  Widget get _empty => const ColoredBox(
        color: Color(0xFF2C2C2E),
        child: Center(
            child: Icon(CupertinoIcons.photo, size: 14, color: Colors.white38)),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _Shimmer(borderRadius: 7);
    final p = _path;
    if (p == null) {
      return _vid
          ? const ColoredBox(
              color: Color(0xFF2C2C2E),
              child: Center(
                  child: Icon(CupertinoIcons.videocam_fill,
                      size: 16, color: Colors.white54)))
          : _empty;
    }
    if (_vid) {
      return Stack(fit: StackFit.expand, children: [
        FutureBuilder<Uint8List?>(
          future: _Poster.of(p, w: 120),
          builder: (_, ps) => ps.data == null
              ? const _Shimmer(borderRadius: 7)
              : Image.memory(ps.data!, fit: BoxFit.cover, gaplessPlayback: true),
        ),
        const Positioned(
            left: 4,
            bottom: 3,
            child: Icon(CupertinoIcons.videocam_fill,
                size: 12, color: Colors.white)),
      ]);
    }
    return Image.file(File(p),
        fit: BoxFit.cover, cacheWidth: 120, errorBuilder: (_, __, ___) => _empty);
  }
}

// ─────────────────────────── actions menu (long-press / ⋯) ───────────────────────────

Future<void> showMediaActions(
    BuildContext context, ChatMediaController ctl, ChatMessage m) {
  HapticFeedback.mediumImpact();
  final serverMsg = int.tryParse(m.id) != null;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Media actions',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (_, a, __, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    pageBuilder: (dc, _, __) {
      Widget row(IconData i, String t, VoidCallback f, {Color? color}) => InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pop(dc);
              f();
            },
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Icon(i, size: 20, color: color ?? Colors.white),
                  const SizedBox(width: 14),
                  Text(t,
                      style: TextStyle(
                          color: color ?? Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none)),
                ]),
              ),
            ),
          );
      final div = Divider(height: 1, thickness: 0.5, color: Colors.white.withValues(alpha: 0.12));

      final rows = <Widget>[
        if (serverMsg && ctl.onReply != null) ...[
          row(CupertinoIcons.reply, 'Reply', () => _replyFromViewer(context, ctl, m)),
          div,
        ],
        if (ctl.onForward != null) ...[
          row(CupertinoIcons.arrowshape_turn_up_right, 'Forward', () => ctl.onForward!(m)),
          div,
        ],
        row(CupertinoIcons.share, 'Share', () => _shareMedia(ctl, m)),
        if (ctl.onToggleStar != null) ...[
          div,
          row(m.isSaved ? CupertinoIcons.star_fill : CupertinoIcons.star,
              m.isSaved ? 'Unstar' : 'Star', () => ctl.onToggleStar!(m),
              color: m.isSaved ? const Color(0xFFFFD60A) : null),
        ],
        if (serverMsg && ctl.onDelete != null) ...[
          div,
          row(CupertinoIcons.trash, 'Delete', () => ctl.onDelete!(m),
              color: const Color(0xFFFF453A)),
        ],
      ];

      return Material(
        color: Colors.transparent,
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(dc),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: const ColoredBox(color: Colors.black38),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (ctl.onReact != null)
                  _Pop(
                    child: _EmojiBar(
                      current: m.reaction,
                      onPick: (e) {
                        Navigator.pop(dc);
                        ctl.react(m, e);
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                _Pop(
                  child: Container(
                    width: 240,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xEE2C2C2E),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: rows),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      );
    },
  );
}

// ═══════════════════════════ PAGER VIEWER ═══════════════════════════

class MediaPagerViewer extends StatefulWidget {
  final ChatMediaController ctl;
  final String initialId;
  const MediaPagerViewer({super.key, required this.ctl, required this.initialId});

  @override
  State<MediaPagerViewer> createState() => _MediaPagerViewerState();
}

class _MediaPagerViewerState extends State<MediaPagerViewer>
    with TickerProviderStateMixin {
  static const double _slot = 52;
  static const _speeds = [1.0, 1.5, 2.0, 0.5];

  late List<ChatMessage> _items;
  late int _index;
  late String _curId;
  late final PageController _page;
  final ScrollController _thumbs = ScrollController();

  bool _chrome = true, _zoomed = false, _picker = false, _ended = false;
  double _dy = 0, _snapFrom = 0, _speed = 1;
  Timer? _hide;

  VideoPlayerController? _vc;
  String? _vcId, _failedId;
  int _gen = 0;

  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() =>
      setState(() => _dy = _snapFrom * (1 - Curves.easeOutCubic.transform(_snap.value))));

  ChatMessage get _msg => _items[_index];

  @override
  void initState() {
    super.initState();
    _items = widget.ctl.media;
    _index = math.max(0, _items.indexWhere((m) => m.id == widget.initialId));
    _curId = _items.isEmpty ? '' : _items[_index].id;
    _page = PageController(initialPage: _index);
    widget.ctl.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_items.isEmpty) {
        Navigator.of(context).maybePop();
        return;
      }
      _centerThumb(animate: false);
      _activate();
      widget.ctl.loadOlder();
    });
  }

  @override
  void dispose() {
    widget.ctl.removeListener(_sync);
    _hide?.cancel();
    _snap.dispose();
    _page.dispose();
    _thumbs.dispose();
    _vc?.removeListener(_tick);
    _vc?.dispose();
    super.dispose();
  }

  // ── data sync (reaction / star / delete / new messages) ──
  void _sync() {
    if (!mounted) return;
    final next = widget.ctl.media;
    if (next.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    var i = next.indexWhere((m) => m.id == _curId);
    final removed = i < 0;
    if (removed) i = math.min(_index, next.length - 1);
    setState(() => _items = next);
    if (i != _index || removed) {
      _index = i;
      _curId = next[i].id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_page.hasClients) _page.jumpToPage(i);
        _centerThumb(animate: false);
      });
      _activate();
    }
  }

  // ── video (one controller, only for the visible page) ──
  Future<void> _activate() async {
    final gen = ++_gen;
    final old = _vc;
    old?.removeListener(_tick);
    setState(() {
      _vc = null;
      _vcId = null;
      _failedId = null;
      _ended = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());

    final m = _msg;
    if (!_isVideoMsg(m)) return;
    final path = await _MediaResolver.resolve(widget.ctl.chatId, m);
    if (!mounted || gen != _gen) return;
    if (path == null) {
      setState(() => _failedId = m.id);
      return;
    }
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
    } catch (e) {
      debugPrint('[PAGER VIDEO INIT ERROR] $e');
      await c.dispose();
      if (mounted && gen == _gen) setState(() => _failedId = m.id);
      return;
    }
    if (!mounted || gen != _gen) {
      await c.dispose();
      return;
    }
    c.addListener(_tick);
    await c.setPlaybackSpeed(_speed);
    setState(() {
      _vc = c;
      _vcId = m.id;
    });
    await c.play();
    _scheduleHide();
  }

  void _tick() {
    final v = _vc?.value;
    if (v == null) return;
    final ended = v.duration > Duration.zero && v.position >= v.duration;
    if (ended != _ended && mounted) {
      setState(() {
        _ended = ended;
        if (ended) {
          _chrome = true;
          _hide?.cancel();
        }
      });
    }
  }

  Future<void> _togglePlay() async {
    final c = _vc;
    if (c == null) return;
    HapticFeedback.lightImpact();
    if (c.value.isPlaying) {
      await c.pause();
      _hide?.cancel();
      if (mounted) setState(() => _chrome = true);
    } else {
      if (_ended) await c.seekTo(Duration.zero);
      await c.play();
      _scheduleHide();
    }
  }

  void _seek(int seconds) {
    final c = _vc;
    if (c == null) return;
    HapticFeedback.selectionClick();
    final t = c.value.position + Duration(seconds: seconds);
    final max = c.value.duration;
    c.seekTo(t < Duration.zero ? Duration.zero : (t > max ? max : t));
  }

  void _cycleSpeed() {
    HapticFeedback.selectionClick();
    _speed = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    _vc?.setPlaybackSpeed(_speed);
    setState(() {});
    _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_vc?.value.isPlaying ?? false) && !_picker) {
        setState(() => _chrome = false);
      }
    });
  }

  void _toggleChrome() {
    if (_picker) {
      setState(() => _picker = false);
      return;
    }
    setState(() => _chrome = !_chrome);
    if (_chrome) _scheduleHide();
  }

  // ── paging ──
  void _onPage(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = i;
      _curId = _items[i].id;
      _zoomed = false;
      _picker = false;
    });
    _centerThumb();
    _activate();
    if (i < 6 || i >= _items.length - 3) widget.ctl.loadOlder();
  }

  void _goTo(int i) {
    HapticFeedback.selectionClick();
    if ((i - _index).abs() > 2) {
      _page.jumpToPage(i);
    } else {
      _page.animateToPage(i,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  }

  void _centerThumb({bool animate = true}) {
    if (!_thumbs.hasClients) return;
    final t = (_index * _slot).clamp(0.0, _thumbs.position.maxScrollExtent).toDouble();
    animate
        ? _thumbs.animateTo(t,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic)
        : _thumbs.jumpTo(t);
  }

  // ── drag to dismiss ──
  void _dragUpdate(DragUpdateDetails d) {
    _snap.stop();
    setState(() => _dy += d.delta.dy);
  }

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dy.abs() > 110 || v.abs() > 800) {
      HapticFeedback.lightImpact();
      _vc?.pause();
      Navigator.of(context).pop();
    } else {
      _snapFrom = _dy;
      _snap.forward(from: 0);
    }
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final m = _msg;
    final p = (_dy.abs() / 300).clamp(0.0, 1.0).toDouble();
    final chromeOpacity = _chrome ? (1 - p * 3).clamp(0.0, 1.0).toDouble() : 0.0;
    final isVid = _isVideoMsg(m);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - p * 0.9),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleChrome,
        onLongPress: () => showMediaActions(context, widget.ctl, m),
        onVerticalDragUpdate: _zoomed ? null : _dragUpdate,
        onVerticalDragEnd: _zoomed ? null : _dragEnd,
        child: Stack(children: [
          Transform.translate(
            offset: Offset(0, _dy),
            child: Transform.scale(
              scale: 1 - p * 0.12,
              child: PageView.builder(
                controller: _page,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                itemCount: _items.length,
                onPageChanged: _onPage,
                itemBuilder: (_, i) {
                  final it = _items[i];
                  if (_isVideoMsg(it)) {
                    return _VideoPage(
                      key: ValueKey(it.id),
                      msg: it,
                      chatId: widget.ctl.chatId,
                      controller: _vcId == it.id ? _vc : null,
                      failed: _failedId == it.id,
                      onTogglePlay: _togglePlay,
                      onSeek: _seek,
                    );
                  }
                  return _ImagePage(
                    key: ValueKey(it.id),
                    msg: it,
                    chatId: widget.ctl.chatId,
                    onZoom: (z) {
                      if (z != _zoomed) setState(() => _zoomed = z);
                    },
                  );
                },
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: AnimatedOpacity(
                opacity: chromeOpacity,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: chromeOpacity < 0.5,
                  child: Column(children: [
                    AnimatedSlide(
                      offset: _chrome ? Offset.zero : const Offset(0, -0.4),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Column(children: [
                        _top(m),
                        if (isVid && _vc != null && _vcId == m.id)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: _VideoPill(
                              c: _vc!,
                              ended: _ended,
                              speed: _speed,
                              onToggle: _togglePlay,
                              onSpeed: _cycleSpeed,
                              onScrubStart: () => _hide?.cancel(),
                              onScrubEnd: _scheduleHide,
                            ),
                          ),
                      ]),
                    ),
                    const Spacer(),
                    AnimatedSlide(
                      offset: _chrome ? Offset.zero : const Offset(0, 0.3),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: _bottom(m),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _top(ChatMessage m) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Row(children: [
          _GlassBtn(CupertinoIcons.back, () => Navigator.of(context).pop()),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(m.senderId == 'user' ? 'You' : widget.ctl.chatName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              Text(_fmtDate(m.timestamp),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          _GlassBtn(CupertinoIcons.ellipsis, () => showMediaActions(context, widget.ctl, m)),
        ]),
      );

  Widget _bottom(ChatMessage m) {
    final ctl = widget.ctl;
    final reacted = _hasReaction(m);
    final cap = _captionOf(m);
    final canReply = ctl.onReply != null && int.tryParse(m.id) != null;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_picker && ctl.onReact != null)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _Pop(
              alignment: Alignment.bottomLeft,
              child: _EmojiBar(
                current: m.reaction,
                onPick: (e) {
                  setState(() => _picker = false);
                  ctl.react(m, e);
                },
              ),
            ),
          ),
        ),
      if (cap != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(cap,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          if (ctl.onReact != null)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _picker = !_picker);
              },
              child: _Glass(
                radius: 22,
                child: SizedBox(
                  width: reacted ? 52 : 42,
                  height: 42,
                  child: Center(
                    child: reacted
                        ? Text(m.reaction!, style: const TextStyle(fontSize: 22))
                        : const Icon(CupertinoIcons.smiley, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          const Spacer(),
          if (canReply)
            GestureDetector(
              onTap: () => _replyFromViewer(context, ctl, m),
              child: const _Glass(
                radius: 22,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(CupertinoIcons.reply, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('Reply',
                      style: TextStyle(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]),
      ),
      if (_items.length > 1) _thumbStrip(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _GlassBtn(CupertinoIcons.share, () => _shareMedia(ctl, m), size: 52),
          _Glass(
            radius: 28,
            child: Row(children: [
              IconButton(
                onPressed: ctl.onForward == null ? null : () => ctl.onForward!(m),
                icon: Icon(CupertinoIcons.arrowshape_turn_up_right,
                    color: ctl.onForward == null ? Colors.white30 : Colors.white),
              ),
              IconButton(
                onPressed: ctl.onToggleStar == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        ctl.onToggleStar!(m);
                      },
                icon: Icon(m.isSaved ? CupertinoIcons.star_fill : CupertinoIcons.star,
                    color: m.isSaved
                        ? const Color(0xFFFFD60A)
                        : (ctl.onToggleStar == null ? Colors.white30 : Colors.white)),
              ),
            ]),
          ),
          _GlassBtn(CupertinoIcons.trash,
              (ctl.onDelete == null || int.tryParse(m.id) == null)
                  ? null
                  : () => ctl.onDelete!(m),
              size: 52),
        ]),
      ),
    ]);
  }

  Widget _thumbStrip() => SizedBox(
        height: 64,
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (_, cs) => ListView.builder(
                controller: _thumbs,
                physics: const BouncingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                itemExtent: _slot,
                padding: EdgeInsets.symmetric(horizontal: math.max(0.0, (cs.maxWidth - _slot) / 2)),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final sel = i == _index;
                  return GestureDetector(
                    key: ValueKey(_items[i].id),
                    onTap: () => _goTo(i),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        width: sel ? 46 : 38,
                        height: sel ? 58 : 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color: sel ? Colors.white : Colors.transparent, width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: _Thumb(_items[i], widget.ctl.chatId),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.ctl.loadingOlder)
              const Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: CupertinoActivityIndicator(color: Colors.white, radius: 8),
                ),
              ),
          ],
        ),
      );
}

// ── image page (pinch + double-tap zoom) ──
class _ImagePage extends StatefulWidget {
  final ChatMessage msg;
  final String chatId;
  final ValueChanged<bool> onZoom;
  const _ImagePage(
      {super.key, required this.msg, required this.chatId, required this.onZoom});

  @override
  State<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<_ImagePage> with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  Animation<Matrix4>? _mat;
  String? _path;
  bool _loading = true;
  Offset _tapAt = Offset.zero;
  bool _zoom = false;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_mat != null) {
        _tc.value = _mat!.value;
        _check();
      }
    });
    final syncP = _MediaResolver.localSync(widget.msg);
    if (syncP != null) {
      _path = syncP;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(_ImagePage old) {
    super.didUpdateWidget(old);
    if (old.msg.id != widget.msg.id || old.msg.mediaUrl != widget.msg.mediaUrl) {
      final syncP = _MediaResolver.localSync(widget.msg);
      if (syncP != null) {
        setState(() {
          _path = syncP;
          _loading = false;
        });
      } else {
        _load();
      }
    }
  }

  Future<void> _load({bool force = false}) async {
    if (force) {
      _MediaResolver.invalidate(widget.msg);
      setState(() => _loading = true);
    }
    final p = await _MediaResolver.resolve(widget.chatId, widget.msg);
    if (!mounted) return;
    setState(() {
      _path = p;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _check() {
    final z = _tc.value.getMaxScaleOnAxis() > 1.03;
    if (z != _zoom) {
      _zoom = z;
      widget.onZoom(z);
    }
  }

  void _doubleTap() {
    HapticFeedback.selectionClick();
    final begin = _tc.value;
    final zoomed = begin.getMaxScaleOnAxis() > 1.03;
    const s = 2.5;
    final end = zoomed
        ? Matrix4.identity()
        : (Matrix4.translationValues(-_tapAt.dx * (s - 1), -_tapAt.dy * (s - 1), 0)
          ..multiply(Matrix4.diagonal3Values(s, s, 1)));
    _mat = Matrix4Tween(begin: begin, end: end)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CupertinoActivityIndicator(color: Colors.white, radius: 14));
    }
    final p = _path;
    if (p == null) return _error();
    return GestureDetector(
      onDoubleTapDown: (d) => _tapAt = d.localPosition,
      onDoubleTap: _doubleTap,
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 5,
        onInteractionUpdate: (_) => _check(),
        onInteractionEnd: (_) => _check(),
        child: Center(
          child: Image.file(File(p),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _error()),
        ),
      ),
    );
  }

  Widget _error() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.broken_image_rounded, size: 48, color: Colors.white38),
          const SizedBox(height: 10),
          const Text('Could not load photo',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 10),
          CupertinoButton(
            color: Colors.white24,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            borderRadius: BorderRadius.circular(20),
            onPressed: () => _load(force: true),
            child: const Text('Retry', style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ]),
      );
}

// ── video page (poster → video, big play button, double-tap ±10s) ──
class _VideoPage extends StatefulWidget {
  final ChatMessage msg;
  final String chatId;
  final VideoPlayerController? controller;
  final bool failed;
  final VoidCallback onTogglePlay;
  final ValueChanged<int> onSeek;
  const _VideoPage({
    super.key,
    required this.msg,
    required this.chatId,
    required this.controller,
    required this.failed,
    required this.onTogglePlay,
    required this.onSeek,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final Future<String?> _path = _MediaResolver.resolve(widget.chatId, widget.msg);
  double _tapX = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return LayoutBuilder(
      builder: (_, cs) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTapDown: (d) => _tapX = d.localPosition.dx,
        onDoubleTap: c == null ? null : () => widget.onSeek(_tapX < cs.maxWidth / 2 ? -10 : 10),
        child: Stack(fit: StackFit.expand, children: [
          FutureBuilder<String?>(
            future: _path,
            builder: (_, s) {
              final p = s.data;
              if (p == null) return const SizedBox.shrink();
              return FutureBuilder<Uint8List?>(
                future: _Poster.of(p),
                builder: (_, ps) => ps.data == null
                    ? const SizedBox.shrink()
                    : Image.memory(ps.data!, fit: BoxFit.contain, gaplessPlayback: true),
              );
            },
          ),
          if (c != null)
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
                child: VideoPlayer(c),
              ),
            )
          else if (widget.failed)
            const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                SizedBox(height: 10),
                Text('Unable to play video',
                    style: TextStyle(color: Colors.white, fontSize: 15)),
              ]),
            )
          else
            const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14)),
          if (c != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (_, v, __) => IgnorePointer(
                ignoring: v.isPlaying,
                child: AnimatedOpacity(
                  opacity: v.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: Center(
                    child: GestureDetector(
                      onTap: widget.onTogglePlay,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.88)),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.play_arrow_rounded,
                              size: 46, color: Color(0xFF2C2C2E)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ── pill under the header (pause / time / slider / -time / speed) ──
class _VideoPill extends StatefulWidget {
  final VideoPlayerController c;
  final bool ended;
  final double speed;
  final VoidCallback onToggle, onSpeed, onScrubStart, onScrubEnd;
  const _VideoPill({
    required this.c,
    required this.ended,
    required this.speed,
    required this.onToggle,
    required this.onSpeed,
    required this.onScrubStart,
    required this.onScrubEnd,
  });

  @override
  State<_VideoPill> createState() => _VideoPillState();
}

class _VideoPillState extends State<_VideoPill> {
  double? _scrub;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    const tab = TextStyle(
        color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]);
    return _Glass(
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: widget.c,
        builder: (_, v, __) {
          final dur = math.max(1.0, v.duration.inMilliseconds.toDouble());
          final pos = (_scrub ?? v.position.inMilliseconds.toDouble()).clamp(0.0, dur).toDouble();
          return Row(children: [
            IconButton(
              onPressed: widget.onToggle,
              icon: Icon(
                widget.ended
                    ? CupertinoIcons.gobackward
                    : (v.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill),
                color: Colors.white,
                size: 22,
              ),
            ),
            Text(_fmt(Duration(milliseconds: pos.round())), style: tab),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  min: 0,
                  max: dur,
                  value: pos,
                  onChangeStart: (_) => widget.onScrubStart(),
                  onChanged: (x) => setState(() => _scrub = x),
                  onChangeEnd: (x) async {
                    await widget.c.seekTo(Duration(milliseconds: x.round()));
                    if (mounted) setState(() => _scrub = null);
                    widget.onScrubEnd();
                  },
                ),
              ),
            ),
            Text('-${_fmt(Duration(milliseconds: (dur - pos).round()))}', style: tab),
            TextButton(
              onPressed: widget.onSpeed,
              style: TextButton.styleFrom(
                  minimumSize: const Size(44, 36), padding: EdgeInsets.zero),
              child: Text(
                  '${widget.speed == widget.speed.roundToDouble() ? widget.speed.toInt() : widget.speed}x',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ]);
        },
      ),
    );
  }
}

// ═══════════════════════════ ALBUM VIEWER (vertical) ═══════════════════════════

class MediaAlbumViewer extends StatefulWidget {
  final ChatMediaController ctl;
  final List<String> ids;
  const MediaAlbumViewer({super.key, required this.ctl, required this.ids});

  @override
  State<MediaAlbumViewer> createState() => _MediaAlbumViewerState();
}

class _MediaAlbumViewerState extends State<MediaAlbumViewer> {
  late List<ChatMessage> _items = _resolve();
  double _pull = 0, _dragPull = 0;
  bool _closing = false;

  List<ChatMessage> _resolve() => [
        for (final id in widget.ids)
          if (widget.ctl.byId(id) != null && ChatMediaController.isMedia(widget.ctl.byId(id)!))
            widget.ctl.byId(id)!
      ];

  @override
  void initState() {
    super.initState();
    widget.ctl.addListener(_sync);
  }

  @override
  void dispose() {
    widget.ctl.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final next = _resolve();
    if (next.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _items = next);
  }

  // pull-down-to-close using the list's own bounce (no gesture conflicts)
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final px = n.metrics.pixels;
    if (px < 0) {
      final dragging = (n is ScrollUpdateNotification && n.dragDetails != null) ||
          (n is OverscrollNotification && n.dragDetails != null);
      if (dragging) {
        _dragPull = -px;
      } else if (!_closing && _dragPull > 80) {
        _closing = true;
        HapticFeedback.lightImpact();
        Navigator.of(context).pop();
      }
      if (_pull != -px) setState(() => _pull = -px);
    } else {
      _dragPull = 0;
      if (_pull != 0) setState(() => _pull = 0);
      if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
        widget.ctl.loadOlder();
      }
    }
    return false;
  }

  String get _sub {
    final v = _items.where(_isVideoMsg).length;
    final p = _items.length - v;
    if (v == 0) return '$p ${p == 1 ? 'Photo' : 'Photos'}';
    if (p == 0) return '$v ${v == 1 ? 'Video' : 'Videos'}';
    return '${_items.length} items';
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final pad = MediaQuery.paddingOf(context);
    final fade = (1 - _pull / 280).clamp(0.0, 1.0).toDouble();
    final first = _items.first;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: fade),
      body: Stack(children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: EdgeInsets.only(top: pad.top + 64, bottom: pad.bottom + 24),
            itemCount: _items.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _AlbumTile(
                key: ValueKey(_items[i].id),
                msg: _items[i],
                ctl: widget.ctl,
                onOpen: () => ChatMediaViewer.openPager(context, widget.ctl, _items[i]),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Opacity(
            opacity: fade,
            child: Container(
              padding: EdgeInsets.fromLTRB(12, pad.top + 4, 12, 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(children: [
                _GlassBtn(CupertinoIcons.back, () => Navigator.of(context).pop()),
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(first.senderId == 'user' ? 'You' : widget.ctl.chatName,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                    Text(_sub, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
                const SizedBox(width: 46),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _AlbumTile extends StatefulWidget {
  final ChatMessage msg;
  final ChatMediaController ctl;
  final VoidCallback onOpen;
  const _AlbumTile({super.key, required this.msg, required this.ctl, required this.onOpen});

  @override
  State<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<_AlbumTile> {
  String? _path;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final syncP = _MediaResolver.localSync(widget.msg);
    if (syncP != null) {
      _path = syncP;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(_AlbumTile old) {
    super.didUpdateWidget(old);
    if (old.msg.id != widget.msg.id || old.msg.mediaUrl != widget.msg.mediaUrl) {
      final syncP = _MediaResolver.localSync(widget.msg);
      if (syncP != null) {
        setState(() {
          _path = syncP;
          _loading = false;
        });
      } else {
        _load();
      }
    }
  }

  Future<void> _load({bool force = false}) async {
    if (force) {
      _MediaResolver.invalidate(widget.msg);
      setState(() => _loading = true);
    }
    final p = await _MediaResolver.resolve(widget.ctl.chatId, widget.msg);
    if (!mounted) return;
    setState(() {
      _path = p;
      _loading = false;
    });
  }

  Widget _ph(bool loading) {
    if (loading) return const _Shimmer(height: 320);
    return GestureDetector(
      onTap: () => _load(force: true),
      child: Container(
        height: 320,
        width: double.infinity,
        color: const Color(0xFF1C1C1E),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.refresh_rounded, color: Colors.white54, size: 36),
            SizedBox(height: 8),
            Text('Tap to retry',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _ticks(ChatMessage m) {
    final s = m.status.toLowerCase();
    final read = m.isRead || s == 'read' || s == 'seen';
    final delivered = read || m.isDelivered || s == 'delivered';
    return Icon(delivered ? Icons.done_all_rounded : Icons.done_rounded,
        size: 14, color: read ? const Color(0xFF53BDEB) : Colors.white70);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.msg;
    final vid = _isVideoMsg(m);
    final canReply = widget.ctl.onReply != null && int.tryParse(m.id) != null;

    return _SwipeToReply(
      enabled: canReply,
      onReply: () => _replyFromViewer(context, widget.ctl, m),
      child: GestureDetector(
        onTap: widget.onOpen,
        onLongPress: () => showMediaActions(context, widget.ctl, m),
        child: Stack(children: [
          Builder(builder: (_) {
            if (_loading) return _ph(true);
            final p = _path;
            if (p == null) return _ph(false);
            if (vid) {
              return FutureBuilder<Uint8List?>(
                future: _Poster.of(p),
                builder: (_, ps) => ps.data == null
                    ? _ph(true)
                    : Image.memory(ps.data!,
                        width: double.infinity, fit: BoxFit.fitWidth, gaplessPlayback: true),
              );
            }
            return Image.file(
              File(p),
              width: double.infinity,
              fit: BoxFit.fitWidth,
              cacheWidth: 1080,
              frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
                opacity: (frame == null && !sync) ? 0 : 1,
                duration: const Duration(milliseconds: 220),
                child: child,
              ),
              errorBuilder: (_, __, ___) => _ph(false),
            );
          }),
          if (vid)
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.85)),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 3),
                    child: Icon(Icons.play_arrow_rounded, size: 36, color: Color(0xFF2C2C2E)),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 64,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                  ),
                ),
              ),
            ),
          ),
          if (_hasReaction(m))
            Positioned(
              left: 10,
              bottom: 10,
              child: _Pop(
                alignment: Alignment.bottomLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(m.reaction!, style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
          Positioned(
            right: 10,
            bottom: 8,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_fmtTime(m.timestamp),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              if (m.senderId == 'user') ...[const SizedBox(width: 3), _ticks(m)],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;
  const _SwipeToReply({required this.child, required this.onReply, required this.enabled});

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> with SingleTickerProviderStateMixin {
  double _dx = 0, _from = 0;
  bool _fired = false;
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..addListener(
      () => setState(() => _dx = _from * (1 - Curves.easeOutCubic.transform(_back.value))));

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _release() {
    if (_fired) widget.onReply();
    _fired = false;
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final t = (_dx / 64).clamp(0.0, 1.0).toDouble();
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        _back.stop();
        setState(() => _dx = math.min(96.0, math.max(0.0, _dx + d.delta.dx * (1 - _dx / 160))));
        if (!_fired && _dx >= 64) {
          _fired = true;
          HapticFeedback.mediumImpact();
        }
      },
      onHorizontalDragEnd: (_) => _release(),
      onHorizontalDragCancel: _release,
      child: Stack(children: [
        Positioned(
          left: 14,
          top: 0,
          bottom: 0,
          child: Center(
            child: Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.6 + 0.4 * t,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
                  child: const Icon(CupertinoIcons.reply, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ),
        Transform.translate(offset: Offset(_dx, 0), child: widget.child),
      ]),
    );
  }
}
