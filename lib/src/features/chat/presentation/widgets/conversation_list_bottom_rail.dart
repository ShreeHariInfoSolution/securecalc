import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class ConversationListBottomRail extends StatelessWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onNewChatTap;

  const ConversationListBottomRail({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.onChanged,
    required this.onNewChatTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding > 0 ? bottomPadding + 6 : 14),
      child: Row(
        children: [
          // Frosted Glass Search Pill
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1C1C1E).withValues(alpha: 0.82)
                        : Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppTheme.glassBorder(isDark),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.search,
                        size: 20,
                        color: AppTheme.secondaryText(isDark),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          focusNode: searchFocusNode,
                          onChanged: onChanged,
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.primaryText(isDark),
                            letterSpacing: -0.2,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintStyle: TextStyle(
                              fontSize: 16,
                              color: AppTheme.secondaryText(isDark),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                      if (searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            searchController.clear();
                            onChanged('');
                          },
                          child: Icon(
                            CupertinoIcons.clear_thick_circled,
                            size: 18,
                            color: AppTheme.secondaryText(isDark),
                          ),
                        )
                      else
                        Icon(
                          CupertinoIcons.mic_fill,
                          size: 18,
                          color: AppTheme.secondaryText(isDark),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Frosted Glass New Chat Circular Button
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C1C1E).withValues(alpha: 0.82)
                      : Colors.white.withValues(alpha: 0.88),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.glassBorder(isDark),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onNewChatTap,
                    borderRadius: BorderRadius.circular(24),
                    child: Center(
                      child: Icon(
                        CupertinoIcons.square_pencil,
                        size: 22,
                        color: AppTheme.primaryText(isDark),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
