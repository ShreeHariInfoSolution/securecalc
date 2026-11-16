import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../../core/utils/app_toast.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/server_api_service.dart';

class VideoViewerActions {
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onReact;
  final Future<bool> Function()? onToggleStar; // returns new starred state
  final bool isStarred;
  const VideoViewerActions({
    this.onReply,
    this.onForward,
    this.onDelete,
    this.onReact,
    this.onToggleStar,
    this.isStarred = false,
  });
}

class AppVideoPlayerModal extends StatefulWidget {
  final String mediaUrl;
  final String? title; // "You" / contact name
  final String? subtitle; // "04/11/26, 3:22 PM"
  final VideoViewerActions? actions;

  const AppVideoPlayerModal({
    super.key,
    required this.mediaUrl,
    this.title,
    this.subtitle,
    this.actions,
  });

  static Future<void> open(
    BuildContext context, {
    required String mediaUrl,
    String? title,
    String? subtitle,
    VideoViewerActions? actions,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent, // Scaffold paints the fading black
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => AppVideoPlayerModal(
          mediaUrl: mediaUrl,
          title: title,
          subtitle: subtitle,
          actions: actions,
        ),
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
      ),
    );
  }

  @override
  State<AppVideoPlayerModal> createState() => _AppVideoPlayerModalState();
}

