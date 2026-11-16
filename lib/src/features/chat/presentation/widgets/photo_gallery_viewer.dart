import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/e2e_crypto_service.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import 'app_video_player.dart';

class PhotoGalleryViewer extends StatefulWidget {
  final List<ChatMessage> photos;
  final int initialIndex;
  final ValueChanged<ChatMessage>? onReply;

  const PhotoGalleryViewer({
    super.key,
    required this.photos,
    this.initialIndex = 0,
    this.onReply,
  });

  static void open(
    BuildContext context, {
    required List<ChatMessage> photos,
    int initialIndex = 0,
    ValueChanged<ChatMessage>? onReply,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.94),
        pageBuilder: (context, animation, secondaryAnimation) =>
            PhotoGalleryViewer(
          photos: photos,
          initialIndex: initialIndex,
          onReply: onReply,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<PhotoGalleryViewer> createState() => _PhotoGalleryViewerState();
}

class _PhotoGalleryViewerState extends State<PhotoGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showControls = true;
  bool _isSharing = false;
  double _dragOffset = 0.0;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 90 ||
        (details.primaryVelocity != null &&
            details.primaryVelocity!.abs() > 300)) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragOffset = 0.0;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.photos.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<String?> _resolveLocalFile(ChatMessage msg) async {
    final rawUrl = msg.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) return null;

    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      if (File(rawUrl).existsSync()) return rawUrl;
    }

    final cached = await AttachmentCacheService.instance.resolveLocalPath(
      rawUrl,
    );
    if (cached != null && File(cached).existsSync()) return cached;

    try {
      final networkUrl = resolveAvatarUrl(rawUrl);
      if (networkUrl == null) return null;

      final headers = ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : null;

      final response = await http.get(Uri.parse(networkUrl), headers: headers);
      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final ext = msg.fileName?.split('.').last ?? 'jpg';
        final file = File(
          '${dir.path}/shared_photo_${msg.id}_${DateTime.now().millisecondsSinceEpoch}.$ext',
        );
        await file.writeAsBytes(response.bodyBytes);
        AttachmentCacheService.instance.updateCache(rawUrl, file.path);
        return file.path;
      }
    } catch (e) {
      debugPrint('[GALLERY DOWNLOAD ERROR] $e');
    }
    return null;
  }

  Future<void> _shareCurrentPhoto() async {
    if (_isSharing || widget.photos.isEmpty) return;
    setState(() => _isSharing = true);
    HapticFeedback.mediumImpact();

    try {
      final currentMsg = widget.photos[_currentIndex];
      final filePath = await _resolveLocalFile(currentMsg);

      if (filePath != null && File(filePath).existsSync()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(filePath)],
            text: currentMsg.content.isNotEmpty ? currentMsg.content : null,
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not prepare photo for sharing.'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[SHARE ERROR] $e');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  String _formatTimestamp(DateTime time) {
    final hour24 = time.hour;
    final hour = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
    final min = time.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '${time.day}/${time.month}/${time.year} $hour:$min $period';
  }

  bool _canReply(ChatMessage m) =>
      widget.onReply != null && int.tryParse(m.id) != null; // only server-confirmed msgs

  String? _captionOf(ChatMessage m) {
    final c = m.content.trim();
    const generic = {'photo', 'video', 'sent a photo', 'sent a video', '[attachment]', 'gif'};
    if (c.isEmpty || generic.contains(c.toLowerCase())) return null;
    if (c.toLowerCase() == (m.fileName ?? '').toLowerCase()) return null;
    return c;
  }

  void _replyToCurrent() {
    final msg = widget.photos[_currentIndex];
    HapticFeedback.selectionClick();
    final cb = widget.onReply;
    Navigator.of(context).pop();
    // wait for the pop so the keyboard focus lands on the chat input
    WidgetsBinding.instance.addPostFrameCallback((_) => cb?.call(msg));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) return const SizedBox();

    final double bgOpacity = (1.0 - (_dragOffset.abs() / 350.0)).clamp(
      0.2,
      1.0,
    );

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: bgOpacity),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => setState(() => _showControls = !_showControls),
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            transform: Matrix4.translationValues(0, _dragOffset, 0),
            child: Stack(
              children: [
                // PageView Gallery
                PageView.builder(
                  controller: _pageController,
                  itemCount: widget.photos.length,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemBuilder: (context, index) {
                    final photo = widget.photos[index];
                    return _GalleryPhotoItem(
                      photoMessage: photo,
                      onLongPress: _shareCurrentPhoto,
                    );
                  },
                ),

                // Top Header Bar
                if (_showControls)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Close button
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: Colors.white24,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),

                          // Counter index
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_currentIndex + 1} of ${widget.photos.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _formatTimestamp(
                                  widget.photos[_currentIndex].timestamp,
                                ),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),

                          // Share button
                          GestureDetector(
                            onTap: _shareCurrentPhoto,
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: Colors.white24,
                                shape: BoxShape.circle,
                              ),
                              child: _isSharing
                                  ? const Padding(
                                      padding: EdgeInsets.all(9.0),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      CupertinoIcons.share,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_showControls)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_captionOf(widget.photos[_currentIndex]) != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                _captionOf(widget.photos[_currentIndex])!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 15),
                              ),
                            ),
                          if (_canReply(widget.photos[_currentIndex]))
                            GestureDetector(
                              onTap: _replyToCurrent,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(CupertinoIcons.reply, color: Colors.white, size: 18),
                                    SizedBox(width: 6),
                                    Text('Reply',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryPhotoItem extends StatefulWidget {
  final ChatMessage photoMessage;
  final VoidCallback onLongPress;

  const _GalleryPhotoItem({
    required this.photoMessage,
    required this.onLongPress,
  });

  @override
  State<_GalleryPhotoItem> createState() => _GalleryPhotoItemState();
}

class _GalleryPhotoItemState extends State<_GalleryPhotoItem> {
  String? _resolvedPath;
  bool _isLoading = true;
  bool _isDownloading = false;
  bool _downloadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final rawUrl = widget.photoMessage.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final cachedSync =
        AttachmentCacheService.instance.resolveLocalPathSync(rawUrl);
    if (cachedSync != null && File(cachedSync).existsSync()) {
      if (mounted) {
        setState(() {
          _resolvedPath = cachedSync;
          _isLoading = false;
          _downloadFailed = false;
        });
      }
      return;
    }

    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      if (File(rawUrl).existsSync()) {
        if (mounted) {
          setState(() {
            _resolvedPath = rawUrl;
            _isLoading = false;
            _downloadFailed = false;
          });
        }
        return;
      }
    }

    final cached = await AttachmentCacheService.instance.resolveLocalPath(
      rawUrl,
    );
    if (cached != null && File(cached).existsSync()) {
      if (mounted) {
        setState(() {
          _resolvedPath = cached;
          _isLoading = false;
          _downloadFailed = false;
        });
      }
      return;
    }

    // Automatically download and decrypt photo from API
    await _downloadAndCachePhoto();
  }

  Future<void> _downloadAndCachePhoto() async {
    final rawUrl = widget.photoMessage.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) return;

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isDownloading = true;
        _downloadFailed = false;
      });
    }

    try {
      final networkUrl = resolveAvatarUrl(rawUrl);
      if (networkUrl != null) {
        final headers = ServerApiService.instance.authToken != null
            ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
            : <String, String>{};
        final response = await http
            .get(Uri.parse(networkUrl), headers: headers)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final rawBytes = response.bodyBytes;
          var fileBytes = rawBytes;
          try {
            final activeChatId = ServerChatManager.instance.activeChatId;
            if (activeChatId != null && activeChatId.isNotEmpty) {
              fileBytes = E2eCryptoService.instance.decryptFileBytes(
                rawBytes,
                'chat_key_$activeChatId',
              );
            }
          } catch (_) {
            fileBytes = rawBytes;
          }

          final dir = await getApplicationDocumentsDirectory();
          final attDir = Directory(
            '${dir.path}${Platform.pathSeparator}chat_attachments',
          );
          if (!attDir.existsSync()) {
            await attDir.create(recursive: true);
          }
          final safeName = widget.photoMessage.fileName?.isNotEmpty == true
              ? widget.photoMessage.fileName!.replaceAll(
                  RegExp(r'[\\/:*?"<>|]'),
                  '_',
                )
              : 'img_${widget.photoMessage.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final file = File(
            '${attDir.path}${Platform.pathSeparator}$safeName',
          );
          await file.writeAsBytes(fileBytes, flush: true);

          AttachmentCacheService.instance.updateCache(rawUrl, file.path);
          if (mounted) {
            setState(() {
              _resolvedPath = file.path;
              _isDownloading = false;
              _downloadFailed = false;
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadFailed = true;
        });
      }
    } catch (e) {
      debugPrint('[FULLSCREEN GALLERY DOWNLOAD ERROR] $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _isDownloading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            SizedBox(height: 12),
            Text(
              'Loading photo…',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final path = _resolvedPath;
    if (path == null || _downloadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_rounded,
              size: 48,
              color: Colors.white38,
            ),
            const SizedBox(height: 12),
            const Text(
              'Failed to load photo',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            CupertinoButton(
              color: Colors.white24,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              borderRadius: BorderRadius.circular(20),
              onPressed: () => _downloadAndCachePhoto(),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Retry Download',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final isLocal = !path.startsWith('http://') && !path.startsWith('https://');

    final isVideo = widget.photoMessage.type.toLowerCase().contains('video') ||
        ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'].any(
          (ext) =>
              (widget.photoMessage.mediaUrl ?? '').toLowerCase().contains('.$ext') ||
              (widget.photoMessage.fileName ?? '').toLowerCase().endsWith('.$ext'),
        ) ||
        widget.photoMessage.previewText.contains('Video');

    if (isVideo) {
      return GestureDetector(
        onTap: () {
          AppVideoPlayerModal.open(
            context,
            mediaUrl: path,
            title: widget.photoMessage.fileName ?? 'Video',
          );
        },
        onLongPress: widget.onLongPress,
        child: Center(
          child: VideoThumbnailCard(
            mediaUrl: path,
            width: double.infinity,
            height: 320,
            showDefaultOverlay: true,
          ),
        ),
      );
    }

    Widget imageWidget;
    if (isLocal) {
      imageWidget = Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_rounded,
                size: 48,
                color: Colors.white38,
              ),
              const SizedBox(height: 12),
              const Text(
                'Failed to render image file',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              CupertinoButton(
                color: Colors.white24,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                borderRadius: BorderRadius.circular(20),
                onPressed: () => _downloadAndCachePhoto(),
                child: const Text(
                  'Re-download',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final headers = ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : null;
      imageWidget = Image.network(
        path,
        headers: headers,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
        errorBuilder: (context, error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_rounded,
                size: 48,
                color: Colors.white38,
              ),
              const SizedBox(height: 12),
              const Text(
                'Failed to load image from network',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              CupertinoButton(
                color: Colors.white24,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                borderRadius: BorderRadius.circular(20),
                onPressed: () => _downloadAndCachePhoto(),
                child: const Text(
                  'Retry Download',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4.0,
        child: Center(child: imageWidget),
      ),
    );
  }
}
