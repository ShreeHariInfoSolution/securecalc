import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class VideoEdit {
  Duration start = Duration.zero;
  Duration? end;
  Duration duration = Duration.zero;
  bool muted = false;

  bool get trimmed =>
      duration > Duration.zero &&
      (start > const Duration(milliseconds: 80) ||
          (end != null && end! < duration - const Duration(milliseconds: 80)));
  bool get isEdited => muted || trimmed;
  Duration get length => (end ?? duration) - start;
}

class VideoPreviewPane extends StatefulWidget {
  final File file;
  final VideoEdit edit;
  final bool active; // false when swiped off-screen -> pause
  final VoidCallback onChanged;
  const VideoPreviewPane({
    super.key,
    required this.file,
    required this.edit,
    required this.active,
    required this.onChanged,
  });

  @override
  State<VideoPreviewPane> createState() => _VideoPreviewPaneState();
}

class _VideoPreviewPaneState extends State<VideoPreviewPane> {
  VideoPlayerController? _c;
  static const _n = 10;
  final List<Uint8List?> _frames = List.filled(_n, null);
  double _l = 0, _r = 1;
  int _bytes = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant VideoPreviewPane old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) _c?.pause();
    if (!old.active && widget.active) _c?.play();
  }

  @override
  void dispose() {
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(widget.file);
    await c.initialize();
    if (!mounted) {
      c.dispose();
      return;
    }
    final e = widget.edit;
    e.duration = c.value.duration;
    e.end ??= e.duration;
    final d = math.max(1, e.duration.inMilliseconds);
    _l = e.start.inMilliseconds / d;
    _r = e.end!.inMilliseconds / d;
    _bytes = await widget.file.length();
    await c.setVolume(e.muted ? 0 : 1);
    c.addListener(_tick);
    setState(() => _c = c);
    if (widget.active) c.play();
    widget.onChanged();
    _genFrames();
  }

  Future<void> _genFrames() async {
    final d = widget.edit.duration.inMilliseconds;
    for (var i = 0; i < _n; i++) {
      final data = await VideoThumbnail.thumbnailData(
        video: widget.file.path,
        imageFormat: ImageFormat.JPEG,
        timeMs: (d * i / _n).round(),
        maxWidth: 160,
        quality: 60,
      );
      if (!mounted) return;
      setState(() => _frames[i] = data);
    }
  }

  // loop inside the trim window
  void _tick() {
    final c = _c;
    if (c == null || _dragging) return;
    final e = widget.edit;
    if (c.value.isPlaying && c.value.position >= (e.end ?? e.duration)) {
      c.seekTo(e.start);
    }
  }

  void _togglePlay() {
    final c = _c;
    if (c == null) return;
    HapticFeedback.selectionClick();
    c.value.isPlaying ? c.pause() : c.play();
  }

  void _toggleMute() {
    HapticFeedback.selectionClick();
    widget.edit.muted = !widget.edit.muted;
    _c?.setVolume(widget.edit.muted ? 0 : 1);
    setState(() {});
    widget.onChanged();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  String _size() {
    final total = math.max(1, widget.edit.duration.inMilliseconds);
    final est = _bytes * (widget.edit.length.inMilliseconds / total);
    if (est >= 1024 * 1024) {
      return '${(est / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(est / 1024).round()} KB';
  }

  void _commitTrim() {
    final e = widget.edit;
    e.start = e.duration * _l;
    e.end = e.duration * _r;
  }

  Widget _handle(bool left, double w, double hw) {
    final minF = math.max(
      1000 / math.max(1, widget.edit.duration.inMilliseconds),
      (2 * hw + 12) / w,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) {
        _dragging = true;
        _c?.pause();
      },
      onHorizontalDragUpdate: (d) {
        setState(() {
          if (left) {
            _l = (_l + d.delta.dx / w).clamp(0.0, _r - minF);
          } else {
            _r = (_r + d.delta.dx / w).clamp(_l + minF, 1.0);
          }
          _commitTrim();
        });
        final t = left
            ? widget.edit.start
            : widget.edit.end! - const Duration(milliseconds: 200);
        _c?.seekTo(t);
      },
      onHorizontalDragEnd: (_) {
        _dragging = false;
        _c?.seekTo(widget.edit.start);
        _c?.play();
        HapticFeedback.selectionClick();
        widget.onChanged();
      },
      child: Container(
        width: hw,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(left ? 8 : 0),
            right: Radius.circular(left ? 0 : 8),
          ),
        ),
        child: Icon(
          left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
          size: 18,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _strip() {
    return LayoutBuilder(
      builder: (_, cs) {
        final w = cs.maxWidth;
        const hw = 18.0;
        final l = _l * w, r = _r * w;
        return SizedBox(
          height: 56,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      for (final f in _frames)
                        Expanded(
                          child: f != null
                              ? Image.memory(
                                  f,
                                  fit: BoxFit.cover,
                                  height: 56,
                                  gaplessPlayback: true,
                                )
                              : Container(color: Colors.white12),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                width: l,
                top: 0,
                bottom: 0,
                child: const ColoredBox(color: Colors.black54),
              ),
              Positioned(
                left: r,
                right: 0,
                top: 0,
                bottom: 0,
                child: const ColoredBox(color: Colors.black54),
              ),
              Positioned(
                left: l,
                width: r - l,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border.symmetric(
                        horizontal: BorderSide(color: Colors.white, width: 2.5),
                      ),
                    ),
                  ),
                ),
              ),
              if (_c != null)
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _c!,
                  builder: (_, v, __) {
                    final d = math.max(1, v.duration.inMilliseconds);
                    final x = (v.position.inMilliseconds / d * w).clamp(
                      l + hw,
                      r - hw,
                    );
                    return Positioned(
                      left: x,
                      top: 2,
                      bottom: 2,
                      width: 2.5,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(color: Colors.black54, blurRadius: 3),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              Positioned(
                left: l,
                top: 0,
                bottom: 0,
                child: _handle(true, w, hw),
              ),
              Positioned(
                left: r - hw,
                top: 0,
                bottom: 0,
                child: _handle(false, w, hw),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color: Colors.black.withValues(alpha: 0.45),
            child: child,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),
          ),
          Center(
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (_, v, __) => AnimatedOpacity(
                opacity: v.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 160),
                child: AnimatedScale(
                  scale: v.isPlaying ? 0.8 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 46,
                        color: Color(0xFF2C2C2E),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: Column(
              children: [
                _strip(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _toggleMute,
                      child: _chip(
                        Icon(
                          widget.edit.muted
                              ? CupertinoIcons.volume_off
                              : CupertinoIcons.volume_up,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _chip(
                      Text(
                        '${_fmt(widget.edit.length)} · ${_size()}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
