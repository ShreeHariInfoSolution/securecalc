import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const Color kVoiceRed = Color(0xFFFF3B30);
const Color kVoiceGreen = Color(0xFF25D366);

String formatVoiceDuration(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

double _seg(double t, double a, double b, [Curve curve = Curves.linear]) =>
    curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0).toDouble());

const _tabular = [FontFeature.tabularFigures()];

// ─────────────────────────────────────────────────────────────────────────────
// 1) HOLD BAR  (screenshot 1)  red mic + timer + "Slide to cancel <"
// ─────────────────────────────────────────────────────────────────────────────
class VoiceHoldBar extends StatelessWidget {
  const VoiceHoldBar({
    super.key,
    required this.elapsed,
    required this.dragDx,
    required this.cancelProgress,
    required this.isDark,
  });

  final Duration elapsed;
  final double dragDx;
  final double cancelProgress;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final hint = isDark ? Colors.white54 : Colors.black45;

    return SizedBox(
      height: 38,
      child: Row(
        children: [
          const SizedBox(width: 8),
          const _BlinkingMic(),
          const SizedBox(width: 10),
          Text(
            formatVoiceDuration(elapsed),
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.w300,
              fontFeatures: _tabular,
            ),
          ),
          Expanded(
            child: Opacity(
              opacity: (1 - cancelProgress).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(dragDx * 0.5, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Slide to cancel',
                      style: TextStyle(color: hint, fontSize: 16),
                    ),
                    const SizedBox(width: 4),
                    Icon(CupertinoIcons.chevron_left, size: 14, color: hint),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlinkingMic extends StatefulWidget {
  const _BlinkingMic();
  @override
  State<_BlinkingMic> createState() => _BlinkingMicState();
}

class _BlinkingMicState extends State<_BlinkingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.25, end: 1).animate(_c),
        child: const Icon(CupertinoIcons.mic_fill, color: kVoiceRed, size: 22),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// 2) LOCK PILL  (above the mic while holding)
// ─────────────────────────────────────────────────────────────────────────────
class VoiceLockPill extends StatelessWidget {
  const VoiceLockPill({super.key, required this.progress, required this.isDark});
  final double progress; // 0..1
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    return Container(
      width: 44,
      height: 122,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xF22C2C2E)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          Icon(
            progress > 0.85 ? CupertinoIcons.lock_fill : CupertinoIcons.lock_open,
            size: 20,
            color: iconColor,
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: (1 - progress).clamp(0.0, 1.0),
            child: Icon(CupertinoIcons.chevron_up, size: 16, color: iconColor),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3) LOCKED PANEL  (screenshot 2)  timer + waveform, bin / pause / send
// ─────────────────────────────────────────────────────────────────────────────
class VoiceLockedPanel extends StatelessWidget {
  const VoiceLockedPanel({
    super.key,
    required this.elapsed,
    required this.levels,
    required this.levelTick,
    required this.isPaused,
    required this.isDark,
    required this.onDelete,
    required this.onPauseResume,
    required this.onSend,
  });

  final Duration elapsed;
  final List<double> levels;
  final int levelTick;
  final bool isPaused;
  final bool isDark;
  final VoidCallback onDelete;
  final VoidCallback onPauseResume;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final waveColor = isDark ? const Color(0xFF9E9E9E) : const Color(0xFF8E8E93);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                formatVoiceDuration(elapsed),
                style: TextStyle(
                  color: textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                  fontFeatures: _tabular,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: CustomPaint(
                    painter: _WavePainter(levels, waveColor, levelTick),
                    size: Size.infinite,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDelete,
                child: SizedBox(
                  width: 52,
                  height: 48,
                  child: Icon(
                    CupertinoIcons.trash,
                    size: 24,
                    color: textColor,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onPauseResume,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: kVoiceRed, width: 2),
                  ),
                  child: Icon(
                    isPaused ? CupertinoIcons.mic_fill : CupertinoIcons.pause_fill,
                    size: 20,
                    color: kVoiceRed,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onSend,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: kVoiceGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    size: 24,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.color, this.tick);
  final List<double> levels;
  final Color color;
  final int tick;

  @override
  void paint(Canvas canvas, Size size) {
    const barW = 3.0;
    const gap = 2.5;
    final n = (size.width / (barW + gap)).floor();
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW;
    final mid = size.height / 2;

    for (var i = 0; i < n; i++) {
      final li = levels.length - n + i; // newest bar at the right edge
      final h = li >= 0
          ? math.max(3.0, levels[li] * size.height)
          : 3.0; // small dots before recording fills the width
      final x = i * (barW + gap) + barW / 2;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.tick != tick || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// 4) CANCEL ANIMATION  red mic rises, spins, falls into bin, lid closes
// ─────────────────────────────────────────────────────────────────────────────
class VoiceCancelAnim extends StatefulWidget {
  const VoiceCancelAnim({
    super.key,
    required this.elapsed,
    required this.isDark,
    required this.onDone,
  });

  final Duration elapsed;
  final bool isDark;
  final VoidCallback onDone;

  @override
  State<VoiceCancelAnim> createState() => _VoiceCancelAnimState();
}

class _VoiceCancelAnimState extends State<VoiceCancelAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : Colors.black87;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final rise = _seg(t, 0.0, 0.45, Curves.easeOut);
        final fall = _seg(t, 0.45, 0.80, Curves.easeIn);
        final micDy = -38 * rise + 38 * fall;
        final micAngle = math.pi * rise;
        final micOpacity = 1 - _seg(t, 0.70, 0.85);
        final micScale = 1 - 0.35 * fall;
        final lid = (_seg(t, 0.30, 0.50) - _seg(t, 0.82, 0.97)).clamp(0.0, 1.0);

        return SizedBox(
          height: 38,
          child: Row(
            children: [
              const SizedBox(width: 8),
              SizedBox(
                width: 26,
                height: 38,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Opacity(
                      opacity: _seg(t, 0.0, 0.2),
                      child: _Bin(lidOpen: lid, color: kVoiceRed),
                    ),
                    Opacity(
                      opacity: micOpacity.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, micDy),
                        child: Transform.rotate(
                          angle: micAngle,
                          child: Transform.scale(
                            scale: micScale,
                            child: const Icon(
                              CupertinoIcons.mic_fill,
                              color: kVoiceRed,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Opacity(
                opacity: 1 - _seg(t, 0.0, 0.35),
                child: Text(
                  formatVoiceDuration(widget.elapsed),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w300,
                    fontFeatures: _tabular,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Bin extends StatelessWidget {
  const _Bin({required this.lidOpen, required this.color});
  final double lidOpen; // 0 closed .. 1 open
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 26,
      child: Stack(
        children: [
          // body
          Positioned(
            left: 3,
            right: 3,
            bottom: 0,
            height: 18,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 2),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(4),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  3,
                  (_) => Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: color,
                  ),
                ),
              ),
            ),
          ),
          // lid (rotates around its left-bottom corner)
          Positioned(
            left: 0,
            top: 0,
            width: 24,
            height: 8,
            child: Transform.rotate(
              angle: -lidOpen * 0.8,
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 1.5),
                  Container(
                    width: 24,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
