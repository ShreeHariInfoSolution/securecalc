import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
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
import '../../domain/models/server_models.dart';
import '../../domain/services/e2e_crypto_service.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/attachment_cache_service.dart';
import 'photo_gallery_viewer.dart';
import 'rich_link_preview_card.dart';
import 'app_video_player.dart';

class ChatBubble extends StatefulWidget {
  final String message;
  final bool isMe;
  final DateTime timestamp;
  final bool isRead;
  final bool isDelivered;
  final bool isEdited;
  final bool isDeleted;
  final bool isSaved;
  final bool isDecrypting;
  final bool showDeliveryStatus;
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
  final String? searchQuery;
  final bool isForwarded;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final Function(ChatMessage, Offset, Size)? onShowMessageActions;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.timestamp,
    this.isRead = true,
    this.isDelivered = false,
    this.isEdited = false,
    this.isDeleted = false,
    this.isSaved = false,
    this.isDecrypting = false,
    this.showDeliveryStatus = false,
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
    this.searchQuery,
    this.isForwarded = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onShowMessageActions,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  AudioPlayer? _audioPlayer;
  StreamSubscription<PlayerState>? _audioStateSubscription;
  StreamSubscription<Duration>? _audioPosSubscription;
  StreamSubscription<Duration>? _audioDurSubscription;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  String? _downloadedPath;
  bool _isDownloading = false;
  bool _isPlayingAudio = false;
  bool _isMediaRevealed = false;
  bool _downloadFailed = false;
  bool _isExpanded = false;

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
    _audioPosSubscription = player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() => _audioPosition = pos);
      }
    });
    _audioDurSubscription = player.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() => _audioDuration = dur);
      }
    });
    return player;
  }

  bool _isAbsoluteFilePath(String path) =>
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
      RegExp(r'^/(?:data|storage|private|var|tmp|Users)/').hasMatch(path);

  bool _isValidImageBytes(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47)
      return true;
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // GIF: 47 49 46 38 ('GIF8')
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38)
      return true;
    // WebP: 'RIFF' at 0..3 and 'WEBP' at 8..11
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50)
      return true;
    // BMP: 42 4D ('BM')
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true;
    return false;
  }

  bool get _hasValidLocalFile {
    return _downloadedPath != null && _downloadedPath!.isNotEmpty;
  }

  Future<String> _getLocalAttachmentPath() async {
    final documents = await getApplicationDocumentsDirectory();
    final attachmentDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}chat_attachments',
    );
    await attachmentDirectory.create(recursive: true);

    final mediaKey =
        (widget.mediaUrl ?? 'att_${widget.timestamp.millisecondsSinceEpoch}')
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
      final cachedPath = await AttachmentCacheService.instance.resolveLocalPath(
        mediaPath,
      );
      if (cachedPath != null && File(cachedPath).existsSync()) {
        if (mounted) {
          setState(() {
            _downloadedPath = cachedPath;
            _isMediaRevealed = true;
            _downloadFailed = false;
          });
        }
        return;
      }

      String mediaType = 'doc';
      if (_isImage) {
        mediaType = 'image';
      } else if (_isVideo) {
        mediaType = 'video';
      }

      final shouldAuto = await AppPreferences.shouldAutoDownload(
        mediaType: mediaType,
      );

      if (shouldAuto) {
        unawaited(_autoDownloadAndReveal());
      } else {
        if (mounted) {
          setState(() {
            _downloadedPath = null;
            _isMediaRevealed = false;
            _downloadFailed = false;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _autoDownloadAndReveal() async {
    try {
      await _downloadAttachment();
      if (mounted) {
        setState(() {
          _isMediaRevealed = true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _audioStateSubscription?.cancel();
    _audioPosSubscription?.cancel();
    _audioDurSubscription?.cancel();
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

  String get _effectiveFileType =>
      inferAttachmentType(
        fileType: widget.type,
        fileName: widget.fileName,
        filePath: widget.mediaUrl,
      ) ??
      widget.type?.toLowerCase() ??
      '';

  bool get _isImage {
    final type = _effectiveFileType;
    if (type.startsWith('image/')) return true;
    final source = widget.fileName?.isNotEmpty == true
        ? widget.fileName!
        : widget.mediaUrl ?? '';
    final ext = source
        .split('?')
        .first
        .split('#')
        .first
        .split('.')
        .last
        .toLowerCase();
    return [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
      'bmp',
    ].contains(ext);
  }

  bool get _isVideo {
    final type = _effectiveFileType;
    if (type.startsWith('video/')) return true;
    final source = widget.fileName?.isNotEmpty == true
        ? widget.fileName!
        : widget.mediaUrl ?? '';
    final ext = source
        .split('?')
        .first
        .split('#')
        .first
        .split('.')
        .last
        .toLowerCase();
    return ['mp4', 'mov', 'webm', 'mkv', 'avi', '3gp'].contains(ext);
  }

  bool get _isAudio {
    final type = _effectiveFileType;
    if (type.startsWith('audio/')) return true;
    final source = widget.fileName?.isNotEmpty == true
        ? widget.fileName!
        : widget.mediaUrl ?? '';
    final ext = source
        .split('?')
        .first
        .split('#')
        .first
        .split('.')
        .last
        .toLowerCase();
    return ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus'].contains(ext);
  }

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

      final response = await http
          .get(Uri.parse(remoteUrl), headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed (${response.statusCode}).');
      }

      final rawBytes = response.bodyBytes;
      String? secretKey;
      if (widget.chatId != null && widget.chatId!.isNotEmpty) {
        secretKey = 'chat_key_${widget.chatId}';
      }

      Uint8List fileBytes = rawBytes;
      if (secretKey != null) {
        fileBytes = E2eCryptoService.instance.decryptFileBytes(
          rawBytes,
          secretKey,
        );
      }

      if (_isImage) {
        if (!_isValidImageBytes(fileBytes)) {
          if (_isValidImageBytes(rawBytes)) {
            fileBytes = rawBytes;
          } else {
            throw Exception('Decrypted image payload is invalid.');
          }
        }
      }

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
      AppToast.show('$_attachmentName saved successfully.');
    } catch (error) {
      AppToast.show(AppToast.userFriendlyMessage('Could not download attachment: $error'), isError: true);
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
      AppToast.show(AppToast.userFriendlyMessage('Could not download photo: $error'), isError: true);
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
      if (_isVideo) {
        if (mounted) {
          AppVideoPlayerModal.open(
            context,
            mediaUrl: path,
            title: widget.fileName ?? 'Video',
          );
        }
        return;
      }
      await OpenFilex.open(path);
    } catch (error) {
      AppToast.show(AppToast.userFriendlyMessage('Could not open attachment: $error'), isError: true);
    }
  }

  String _formatAudioDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggleAudioPlayback() async {
    try {
      if (_isPlayingAudio) {
        await _audioPlayer?.pause();
        return;
      }
      final path = await _downloadAttachment();
      final player = _ensureAudioPlayer();
      if (_audioPosition >= _audioDuration && _audioDuration > Duration.zero) {
        await player.seek(Duration.zero);
      }
      await player.play(DeviceFileSource(path));
    } catch (error) {
      AppToast.show(AppToast.userFriendlyMessage('Could not play voice message: $error'), isError: true);
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
          _buildStatusTick(isDark),
        ],
      ],
    );
  }

  Widget _buildStatusTick(bool isDark) {
    if (widget.isRead) {
      return const Icon(
        Icons.done_all_rounded,
        size: 14,
        color: Color(0xFF53BDEB),
      );
    }

    if (widget.isDelivered) {
      return Icon(
        Icons.done_all_rounded,
        size: 14,
        color: widget.isMe
            ? Colors.white.withValues(alpha: 0.8)
            : (isDark ? Colors.white60 : AppTheme.subtitleGrey),
      );
    }

    return Icon(
      Icons.done_rounded,
      size: 14,
      color: widget.isMe
          ? Colors.white.withValues(alpha: 0.8)
          : (isDark ? Colors.white60 : AppTheme.subtitleGrey),
    );
  }

  Widget _buildReplyMediaThumbnail(ChatMessage msg, bool isDark) {
    if (!msg.hasMedia) return const SizedBox.shrink();

    final url = msg.mediaUrl;
    final type = msg.type.toLowerCase();

    final isImage = type.contains('image') ||
        type == 'photo' ||
        (url != null &&
            ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].any(
                (ext) => url.toLowerCase().split('?').first.endsWith('.$ext')));

    final isVideo = type.contains('video') ||
        (url != null &&
            ['mp4', 'mov', 'avi', 'mkv'].any(
                (ext) => url.toLowerCase().split('?').first.endsWith('.$ext')));

    final isAudio = type.contains('audio') ||
        type.contains('voice') ||
        (url != null &&
            ['m4a', 'mp3', 'wav', 'aac'].any(
                (ext) => url.toLowerCase().split('?').first.endsWith('.$ext')));

    if (isImage && url != null && url.isNotEmpty) {
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
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.photo_rounded,
                    size: 16,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    if (isVideo) {
      return _buildReplyIconBadge(Icons.play_circle_fill_rounded);
    }

    if (isAudio) {
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
    final hasText =
        widget.message.isNotEmpty && widget.message != '[Attachment]';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isForwarded) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shortcut_rounded,
                  size: 13,
                  color: widget.isMe
                      ? Colors.white.withValues(alpha: 0.85)
                      : (isDark ? Colors.white60 : Colors.black54),
                ),
                const SizedBox(width: 3),
                Text(
                  'Forwarded',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: widget.isMe
                        ? Colors.white.withValues(alpha: 0.85)
                        : (isDark ? Colors.white60 : Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                  if (widget.repliedMessage != null && widget.repliedMessage!.hasMedia) ...[
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
              _buildAttachment(isDark, mediaUrl),
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
        if (widget.isDecrypting && !hasMedia) ...[
          const _DecryptionShimmer(),
        ] else if (hasText) ...[
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
                      fontSize: 17.0,
                      height: 1.17,
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
            _buildExpandableTextMessage(context, isDark, textColor),
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

  List<InlineSpan> _buildHighlightedTextSpans(
    String text,
    Color textColor,
    bool isDark,
  ) {
    final query = widget.searchQuery?.trim();
    if (query == null || query.isEmpty) {
      return [TextSpan(text: text)];
    }

    final queryLower = query.toLowerCase();
    final textLower = text.toLowerCase();

    if (!textLower.contains(queryLower)) {
      return [TextSpan(text: text)];
    }

    final spans = <InlineSpan>[];
    int start = 0;
    int indexOfMatch;

    final highlightBg = isDark
        ? const Color(0xFFFFD60A)
        : const Color(0xFFFFC107);

    while ((indexOfMatch = textLower.indexOf(queryLower, start)) != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfMatch)));
      }
      final matchText =
          text.substring(indexOfMatch, indexOfMatch + queryLower.length);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: highlightBg,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 2,
                ),
              ],
            ),
            child: Text(
              matchText,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16.0,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
      start = indexOfMatch + queryLower.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return spans;
  }

  Widget _buildLinkPreviewCard(String urlStr, bool isDark) {
    return RichLinkPreviewCard(
      url: urlStr,
      isMe: widget.isMe,
      isDark: isDark,
    );
  }

  Widget _buildExpandableTextMessage(
    BuildContext context,
    bool isDark,
    Color textColor,
  ) {
    final text = widget.message;
    final lines = text.split('\n');
    final isLongParagraph = text.length > 320 || lines.length > 6;
    final textSpans = _buildHighlightedTextSpans(text, textColor, isDark);

    final linkRegex = RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);
    final matches = linkRegex.allMatches(text);
    final hasLink = matches.isNotEmpty;
    final firstLink = hasLink ? text.substring(matches.first.start, matches.first.end) : null;

    Widget buildTextBody() {
      if (!isLongParagraph) {
        return RichText(
          text: TextSpan(
            style: TextStyle(
              color: textColor,
              fontSize: 17.0,
              height: 1.17,
              fontWeight: FontWeight.w400,
              fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
            ),
            children: [
              ...textSpans,
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
        );
      }

      if (!_isExpanded) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 17.0,
                height: 1.17,
                fontWeight: FontWeight.w400,
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = true),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 2.0,
                      horizontal: 2.0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'More',
                          style: TextStyle(
                            color: widget.isMe
                                ? Colors.white.withValues(alpha: 0.95)
                                : AppTheme.primaryColor,
                            fontSize: 14.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: widget.isMe
                              ? Colors.white.withValues(alpha: 0.95)
                              : AppTheme.primaryColor,
                        ),
                      ],
                    ),
                  ),
                ),
                _buildTimestampWidget(isDark),
              ],
            ),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            text: TextSpan(
              style: TextStyle(
                color: textColor,
                fontSize: 17.0,
                height: 1.17,
                fontWeight: FontWeight.w400,
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
              ),
              children: textSpans,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => setState(() => _isExpanded = false),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 2.0,
                    horizontal: 2.0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Less',
                        style: TextStyle(
                          color: widget.isMe
                              ? Colors.white.withValues(alpha: 0.95)
                              : AppTheme.primaryColor,
                          fontSize: 14.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 16,
                        color: widget.isMe
                            ? Colors.white.withValues(alpha: 0.95)
                            : AppTheme.primaryColor,
                      ),
                    ],
                  ),
                ),
              ),
              _buildTimestampWidget(isDark),
            ],
          ),
        ],
      );
    }

    if (!hasLink) {
      return buildTextBody();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        buildTextBody(),
        _buildLinkPreviewCard(firstLink!, isDark),
      ],
    );
  }

  Widget _buildAttachment(bool isDark, String? mediaUrl) {
    if (mediaUrl == null || mediaUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasLocal = _hasValidLocalFile;

    // ─── 1. IMAGE ATTACHMENT ────────────────────────────────────────────────
    if (_isImage) {
      final showFullImage = hasLocal && _isMediaRevealed;

      final double maxW = MediaQuery.of(context).size.width * 0.70;

      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: GestureDetector(
          onTap: showFullImage ? _showImageViewer : _revealImage,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: maxW,
              maxHeight: 310,
              minWidth: 160,
              minHeight: 140,
            ),
            color: isDark ? const Color(0xFF263238) : const Color(0xFFE7E9EC),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (showFullImage)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxW,
                      maxHeight: 310,
                      minWidth: 160,
                      minHeight: 140,
                    ),
                    child: Image.file(
                      File(_downloadedPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        try {
                          if (_downloadedPath != null) {
                            File(_downloadedPath!).deleteSync();
                          }
                        } catch (_) {}
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _downloadedPath = null;
                              _downloadFailed = true;
                            });
                          }
                        });
                        return Container(
                          constraints: BoxConstraints(
                            maxWidth: maxW,
                            maxHeight: 310,
                            minWidth: 160,
                            minHeight: 140,
                          ),
                          color: isDark
                              ? const Color(0xFF1F2A30)
                              : const Color(0xFFCFD8DC),
                          child: const Center(
                            child: Icon(
                              Icons.broken_image_rounded,
                              size: 40,
                              color: Colors.white70,
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else if (hasLocal)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxW,
                      maxHeight: 310,
                      minWidth: 160,
                      minHeight: 140,
                    ),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Image.file(
                        File(_downloadedPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          try {
                            if (_downloadedPath != null) {
                              File(_downloadedPath!).deleteSync();
                            }
                          } catch (_) {}
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                _downloadedPath = null;
                                _downloadFailed = true;
                              });
                            }
                          });
                          return Container(
                            constraints: BoxConstraints(
                              maxWidth: maxW,
                              maxHeight: 310,
                              minWidth: 160,
                              minHeight: 140,
                            ),
                            color: isDark
                                ? const Color(0xFF1F2A30)
                                : const Color(0xFFCFD8DC),
                            child: const Center(
                              child: Icon(
                                Icons.broken_image_rounded,
                                size: 40,
                                color: Colors.white70,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  )
                else
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: maxW,
                      maxHeight: 210,
                      minWidth: 160,
                      minHeight: 140,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? const [Color(0xFF1F2A30), Color(0xFF2C3840)]
                            : const [Color(0xFFCFD8DC), Color(0xFFB0BEC5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.photo_outlined,
                        size: 44,
                        color: Colors.white70,
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
                                  _downloadFailed
                                      ? 'Download again'
                                      : 'Download',
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

    // ─── 2. VIDEO ATTACHMENTS ─────────────────
    if (_isVideo) {
      final videoSource = _downloadedPath ?? widget.mediaUrl ?? '';
      return GestureDetector(
        onTap: hasLocal
            ? _openAttachment
            : (_isDownloading ? null : _revealImage),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(
            maxWidth: 260,
            maxHeight: 220,
            minWidth: 180,
            minHeight: 140,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (videoSource.isNotEmpty)
                VideoThumbnailCard(
                  mediaUrl: videoSource,
                  width: double.infinity,
                  height: 220,
                  borderRadius: BorderRadius.circular(14),
                )
              else
                Container(
                  color: const Color(0xFF1C1C1E),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.videocam_fill,
                      size: 44,
                      color: Colors.white38,
                    ),
                  ),
                ),
              if (!hasLocal)
                Container(
                  color: Colors.black.withValues(alpha: 0.45),
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
                                _downloadFailed
                                    ? 'Download again'
                                    : 'Download',
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
      );
    }

    if (_isAudio) {
      final maxDur = _audioDuration.inMilliseconds > 0
          ? _audioDuration.inMilliseconds.toDouble()
          : 1.0;
      final curPos = _audioPosition.inMilliseconds
          .toDouble()
          .clamp(0.0, maxDur);

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF182229) : const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: _isDownloading ? null : _toggleAudioPlayback,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: Color(0xFF007AFF),
                      shape: BoxShape.circle,
                    ),
                    child: _isDownloading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _isPlayingAudio
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                  ),
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
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasLocal
                            ? '${_formatAudioDuration(_audioPosition)} / ${_formatAudioDuration(_audioDuration)}'
                            : (_downloadFailed
                                  ? 'Download failed'
                                  : 'Tap to download audio'),
                        style: TextStyle(
                          fontSize: 11,
                          color: _downloadFailed
                              ? Colors.redAccent
                              : (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasLocal) ...[
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  activeTrackColor: const Color(0xFF007AFF),
                  inactiveTrackColor: isDark ? Colors.white24 : Colors.black12,
                  thumbColor: const Color(0xFF007AFF),
                ),
                child: Slider(
                  min: 0.0,
                  max: maxDur,
                  value: curPos,
                  onChanged: (val) {
                    _audioPlayer?.seek(Duration(milliseconds: val.toInt()));
                  },
                ),
              ),
            ],
          ],
        ),
      );
    }

    // ─── 3. OTHER ATTACHMENTS (Document/File) ─────────────────
    final icon = _isVideo
        ? Icons.movie_outlined
        : Icons.insert_drive_file_outlined;

    final kind = _isVideo
        ? 'Video'
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
                  backgroundColor: AppTheme.primaryColor.withValues(
                    alpha: 0.15,
                  ),
                  foregroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _isAudio
                    ? _toggleAudioPlayback
                    : (_isImage || _isVideo ? _revealImage : _openAttachment),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: Text(
                  _downloadFailed ? 'Download again' : 'Download',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
      final gridBody = Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 12.0),
        child: Column(
          crossAxisAlignment: widget.isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (widget.isForwarded) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shortcut_rounded,
                      size: 13,
                      color: widget.isMe
                          ? Colors.white.withValues(alpha: 0.85)
                          : (isDark ? Colors.white60 : Colors.black54),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Forwarded',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        color: widget.isMe
                            ? Colors.white.withValues(alpha: 0.85)
                            : (isDark ? Colors.white60 : Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
              isDelivered: widget.isDelivered,
              isEdited: widget.isEdited,
              isSaved: widget.isSaved,
              isSelectionMode: widget.isSelectionMode,
              isSelected: widget.isSelected,
              onToggleSelect: widget.onToggleSelect,
              onShowMessageActions: widget.onShowMessageActions,
            ),
          ],
        ),
      );

      if (widget.isSelectionMode) {
        return GestureDetector(
          onTap: widget.onToggleSelect,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
            child: Row(
              children: [
                Icon(
                  widget.isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: widget.isSelected
                      ? const Color(0xFF007AFF)
                      : (isDark ? Colors.white54 : Colors.black38),
                  size: 22,
                ),
                const SizedBox(width: 4),
                Expanded(child: gridBody),
              ],
            ),
          ),
        );
      }

      return gridBody;
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

    final sentColor = AppPreferences.getChatBubbleColor(chatId: widget.chatId);
    final highlightBorderColor = isDark
        ? const Color(0xFFFFD60A)
        : const Color(0xFFFF9500);

    final bubbleColor =
        widget.isMe ? sentColor : AppTheme.receivedBubble(isDark);

    final textColor = widget.isMe
        ? Colors.white
        : (isDark ? Colors.white : Colors.black);

    final mediaUrl = widget.mediaUrl;

    final Widget bubbleBody = Padding(
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
                    decoration: widget.isHighlighted
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: highlightBorderColor,
                              width: 2.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: highlightBorderColor.withValues(alpha: 0.55),
                                blurRadius: 14,
                                spreadRadius: 2,
                              ),
                            ],
                          )
                        : null,
                    child: CustomPaint(
                      painter: IMessageBubblePainter(
                        color: bubbleColor,
                        isOutgoing: widget.isMe,
                      ),
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.76,
                        ),
                        margin: EdgeInsets.only(
                          left: widget.isMe ? 0 : 6,
                          right: widget.isMe ? 6 : 0,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        child: _buildBubbleContent(
                          context,
                          isDark,
                          textColor,
                          mediaUrl,
                        ),
                      ),
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
          if (widget.isMe &&
              widget.showDeliveryStatus &&
              (widget.isRead || widget.isDelivered))
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  widget.isRead ? 'Seen' : 'Delivered',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.isSelectionMode) {
      return GestureDetector(
        onTap: widget.onToggleSelect,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
          child: Row(
            children: [
              Icon(
                widget.isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: widget.isSelected
                    ? const Color(0xFF007AFF)
                    : (isDark ? Colors.white54 : Colors.black38),
                size: 22,
              ),
              const SizedBox(width: 4),
              Expanded(child: bubbleBody),
            ],
          ),
        ),
      );
    }

    return bubbleBody;
  }
}

