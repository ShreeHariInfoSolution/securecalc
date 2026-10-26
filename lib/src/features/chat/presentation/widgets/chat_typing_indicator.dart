import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../../../core/widgets/typing_dots.dart';

class ChatTypingIndicator extends StatefulWidget {
  final String chatName;
  final String chatAvatar;

  const ChatTypingIndicator({
    super.key,
    required this.chatName,
    required this.chatAvatar,
  });

  @override
  State<ChatTypingIndicator> createState() => _ChatTypingIndicatorState();
}

class _ChatTypingIndicatorState extends State<ChatTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  late final Animation<double> _scaleAnimation = Tween<double>(
    begin: 0.2,
    end: 1.0,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ),
  );

  late final Animation<Offset> _slideAnimation = Tween<Offset>(
    begin: const Offset(-0.15, 0.2),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = isDark
        ? AppTheme.darkBubbleOther
        : AppTheme.lightBubbleOther;

    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IosAvatar(
                name: widget.chatName,
                imagePath: widget.chatAvatar,
                size: 28,
                showOnline: false,
              ),
              const SizedBox(width: 6),

              // Smallest Cloud Bubble Tail Circle
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 3),

              // Medium Cloud Bubble Tail Circle
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(bottom: 5),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),

              // Main Cloud Speech Bubble Container
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                    bottomLeft: Radius.circular(6),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const TypingDots(color: AppTheme.subtitleGrey, dotSize: 5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
