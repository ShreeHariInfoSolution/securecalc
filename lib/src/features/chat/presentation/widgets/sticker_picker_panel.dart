import 'dart:ui';
import 'package:flutter/material.dart';

class StickerItem {
  final String id;
  final String emoji;
  final String label;
  final Color bgGradientStart;
  final Color bgGradientEnd;
  final bool isMemoji;

  const StickerItem({
    required this.id,
    required this.emoji,
    required this.label,
    required this.bgGradientStart,
    required this.bgGradientEnd,
    this.isMemoji = false,
  });
}

class StickerPack {
  final String id;
  final String name;
  final String iconSymbol;
  final List<StickerItem> stickers;

  const StickerPack({
    required this.id,
    required this.name,
    required this.iconSymbol,
    required this.stickers,
  });
}

class StickerData {
  static const List<StickerPack> packs = [
    // 1. Recents & Frequently Used
    StickerPack(
      id: 'recents',
      name: 'FREQUENTLY USED',
      iconSymbol: '🕒',
      stickers: [
        StickerItem(
          id: 'stk_jetpack',
          emoji: '🐊',
          label: 'Jetpack',
          bgGradientStart: Color(0xFF2E7D32),
          bgGradientEnd: Color(0xFF1B5E20),
          isMemoji: true,
        ),
        StickerItem(
          id: 'stk_friends',
          emoji: '📸',
          label: 'Memories',
          bgGradientStart: Color(0xFF1565C0),
          bgGradientEnd: Color(0xFF0D47A1),
          isMemoji: true,
        ),
        StickerItem(
          id: 'stk_upvote',
          emoji: '🤖',
          label: 'Upvote',
          bgGradientStart: Color(0xFFFF6D00),
          bgGradientEnd: Color(0xFFDD2C00),
          isMemoji: true,
        ),
        StickerItem(
          id: 'stk_mouse_love',
          emoji: '🐭',
          label: 'In Love',
          bgGradientStart: Color(0xFFFF1744),
          bgGradientEnd: Color(0xFFD50000),
          isMemoji: true,
        ),
      ],
    ),

    // 2. Apple Smileys & People
    StickerPack(
      id: 'smileys',
      name: 'SMILEYS & PEOPLE',
      iconSymbol: '😀',
      stickers: [
        StickerItem(id: 'stk_smile_1', emoji: '😆', label: 'Grin', bgGradientStart: Color(0xFFFFD600), bgGradientEnd: Color(0xFFFF9100)),
        StickerItem(id: 'stk_smile_2', emoji: '😂', label: 'LOL', bgGradientStart: Color(0xFFFFD600), bgGradientEnd: Color(0xFFFF9100)),
        StickerItem(id: 'stk_smile_3', emoji: '😜', label: 'Wink', bgGradientStart: Color(0xFFFFAB00), bgGradientEnd: Color(0xFFFF6D00)),
        StickerItem(id: 'stk_smile_4', emoji: '😢', label: 'Sad', bgGradientStart: Color(0xFF0288D1), bgGradientEnd: Color(0xFF01579B)),
        StickerItem(id: 'stk_smile_5', emoji: '😈', label: 'Devil', bgGradientStart: Color(0xFFAA00FF), bgGradientEnd: Color(0xFF4A148C)),
        StickerItem(id: 'stk_smile_6', emoji: '😛', label: 'Tongue', bgGradientStart: Color(0xFFFFAB00), bgGradientEnd: Color(0xFFFF6D00)),
        StickerItem(id: 'stk_smile_7', emoji: '🫡', label: 'Salute', bgGradientStart: Color(0xFFFFD700), bgGradientEnd: Color(0xFFFF8C00)),
        StickerItem(id: 'stk_smile_8', emoji: '🍆', label: 'Yum', bgGradientStart: Color(0xFF8E24AA), bgGradientEnd: Color(0xFF4A148C)),
        StickerItem(id: 'stk_smile_9', emoji: '👄', label: 'Kiss', bgGradientStart: Color(0xFFFF1744), bgGradientEnd: Color(0xFFC2185B)),
        StickerItem(id: 'stk_smile_10', emoji: '👍', label: 'Like', bgGradientStart: Color(0xFF00E5FF), bgGradientEnd: Color(0xFF0288D1)),
        StickerItem(id: 'stk_smile_11', emoji: '😁', label: 'Beam', bgGradientStart: Color(0xFFFFD600), bgGradientEnd: Color(0xFFFF8F00)),
        StickerItem(id: 'stk_smile_12', emoji: '🙂', label: 'Smile', bgGradientStart: Color(0xFFFFD600), bgGradientEnd: Color(0xFFFF8F00)),
        StickerItem(id: 'stk_smile_13', emoji: '🥰', label: 'Hearts', bgGradientStart: Color(0xFFFF1744), bgGradientEnd: Color(0xFFD50000)),
        StickerItem(id: 'stk_smile_14', emoji: '😒', label: 'Meh', bgGradientStart: Color(0xFF78909C), bgGradientEnd: Color(0xFF37474F)),
        StickerItem(id: 'stk_smile_15', emoji: '🥺', label: 'Plea', bgGradientStart: Color(0xFFFF80AB), bgGradientEnd: Color(0xFFC2185B)),
        StickerItem(id: 'stk_smile_16', emoji: '🥳', label: 'Party', bgGradientStart: Color(0xFFAA00FF), bgGradientEnd: Color(0xFF6200EA)),
        StickerItem(id: 'stk_smile_17', emoji: '😎', label: 'Cool', bgGradientStart: Color(0xFF00B0FF), bgGradientEnd: Color(0xFF0056B3)),
        StickerItem(id: 'stk_smile_18', emoji: '🤯', label: 'Blown', bgGradientStart: Color(0xFF00E676), bgGradientEnd: Color(0xFF00A846)),
        StickerItem(id: 'stk_smile_19', emoji: '🤗', label: 'Hug', bgGradientStart: Color(0xFFFF80AB), bgGradientEnd: Color(0xFFF50057)),
        StickerItem(id: 'stk_smile_20', emoji: '🤩', label: 'Star', bgGradientStart: Color(0xFFFFC400), bgGradientEnd: Color(0xFFFF8F00)),
      ],
    ),

    // 3. Mouse Memoji Pack
    StickerPack(
      id: 'mouse',
      name: 'MOUSE MEMOJIS',
      iconSymbol: '🐭',
      stickers: [
        StickerItem(id: 'stk_mouse_laugh', emoji: '🐭😂', label: 'Laugh', bgGradientStart: Color(0xFFCFD8DC), bgGradientEnd: Color(0xFF546E7A), isMemoji: true),
        StickerItem(id: 'stk_mouse_love', emoji: '🐭😍', label: 'Love', bgGradientStart: Color(0xFFFF5252), bgGradientEnd: Color(0xFFD50000), isMemoji: true),
        StickerItem(id: 'stk_mouse_blown', emoji: '🐭🤯', label: 'Mind Blown', bgGradientStart: Color(0xFF00E676), bgGradientEnd: Color(0xFF0091EA), isMemoji: true),
        StickerItem(id: 'stk_mouse_sleep', emoji: '🐭💤', label: 'Sleepy', bgGradientStart: Color(0xFF7C4DFF), bgGradientEnd: Color(0xFF3F51B5), isMemoji: true),
        StickerItem(id: 'stk_mouse_star', emoji: '🐭🤩', label: 'Stars', bgGradientStart: Color(0xFFFFD700), bgGradientEnd: Color(0xFFFF8C00), isMemoji: true),
        StickerItem(id: 'stk_mouse_sad', emoji: '🐭😢', label: 'Crying', bgGradientStart: Color(0xFF40C4FF), bgGradientEnd: Color(0xFF0091EA), isMemoji: true),
      ],
    ),

    // 4. Octopus Memoji Pack
    StickerPack(
      id: 'octopus',
      name: 'OCTOPUS MEMOJIS',
      iconSymbol: '🐙',
      stickers: [
        StickerItem(id: 'stk_octo_happy', emoji: '🐙😊', label: 'Happy', bgGradientStart: Color(0xFFFF4081), bgGradientEnd: Color(0xFFC2185B), isMemoji: true),
        StickerItem(id: 'stk_octo_love', emoji: '🐙😍', label: 'Love', bgGradientStart: Color(0xFFFF1744), bgGradientEnd: Color(0xFF880E4F), isMemoji: true),
        StickerItem(id: 'stk_octo_blown', emoji: '🐙🤯', label: 'Blown', bgGradientStart: Color(0xFF00E676), bgGradientEnd: Color(0xFF00B0FF), isMemoji: true),
        StickerItem(id: 'stk_octo_cool', emoji: '🐙😎', label: 'Cool', bgGradientStart: Color(0xFF00B0FF), bgGradientEnd: Color(0xFF1A237E), isMemoji: true),
        StickerItem(id: 'stk_octo_sleep', emoji: '🐙💤', label: 'Sleep', bgGradientStart: Color(0xFF7C4DFF), bgGradientEnd: Color(0xFF303F9F), isMemoji: true),
        StickerItem(id: 'stk_octo_sad', emoji: '🐙😢', label: 'Sad', bgGradientStart: Color(0xFF80DEEA), bgGradientEnd: Color(0xFF00838F), isMemoji: true),
      ],
    ),

    // 5. Cow Memoji Pack
    StickerPack(
      id: 'cow',
      name: 'COW MEMOJIS',
      iconSymbol: '🐮',
      stickers: [
        StickerItem(id: 'stk_cow_happy', emoji: '🐮😊', label: 'Happy', bgGradientStart: Color(0xFFFFF59D), bgGradientEnd: Color(0xFFFBC02D), isMemoji: true),
        StickerItem(id: 'stk_cow_love', emoji: '🐮😍', label: 'Love', bgGradientStart: Color(0xFFFF5252), bgGradientEnd: Color(0xFFC2185B), isMemoji: true),
        StickerItem(id: 'stk_cow_blown', emoji: '🐮🤯', label: 'Blown', bgGradientStart: Color(0xFFB9F6CA), bgGradientEnd: Color(0xFF00C853), isMemoji: true),
        StickerItem(id: 'stk_cow_cool', emoji: '🐮😎', label: 'Cool', bgGradientStart: Color(0xFF80D8FF), bgGradientEnd: Color(0xFF0091EA), isMemoji: true),
        StickerItem(id: 'stk_cow_sleep', emoji: '🐮💤', label: 'Sleepy', bgGradientStart: Color(0xFFE1BEE7), bgGradientEnd: Color(0xFF6A1B9A), isMemoji: true),
        StickerItem(id: 'stk_cow_sad', emoji: '🐮😢', label: 'Sad', bgGradientStart: Color(0xFF90CAF9), bgGradientEnd: Color(0xFF1565C0), isMemoji: true),
      ],
    ),

    // 6. Giraffe Memoji Pack
    StickerPack(
      id: 'giraffe',
      name: 'GIRAFFE MEMOJIS',
      iconSymbol: '🦒',
      stickers: [
        StickerItem(id: 'stk_giraffe_happy', emoji: '🦒😊', label: 'Happy', bgGradientStart: Color(0xFFFFE082), bgGradientEnd: Color(0xFFFF8F00), isMemoji: true),
        StickerItem(id: 'stk_giraffe_love', emoji: '🦒😍', label: 'Love', bgGradientStart: Color(0xFFFF5252), bgGradientEnd: Color(0xFFD50000), isMemoji: true),
        StickerItem(id: 'stk_giraffe_blown', emoji: '🦒🤯', label: 'Blown', bgGradientStart: Color(0xFFA7FFEB), bgGradientEnd: Color(0xFF00BFA5), isMemoji: true),
        StickerItem(id: 'stk_giraffe_cool', emoji: '🦒😎', label: 'Cool', bgGradientStart: Color(0xFF82B1FF), bgGradientEnd: Color(0xFF2979FF), isMemoji: true),
        StickerItem(id: 'stk_giraffe_sleep', emoji: '🦒💤', label: 'Sleepy', bgGradientStart: Color(0xFFEA80FC), bgGradientEnd: Color(0xFFAA00FF), isMemoji: true),
        StickerItem(id: 'stk_giraffe_sad', emoji: '🦒😢', label: 'Sad', bgGradientStart: Color(0xFF80DEEA), bgGradientEnd: Color(0xFF00838F), isMemoji: true),
      ],
    ),

    // 7. Shark Memoji Pack
    StickerPack(
      id: 'shark',
      name: 'SHARK MEMOJIS',
      iconSymbol: '🦈',
      stickers: [
        StickerItem(id: 'stk_shark_happy', emoji: '🦈😊', label: 'Happy', bgGradientStart: Color(0xFF80D8FF), bgGradientEnd: Color(0xFF0091EA), isMemoji: true),
        StickerItem(id: 'stk_shark_love', emoji: '🦈😍', label: 'Love', bgGradientStart: Color(0xFFFF4081), bgGradientEnd: Color(0xFFC2185B), isMemoji: true),
        StickerItem(id: 'stk_shark_blown', emoji: '🦈🤯', label: 'Blown', bgGradientStart: Color(0xFFA7FFEB), bgGradientEnd: Color(0xFF00B16A), isMemoji: true),
        StickerItem(id: 'stk_shark_cool', emoji: '🦈😎', label: 'Cool', bgGradientStart: Color(0xFF448AFF), bgGradientEnd: Color(0xFF0D47A1), isMemoji: true),
        StickerItem(id: 'stk_shark_sleep', emoji: '🦈💤', label: 'Sleepy', bgGradientStart: Color(0xFFB388FF), bgGradientEnd: Color(0xFF4A148C), isMemoji: true),
        StickerItem(id: 'stk_shark_sad', emoji: '🦈😢', label: 'Sad', bgGradientStart: Color(0xFF80CBC4), bgGradientEnd: Color(0xFF00695C), isMemoji: true),
      ],
    ),

    // 8. Vault & Security
    StickerPack(
      id: 'vault',
      name: 'VAULT & SECURITY',
      iconSymbol: '🔒',
      stickers: [
        StickerItem(id: 'stk_vault', emoji: '🔒', label: 'Encrypted', bgGradientStart: Color(0xFF007AFF), bgGradientEnd: Color(0xFF5856D6)),
        StickerItem(id: 'stk_key', emoji: '🔑', label: 'Secret Key', bgGradientStart: Color(0xFFFFD600), bgGradientEnd: Color(0xFFFF8F00)),
        StickerItem(id: 'stk_shield', emoji: '🛡️', label: 'Protected', bgGradientStart: Color(0xFF00E676), bgGradientEnd: Color(0xFF00B0FF)),
        StickerItem(id: 'stk_diamond', emoji: '💎', label: 'Diamond', bgGradientStart: Color(0xFF00B0FF), bgGradientEnd: Color(0xFF651FFF)),
        StickerItem(id: 'stk_rocket', emoji: '🚀', label: 'Rocket', bgGradientStart: Color(0xFFFF3D00), bgGradientEnd: Color(0xFFD50000)),
        StickerItem(id: 'stk_crown', emoji: '👑', label: 'VIP', bgGradientStart: Color(0xFFFFC400), bgGradientEnd: Color(0xFFFFAB00)),
        StickerItem(id: 'stk_sparkles', emoji: '✨', label: 'Magic', bgGradientStart: Color(0xFFE040FB), bgGradientEnd: Color(0xFFAA00FF)),
        StickerItem(id: 'stk_detective', emoji: '🕵️', label: 'Incognito', bgGradientStart: Color(0xFF78909C), bgGradientEnd: Color(0xFF37474F)),
      ],
    ),
  ];
}