class GroupedPhotoGrid extends StatelessWidget {
  final List<ChatMessage> groupedImages;
  final bool isMe;
  final DateTime timestamp;
  final bool isRead;
  final bool isDelivered;
  final bool isEdited;
  final bool isSaved;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final Function(ChatMessage, Offset, Size)? onShowMessageActions;

  const GroupedPhotoGrid({
    super.key,
    required this.groupedImages,
    required this.isMe,
    required this.timestamp,
    required this.isRead,
    this.isDelivered = false,
    required this.isEdited,
    this.isSaved = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onShowMessageActions,
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

    final sentColor = AppPreferences.getChatBubbleColor();
    return Container(
      constraints: const BoxConstraints(maxWidth: 270),
      decoration: BoxDecoration(
        color: isMe
            ? sentColor
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
                        horizontal: 4,
                        vertical: 1,
                      ),
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bookmark_rounded,
                            size: 8,
                            color: Colors.white,
                          ),
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
                      (isRead || isDelivered)
                          ? Icons.done_all_rounded
                          : Icons.done_rounded,
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
      onTap: () {
        if (isSelectionMode) {
          onToggleSelect?.call();
        } else {
          PhotoGalleryViewer.open(
            context,
            photos: groupedImages,
            initialIndex: 0,
          );
        }
      },
      isSelectionMode: isSelectionMode,
      onToggleSelect: onToggleSelect,
      onShowMessageActions: onShowMessageActions,
    );
  }

