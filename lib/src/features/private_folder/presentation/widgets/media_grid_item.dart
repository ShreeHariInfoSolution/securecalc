import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/features/chat/domain/models/server_models.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:securecalc/src/features/chat/presentation/widgets/app_video_player.dart';

class MediaGridItem extends StatelessWidget {
  final UploadItemModel item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final bool isSquareGrid;

  const MediaGridItem({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.onRename,
    this.onDelete,
    this.isSquareGrid = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content;
    if (item.isFolder) {
      content = isSquareGrid
          ? _buildFolderSquareTile(context, isDark)
          : _buildFolderListTile(context, isDark);
    } else if (item.isImage) {
      content = isSquareGrid
          ? _buildImageSquareTile(context, isDark)
          : _buildImageListTile(context, isDark);
    } else if (item.isVideo) {
      content = isSquareGrid
          ? _buildVideoSquareTile(context, isDark)
          : _buildVideoListTile(context, isDark);
    } else if (item.isAudio) {
      content = isSquareGrid
          ? _buildAudioSquareTile(context, isDark)
          : _buildAudioListTile(context, isDark);
    } else {
      content = isSquareGrid
          ? _buildDocSquareTile(context, isDark)
          : _buildDocListTile(context, isDark);
    }

    return RepaintBoundary(child: content);
  }

  void _showContextMenu(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(item.fileName),
        message: Text(item.isFolder ? 'Folder Actions' : 'File Actions'),
        actions: [
          if (onRename != null)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                onRename!();
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.pencil, size: 20),
                  SizedBox(width: 8),
                  Text('Rename'),
                ],
              ),
            ),
          if (onDelete != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(ctx);
                onDelete!();
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.delete, size: 20),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _buildFolderSquareTile(BuildContext context, bool isDark) {
    const folderColor = Color(0xFF007AFF);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress ?? () => _showContextMenu(context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: folderColor.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.18) : folderColor.withOpacity(0.3),
                  width: 1.0,
                ),
              ),
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: folderColor.withOpacity(0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          CupertinoIcons.folder_fill,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      if (onRename != null || onDelete != null)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(28, 28),
                          onPressed: () => _showContextMenu(context),
                          child: Icon(
                            CupertinoIcons.ellipsis,
                            color: isDark ? Colors.white70 : const Color(0xFF6C6C70),
                            size: 16,
                          ),
                        ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Folder',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderListTile(BuildContext context, bool isDark) {
    const folderColor = Color(0xFF007AFF);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress ?? () => _showContextMenu(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.18) : folderColor.withOpacity(0.2),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: folderColor.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                CupertinoIcons.folder_fill,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.formattedDate.isNotEmpty
                        ? 'Folder  •  ${item.formattedDate}'
                        : 'Folder',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (onRename != null || onDelete != null)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showContextMenu(context),
                child: Icon(
                  CupertinoIcons.ellipsis,
                  color: isDark ? Colors.white70 : const Color(0xFF6C6C70),
                  size: 20,
                ),
              )
            else
              Icon(
                CupertinoIcons.chevron_right,
                color: isDark ? const Color(0xFF48484A) : const Color(0xFFC7C7CC),
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSquareTile(BuildContext context, bool isDark) {
    final mediaUrl = item.fullUrl;
    final headers = ServerApiService.instance.authToken != null
        ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
        : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress ?? () => _showContextMenu(context),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFE5E5EA),
            width: 0.8,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (mediaUrl.isNotEmpty)
                Image.network(
                  mediaUrl,
                  headers: headers,
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (context, error, stackTrace) => _buildFallbackThumbnail(
                    isDark,
                    CupertinoIcons.photo_fill,
                    const Color(0xFFAF52DE),
                  ),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      child: const Center(
                        child: CupertinoActivityIndicator(radius: 10),
                      ),
                    );
                  },
                )
              else
                _buildFallbackThumbnail(
                  isDark,
                  CupertinoIcons.photo_fill,
                  const Color(0xFFAF52DE),
                ),
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.formattedSize,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageListTile(BuildContext context, bool isDark) {
    final mediaUrl = item.fullUrl;
    final headers = ServerApiService.instance.authToken != null
        ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
        : null;

    final subtitle = item.formattedDate.isNotEmpty
        ? '${item.formattedSize}  •  ${item.formattedDate}'
        : item.formattedSize;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress ?? () => _showContextMenu(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFE5E5EA),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 44,
                height: 44,
                child: mediaUrl.isNotEmpty
                    ? Image.network(
                        mediaUrl,
                        headers: headers,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _buildFallbackThumbnail(
                          isDark,
                          CupertinoIcons.photo_fill,
                          const Color(0xFFAF52DE),
                        ),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                            child: const Center(
                              child: CupertinoActivityIndicator(radius: 8),
                            ),
                          );
                        },
                      )
                    : _buildFallbackThumbnail(
                        isDark,
                        CupertinoIcons.photo_fill,
                        const Color(0xFFAF52DE),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onRename != null || onDelete != null)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showContextMenu(context),
                child: Icon(
                  CupertinoIcons.ellipsis,
                  color: isDark ? Colors.white70 : const Color(0xFF6C6C70),
                  size: 20,
                ),
              )
            else
              Icon(
                CupertinoIcons.chevron_right,
                color: isDark ? const Color(0xFF48484A) : const Color(0xFFC7C7CC),
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSquareTile(BuildContext context, bool isDark) {
    final mediaUrl = item.fullUrl;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress ?? () => _showContextMenu(context),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFE5E5EA),
            width: 0.8,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: VideoThumbnailCard(
            mediaUrl: mediaUrl,
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoListTile(BuildContext context, bool isDark) {
    final mediaUrl = item.fullUrl;
    final headers = ServerApiService.instance.authToken != null
        ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
        : null;

    final subtitle = item.formattedDate.isNotEmpty
        ? '${item.formattedSize}  •  ${item.formattedDate}'
        : item.formattedSize;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress ?? () => _showContextMenu(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFE5E5EA),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (mediaUrl.isNotEmpty)
                      Image.network(
                        mediaUrl,
                        headers: headers,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _buildFallbackThumbnail(
                          isDark,
                          CupertinoIcons.videocam_fill,
                          const Color(0xFF007AFF),
                        ),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                            child: const Center(
                              child: CupertinoActivityIndicator(radius: 8),
                            ),
                          );
                        },
                      )
                    else
                      _buildFallbackThumbnail(
                        isDark,
                        CupertinoIcons.videocam_fill,
                        const Color(0xFF007AFF),
                      ),
                    Center(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.play_fill,
                          color: Colors.white,
                          size: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onRename != null || onDelete != null)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showContextMenu(context),
                child: Icon(
                  CupertinoIcons.ellipsis,
                  color: isDark ? Colors.white70 : const Color(0xFF6C6C70),
                  size: 20,
                ),
              )
            else
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.play_arrow_solid,
                  color: Color(0xFF007AFF),
                  size: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioSquareTile(BuildContext context, bool isDark) {
    const accentColor = Color(0xFFFF9500);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress ?? () => _showContextMenu(context),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFE5E5EA),
            width: 0.8,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        CupertinoIcons.waveform,
                        color: accentColor,
                        size: 18,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.formattedSize,
                        style: const TextStyle(
                          color: accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  item.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioListTile(BuildContext context, bool isDark) {
    const accentColor = Color(0xFFFF9500);

    final subtitle = item.formattedDate.isNotEmpty
        ? '${item.formattedSize}  •  ${item.formattedDate}'
        : item.formattedSize;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress ?? () => _showContextMenu(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFE5E5EA),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                CupertinoIcons.waveform_circle_fill,
                color: accentColor,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onRename != null || onDelete != null)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showContextMenu(context),
                child: Icon(
                  CupertinoIcons.ellipsis,
                  color: isDark ? Colors.white70 : const Color(0xFF6C6C70),
                  size: 20,
                ),
              )
            else
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.play_arrow_solid,
                  color: accentColor,
                  size: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocSquareTile(BuildContext context, bool isDark) {
    final ext = item.fileName.split('.').last.toUpperCase();
    final extColor = _getExtColor(ext);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress ?? () => _showContextMenu(context),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFE5E5EA),
            width: 0.8,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: extColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          ext.length > 4 ? ext.substring(0, 4) : ext,
                          style: TextStyle(
                            color: extColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: extColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.formattedSize,
                        style: TextStyle(
                          color: extColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  item.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocListTile(BuildContext context, bool isDark) {
    final ext = item.fileName.split('.').last.toUpperCase();
    final extColor = _getExtColor(ext);

    final subtitle = item.formattedDate.isNotEmpty
        ? '${item.formattedSize}  •  ${item.formattedDate}'
        : item.formattedSize;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress ?? () => _showContextMenu(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFE5E5EA),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: extColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  ext.length > 4 ? ext.substring(0, 4) : ext,
                  style: TextStyle(
                    color: extColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onRename != null || onDelete != null)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showContextMenu(context),
                child: Icon(
                  CupertinoIcons.ellipsis,
                  color: isDark ? Colors.white70 : const Color(0xFF6C6C70),
                  size: 20,
                ),
              )
            else
              Icon(
                CupertinoIcons.chevron_right,
                color: isDark ? const Color(0xFF48484A) : const Color(0xFFC7C7CC),
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackThumbnail(bool isDark, IconData icon, Color color) {
    return Container(
      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
      child: Center(
        child: Icon(
          icon,
          color: color.withOpacity(0.7),
          size: 36,
        ),
      ),
    );
  }

  Color _getExtColor(String ext) {
    switch (ext) {
      case 'PDF':
        return const Color(0xFFFF3B30);
      case 'DOC':
      case 'DOCX':
        return const Color(0xFF007AFF);
      case 'XLS':
      case 'XLSX':
      case 'CSV':
        return const Color(0xFF34C759);
      case 'PPT':
      case 'PPTX':
        return const Color(0xFFFF9500);
      case 'ZIP':
      case 'RAR':
      case '7Z':
        return const Color(0xFFAF52DE);
      default:
        return const Color(0xFF8E8E93);
    }
  }
}
