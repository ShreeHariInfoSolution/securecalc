import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Rounded reply / edit card shown INSIDE the glass composer pill,
/// above the text field row (WhatsApp / iMessage style).
class ChatReplyPreview extends StatelessWidget {
  const ChatReplyPreview({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onCancel,
    required this.isDark,
    this.icon,
    this.accent = AppTheme.primaryColor,
    this.thumbnail,
  });

  final String title;
  final String subtitle;
  final VoidCallback onCancel;
  final bool isDark;
  final IconData? icon;
  final Color accent;
  final Widget? thumbnail;

  @override
  Widget build(BuildContext context) {
    final tint = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final subColor = isDark ? Colors.white60 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          color: tint,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (icon != null) ...[
                              Icon(icon, size: 14, color: subColor),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: subColor,
                                  fontSize: 13.5,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (thumbnail != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(child: thumbnail),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onCancel,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.14)
                              : Colors.black.withValues(alpha: 0.08),
                        ),
                        child: Icon(
                          CupertinoIcons.xmark,
                          size: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
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
}