  Widget _buildTwoImages(BuildContext context, List<ChatMessage> photos) {
    return Row(
      children: [
        Expanded(
          child: _GridTileItem(
            photoMessage: photos[0],
            height: 140,
            onTap: () {
              if (isSelectionMode) {
                onToggleSelect?.call();
              } else {
                PhotoGalleryViewer.open(
                  context,
                  photos: photos,
                  initialIndex: 0,
                );
              }
            },
            isSelectionMode: isSelectionMode,
            onToggleSelect: onToggleSelect,
            onShowMessageActions: onShowMessageActions,
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: _GridTileItem(
            photoMessage: photos[1],
            height: 140,
            onTap: () {
              if (isSelectionMode) {
                onToggleSelect?.call();
              } else {
                PhotoGalleryViewer.open(
                  context,
                  photos: photos,
                  initialIndex: 1,
                );
              }
            },
            isSelectionMode: isSelectionMode,
            onToggleSelect: onToggleSelect,
            onShowMessageActions: onShowMessageActions,
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
            onTap: () {
              if (isSelectionMode) {
                onToggleSelect?.call();
              } else {
                PhotoGalleryViewer.open(
                  context,
                  photos: photos,
                  initialIndex: 0,
                );
              }
            },
            isSelectionMode: isSelectionMode,
            onToggleSelect: onToggleSelect,
            onShowMessageActions: onShowMessageActions,
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
                onTap: () {
                  if (isSelectionMode) {
                    onToggleSelect?.call();
                  } else {
                    PhotoGalleryViewer.open(
                      context,
                      photos: photos,
                      initialIndex: 1,
                    );
                  }
                },
                isSelectionMode: isSelectionMode,
                onToggleSelect: onToggleSelect,
                onShowMessageActions: onShowMessageActions,
              ),
              const SizedBox(height: 2),
              _GridTileItem(
                photoMessage: photos[2],
                height: 89,
                onTap: () {
                  if (isSelectionMode) {
                    onToggleSelect?.call();
                  } else {
                    PhotoGalleryViewer.open(
                      context,
                      photos: photos,
                      initialIndex: 2,
                    );
                  }
                },
                isSelectionMode: isSelectionMode,
                onToggleSelect: onToggleSelect,
                onShowMessageActions: onShowMessageActions,
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
                onTap: () {
                  if (isSelectionMode) {
                    onToggleSelect?.call();
                  } else {
                    PhotoGalleryViewer.open(
                      context,
                      photos: photos,
                      initialIndex: 0,
                    );
                  }
                },
                isSelectionMode: isSelectionMode,
                onToggleSelect: onToggleSelect,
                onShowMessageActions: onShowMessageActions,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _GridTileItem(
                photoMessage: photos[1],
                height: 110,
                onTap: () {
                  if (isSelectionMode) {
                    onToggleSelect?.call();
                  } else {
                    PhotoGalleryViewer.open(
                      context,
                      photos: photos,
                      initialIndex: 1,
                    );
                  }
                },
                isSelectionMode: isSelectionMode,
                onToggleSelect: onToggleSelect,
                onShowMessageActions: onShowMessageActions,
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
                onTap: () {
                  if (isSelectionMode) {
                    onToggleSelect?.call();
                  } else {
                    PhotoGalleryViewer.open(
                      context,
                      photos: photos,
                      initialIndex: 2,
                    );
                  }
                },
                isSelectionMode: isSelectionMode,
                onToggleSelect: onToggleSelect,
                onShowMessageActions: onShowMessageActions,
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
                    onTap: () {
                      if (isSelectionMode) {
                        onToggleSelect?.call();
                      } else {
                        PhotoGalleryViewer.open(
                          context,
                          photos: photos,
                          initialIndex: 3,
                        );
                      }
                    },
                    isSelectionMode: isSelectionMode,
                    onToggleSelect: onToggleSelect,
                    onShowMessageActions: onShowMessageActions,
                  ),
                  if (extraCount > 0)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          if (isSelectionMode) {
                            onToggleSelect?.call();
                          } else {
                            PhotoGalleryViewer.open(
                              context,
                              photos: photos,
                              initialIndex: 3,
                            );
                          }
                        },
                        onLongPress: () {
                          if (isSelectionMode) {
                            onToggleSelect?.call();
                          } else if (onShowMessageActions != null) {
                            final box = context.findRenderObject() as RenderBox?;
                            final globalPos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                            final size = box?.size ?? const Size(200, 200);
                            onShowMessageActions!(photos[3], globalPos, size);
                          }
                        },
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
  final bool isSelectionMode;
  final VoidCallback? onToggleSelect;
  final Function(ChatMessage, Offset, Size)? onShowMessageActions;

  const _GridTileItem({
    required this.photoMessage,
    this.width,
    required this.height,
    required this.onTap,
    this.isSelectionMode = false,
    this.onToggleSelect,
    this.onShowMessageActions,
  });

  @override
  State<_GridTileItem> createState() => _GridTileItemState();
}

class _GridTileItemState extends State<_GridTileItem> {
  String? _resolvedPath;
  bool _isLoading = true;
  bool _isDownloading = false;
  bool _downloadFailed = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadTilePhoto();
  }

  Future<void> _loadTilePhoto() async {
    final generation = ++_loadGeneration;
    final rawUrl = widget.photoMessage.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _resolvedPath = null;
        });
      }
      return;
    }

    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      if (File(rawUrl).existsSync()) {
        if (mounted && generation == _loadGeneration) {
          setState(() {
            _resolvedPath = rawUrl;
            _isLoading = false;
            _downloadFailed = false;
          });
        }
        return;
      }
    }

