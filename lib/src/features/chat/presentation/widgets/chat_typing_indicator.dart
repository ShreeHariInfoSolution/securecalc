import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../../../core/widgets/typing_dots.dart';

class ChatTypingIndicator extends StatelessWidget {
  final String chatName;
  final String chatAvatar;

  const ChatTypingIndicator({
    super.key,
    required this.chatName,
    required this.chatAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          IosAvatar(
            name: chatName,
            imagePath: chatAvatar,
            size: 28,
            showOnline: false,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkBubbleOther : AppTheme.lightBubbleOther,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const TypingDots(
              color: AppTheme.subtitleGrey,
              dotSize: 5,
            ),
          ),
        ],
      ),
    );
  }
}
