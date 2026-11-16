import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MessageMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const MessageMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
}

class MessageActionsOverlay {
  MessageActionsOverlay._();

  /// [items] empty  => reactions only (double tap)
  /// [items] filled => reactions + bubble + menu (long press)
  static Future<void> show(
    BuildContext context, {
    required Rect bubbleRect,
    required Widget bubble,
    required bool isMine,
    required bool canReact,
    required List<String> emojis,
    required List<MessageMenuItem> items,
    required ValueChanged<String> onReact,
    required VoidCallback onMoreReactions,
    String? currentReaction,
  }) {
    HapticFeedback.mediumImpact();
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, anim, _) => _OverlayBody(
          anim: anim,
          bubbleRect: bubbleRect,
          bubble: bubble,
          isMine: isMine,
          canReact: canReact,
          emojis: emojis,
          items: items,
          onReact: onReact,
          onMore: onMoreReactions,
          currentReaction: currentReaction,
        ),
        // the body animates itself, so nothing (e.g. the blur) gets scaled
        transitionsBuilder: (_, __, ___, child) => child,
      ),
    );
  }
}

class _OverlayBody extends StatelessWidget {
  final Animation<double> anim;
  final Rect bubbleRect;
  final Widget bubble;
  final bool isMine, canReact;
  final List<String> emojis;
  final List<MessageMenuItem> items;
  final ValueChanged<String> onReact;
  final VoidCallback onMore;
  final String? currentReaction;

  const _OverlayBody({
    required this.anim,
    required this.bubbleRect,
    required this.bubble,
    required this.isMine,
    required this.canReact,
    required this.emojis,
    required this.items,
    required this.onReact,
    required this.onMore,
    required this.currentReaction,
  });

  static const _barH = 52.0, _gap = 8.0, _rowH = 48.0, _menuW = 232.0, _edge = 12.0;

  Animation<double> _curve(double a, double b, Curve c) =>
      anim.drive(CurveTween(curve: Interval(a, b, curve: c)));

