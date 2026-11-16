import 'package:flutter/material.dart';

class ForwardedTag extends StatelessWidget {
  final Color color;
  final bool pill; // true = overlay on image/video
  const ForwardedTag({super.key, required this.color, this.pill = false});

  @override
  Widget build(BuildContext context) {
    final row = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.shortcut_rounded, size: 14, color: color),
      const SizedBox(width: 4),
      Text('Forwarded',
          style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              color: color)),
    ]);
    if (!pill) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: row,
    );
  }
}
