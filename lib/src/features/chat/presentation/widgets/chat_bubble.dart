import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/services/e2e_crypto_service.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/attachment_cache_service.dart';
import 'photo_gallery_viewer.dart';

class ChatBubble extends StatefulWidget {
  final String message;
  final bool isMe;
  final DateTime timestamp;
  final bool isRead;
  final bool isEdited;
  final bool isDeleted;
  final bool isSaved;
  final String? type;
  final String? mediaUrl;
  final String? fileName;
  final List<String>? reactions;
  final String? senderName;
  final String? replySender;
  final String? replyText;
  final String? chatId;
  final List<ChatMessage>? groupedImages;
  final int? replyToId;
  final ChatMessage? repliedMessage;
  final Function(int)? onTapReply;
  final bool isHighlighted;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.timestamp,
    this.isRead = true,
    this.isEdited = false,
    this.isDeleted = false,
    this.isSaved = false,
    this.type = 'text',
    this.mediaUrl,
    this.fileName,
    this.reactions,
    this.senderName,
    this.replySender,
    this.replyText,
    this.chatId,
    this.groupedImages,
    this.replyToId,
    this.repliedMessage,
    this.onTapReply,
    this.isHighlighted = false,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  AudioPlayer? _audioPlayer;
  StreamSubscription<PlayerState>? _audioStateSubscription;
  String? _downloadedPath;
  bool _isDownloading = false;
  bool _isPlayingAudio = false;
  bool _isMediaRevealed = false;
  bool _downloadFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.mediaUrl?.isNotEmpty == true) {
      unawaited(_restoreDownloadedAttachment());
    }
  }

  @override
  void didUpdateWidget(ChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      unawaited(_restoreDownloadedAttachment());
    }
  }

  AudioPlayer _ensureAudioPlayer() {
    final existing = _audioPlayer;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _audioPlayer = player;
    _audioStateSubscription = player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlayingAudio = state == PlayerState.playing);
      }
    });
    return player;
  }

  bool _isAbsoluteFilePath(String path) =>
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
      RegExp(r'^/(?:data|storage|private|var|tmp|Users)/').hasMatch(path);

  bool get _hasValidLocalFile =>
      _downloadedPath != null && File(_downloadedPath!).existsSync();

  Future<String> _getLocalAttachmentPath() async {
    final documents = await getApplicationDocumentsDirectory();
    final attachmentDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}chat_attachments',
    );
    await attachmentDirectory.create(recursive: true);

    final mediaKey = (widget.mediaUrl ?? 'att_${widget.timestamp.millisecondsSinceEpoch}')
        .split('/')
        .last
        .split('\\')
        .last
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeName = _attachmentName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    return '${attachmentDirectory.path}${Platform.pathSeparator}${mediaKey}_$safeName';
  }

  Future<void> _restoreDownloadedAttachment() async {
    try {
      final mediaPath = widget.mediaUrl;
      final cachedPath = await AttachmentCacheService.instance.resolveLocalPath(mediaPath);
      if (cachedPath != null) {
        if (mounted) {
          setState(() {
            _downloadedPath = cachedPath;
            _isMediaRevealed = true;
            _downloadFailed = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _downloadedPath = null;
          _isMediaRevealed = false;
          _downloadFailed = false;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _audioStateSubscription?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }

  String _resolveRemoteMediaUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;

    String cleanPath = path;
    if (_isAbsoluteFilePath(path)) {
      if (path.contains('uploads/')) {
        cleanPath = 'uploads/${path.split('uploads/').last}';
      } else if (path.contains('files/')) {
        cleanPath = 'files/${path.split('files/').last}';
      } else {
        final name = widget.fileName?.trim();
        if (name != null && name.isNotEmpty) {
          cleanPath = name;
        } else {
          cleanPath = path.split(RegExp(r'[/\\]')).last;
        }
      }
    }

    final normalized = cleanPath.replaceFirst(RegExp(r'^/+'), '');
    final apiBase = ServerApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final filePath = normalized.startsWith('api/files/')
        ? normalized.substring('api/files/'.length)
        : normalized.startsWith('files/')
        ? normalized.substring('files/'.length)
        : normalized.startsWith('calculatorchat/')
        ? normalized.substring('calculatorchat/'.length)
        : normalized;
    final encodedPath = filePath.split('/').map(Uri.encodeComponent).join('/');
    return '$apiBase/files/$encodedPath';
  }

  String get _attachmentName {
    final suppliedName = widget.fileName?.trim();
    if (suppliedName != null && suppliedName.isNotEmpty) return suppliedName;
    final path = widget.mediaUrl ?? '';
    final segments = Uri.tryParse(path)?.pathSegments ?? const <String>[];
    final name = segments.isEmpty ? null : segments.last;
    return name == null || name.isEmpty ? 'Attachment' : name;
  }

  bool get _isImage => widget.type?.toLowerCase().startsWith('image') == true;
  bool get _isVideo => widget.type?.toLowerCase().startsWith('video') == true;
  bool get _isAudio => widget.type?.toLowerCase().startsWith('audio') == true;

  Future<String> _downloadAttachment() async {
    if (_hasValidLocalFile) {
      return _downloadedPath!;
    }
    final mediaUrl = widget.mediaUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) {
      throw Exception('This attachment has no download URL.');
    }
    if (mounted) {
      setState(() {
        _isDownloading = true;
        _downloadFailed = false;
      });
    }
    try {
      if (_isAbsoluteFilePath(mediaUrl) && File(mediaUrl).existsSync()) {
        _downloadedPath = mediaUrl;
        _downloadFailed = false;
        return mediaUrl;
      }

      final remoteUrl = _resolveRemoteMediaUrl(mediaUrl);
      final headers = ServerApiService.instance.authToken == null
          ? <String, String>{}
          : {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'};

      final response = await http.get(
        Uri.parse(remoteUrl),
        headers: headers,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed (${response.statusCode}).');
      }

      final rawBytes = response.bodyBytes;
      final secretKey = widget.chatId != null ? 'chat_key_${widget.chatId}' : null;
      final fileBytes = secretKey != null
          ? E2eCryptoService.instance.decryptFileBytes(rawBytes, secretKey)
          : rawBytes;

      final outputPath = await _getLocalAttachmentPath();
      final output = File(outputPath);
      await output.writeAsBytes(fileBytes, flush: true);
      _downloadedPath = output.path;
      AttachmentCacheService.instance.updateCache(mediaUrl, output.path);
      _downloadFailed = false;
      return output.path;
    } catch (e) {
      if (mounted) {
        setState(() => _downloadFailed = true);
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _saveAttachment() async {
    AppPreferences.isPickerActive = true;
    try {
      final path = await _downloadAttachment();
      final safeName = _attachmentName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final savedUri = await FilePicker.saveFile(
        fileName: safeName,
        bytes: await File(path).readAsBytes(),
      );
      if (savedUri == null) return;
      AppToast.show('$_attachmentName saved.');
    } catch (error) {
      AppToast.show('Could not download attachment: $error', isError: true);
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _revealImage() async {
    try {
      await _downloadAttachment();
      if (mounted) {
        setState(() {
          _isMediaRevealed = true;
          _downloadFailed = false;
        });
      }
    } catch (error) {
      AppToast.show('Could not download photo: $error', isError: true);
    }
  }

  Future<void> _showImageViewer() async {
    final localPath = _hasValidLocalFile ? _downloadedPath : widget.mediaUrl;
    final singleMsg = ChatMessage(
      id: widget.timestamp.millisecondsSinceEpoch.toString(),
      senderId: widget.isMe ? 'user' : 'peer',
      content: widget.message,
      timestamp: widget.timestamp,
      type: widget.type ?? 'image/jpeg',
      mediaUrl: localPath,
      fileName: widget.fileName,
    );
    PhotoGalleryViewer.open(context, photos: [singleMsg], initialIndex: 0);
  }

  Future<void> _openAttachment() async {
    try {
      final path = await _downloadAttachment();
      await OpenFilex.open(path);
    } catch (error) {
      AppToast.show('Could not open attachment: $error', isError: true);
    }
  }

  Future<void> _toggleAudioPlayback() async {
    try {
      if (_isPlayingAudio) {
        await _audioPlayer?.pause();
        return;
      }
      final path = await _downloadAttachment();
      await _ensureAudioPlayer().play(DeviceFileSource(path));
    } catch (error) {
      AppToast.show('Could not play voice message: $error', isError: true);
    }
  }

  Widget _buildTimestampWidget(bool isDark) {
    final time = widget.timestamp.toLocal();
    final hour24 = time.hour;
    final hour = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
    final min = time.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final formattedTime = '$hour:$min $period';

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.isSaved) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : (widget.isMe
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.grey.withValues(alpha: 0.18)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bookmark_rounded,
                  size: 9,
                  color: widget.isMe
                      ? Colors.white.withValues(alpha: 0.9)
                      : (isDark ? Colors.white70 : Colors.grey.shade700),
                ),
                const SizedBox(width: 2),
                Text(
                  'Saved',
                  style: TextStyle(
                    color: widget.isMe
                        ? Colors.white.withValues(alpha: 0.9)
                        : (isDark ? Colors.white70 : Colors.grey.shade700),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (widget.isEdited) ...[
          Text(
            'edited ',
            style: TextStyle(
              color: widget.isMe
                  ? Colors.white.withValues(alpha: 0.7)
                  : (isDark ? Colors.white60 : AppTheme.subtitleGrey),
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        Text(
          formattedTime,
          style: TextStyle(
            color: widget.isMe
                ? Colors.white.withValues(alpha: 0.75)
                : (isDark ? Colors.white60 : AppTheme.subtitleGrey),
            fontSize: 11,
          ),
        ),
        if (widget.isMe) ...[
          const SizedBox(width: 3),
          Icon(
            widget.isRead ? Icons.done_all_rounded : Icons.done_rounded,
            size: 13,
            color: widget.isRead
                ? const Color(0xFF53BDEB)
                : Colors.white.withValues(alpha: 0.8),
          ),
        ],
      ],
    );
  }

  Widget _buildReplyMediaThumbnail(ChatMessage msg, bool isDark) {
    final url = msg.mediaUrl;
    final type = msg.type.toLowerCase();

    if (type.startsWith('image/') ||
        type == 'image' ||
        (url != null &&
            ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic']
                .contains(url.split('.').last.split('?').first.toLowerCase()))) {
      if (url != null && url.isNotEmpty) {
        return FutureBuilder<String?>(
          future: AttachmentCacheService.instance.resolveLocalPath(url),
          builder: (context, snapshot) {
            final localPath = snapshot.data;
            if (localPath != null &&
                localPath.isNotEmpty &&
                File(localPath).existsSync()) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(localPath),
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              );
            }
            final resolved = _resolveRemoteMediaUrl(url);
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Image.network(
                  resolved,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF3F51B5), Color(0xFF7E57C2)],
                      ),
                    ),
                    child: const Icon(
                      Icons.image_outlined,
                      size: 16,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: const LinearGradient(
            colors: [Color(0xFF3F51B5), Color(0xFF7E57C2)],
          ),
        ),
        child: const Icon(
          Icons.image_outlined,
          size: 16,
          color: Colors.white70,
        ),
      );
    }

    if (type.startsWith('video/') || type == 'video') {
      return _buildReplyIconBadge(Icons.play_circle_fill_rounded);
    }

    if (type.startsWith('audio/') || type == 'audio') {
      return _buildReplyIconBadge(Icons.mic_rounded);
    }

    return _buildReplyIconBadge(Icons.insert_drive_file_rounded);
  }

  Widget _buildReplyIconBadge(IconData icon) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        icon,
        size: 18,
        color: widget.isMe ? Colors.white : AppTheme.primaryColor,
      ),
    );
  }

  Widget _buildBubbleContent(
    BuildContext context,
    bool isDark,
    Color textColor,
    String? mediaUrl,
  ) {
    final hasMedia = mediaUrl != null && mediaUrl.isNotEmpty;
    final hasReply = widget.replyText != null;
    final hasText = widget.message.isNotEmpty && widget.message != '[Attachment]';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasReply) ...[
          GestureDetector(
            onTap: () {
              if (widget.onTapReply != null && widget.replyToId != null) {
                widget.onTapReply!(widget.replyToId!);
              }
            },
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: widget.isMe
                    ? Colors.black.withValues(alpha: 0.14)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(9),
                border: Border(
                  left: BorderSide(
                    color: widget.isMe
                        ? Colors.white.withValues(alpha: 0.88)
                        : AppTheme.primaryColor,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.replySender ?? 'Reply',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.replyText!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.82),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.repliedMessage != null &&
                      (widget.repliedMessage!.mediaUrl?.isNotEmpty == true ||
                          widget.repliedMessage!.type != 'text')) ...[
                    const SizedBox(width: 6),
                    _buildReplyMediaThumbnail(widget.repliedMessage!, isDark),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (hasMedia) ...[
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              _buildAttachment(
                isDark,
                mediaUrl,
              ),
              if (_isImage)
                Positioned(
                  bottom: 6,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _buildTimestampWidget(isDark),
                  ),
                ),
            ],
          ),
          if (!_isImage && hasText) const SizedBox(height: 6),
        ],
        if (hasText) ...[
          if (_isImage && hasMedia)
            const SizedBox.shrink()
          else if (hasMedia && !_isImage)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    widget.message,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15.0,
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _buildTimestampWidget(isDark),
                ),
              ],
            )
          else
            RichText(
              text: TextSpan(
                text: widget.message,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15.0,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                  fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                ),
                children: [
                  const TextSpan(text: '    '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: _buildTimestampWidget(isDark),
                    ),
                  ),
                ],
              ),
            ),
        ] else if (!hasMedia && widget.message.isEmpty) ...[
          _buildTimestampWidget(isDark),
        ] else if (hasMedia && !_isImage) ...[
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _buildTimestampWidget(isDark),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAttachment(
    bool isDark,
    String? mediaUrl,
  ) {
    if (mediaUrl == null || mediaUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasLocal = _hasValidLocalFile;
    final resolvedUrl = _resolveRemoteMediaUrl(mediaUrl);

    // ─── 1. IMAGE ATTACHMENT ────────────────────────────────────────────────
    if (_isImage) {
      final showFullImage = hasLocal && _isMediaRevealed;

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: showFullImage ? _showImageViewer : _revealImage,
          child: Container(
            height: 210,
            width: 260,
            color: isDark ? const Color(0xFF263238) : const Color(0xFFE7E9EC),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (showFullImage)
                  Image.file(
                    File(_downloadedPath!),
                    height: 210,
                    width: 260,
                    fit: BoxFit.cover,
                  )
                else if (hasLocal)
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Image.file(
                      File(_downloadedPath!),
                      height: 210,
                      width: 260,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Image.network(
                      resolvedUrl,
                      headers: ServerApiService.instance.authToken == null
                          ? null
                          : {
                              'Authorization':
                                  'Bearer ${ServerApiService.instance.authToken}',
                            },
                      height: 210,
                      width: 260,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFF2B3A42),
                                  Color(0xFF3F51B5),
                                  Color(0xFF7E57C2),
                                  Color(0xFF26A69A),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                          BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.15),
                            ),
                          ),
                          const Center(
                            child: Icon(
                              Icons.photo_outlined,
                              size: 44,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Blur Overlay with Download / Download again button
                if (!showFullImage)
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.black.withValues(alpha: 0.38),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isDownloading)
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.download_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _downloadFailed ? 'Download again' : 'Download',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // ─── 2. OTHER ATTACHMENTS (Video, Audio, Document/File) ─────────────────
    final icon = _isVideo
        ? Icons.movie_outlined
        : _isAudio
        ? Icons.graphic_eq_rounded
        : Icons.insert_drive_file_outlined;

    final kind = _isVideo
        ? 'Video'
        : _isAudio
        ? 'Voice message'
        : 'Document';

    final statusText = hasLocal
        ? kind
        : (_downloadFailed
            ? '$kind • Download failed'
            : '$kind • Not downloaded');

    return GestureDetector(
      onTap: hasLocal
          ? (_isAudio ? _toggleAudioPlayback : _openAttachment)
          : null,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF182229) : const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(12),
        ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _attachmentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: _downloadFailed
                        ? Colors.redAccent
                        : (isDark ? Colors.white60 : Colors.black54),
                  ),
                ),
              ],
            ),
          ),

          // Action Button Area
          if (_isDownloading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_isAudio && hasLocal)
            _attachmentActionButton(
              icon: _isPlayingAudio
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              onPressed: _toggleAudioPlayback,
              tooltip: _isPlayingAudio ? 'Pause' : 'Play',
            )
          else if (!hasLocal)
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                foregroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _isAudio
                  ? _toggleAudioPlayback
                  : (_isImage || _isVideo
                      ? _revealImage
                      : _openAttachment),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text(
                _downloadFailed ? 'Download again' : 'Download',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            )
          else
            _attachmentActionButton(
              icon: Icons.open_in_new_rounded,
              onPressed: _openAttachment,
              tooltip: 'Open',
            ),
        ],
      ),
    ),
    );
  }

  Widget _attachmentActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.58),
      shape: const CircleBorder(),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (widget.groupedImages != null && widget.groupedImages!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 12.0),
        child: Column(
          crossAxisAlignment: widget.isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (widget.senderName != null && widget.senderName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
                child: Text(
                  widget.senderName!,
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            GroupedPhotoGrid(
              groupedImages: widget.groupedImages!,
              isMe: widget.isMe,
              timestamp: widget.timestamp,
              isRead: widget.isRead,
              isEdited: widget.isEdited,
            ),
          ],
        ),
      );
    }

    if (widget.isDeleted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 36),
        child: Row(
          children: [
            Expanded(
              child: Divider(
                color: AppTheme.subtitleGrey.withValues(alpha: 0.35),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'This message was deleted',
                style: TextStyle(
                  color: AppTheme.subtitleGrey,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            Expanded(
              child: Divider(
                color: AppTheme.subtitleGrey.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      );
    }

    final bubbleColor = widget.isHighlighted
        ? AppTheme.primaryColor.withValues(alpha: 0.45)
        : (widget.isMe
            ? AppTheme.sentBubble(isDark)
            : AppTheme.receivedBubble(isDark));

    final textColor = widget.isMe
        ? Colors.white
        : (isDark ? Colors.white : Colors.black);

    final mediaUrl = widget.mediaUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 12.0),
      child: Column(
        crossAxisAlignment: widget.isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (widget.senderName != null && widget.senderName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
              child: Text(
                widget.senderName!,
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(
              bottom: widget.reactions?.isNotEmpty == true ? 18 : 0,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Align(
                  alignment: widget.isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
                        bottomRight: Radius.circular(widget.isMe ? 4 : 18),
                      ),
                    ),
                    child: _buildBubbleContent(
                      context,
                      isDark,
                      textColor,
                      mediaUrl,
                    ),
                  ),
                ),
                if (widget.reactions?.isNotEmpty == true)
                  Positioned(
                    bottom: -16,
                    right: widget.isMe ? 9 : null,
                    left: widget.isMe ? null : 9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.reactions!
                            .map(
                              (reaction) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: reaction == 'star'
                                    ? const Icon(
                                        Icons.star_rounded,
                                        color: Colors.amber,
                                        size: 15,
                                      )
                                    : Text(
                                        reaction,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GroupedPhotoGrid extends StatelessWidget {
  final List<ChatMessage> groupedImages;
  final bool isMe;
  final DateTime timestamp;
  final bool isRead;
  final bool isEdited;
  final bool isSaved;

  const GroupedPhotoGrid({
    super.key,
    required this.groupedImages,
    required this.isMe,
    required this.timestamp,
    required this.isRead,
    required this.isEdited,
    this.isSaved = false,
  });

  @override
  Widget build(BuildContext context) {
    final count = groupedImages.length;

    Widget gridContent;
    if (count == 1) {
      gridContent = _buildSingleImage(context, groupedImages[0]);
    } else if (count == 2) {
      gridContent = _buildTwoImages(context, groupedImages);
    } else if (count == 3) {
      gridContent = _buildThreeImages(context, groupedImages);
    } else {
      gridContent = _buildFourPlusImages(context, groupedImages);
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 270),
      decoration: BoxDecoration(
        color: isMe
            ? AppTheme.primaryColor
            : (Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF2C2C2E)
                : Colors.white),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          gridContent,
          // Time badge overlay
          Positioned(
            right: 8,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSaved) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bookmark_rounded,
                              size: 8, color: Colors.white),
                          SizedBox(width: 2),
                          Text(
                            'Saved',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (isEdited) ...[
                    const Text(
                      'edited ',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  Text(
                    _formatTime(timestamp),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 3),
                    Icon(
                      isRead ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 12,
                      color: isRead ? const Color(0xFF53BDEB) : Colors.white70,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour24 = time.toLocal().hour;
    final hour = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
    final min = time.toLocal().minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour:$min $period';
  }

  Widget _buildSingleImage(BuildContext context, ChatMessage msg) {
    return _GridTileItem(
      photoMessage: msg,
      width: 270,
      height: 220,
      onTap: () => PhotoGalleryViewer.open(
        context,
        photos: groupedImages,
        initialIndex: 0,
      ),
    );
  }

  Widget _buildTwoImages(BuildContext context, List<ChatMessage> photos) {
    return Row(
      children: [
        Expanded(
          child: _GridTileItem(
            photoMessage: photos[0],
            height: 140,
            onTap: () => PhotoGalleryViewer.open(
              context,
              photos: photos,
              initialIndex: 0,
            ),
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: _GridTileItem(
            photoMessage: photos[1],
            height: 140,
            onTap: () => PhotoGalleryViewer.open(
              context,
              photos: photos,
              initialIndex: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThreeImages(BuildContext context, List<ChatMessage> photos) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _GridTileItem(
            photoMessage: photos[0],
            height: 180,
            onTap: () => PhotoGalleryViewer.open(
              context,
              photos: photos,
              initialIndex: 0,
            ),
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          flex: 5,
          child: Column(
            children: [
              _GridTileItem(
                photoMessage: photos[1],
                height: 89,
                onTap: () => PhotoGalleryViewer.open(
                  context,
                  photos: photos,
                  initialIndex: 1,
                ),
              ),
              const SizedBox(height: 2),
              _GridTileItem(
                photoMessage: photos[2],
                height: 89,
                onTap: () => PhotoGalleryViewer.open(
                  context,
                  photos: photos,
                  initialIndex: 2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFourPlusImages(BuildContext context, List<ChatMessage> photos) {
    final extraCount = photos.length - 3;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _GridTileItem(
                photoMessage: photos[0],
                height: 110,
                onTap: () => PhotoGalleryViewer.open(
                  context,
                  photos: photos,
                  initialIndex: 0,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _GridTileItem(
                photoMessage: photos[1],
                height: 110,
                onTap: () => PhotoGalleryViewer.open(
                  context,
                  photos: photos,
                  initialIndex: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: _GridTileItem(
                photoMessage: photos[2],
                height: 110,
                onTap: () => PhotoGalleryViewer.open(
                  context,
                  photos: photos,
                  initialIndex: 2,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  _GridTileItem(
                    photoMessage: photos[3],
                    height: 110,
                    onTap: () => PhotoGalleryViewer.open(
                      context,
                      photos: photos,
                      initialIndex: 3,
                    ),
                  ),
                  if (extraCount > 0)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => PhotoGalleryViewer.open(
                          context,
                          photos: photos,
                          initialIndex: 3,
                        ),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.58),
                          alignment: Alignment.center,
                          child: Text(
                            '+$extraCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GridTileItem extends StatefulWidget {
  final ChatMessage photoMessage;
  final double? width;
  final double height;
  final VoidCallback onTap;

  const _GridTileItem({
    required this.photoMessage,
    this.width,
    required this.height,
    required this.onTap,
  });

  @override
  State<_GridTileItem> createState() => _GridTileItemState();
}

class _GridTileItemState extends State<_GridTileItem> {
  String? _resolvedPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTilePhoto();
  }

  Future<void> _loadTilePhoto() async {
    final rawUrl = widget.photoMessage.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      if (File(rawUrl).existsSync()) {
        if (mounted) {
          setState(() {
            _resolvedPath = rawUrl;
            _isLoading = false;
          });
        }
        return;
      }
    }

    final cached = await AttachmentCacheService.instance.resolveLocalPath(rawUrl);
    if (cached != null && File(cached).existsSync()) {
      if (mounted) {
        setState(() {
          _resolvedPath = cached;
          _isLoading = false;
        });
      }
      return;
    }

    final networkUrl = resolveAvatarUrl(rawUrl);
    if (mounted) {
      setState(() {
        _resolvedPath = networkUrl;
        _isLoading = false;
      });
    }
  }

  Future<void> _sharePhoto() async {
    HapticFeedback.mediumImpact();
    final rawUrl = widget.photoMessage.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) return;

    try {
      String? localPath = _resolvedPath;
      if (localPath == null || localPath.startsWith('http')) {
        localPath = await AttachmentCacheService.instance.resolveLocalPath(rawUrl);
      }
      if (localPath != null && File(localPath).existsSync()) {
        await SharePlus.instance.share(ShareParams(files: [XFile(localPath)]));
      } else {
        AppToast.show('Downloading photo to share...');
        final networkUrl = resolveAvatarUrl(rawUrl);
        if (networkUrl != null) {
          final headers = ServerApiService.instance.authToken != null
              ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
              : null;
          final res = await http.get(Uri.parse(networkUrl), headers: headers);
          if (res.statusCode == 200) {
            final tempDir = await getTemporaryDirectory();
            final file = File(
              '${tempDir.path}/shared_${DateTime.now().millisecondsSinceEpoch}.jpg',
            );
            await file.writeAsBytes(res.bodyBytes);
            await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
          }
        }
      }
    } catch (e) {
      debugPrint('[GRID TILE SHARE ERROR] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey.withValues(alpha: 0.2),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final path = _resolvedPath;
    if (path == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey.withValues(alpha: 0.3),
        child: const Icon(Icons.broken_image_rounded, color: Colors.white70),
      );
    }

    final isLocal = !path.startsWith('http://') && !path.startsWith('https://');

    Widget imageWidget;
    if (isLocal) {
      imageWidget = Image.file(
        File(path),
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_rounded, color: Colors.white70),
        ),
      );
    } else {
      final headers = ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : null;
      imageWidget = Image.network(
        path,
        headers: headers,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey.withValues(alpha: 0.2),
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_rounded, color: Colors.white70),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: _sharePhoto,
      child: Container(
        width: widget.width,
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(),
        child: imageWidget,
      ),
    );
  }
}