  void _close(BuildContext c, [VoidCallback? after]) {
    Navigator.of(c).pop();
    if (after != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => after());
    }
  }

  Future<void> _pick(BuildContext c, String e) async {
    HapticFeedback.selectionClick();
    await Future<void>.delayed(const Duration(milliseconds: 110)); // let the emoji pop
    if (c.mounted) {
      _close(c, () => onReact(e == currentReaction ? '' : e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasMenu = items.isNotEmpty;

    // ── layout maths ──
    final top = mq.padding.top + _edge;
    final bottom = mq.size.height - mq.padding.bottom - _edge;
    final above = canReact ? _barH + _gap : 0.0;
    final menuH = items.length * _rowH;
    final below = hasMenu ? menuH + _gap : 0.0;
    final maxBubbleH = math.max(60.0, bottom - top - above - below);
    final bubbleH = math.min(bubbleRect.height, maxBubbleH);
    final totalH = above + bubbleH + below;
    final desiredTop = bubbleRect.top - above;
    final finalTop =
        desiredTop.clamp(top, math.max(top, bottom - totalH)).toDouble();
    final dy = finalTop - desiredTop; // how far the whole stack must move

    // ── animations ──
    final move = anim.drive(CurveTween(curve: Curves.easeOutCubic));
    final backdrop = _curve(0, .5, Curves.easeOut);
    final barScale = _curve(.05, .6, Curves.easeOutBack);
    final barFade = _curve(.05, .3, Curves.easeOut);
    final menuScale = _curve(.15, .75, Curves.easeOutBack);
    final menuFade = _curve(.15, .45, Curves.easeOut);
    final lift = anim.drive(TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.035)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 35),
      TweenSequenceItem(
          tween: Tween(begin: 1.035, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 65),
    ]));

    final side = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final barOrigin = isMine ? Alignment.bottomRight : Alignment.bottomLeft;
    final menuOrigin = isMine ? Alignment.topRight : Alignment.topLeft;

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final shift = dy * move.value;
          return Stack(
            children: [
              // 1. blur + dim (fades in, never scaled)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _close(context),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 14 * backdrop.value + 0.01,
                      sigmaY: 14 * backdrop.value + 0.01,
                    ),
                    child: ColoredBox(
                      color: Colors.black.withValues(
                          alpha: (isDark ? 0.45 : 0.25) * backdrop.value),
                    ),
                  ),
                ),
              ),

              // 2. the bubble, exactly where it was, lifting a little
              Positioned(
                left: bubbleRect.left,
                top: bubbleRect.top + shift,
                width: bubbleRect.width,
                height: bubbleH,
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: lift.value,
                    alignment: side,
                    child: ClipRect(
                      child: OverflowBox(
                        minHeight: 0,
                        maxHeight: double.infinity,
                        alignment: Alignment.topCenter,
                        child: bubble,
                      ),
                    ),
                  ),
                ),
              ),

              // 3. reaction bar (springs out of the bubble corner)
              if (canReact)
                Positioned(
                  top: bubbleRect.top - _barH - _gap + shift,
                  left: isMine ? null : _edge,
                  right: isMine ? _edge : null,
                  child: FadeTransition(
                    opacity: barFade,
                    child: ScaleTransition(
                      alignment: barOrigin,
                      scale: barScale.drive(Tween(begin: 0.3, end: 1.0)),
                      child: _bar(context, isDark),
                    ),
                  ),
                ),

              // 4. action menu
              if (hasMenu)
                Positioned(
                  top: bubbleRect.top + bubbleH + _gap + shift,
                  left: isMine ? null : 16,
                  right: isMine ? 16 : null,
                  width: _menuW,
                  child: FadeTransition(
                    opacity: menuFade,
                    child: ScaleTransition(
                      alignment: menuOrigin,
                      scale: menuScale.drive(Tween(begin: 0.5, end: 1.0)),
                      child: _menu(context, isDark),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ───────────── reaction bar ─────────────
  Widget _pop(int i, Widget child) {
    final s = .12 + i * .045;
    return ScaleTransition(
      scale: _curve(s, s + .4, Curves.easeOutBack),
      child: child,
    );
  }

  Widget _bar(BuildContext context, bool isDark) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: _barH,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xE62C2C2E)
                  : Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12, width: 0.6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < emojis.length; i++)
                  _pop(
                    i,
                    _EmojiButton(
                      emoji: emojis[i],
                      selected: emojis[i] == currentReaction,
                      isDark: isDark,
                      onTap: () => _pick(context, emojis[i]),
                    ),
                  ),
                _pop(
                  emojis.length,
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _close(context, onMore);
                    },
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(Icons.add_rounded,
                          size: 26,
                          color: isDark ? Colors.white60 : Colors.black45),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────────── menu ─────────────
  Widget _menu(BuildContext context, bool isDark) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xE62C2C2E)
                  : Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12, width: 0.6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < items.length; i++)
                  _row(context, items[i], i == items.length - 1, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext c, MessageMenuItem it, bool last, bool isDark) {
    final col = it.color ?? (isDark ? Colors.white : Colors.black87);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            _close(c, it.onTap);
          },
          child: SizedBox(
            height: _rowH,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      it.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: col,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(it.icon, size: 20, color: col),
                ],
              ),
            ),
          ),
        ),
        if (!last)
          Divider(
            height: 0.5,
            thickness: 0.5,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
      ],
    );
  }
}

class _EmojiButton extends StatefulWidget {
  final String emoji;
  final bool selected, isDark;
  final VoidCallback onTap;
  const _EmojiButton({
    required this.emoji,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_EmojiButton> createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<_EmojiButton> {
  bool _down = false;
  bool _picked = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        setState(() => _picked = true);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _picked ? 1.55 : (_down ? 1.3 : 1.0),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.selected
                ? (widget.isDark ? Colors.white24 : Colors.black12)
                : Colors.transparent,
          ),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 26)),
        ),
      ),
    );
  }
}