class _AppVideoPlayerModalState extends State<AppVideoPlayerModal>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _loading = true, _error = false, _ended = false;
  bool _showControls = true, _muted = false, _showReactions = false;
  bool _starred = false;
  double _speed = 1.0;
  double? _scrub; // ms while dragging the slider
  String? _resolvedPath, _errorMessage;
  Timer? _hideTimer, _flashTimer;

  // drag-to-dismiss
  double _dragOffset = 0, _snapFrom = 0;
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => setState(() => _dragOffset =
      _snapFrom * (1 - Curves.easeOutCubic.transform(_snap.value))));

  // double-tap seek flash
  Offset _tapPos = Offset.zero;
  int _flashSide = 0;

  static const _speeds = [1.0, 1.5, 2.0, 0.5];
  static const _emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _starred = widget.actions?.isStarred ?? false;
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _snap.dispose();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) _controller?.pause();
  }

  Future<void> _init() async {
    try {
      final raw = widget.mediaUrl;
      String? local;
      if (!raw.startsWith('http') && File(raw).existsSync()) local = raw;
      if (local == null) {
        final c = await AttachmentCacheService.instance.resolveLocalPath(raw);
        if (c != null && File(c).existsSync()) local = c;
      }
      late VideoPlayerController ctrl;
      if (local != null) {
        _resolvedPath = local;
        ctrl = VideoPlayerController.file(File(local));
      } else {
        final url = resolveAvatarUrl(raw) ?? raw;
        _resolvedPath = url;
        final t = ServerApiService.instance.authToken;
        ctrl = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: t != null ? {'Authorization': 'Bearer $t'} : {},
        );
      }
      await ctrl.initialize();
      ctrl.addListener(_onTick);
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _loading = false;
      });
      await ctrl.play();
      _scheduleHide();
    } catch (e) {
      debugPrint('[VIDEO PLAYER INIT ERROR] $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
          _errorMessage = '$e';
        });
      }
    }
  }

  // Only rebuild when "ended" flips. Everything else uses ValueListenableBuilder.
  void _onTick() {
    final v = _controller!.value;
    final ended = v.duration > Duration.zero && v.position >= v.duration;
    if (ended != _ended && mounted) {
      setState(() {
        _ended = ended;
        if (ended) {
          _showControls = true;
          _hideTimer?.cancel();
        }
      });
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          (_controller?.value.isPlaying ?? false) &&
          _scrub == null &&
          !_showReactions) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_showReactions) {
      setState(() => _showReactions = false);
      return;
    }
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    HapticFeedback.lightImpact();
    if (c.value.isPlaying) {
      await c.pause();
      _hideTimer?.cancel();
      if (mounted) setState(() => _showControls = true);
    } else {
      if (_ended) await c.seekTo(Duration.zero);
      await c.play();
      _scheduleHide();
    }
  }

  void _seekBy(Duration d) {
    final c = _controller;
    if (c == null) return;
    final t = c.value.position + d;
    final max = c.value.duration;
    c.seekTo(t < Duration.zero ? Duration.zero : (t > max ? max : t));
  }

  void _onDoubleTap() {
    final w = MediaQuery.sizeOf(context).width;
    final side = _tapPos.dx < w / 2 ? -1 : 1;
    HapticFeedback.selectionClick();
    _seekBy(Duration(seconds: 10 * side));
    setState(() => _flashSide = side);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flashSide = 0);
    });
  }

  void _cycleSpeed() {
    HapticFeedback.selectionClick();
    _speed = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    _controller?.setPlaybackSpeed(_speed);
    setState(() {});
    _scheduleHide();
  }

  void _toggleMute() {
    HapticFeedback.selectionClick();
    setState(() => _muted = !_muted);
    _controller?.setVolume(_muted ? 0 : 1);
  }

  // ── drag to dismiss ──
  void _dragUpdate(DragUpdateDetails d) {
    _snap.stop();
    setState(() => _dragOffset += d.delta.dy);
  }

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dragOffset.abs() > 110 || v.abs() > 700) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop();
    } else {
      _snapFrom = _dragOffset;
      _snap.forward(from: 0);
    }
  }

  // ── actions ──
  void _popThen(VoidCallback? cb) {
    if (cb == null) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => cb());
  }

  Future<void> _share() async {
    final p = _resolvedPath;
    if (p == null || !File(p).existsSync()) {
      AppToast.show('Video is not downloaded yet', isError: true);
      return;
    }
    HapticFeedback.mediumImpact();
    await SharePlus.instance.share(ShareParams(files: [XFile(p)]));
  }

  Future<void> _star() async {
    final f = widget.actions?.onToggleStar;
    if (f == null) return;
    HapticFeedback.selectionClick();
    final r = await f();
    if (mounted) setState(() => _starred = r);
  }

  Future<void> _delete() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete message?'),
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
    if (ok == true) _popThen(widget.actions?.onDelete);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  // ── UI ──
  Widget _glass({
    required Widget child,
    double radius = 28,
    EdgeInsets? padding,
  }) {
    return ClipRRect(
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

  Widget _circleBtn(
    IconData icon,
    VoidCallback? onTap, {
    Color color = Colors.white,
    double size = 22,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: _glass(
        radius: 24,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            icon,
            color: onTap == null ? Colors.white30 : color,
            size: size,
          ),
        ),
      ),
    );
  }

  Widget _buildVideo() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error || _controller == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.redAccent,
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text(
                'Unable to play video',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage ?? 'Unsupported video format',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    final ar = _controller!.value.aspectRatio;
    return Center(
      child: AspectRatio(
        aspectRatio: ar > 0 ? ar : 16 / 9,
        child: VideoPlayer(_controller!),
      ),
    );
  }

  Widget _buildFlash() {
    if (_flashSide == 0) return const SizedBox.shrink();
    final left = _flashSide < 0;
    return Positioned(
      top: 0,
      bottom: 0,
      left: left ? 0 : null,
      right: left ? null : 0,
      width: MediaQuery.sizeOf(context).width * 0.4,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  left ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  left ? '10s' : '10s',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTop() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          _circleBtn(CupertinoIcons.back, () => Navigator.of(context).pop()),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title ?? 'Video',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.subtitle != null)
                  Text(
                    widget.subtitle!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          _circleBtn(
            _muted ? CupertinoIcons.volume_off : CupertinoIcons.volume_up,
            _toggleMute,
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackPill() {
    final c = _controller!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: _glass(
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (_, v, __) {
            final dur = math.max(1.0, v.duration.inMilliseconds.toDouble());
            final pos = (_scrub ?? v.position.inMilliseconds.toDouble())
                .clamp(0.0, dur);
            return Row(
              children: [
                IconButton(
                  onPressed: _togglePlay,
                  icon: Icon(
                    _ended
                        ? CupertinoIcons.gobackward
                        : (v.isPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill),
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                Text(
                  _fmt(Duration(milliseconds: pos.round())),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      min: 0,
                      max: dur,
                      value: pos,
                      onChangeStart: (_) {
                        _hideTimer?.cancel();
                      },
                      onChanged: (x) => setState(() => _scrub = x),
                      onChangeEnd: (x) async {
                        await c.seekTo(Duration(milliseconds: x.round()));
                        if (mounted) setState(() => _scrub = null);
                        if (c.value.isPlaying) _scheduleHide();
                      },
                    ),
                  ),
                ),
                Text(
                  '-${_fmt(Duration(milliseconds: (dur - pos).round()))}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                TextButton(
                  onPressed: _cycleSpeed,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 36),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    '${_speed == _speed.roundToDouble() ? _speed.toInt() : _speed}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottom() {
    final a = widget.actions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (a?.onReact != null)
                GestureDetector(
                  onTap: () =>
                      setState(() => _showReactions = !_showReactions),
                  child: _glass(
                    radius: 20,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        CupertinoIcons.smiley,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (a?.onReply != null)
                GestureDetector(
                  onTap: () => _popThen(a!.onReply),
                  child: _glass(
                    radius: 22,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.reply,
                            color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Reply',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _circleBtn(CupertinoIcons.share, _share),
              _circleBtn(
                CupertinoIcons.arrowshape_turn_up_right,
                a?.onForward == null ? null : () => _popThen(a!.onForward),
              ),
              _circleBtn(
                CupertinoIcons.trash,
                a?.onDelete == null ? null : _delete,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReactionBar() {
    return Positioned(
      left: 16,
      bottom: 130,
      child: AnimatedScale(
        scale: _showReactions ? 1 : 0.6,
        alignment: Alignment.bottomLeft,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: _showReactions ? 1 : 0,
          duration: const Duration(milliseconds: 140),
          child: IgnorePointer(
            ignoring: !_showReactions,
            child: _glass(
              radius: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: _emojis
                    .map(
                      (e) => GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          final cb = widget.actions?.onReact;
                          setState(() => _showReactions = false);
                          cb?.call(e);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(e, style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = (_dragOffset.abs() / 300).clamp(0.0, 1.0);
    final ready = !_loading && !_error && _controller != null;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - p * 0.85),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (d) => _tapPos = d.localPosition,
        onDoubleTap: ready ? _onDoubleTap : null,
        onVerticalDragUpdate: _dragUpdate,
        onVerticalDragEnd: _dragEnd,
        child: Stack(
          children: [
            Transform.translate(
              offset: Offset(0, _dragOffset),
              child: Transform.scale(
                scale: 1 - p * 0.15,
                child: _buildVideo(),
              ),
            ),
            _buildFlash(),
            if (ready)
              Positioned.fill(
                child: SafeArea(
                  child: AnimatedOpacity(
                    opacity: _showControls ? (1 - p) : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: Column(
                        children: [
                          _buildTop(),
                          _buildPlaybackPill(),
                          const Spacer(),
                          _buildBottom(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (ready && widget.actions?.onReact != null) _buildReactionBar(),
            if (!ready && !_loading)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _circleBtn(
                    CupertinoIcons.back,
                    () => Navigator.of(context).pop(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class VideoPoster {
  static final _mem = <String, Uint8List>{};
  static Future<Uint8List?> get(String path) async {
    if (_mem.containsKey(path)) return _mem[path];
    final d = await VideoThumbnail.thumbnailData(
      video: path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 480,
      quality: 70,
    );
    if (d != null) _mem[path] = d;
    return d;
  }
}

class _VideoInfoCache {
  static final Map<String, _VideoMeta> _cache = {};
  static final Set<String> _loading = {};

  static _VideoMeta? get(String pathOrUrl) => _cache[pathOrUrl];

  static Future<_VideoMeta?> resolve(String pathOrUrl) async {
    if (pathOrUrl.isEmpty) return null;
    if (_cache.containsKey(pathOrUrl)) return _cache[pathOrUrl];
    if (_loading.contains(pathOrUrl)) return null;
    _loading.add(pathOrUrl);

    try {
      if (!pathOrUrl.startsWith('http://') && !pathOrUrl.startsWith('https://')) {
        try {
          final info = await VideoCompress.getMediaInfo(pathOrUrl);
          final durMs = (info.duration ?? 0).toInt();
          final w = (info.width ?? 0).toDouble();
          final h = (info.height ?? 0).toDouble();
          if (durMs > 0 && w > 0 && h > 0) {
            final meta = _VideoMeta(w / h, Duration(milliseconds: durMs));
            _cache[pathOrUrl] = meta;
            return meta;
          }
        } catch (_) {}
      }

      VideoPlayerController? ctrl;
      try {
        if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
          ctrl = VideoPlayerController.networkUrl(Uri.parse(pathOrUrl));
        } else {
          ctrl = VideoPlayerController.file(File(pathOrUrl));
        }
        await ctrl.initialize();
        final dur = ctrl.value.duration;
        final aspect = ctrl.value.aspectRatio;
        await ctrl.dispose();
        if (dur > Duration.zero && aspect > 0) {
          final meta = _VideoMeta(aspect, dur);
          _cache[pathOrUrl] = meta;
          return meta;
        }
      } catch (_) {
        try {
          await ctrl?.dispose();
        } catch (_) {}
      }
    } finally {
      _loading.remove(pathOrUrl);
    }
    return null;
  }
}

class _VideoMeta {
  final double aspectRatio;
  final Duration duration;
  const _VideoMeta(this.aspectRatio, this.duration);
}

String _formatVideoDuration(Duration duration) {
  if (duration.inHours > 0) {
    final h = duration.inHours;
    final m = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  } else {
    final m = duration.inMinutes;
    final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class VideoThumbnailCard extends StatefulWidget {
  final String mediaUrl;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final Function(double aspectRatio, Duration duration)? onInfoResolved;
  final Widget? bottomTrailing;
  final Widget? bottomLeading;
  final bool showDefaultOverlay;

  const VideoThumbnailCard({
    super.key,
    required this.mediaUrl,
    this.width = double.infinity,
    this.height = 200,
    this.borderRadius,
    this.onInfoResolved,
    this.bottomTrailing,
    this.bottomLeading,
    this.showDefaultOverlay = true,
  });

  @override
  State<VideoThumbnailCard> createState() => _VideoThumbnailCardState();
}

class _VideoThumbnailCardState extends State<VideoThumbnailCard> {
  Uint8List? _posterBytes;
  bool _loading = true;
  Duration? _resolvedDuration;

  @override
  void initState() {
    super.initState();
    _loadPoster();
  }

  @override
  void didUpdateWidget(VideoThumbnailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      _loadPoster();
    }
  }

  Future<void> _loadPoster() async {
    try {
      final rawUrl = widget.mediaUrl;
      String path = rawUrl;
      if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
        final cached = await AttachmentCacheService.instance.resolveLocalPath(rawUrl);
        if (cached != null) path = cached;
      }
      final bytes = await VideoPoster.get(path);
      if (mounted) {
        setState(() {
          _posterBytes = bytes;
          _loading = false;
        });
      }
      _resolveVideoInfo(path);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveVideoInfo(String path) async {
    final meta = _VideoInfoCache.get(path) ?? await _VideoInfoCache.resolve(path);
    if (meta != null && mounted) {
      setState(() {
        _resolvedDuration = meta.duration;
      });
      widget.onInfoResolved?.call(meta.aspectRatio, meta.duration);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF1C1C1E),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_posterBytes != null)
            Image.memory(
              _posterBytes!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            )
          else
            const Center(
              child: Icon(
                CupertinoIcons.videocam_fill,
                size: 38,
                color: Colors.white38,
              ),
            ),

          // Translucent Play Button Overlay (WhatsApp style)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Padding(
                padding: EdgeInsets.only(left: 3),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Color(0xFF2C2C2E),
                  size: 36,
                ),
              ),
            ),
          ),

          // Bottom Gradient Overlay for text readability
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Leading
          if (widget.bottomLeading != null)
            Positioned(
              left: 10,
              bottom: 6,
              child: widget.bottomLeading!,
            )
          else if (widget.showDefaultOverlay)
            Positioned(
              left: 10,
              bottom: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.videocam_fill,
                    color: Colors.white,
                    size: 13,
                  ),
                  if (_resolvedDuration != null && _resolvedDuration! > Duration.zero) ...[
                    const SizedBox(width: 4),
                    Text(
                      _formatVideoDuration(_resolvedDuration!),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Bottom Trailing (Timestamp + Status Ticks)
          if (widget.bottomTrailing != null)
            Positioned(
              right: 8,
              bottom: 6,
              child: widget.bottomTrailing!,
            ),
        ],
      ),
    );

    if (widget.borderRadius != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius!,
        child: cardContent,
      );
    }

    return cardContent;
  }
}