class StickerPickerPanel extends StatefulWidget {
  final Function(StickerItem item) onStickerSelected;
  final VoidCallback onClose;

  const StickerPickerPanel({
    super.key,
    required this.onStickerSelected,
    required this.onClose,
  });

  @override
  State<StickerPickerPanel> createState() => _StickerPickerPanelState();
}

class _StickerPickerPanelState extends State<StickerPickerPanel> {
  int _selectedPackIndex = 1; // Default to Smileys & People

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentPack = StickerData.packs[_selectedPackIndex];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          height: 310,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xEE1C1C1E)
                : const Color(0xFDF2F2F7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Drag Handle Pill
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF545458)
                        : const Color(0xFFC7C7CC),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 2. iOS Horizontal App / Category Selector Bar
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: StickerData.packs.length,
                  itemBuilder: (context, index) {
                    final pack = StickerData.packs[index];
                    final isSelected = index == _selectedPackIndex;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedPackIndex = index;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark
                                    ? const Color(0xFF3A3A3C)
                                    : const Color(0xFFD1D1D6))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            pack.iconSymbol,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const Divider(height: 1, thickness: 0.4),

              // 3. Section Title Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  currentPack.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),

              // 4. Sticker & Emoji Grid Surface
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: currentPack.id == 'smileys' ? 5 : 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: currentPack.id == 'smileys' ? 1.0 : 1.1,
                  ),
                  itemCount: currentPack.stickers.length,
                  itemBuilder: (context, index) {
                    final sticker = currentPack.stickers[index];
                    return _IosStickerGridTile(
                      sticker: sticker,
                      onTap: () => widget.onStickerSelected(sticker),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IosStickerGridTile extends StatefulWidget {
  final StickerItem sticker;
  final VoidCallback onTap;

  const _IosStickerGridTile({
    required this.sticker,
    required this.onTap,
  });

  @override
  State<_IosStickerGridTile> createState() => _IosStickerGridTileState();
}

class _IosStickerGridTileState extends State<_IosStickerGridTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.86 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.sticker.isMemoji
            ? Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.sticker.bgGradientStart.withValues(alpha: 0.25),
                      widget.sticker.bgGradientEnd.withValues(alpha: 0.38),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.sticker.bgGradientStart.withValues(alpha: 0.35),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.sticker.bgGradientEnd.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.sticker.emoji,
                        style: const TextStyle(fontSize: 34),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.sticker.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Center(
                child: Text(
                  widget.sticker.emoji,
                  style: const TextStyle(fontSize: 32),
                ),
              ),
      ),
    );
  }
}

