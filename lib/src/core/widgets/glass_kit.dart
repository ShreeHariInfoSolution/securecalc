import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 24,
    this.blurEnabled = true,
    this.padding,
    this.tint,
  });
  final Widget child;
  final double radius, blur;
  final bool blurEnabled;
  final EdgeInsetsGeometry? padding;
  final Color? tint; // e.g. red for destructive, orange for live

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    final t = tint;

    final fill = Material(
      color: Colors.transparent,
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: t != null
                  ? [t.withValues(alpha: dark ? 0.55 : 0.26), t.withValues(alpha: dark ? 0.38 : 0.12)]
                  : dark
                      ? [
                          const Color(0xFF2C2C2E).withValues(alpha: 0.70),
                          const Color(0xFF1C1C1E).withValues(alpha: 0.60),
                        ]
                      : [Colors.white.withValues(alpha: 0.80), Colors.white.withValues(alpha: 0.52)],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.12 : 0.9),
              width: 0.8,
            ),
          ),
          child: child,
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          children: [
            blurEnabled
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: fill,
                  )
                : fill,
            // specular top edge highlight
            Positioned(
              top: 0,
              left: radius * 0.6,
              right: radius * 0.6,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: dark ? 0.55 : 1),
                    Colors.white.withValues(alpha: 0),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.color,
    this.blurEnabled = true,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final bool blurEnabled;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: SizedBox(
          width: size,
          height: size,
          child: GlassSurface(
            radius: size / 2,
            blur: 18,
            blurEnabled: blurEnabled,
            child: Center(
              child: Icon(
                icon,
                size: size * 0.46,
                color: color ??
                    (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF0A84FF)
                        : Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
        ),
      );
}

class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.blurEnabled = true,
    this.tint,
  });
  final Widget child;
  final bool blurEnabled;
  final Color? tint;
  @override
  Widget build(BuildContext context) => GlassSurface(
        radius: 20,
        blur: 18,
        blurEnabled: blurEnabled,
        tint: tint,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: child,
      );
}

/// One tappable row used in the picker and the map sheet.
class GlassActionRow extends StatelessWidget {
  const GlassActionRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.trailing,
    this.onTap,
  });
  final Widget leading;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: titleColor ?? (dark ? Colors.white : Colors.black87),
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: dark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Round tinted icon used as `leading` in GlassActionRow.
class GlassIconBadge extends StatelessWidget {
  const GlassIconBadge({super.key, required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
        ),
        child: Icon(icon, color: color, size: 22),
      );
}

class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.color = const Color(0xFFFF9500), this.size = 8});
  final Color color;
  final double size;
  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 6)],
          ),
        ),
      );
}

/// Glass bottom sheet for the live duration. Returns minutes or null.
Future<int?> showLiveDurationSheet(BuildContext context) {
  return showCupertinoModalPopup<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassSurface(
              radius: 26,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GlassIconBadge(
                      icon: CupertinoIcons.antenna_radiowaves_left_right,
                      color: Color(0xFFFF9500),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Share live location',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(ctx).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'People in this chat can see where you are in real time.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(ctx).brightness == Brightness.dark
                            ? Colors.white60
                            : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final o in const [(15, '15 minutes'), (60, '1 hour'), (480, '8 hours')])
                      GlassActionRow(
                        leading: const Icon(CupertinoIcons.timer, color: Color(0xFFFF9500)),
                        title: o.$2,
                        trailing: Icon(
                          CupertinoIcons.chevron_right,
                          size: 15,
                          color: Theme.of(ctx).brightness == Brightness.dark ? Colors.white54 : Colors.black45,
                        ),
                        onTap: () => Navigator.pop(ctx, o.$1),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: const SizedBox(
                width: double.infinity,
                child: GlassSurface(
                  radius: 22,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0A84FF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
