import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../chat/domain/models/server_models.dart';
import '../models/vault_folder_descriptor.dart';
import 'folder_card.dart';
import 'media_grid_item.dart';

class PrivateFolderOverview extends StatelessWidget {
  final bool isDark;
  final List<VaultFolderDescriptor> descriptors;
  final Map<String, int> totalCounts;
  final List<UploadItemModel> recentItems;
  final Function(int) onFolderTap;
  final Function(UploadItemModel) onItemTap;

  const PrivateFolderOverview({
    super.key,
    required this.isDark,
    required this.descriptors,
    required this.totalCounts,
    required this.recentItems,
    required this.onFolderTap,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.15,
                ),
                itemCount: descriptors.length,
                itemBuilder: (context, index) {
                  final meta = descriptors[index];
                  final totalCount = totalCounts[meta.key] ?? 0;
                  return FolderCard(
                    title: meta.title,
                    subtitle: meta.subtitle,
                    icon: meta.icon,
                    accentColor: meta.color,
                    itemCount: totalCount,
                    onTap: () => onFolderTap(index + 1),
                  );
                },
              );
            },
          ),
          if (recentItems.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Vault Storage',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${totalCounts.values.fold(0, (sum, count) => sum + count)} Total Items',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: recentItems.length,
                  itemBuilder: (context, index) {
                    final item = recentItems[index];
                    return MediaGridItem(
                      item: item,
                      isSquareGrid: true,
                      onTap: () => onItemTap(item),
                    );
                  },
                );
              },
            ),
          ],
        ]),
      ),
    );
  }
}
