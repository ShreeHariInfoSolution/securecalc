import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/server_api_service.dart';

class AppVideoPlayerModal extends StatefulWidget {
  final String mediaUrl;
  final String? title;

  const AppVideoPlayerModal({
    super.key,
    required this.mediaUrl,
    this.title,
  });

  static void open(
    BuildContext context, {
    required String mediaUrl,
    String? title,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.94),
        pageBuilder: (context, animation, secondaryAnimation) =>
            AppVideoPlayerModal(mediaUrl: mediaUrl, title: title),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<AppVideoPlayerModal> createState() => _AppVideoPlayerModalState();
}

class _AppVideoPlayerModalState extends State<AppVideoPlayerModal> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  bool _showControls = true;
  bool _isMuted = false;
  Timer? _hideTimer;
  double _dragOffset = 0.0;
  String? _resolvedPath;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    try {
      final rawUrl = widget.mediaUrl;
      String? localPath;

      if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
        if (File(rawUrl).existsSync()) {
          localPath = rawUrl;
        }
      }

      if (localPath == null) {
        final cached = await AttachmentCacheService.instance.resolveLocalPath(
          rawUrl,
        );
        if (cached != null && File(cached).existsSync()) {
          localPath = cached;
        }
      }

      VideoPlayerController controller;
      if (localPath != null) {
        _resolvedPath = localPath;
        controller = VideoPlayerController.file(File(localPath));
      } else {
        final networkUrl = resolveAvatarUrl(rawUrl) ?? rawUrl;
        _resolvedPath = networkUrl;
        final headers = ServerApiService.instance.authToken != null
            ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
            : <String, String>{};
        controller = VideoPlayerController.networkUrl(
          Uri.parse(networkUrl),
          httpHeaders: headers,
        );
      }

      await controller.initialize();
      controller.addListener(_videoListener);

      if (mounted) {
        setState(() {
          _controller = controller;
          _isLoading = false;
        });
        await controller.play();
        _startHideControlsTimer();
      }
    } catch (e) {
      debugPrint('[VIDEO PLAYER INIT ERROR] $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _videoListener() {
    if (mounted) setState(() {});
  }

  void _startHideControlsTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _togglePlay() {
    if (_controller == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _showControls = true;
        _hideTimer?.cancel();
      } else {
        _controller!.play();
        _startHideControlsTimer();
      }
    });
  }

  void _toggleMute() {
    if (_controller == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _seekRelative(Duration delta) {
    if (_controller == null) return;
    HapticFeedback.selectionClick();
    final current = _controller!.value.position;
    final target = current + delta;
    _controller!.seekTo(
      target < Duration.zero
          ? Duration.zero
          : (target > _controller!.value.duration
                ? _controller!.value.duration
                : target),
    );
    _startHideControlsTimer();
  }

  Future<void> _shareVideo() async {
    if (_resolvedPath == null) return;
    HapticFeedback.mediumImpact();
    try {
      if (File(_resolvedPath!).existsSync()) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(_resolvedPath!)]),
        );
      }
    } catch (e) {
      debugPrint('[VIDEO SHARE ERROR] $e');
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString();
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 90 ||
        (details.primaryVelocity != null &&
            details.primaryVelocity!.abs() > 300)) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragOffset = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double bgOpacity = (1.0 - (_dragOffset.abs() / 350.0)).clamp(
      0.2,
      1.0,
    );

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: bgOpacity),
      body: SafeArea(
        child: GestureDetector(
          onTap: () {
            setState(() {
              _showControls = !_showControls;
            });
            if (_showControls) _startHideControlsTimer();
          },
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            transform: Matrix4.translationValues(0, _dragOffset, 0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Video Content
                if (_isLoading)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 12),
                        Text(
                          'Loading video...',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else if (_hasError || _controller == null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
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
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  ),

                // Overlay Controls
                if (_showControls && !_isLoading && !_hasError && _controller != null) ...[
                  // Top Header Bar
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: Colors.white24,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.title ?? 'Video',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (_resolvedPath != null &&
                              File(_resolvedPath!).existsSync())
                            GestureDetector(
                              onTap: _shareVideo,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                  color: Colors.white24,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  CupertinoIcons.share,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Center Play/Pause & Skip Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(
                          Icons.replay_10_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => _seekRelative(const Duration(seconds: -10)),
                      ),
                      const SizedBox(width: 20),
                      GestureDetector(
                        onTap: _togglePlay,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white38, width: 1.5),
                          ),
                          child: Icon(
                            _controller!.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(
                          Icons.forward_10_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => _seekRelative(const Duration(seconds: 10)),
                      ),
                    ],
                  ),

                  // Bottom Timeline Seek Bar & Time Text
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VideoProgressIndicator(
                            _controller!,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: Color(0xFF007AFF),
                              bufferedColor: Colors.white30,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  _isMuted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: _toggleMute,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
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
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(VideoThumbnailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      _controller?.dispose();
      _controller = null;
      _isInitialized = false;
      _loadThumbnail();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadThumbnail() async {
    try {
      final rawUrl = widget.mediaUrl;
      String? localPath;

      if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
        if (File(rawUrl).existsSync()) {
          localPath = rawUrl;
        }
      }

      if (localPath == null) {
        final cached = await AttachmentCacheService.instance.resolveLocalPath(
          rawUrl,
        );
        if (cached != null && File(cached).existsSync()) {
          localPath = cached;
        }
      }

      VideoPlayerController controller;
      if (localPath != null) {
        controller = VideoPlayerController.file(File(localPath));
      } else {
        final networkUrl = resolveAvatarUrl(rawUrl) ?? rawUrl;
        final headers = ServerApiService.instance.authToken != null
            ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
            : <String, String>{};
        controller = VideoPlayerController.networkUrl(
          Uri.parse(networkUrl),
          httpHeaders: headers,
        );
      }

      await controller.initialize();
      if (mounted) {
        setState(() {
          _controller = controller;
          _isInitialized = true;
        });
        if (controller.value.size.width > 0 && controller.value.size.height > 0) {
          widget.onInfoResolved?.call(
            controller.value.aspectRatio,
            controller.value.duration,
          );
        }
      }
    } catch (e) {
      debugPrint('[VIDEO THUMBNAIL INIT ERROR] $e');
    }
  }

  String _formatDuration(Duration duration) {
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

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF1C1C1E),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isInitialized && _controller != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
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

          // Bottom Leading (Duration / Video Icon)
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
                  const SizedBox(width: 4),
                  Text(
                    _isInitialized && _controller != null
                        ? _formatDuration(_controller!.value.duration)
                        : '0:00',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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
