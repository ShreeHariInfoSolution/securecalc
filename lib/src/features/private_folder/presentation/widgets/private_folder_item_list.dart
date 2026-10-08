import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../chat/domain/models/server_models.dart';
import 'media_grid_item.dart';

class PrivateFolderItemList extends StatelessWidget {
  final List<UploadItemModel> items;
  final Function(UploadItemModel) onItemTap;

  const PrivateFolderItemList({
    super.key,
    required this.items,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: MediaGridItem(
              item: item,
              isSquareGrid: false,
              onTap: () => onItemTap(item),
            ),
          );
        },
        childCount: items.length,
      ),
    );
  }
}
