import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';

/// Wrapper widget that enables smooth horizontal swipe-to-reply with translation
/// animation and tactile haptic feedback.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animOffset;
  double _dragOffset = 0.0;
  bool _hasTriggeredHaptic = false;

  static const double _threshold = 40.0;
  static const double _maxDrag = 75.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animOffset = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() {
          _dragOffset = _animOffset.value;
        });
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    final delta = details.delta.dx;
    double newOffset = _dragOffset + delta;

    if (newOffset.abs() > _maxDrag) {
      newOffset = newOffset.sign * _maxDrag;
    }

    if (newOffset.abs() >= _threshold && !_hasTriggeredHaptic) {
      HapticFeedback.mediumImpact();
      _hasTriggeredHaptic = true;
    } else if (newOffset.abs() < _threshold) {
      _hasTriggeredHaptic = false;
    }

    setState(() {
      _dragOffset = newOffset;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled) return;
    if (_dragOffset.abs() >= _threshold) {
      HapticFeedback.lightImpact();
      widget.onReply();
    }
    _hasTriggeredHaptic = false;

    _animOffset = Tween<double>(
      begin: _dragOffset,
      end: 0.0,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _animController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDragging = _dragOffset.abs() > 0.1;
    final progress = (_dragOffset.abs() / _threshold).clamp(0.0, 1.0);
    final isRightDrag = _dragOffset > 0;

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isDragging)
            Positioned(
              left: isRightDrag ? 14 : null,
              right: !isRightDrag ? 14 : null,
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.5 + (progress * 0.5),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.reply_rounded,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
