import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/features/chat/domain/models/server_models.dart';

class PrivateFolderHeader extends StatelessWidget {
  final bool isDark;
  final VoidCallback onBack;
  final VoidCallback onUpload;
  final VoidCallback? onCreateFolder;
  final bool isGridView;
  final VoidCallback onToggleLayout;
  final TextEditingController? searchController;
  final Function(String)? onSearchChanged;
  final List<BreadcrumbItem> breadcrumbs;
  final Function(BreadcrumbItem item, int index)? onBreadcrumbTap;

  const PrivateFolderHeader({
    super.key,
    required this.isDark,
    required this.onBack,
    required this.onUpload,
    this.onCreateFolder,
    required this.isGridView,
    required this.onToggleLayout,
    this.searchController,
    this.onSearchChanged,
    this.breadcrumbs = const [],
    this.onBreadcrumbTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Navigation Bar
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onBack,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.7),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.18) : const Color(0xFFE5E5EA),
                        ),
                      ),
                      child: Icon(
                        CupertinoIcons.chevron_left,
                        color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Private Vault',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    Text(
                      'Encrypted Storage Drive',
                      style: TextStyle(
                        color: isDark ? const Color(0xFFA0A0A5) : const Color(0xFF6C6C70),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onToggleLayout,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isGridView ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2,
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (onCreateFolder != null) ...[
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onCreateFolder,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFF007AFF).withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF007AFF).withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      CupertinoIcons.folder_badge_plus,
                      color: Color(0xFF007AFF),
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onUpload,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFAF52DE), Color(0xFF007AFF)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFAF52DE).withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.add, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Upload',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Search Input Bar
          if (searchController != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFE5E5EA),
                      width: 0.8,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.search,
                        color: isDark ? Colors.white54 : Colors.black45,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          onChanged: onSearchChanged,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search vault items...',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white38 : Colors.black38,
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (searchController!.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            searchController!.clear();
                            if (onSearchChanged != null) onSearchChanged!('');
                          },
                          child: Icon(
                            CupertinoIcons.xmark_circle_fill,
                            color: isDark ? Colors.white38 : Colors.black38,
                            size: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Breadcrumbs Navigation Trail
          if (breadcrumbs.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  for (int i = 0; i < breadcrumbs.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          CupertinoIcons.chevron_right,
                          size: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    GestureDetector(
                      onTap: () {
                        if (onBreadcrumbTap != null) {
                          onBreadcrumbTap!(breadcrumbs[i], i);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: i == breadcrumbs.length - 1
                              ? (isDark ? Colors.white.withOpacity(0.18) : const Color(0xFF007AFF).withOpacity(0.15))
                              : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: i == breadcrumbs.length - 1
                                ? const Color(0xFF007AFF).withOpacity(0.4)
                                : Colors.transparent,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          breadcrumbs[i].name,
                          style: TextStyle(
                            color: i == breadcrumbs.length - 1
                                ? (isDark ? Colors.white : const Color(0xFF007AFF))
                                : (isDark ? Colors.white70 : Colors.black87),
                            fontSize: 12,
                            fontWeight: i == breadcrumbs.length - 1
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
