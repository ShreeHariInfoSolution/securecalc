import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/server_api_service.dart';
import '../widgets/app_video_player.dart';
import '../widgets/photo_gallery_viewer.dart';
import 'chat_info_page.dart';

class ChatMediaGalleryPage extends StatefulWidget {
  final String title;
  final List<ChatMediaItem> mediaItems;
  final List<ChatMessage> messages;

  const ChatMediaGalleryPage({
    super.key,
    required this.title,
    required this.mediaItems,
    required this.messages,
  });

  @override
  State<ChatMediaGalleryPage> createState() => _ChatMediaGalleryPageState();
}

class _ChatMediaGalleryPageState extends State<ChatMediaGalleryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<ChatMediaItem> get _photosAndVideos =>
      widget.mediaItems.where((x) => x.folder == 'image' || x.folder == 'video').toList();

  List<ChatMediaItem> get _docsAndAudio =>
      widget.mediaItems.where((x) => x.folder == 'doc' || x.folder == 'audio').toList();

  List<String> get _sharedLinks {
    final links = <String>[];
    final linkRegex = RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);
    for (final m in widget.messages) {
      final matches = linkRegex.allMatches(m.content);
      for (final match in matches) {
        final raw = m.content.substring(match.start, match.end);
        if (!links.contains(raw)) {
          links.add(raw);
        }
      }
    }
    return links;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openImageGallery(ChatMediaItem selected) {
    final imageItems = widget.mediaItems.where((x) => x.folder == 'image').toList();
    final photos = imageItems.map((item) {
      return ChatMessage(
        id: item.id,
        senderId: item.isMe ? 'user' : 'peer',
        content: '',
        timestamp: item.createdAt,
        type: 'image/jpeg',
        mediaUrl: item.fullUrl,
        fileName: item.fileName,
      );
    }).toList();

    final initialIndex = imageItems.indexWhere((x) => x.id == selected.id);
    PhotoGalleryViewer.open(
      context,
      photos: photos,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
    );
  }

  Future<void> _openDocument(ChatMediaItem item) async {
    final url = item.fullUrl;
    if (url.isEmpty) return;
    try {
      final cached = await AttachmentCacheService.instance.resolveLocalPath(url);
      if (cached != null && File(cached).existsSync()) {
        await OpenFilex.open(cached);
      } else if (url.startsWith('http://') || url.startsWith('https://')) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[MEDIA GALLERY DOC ERROR] $e');
    }
  }

  Future<void> _launchUrl(String rawUrl) async {
    var clean = rawUrl.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'https://$clean';
    }
    try {
      await launchUrl(Uri.parse(clean), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[MEDIA GALLERY LINK ERROR] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '${_photosAndVideos.length} Media • ${_docsAndAudio.length} Docs • ${_sharedLinks.length} Links',
              style: const TextStyle(fontSize: 11, color: AppTheme.subtitleGrey),
            ),
          ],
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.subtitleGrey,
          indicatorColor: AppTheme.primaryColor,
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'Media (${_photosAndVideos.length})'),
            Tab(text: 'Docs (${_docsAndAudio.length})'),
            Tab(text: 'Links (${_sharedLinks.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Media Tab (Photos & Videos)
          _photosAndVideos.isEmpty
              ? _buildEmptyState('No photos or videos shared yet.', Icons.photo_library_outlined, isDark)
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: _photosAndVideos.length,
                  itemBuilder: (context, index) {
                    final item = _photosAndVideos[index];
                    final isVideo = item.folder == 'video';
                    return GestureDetector(
                      onTap: () {
                        if (isVideo) {
                          AppVideoPlayerModal.open(
                            context,
                            mediaUrl: item.rawUrl,
                            title: item.fileName,
                          );
                        } else {
                          _openImageGallery(item);
                        }
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ChatMediaThumbnail(rawUrl: item.rawUrl),
                            if (isVideo)
                              Container(
                                color: Colors.black26,
                                child: const Center(
                                  child: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Colors.black54,
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

          // 2. Docs Tab
          _docsAndAudio.isEmpty
              ? _buildEmptyState('No documents or audio shared yet.', Icons.insert_drive_file_outlined, isDark)
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _docsAndAudio.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _docsAndAudio[index];
                    final isAudio = item.folder == 'audio';
                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                          child: Icon(
                            isAudio ? Icons.mic_rounded : Icons.insert_drive_file_rounded,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        title: Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        subtitle: Text(
                          isAudio ? 'Voice note' : 'Document file',
                          style: const TextStyle(fontSize: 12, color: AppTheme.subtitleGrey),
                        ),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: AppTheme.subtitleGrey),
                        onTap: () => _openDocument(item),
                      ),
                    );
                  },
                ),

          // 3. Links Tab
          _sharedLinks.isEmpty
              ? _buildEmptyState('No web links shared in this chat.', Icons.link_rounded, isDark)
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _sharedLinks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final link = _sharedLinks[index];
                    final uri = Uri.tryParse(link.startsWith('http') ? link : 'https://$link');
                    final host = uri?.host.replaceAll('www.', '') ?? link;

                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFEFF6FF),
                          child: Icon(Icons.language_rounded, color: AppTheme.primaryColor),
                        ),
                        title: Text(
                          host.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        subtitle: Text(
                          link,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppTheme.subtitleGrey),
                        ),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: AppTheme.subtitleGrey),
                        onTap: () => _launchUrl(link),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg, IconData icon, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppTheme.subtitleGrey),
          const SizedBox(height: 12),
          Text(
            msg,
            style: const TextStyle(color: AppTheme.subtitleGrey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Resolves attachment-cache entries and network URLs with full authentication headers,
/// showing an animated shimmer loading placeholder while loading.
class ChatMediaThumbnail extends StatefulWidget {
  final String rawUrl;

  const ChatMediaThumbnail({super.key, required this.rawUrl});

  @override
  State<ChatMediaThumbnail> createState() => _ChatMediaThumbnailState();
}

class _ChatMediaThumbnailState extends State<ChatMediaThumbnail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;
  String? _resolvedPath;
  bool _isResolving = true;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant ChatMediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawUrl != widget.rawUrl) {
      _resolvedPath = null;
      _isResolving = true;
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _resolveImage() async {
    final rawUrl = widget.rawUrl.trim();
    if (rawUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _resolvedPath = null;
          _isResolving = false;
        });
      }
      return;
    }

    if (File(rawUrl).existsSync()) {
      if (mounted) {
        setState(() {
          _resolvedPath = rawUrl;
          _isResolving = false;
        });
      }
      return;
    }

    final networkUrl = resolveAvatarUrl(rawUrl);
    var cached = await AttachmentCacheService.instance.resolveLocalPath(rawUrl);
    if (networkUrl != null) {
      cached ??= await AttachmentCacheService.instance.resolveLocalPath(networkUrl);
    }

    if (!mounted || rawUrl != widget.rawUrl.trim()) return;

    setState(() {
      _resolvedPath = cached ?? networkUrl ?? rawUrl;
      _isResolving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isResolving) {
      return MediaThumbnailShimmer(controller: _shimmerController);
    }

    if (_resolvedPath == null || _resolvedPath!.isEmpty) {
      return const MediaThumbnailUnavailable();
    }

    final path = _resolvedPath!;
    final isLocal = !path.startsWith('http://') && !path.startsWith('https://');

    final headers = ServerApiService.instance.authToken != null
        ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
        : null;

    final image = isLocal
        ? Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: 320,
            errorBuilder: (_, __, ___) => const MediaThumbnailUnavailable(),
          )
        : Image.network(
            path,
            headers: headers,
            fit: BoxFit.cover,
            cacheWidth: 320,
            errorBuilder: (_, __, ___) => const MediaThumbnailUnavailable(),
          );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: image,
    );
  }
}

class MediaThumbnailShimmer extends StatelessWidget {
  final AnimationController controller;

  const MediaThumbnailShimmer({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    final highlightColor = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + (controller.value * 3.0), -0.3),
              end: Alignment(1.0 + (controller.value * 3.0), 0.3),
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.1, 0.5, 0.9],
            ),
          ),
        );
      },
    );
  }
}

class MediaThumbnailUnavailable extends StatelessWidget {
  const MediaThumbnailUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 22,
          color: AppTheme.subtitleGrey.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
