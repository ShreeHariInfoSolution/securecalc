import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../chat/domain/models/server_models.dart';
import 'media_grid_item.dart';

class PrivateFolderItemGrid extends StatelessWidget {
  final List<UploadItemModel> items;
  final Function(UploadItemModel) onItemTap;

  const PrivateFolderItemGrid({
    super.key,
    required this.items,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.crossAxisExtent > 600 ? 4 : 3;

        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              return MediaGridItem(
                item: item,
                isSquareGrid: true,
                onTap: () => onItemTap(item),
              );
            },
            childCount: items.length,
          ),
        );
      },
    );
  }
}