    // The chat page warms this index before rendering, so returning to a chat
    // can show already-downloaded groups without another async lookup.
    final cachedSync = AttachmentCacheService.instance.resolveLocalPathSync(
      rawUrl,
    );
    if (cachedSync != null && File(cachedSync).existsSync()) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _resolvedPath = cachedSync;
          _isLoading = false;
          _downloadFailed = false;
        });
      }
      return;
    }

    final cached = await AttachmentCacheService.instance.resolveLocalPath(
      rawUrl,
    );
    if (cached != null && File(cached).existsSync()) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _resolvedPath = cached;
          _isLoading = false;
          _downloadFailed = false;
        });
      }
      return;
    }

    final autoDownload = AppPreferences.getAutoDownloadImages();
    if (autoDownload) {
      await _downloadAndCacheTilePhoto(generation);
    } else {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _resolvedPath = null;
          _isLoading = false;
          _downloadFailed = false;
        });
      }
    }
  }

  Future<void> _downloadAndCacheTilePhoto([int? generation]) async {
    final currentGen = generation ?? _loadGeneration;
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
      String? localPath;
      if (!rawUrl.startsWith('http://') &&
          !rawUrl.startsWith('https://') &&
          File(rawUrl).existsSync()) {
        localPath = rawUrl;
      } else {
        final networkUrl = resolveAvatarUrl(rawUrl);
        if (networkUrl != null) {
          final headers = ServerApiService.instance.authToken != null
              ? {
                  'Authorization':
                      'Bearer ${ServerApiService.instance.authToken}',
                }
              : <String, String>{};
          final response = await http.get(
            Uri.parse(networkUrl),
            headers: headers,
          );
          if (response.statusCode >= 200 && response.statusCode < 300) {
            final rawBytes = response.bodyBytes;
            final secretKey = widget.photoMessage.replyToId != null
                ? 'chat_key_${widget.photoMessage.replyToId}'
                : null;
            final fileBytes = secretKey != null
                ? E2eCryptoService.instance.decryptFileBytes(
                    rawBytes,
                    secretKey,
                  )
                : rawBytes;

            final dir = await getApplicationDocumentsDirectory();
            final attDir = Directory(
              '${dir.path}${Platform.pathSeparator}chat_attachments',
            );
            if (!attDir.existsSync()) {
              await attDir.create(recursive: true);
            }
            final safeName = widget.photoMessage.fileName?.isNotEmpty == true
                ? widget.photoMessage.fileName!
                : 'img_${widget.photoMessage.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final file = File(
              '${attDir.path}${Platform.pathSeparator}$safeName',
            );
            await file.writeAsBytes(fileBytes, flush: true);
            localPath = file.path;
            AttachmentCacheService.instance.updateCache(rawUrl, localPath);
          }
        }
      }

      if (localPath != null && mounted && currentGen == _loadGeneration) {
        setState(() {
          _resolvedPath = localPath;
          _downloadFailed = false;
        });
      } else if (mounted && currentGen == _loadGeneration) {
        setState(() {
          _downloadFailed = true;
        });
      }
    } catch (e) {
      debugPrint('[GRID TILE DOWNLOAD ERROR] $e');
      if (mounted && currentGen == _loadGeneration) {
        setState(() {
          _downloadFailed = true;
        });
      }
    } finally {
      if (mounted && currentGen == _loadGeneration) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant _GridTileItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoMessage.mediaUrl != widget.photoMessage.mediaUrl) {
      _loadTilePhoto();
    }
  }

  Future<void> _sharePhoto() async {
    HapticFeedback.mediumImpact();
    final rawUrl = widget.photoMessage.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) return;

    try {
      String? localPath = _resolvedPath;
      if (localPath == null || localPath.startsWith('http')) {
        localPath = await AttachmentCacheService.instance.resolveLocalPath(
          rawUrl,
        );
      }
      if (localPath != null && File(localPath).existsSync()) {
        await SharePlus.instance.share(ShareParams(files: [XFile(localPath)]));
      } else {
        AppToast.show('Downloading photo to share...');
        await _downloadAndCacheTilePhoto();
        if (_resolvedPath != null && File(_resolvedPath!).existsSync()) {
          await SharePlus.instance.share(
            ShareParams(files: [XFile(_resolvedPath!)]),
          );
        }
      }
    } catch (e) {
      debugPrint('[GRID TILE SHARE ERROR] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tileWidth = widget.width ?? double.infinity;

    if (_isLoading) {
      return _buildThumbnailPlaceholder(tileWidth);
    }

    final path = _resolvedPath;
    if (path == null) {
      return GestureDetector(
        onTap: _isDownloading ? null : () => _downloadAndCacheTilePhoto(),
        child: Container(
          width: tileWidth,
          height: widget.height,
          color: const Color(0xFF263238),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.photo_outlined, size: 36, color: Colors.white38),
              Container(color: Colors.black.withValues(alpha: 0.35)),
              if (_isDownloading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white30, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.download_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _downloadFailed ? 'Retry' : 'Download',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final isLocal = !path.startsWith('http://') && !path.startsWith('https://');

    Widget imageWidget;
    if (isLocal) {
      imageWidget = Image.file(
        File(path),
        width: tileWidth,
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
        key: ValueKey(path),
        headers: headers,
        width: tileWidth,
        height: widget.height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              child,
              const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          );
        },
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_rounded, color: Colors.white70),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () {
        if (widget.isSelectionMode) {
          widget.onToggleSelect?.call();
        } else if (widget.onShowMessageActions != null) {
          final box = context.findRenderObject() as RenderBox?;
          final globalPos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
          final size = box?.size ?? const Size(200, 200);
          widget.onShowMessageActions!(widget.photoMessage, globalPos, size);
        } else {
          _sharePhoto();
        }
      },
      child: Container(
        width: tileWidth,
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(),
        child: imageWidget,
      ),
    );
  }

  Widget _buildThumbnailPlaceholder([double? width]) {
    final tileWidth = width ?? widget.width ?? double.infinity;
    return Container(
      width: tileWidth,
      height: widget.height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2B3A42), Color(0xFF3F51B5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

class IMessageBubblePainter extends CustomPainter {
  const IMessageBubblePainter({required this.color, required this.isOutgoing});

  final Color color;
  final bool isOutgoing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path();
    final double w = size.width;
    final double h = size.height;
    const double r = 18.0;

    if (isOutgoing) {
      // Outgoing (Me / Right Tail)
      path.moveTo(r, 0);
      path.lineTo(w - r, 0);
      path.quadraticBezierTo(w, 0, w, r);
      path.lineTo(w, h - 12);
      path.quadraticBezierTo(w, h - 4, w + 6, h);
      path.quadraticBezierTo(w - 2, h, w - 14, h);
      path.lineTo(r, h);
      path.quadraticBezierTo(0, h, 0, h - r);
      path.lineTo(0, r);
      path.quadraticBezierTo(0, 0, r, 0);
    } else {
      // Incoming (Peer / Left Tail)
      path.moveTo(w - r, 0);
      path.lineTo(r, 0);
      path.quadraticBezierTo(0, 0, 0, r);
      path.lineTo(0, h - 12);
      path.quadraticBezierTo(0, h - 4, -6, h);
      path.quadraticBezierTo(2, h, 14, h);
      path.lineTo(w - r, h);
      path.quadraticBezierTo(w, h, w, h - r);
      path.lineTo(w, r);
      path.quadraticBezierTo(w, 0, w - r, 0);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant IMessageBubblePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isOutgoing != isOutgoing;
  }
}

class DateLabel extends StatelessWidget {
  const DateLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 13),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF8E8E93),
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: .1,
        ),
      ),
    );
  }
}

class _DecryptionShimmer extends StatefulWidget {
  const _DecryptionShimmer();

  @override
  State<_DecryptionShimmer> createState() => _DecryptionShimmerState();
}

class _DecryptionShimmerState extends State<_DecryptionShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.11);
    return SizedBox(
      width: 132,
      height: 18,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1.8 + (_controller.value * 3.6), 0),
                end: Alignment(-0.8 + (_controller.value * 3.6), 0),
                colors: [
                  baseColor,
                  baseColor.withValues(alpha: 0.42),
                  baseColor,
                ],
                stops: const [0.18, 0.5, 0.82],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