/// Standalone Sticker Display Widget rendered inside Chat Message Bubbles
class StickerDisplayWidget extends StatefulWidget {
  final String stickerCode;
  final double size;

  const StickerDisplayWidget({
    super.key,
    required this.stickerCode,
    this.size = 120.0,
  });

  @override
  State<StickerDisplayWidget> createState() => _StickerDisplayWidgetState();
}

class _StickerDisplayWidgetState extends State<StickerDisplayWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  late final Animation<double> _pulseAnimation = Tween<double>(
    begin: 0.95,
    end: 1.05,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutSine,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  StickerItem _resolveSticker() {
    final code = widget.stickerCode.trim();
    for (final pack in StickerData.packs) {
      for (final s in pack.stickers) {
        if (s.id == code || s.emoji == code) {
          return s;
        }
      }
    }
    return StickerItem(
      id: 'custom',
      emoji: code.length <= 4 ? code : '✨',
      label: 'Sticker',
      bgGradientStart: const Color(0xFF007AFF),
      bgGradientEnd: const Color(0xFF5856D6),
      isMemoji: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _resolveSticker();

    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              item.bgGradientStart,
              item.bgGradientEnd,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: item.bgGradientEnd.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.emoji,
                style: TextStyle(
                  fontSize: widget.size * 0.48,
                ),
              ),
              if (item.label.isNotEmpty && item.id != 'custom') ...[
                Text(
                  item.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: widget.size * 0.09,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.8,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Normalizes emoji strings by ensuring emojis that default to text presentation
/// (such as U+2764 Heavy Black Heart) have Variation Selector-16 (\uFE0F) attached,
/// forcing them to render as full-color emojis instead of monochrome text glyphs (which render white).
String normalizeEmojiText(String text) {
  if (text.isEmpty) return text;
  return text
      .replaceAll(RegExp(r'\u2764(?!\uFE0F)'), '\u2764\uFE0F')
      .replaceAll(RegExp(r'\u2665(?!\uFE0F)'), '\u2665\uFE0F')
      .replaceAll(RegExp(r'\u2763(?!\uFE0F)'), '\u2763\uFE0F')
      .replaceAll(RegExp(r'\u26A1(?!\uFE0F)'), '\u26A1\uFE0F')
      .replaceAll(RegExp(r'\u263A(?!\uFE0F)'), '\u263A\uFE0F')
      .replaceAll(RegExp(r'\u270C(?!\uFE0F)'), '\u270C\uFE0F')
      .replaceAll(RegExp(r'\u261D(?!\uFE0F)'), '\u261D\uFE0F')
      .replaceAll(RegExp(r'\u270B(?!\uFE0F)'), '\u270B\uFE0F')
      .replaceAll(RegExp(r'\u270A(?!\uFE0F)'), '\u270A\uFE0F')
      .replaceAll(RegExp(r'\u260E(?!\uFE0F)'), '\u260E\uFE0F')
      .replaceAll(RegExp(r'\u26A0(?!\uFE0F)'), '\u26A0\uFE0F');
}

/// Animated Jumbo Single Emoji Widget (WhatsApp & iMessage Style)
class JumboAnimatedEmoji extends StatefulWidget {
  final String emoji;
  final double fontSize;

  const JumboAnimatedEmoji({
    super.key,
    required this.emoji,
    this.fontSize = 56.0,
  });

  @override
  State<JumboAnimatedEmoji> createState() => _JumboAnimatedEmojiState();
}

class _JumboAnimatedEmojiState extends State<JumboAnimatedEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  late final Animation<double> _scaleAnimation = Tween<double>(
    begin: 0.92,
    end: 1.08,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutSine,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cleanEmoji = normalizeEmojiText(widget.emoji);
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Text(
        cleanEmoji,
        style: TextStyle(
          fontSize: widget.fontSize,
          height: 1.15,
        ),
      ),
    );
  }
}

/// Helper function to check if text contains ONLY 1, 2, or 3 emojis
int getEmojiOnlyCount(String text) {
  final clean = text.trim();
  if (clean.isEmpty) return 0;

  final runes = clean.runes.toList();
  var emojiCount = 0;
  var isEmoji = true;

  for (int i = 0; i < runes.length; i++) {
    final r = runes[i];

    // Skip variation selectors, ZWJ, skin tones, whitespace, keycap combiners
    if (r == 0xFE0F ||
        r == 0xFE0E ||
        r == 0x200D ||
        r == 0x200E ||
        r == 0x200F ||
        r == 0x20E3 ||
        (r >= 0x1F3FB && r <= 0x1F3FF) ||
        r == 0x0020 ||
        r == 0x00A0) {
      continue;
    }

    final inEmojiRange = (r >= 0x1F600 && r <= 0x1F64F) || // Emoticons
        (r >= 0x1F300 && r <= 0x1F5FF) || // Misc Symbols & Pictographs
        (r >= 0x1F680 && r <= 0x1F6FF) || // Transport & Map
        (r >= 0x1F1E6 && r <= 0x1F1FF) || // Flags
        (r >= 0x2600 && r <= 0x27BF) ||   // Misc Symbols & Dingbats
        (r >= 0x1F900 && r <= 0x1F9FF) || // Supplemental Symbols
        (r >= 0x1FA70 && r <= 0x1FAFF) || // Symbols Extended
        (r >= 0x2300 && r <= 0x23FF) ||   // Misc Technical
        (r >= 0x2B00 && r <= 0x2BFF) ||   // Misc Arrows & Symbols
        (r >= 0x2190 && r <= 0x21FF) ||   // Arrows
        (r >= 0x2900 && r <= 0x297F) ||   // Supplemental Arrows
        (r >= 0x3200 && r <= 0x32FF) ||   // Enclosed CJK
        (r == 0x00A9 || r == 0x00AE) ||
        (r >= 0x203C && r <= 0x2049);

    if (inEmojiRange) {
      emojiCount++;
    } else {
      isEmoji = false;
      break;
    }
  }

  if (isEmoji && emojiCount >= 1 && emojiCount <= 3) {
    return emojiCount;
  }
  return 0;
}
