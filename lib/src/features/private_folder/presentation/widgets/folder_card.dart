import 'dart:ui';
import 'package:flutter/material.dart';

class FolderCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final int itemCount;
  final VoidCallback onTap;
  final bool isSelected;

  const FolderCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.itemCount,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  State<FolderCard> createState() => _FolderCardState();
}

class _FolderCardState extends State<FolderCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardBg = widget.isSelected
        ? widget.accentColor.withOpacity(isDark ? 0.3 : 0.2)
        : (isDark
            ? Colors.white.withOpacity(0.08)
            : Colors.white.withOpacity(0.7));

    final glassBorderColor = widget.isSelected
        ? widget.accentColor.withOpacity(0.8)
        : (isDark
            ? Colors.white.withOpacity(0.18)
            : widget.accentColor.withOpacity(0.2));

    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subTextColor = isDark ? const Color(0xFFA0A0A5) : const Color(0xFF6C6C70);

    return AnimatedScale(
      scale: _isPressed ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: widget.accentColor.withOpacity(isDark ? 0.15 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: glassBorderColor, width: widget.isSelected ? 1.5 : 1.0),
                  gradient: LinearGradient(
                    colors: [
                      isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.85),
                      isDark ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.55),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  widget.accentColor,
                                  widget.accentColor.withOpacity(0.8),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.accentColor.withOpacity(0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              widget.icon,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: widget.accentColor.withOpacity(isDark ? 0.25 : 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: widget.accentColor.withOpacity(0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              '${widget.itemCount}',
                              style: TextStyle(
                                color: widget.accentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: subTextColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
