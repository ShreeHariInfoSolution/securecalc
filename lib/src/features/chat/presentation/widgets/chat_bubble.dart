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
import 'package:securecalc/src/core/theme/font_size_controller.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';

import '../../domain/entities/chat_message.dart';
import 'sticker_picker_panel.dart';
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
  final String? msgType;
  final int? callId;
  final String? callType;
  final String? callStatus;
  final int? callDuration;
  final VoidCallback? onVoiceCallTap;
  final VoidCallback? onVideoCallTap;

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
    this.msgType,
    this.callId,
    this.callType,
    this.callStatus,
    this.callDuration,
    this.onVoiceCallTap,
    this.onVideoCallTap,
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

  Widget _buildTimestampWidget(bool isDark, {Color? overrideTextColor}) {
    final time = widget.timestamp.toLocal();
    final hour24 = time.hour;
    final hour = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
    final min = time.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final formattedTime = '$hour:$min $period';

    final textStyleColor = overrideTextColor ??
        (widget.isMe
            ? Colors.white.withValues(alpha: 0.75)
            : (isDark ? Colors.white60 : AppTheme.subtitleGrey));

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
              color: textStyleColor,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        Text(
          formattedTime,
          style: TextStyle(
            color: textStyleColor,
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
              child: RepaintBoundary(
                child: Image.file(
                  File(localPath),
                  width: 32,
                  height: 32,
                  cacheWidth: 96,
                  cacheHeight: 96,
                  fit: BoxFit.cover,
                ),
              ),
            );
          }
          final resolved = _resolveRemoteMediaUrl(url);
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: RepaintBoundary(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Image.network(
                  resolved,
                  width: 32,
                  height: 32,
                  cacheWidth: 96,
                  cacheHeight: 96,
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

  Widget _buildCallBubbleContent(
    BuildContext context,
    bool isDark,
    Color textColor,
  ) {
    final isVideo = (widget.callType ?? '').toLowerCase() == 'video' ||
        widget.message.toLowerCase().contains('video');

    final status = (widget.callStatus ?? '').toLowerCase().trim();
    final msgLower = widget.message.toLowerCase().trim();

    final isMissed = status == 'missed' ||
        status == 'rejected' ||
        status == 'declined' ||
        status == 'no answer' ||
        status == 'cancelled' ||
        msgLower.contains('missed') ||
        msgLower.contains('declined') ||
        msgLower.contains('no answer') ||
        msgLower.contains('rejected');

    final isOutgoing = widget.isMe || msgLower.startsWith('outgoing') || status == 'outgoing';

    final Color iconBgColor;
    final Color iconColor;
    final IconData callIcon;

    if (isMissed) {
      iconBgColor = const Color(0x26FF3B30);
      iconColor = const Color(0xFFFF3B30);
      callIcon = isVideo ? Icons.videocam_off_rounded : Icons.phone_missed_rounded;
    } else if (isOutgoing) {
      iconBgColor = widget.isMe
          ? Colors.white.withValues(alpha: 0.2)
          : (isDark ? const Color(0x2634C759) : const Color(0x1A34C759));
      iconColor = widget.isMe ? Colors.white : const Color(0xFF34C759);
      callIcon = isVideo ? Icons.videocam_rounded : Icons.call_made_rounded;
    } else {
      iconBgColor = widget.isMe
          ? Colors.white.withValues(alpha: 0.2)
          : (isDark ? const Color(0x2634C759) : const Color(0x1A34C759));
      iconColor = widget.isMe ? Colors.white : const Color(0xFF34C759);
      callIcon = isVideo ? Icons.videocam_rounded : Icons.call_received_rounded;
    }

    final titleText = widget.message.isNotEmpty
        ? widget.message
        : (isMissed
            ? (isVideo ? 'Missed video call' : 'Missed voice call')
            : (isVideo ? 'Video call' : 'Voice call'));

    final hour = widget.timestamp.hour == 0
        ? 12
        : (widget.timestamp.hour > 12
            ? widget.timestamp.hour - 12
            : widget.timestamp.hour);
    final period = widget.timestamp.hour >= 12 ? 'PM' : 'AM';
    final timeStr =
        '$hour:${widget.timestamp.minute.toString().padLeft(2, '0')} $period';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      constraints: const BoxConstraints(minWidth: 190),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              callIcon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isMissed
                        ? (widget.isMe ? Colors.white : const Color(0xFFFF3B30))
                        : textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isMe
                            ? Colors.white.withValues(alpha: 0.7)
                            : (isDark ? Colors.white54 : Colors.black45),
                      ),
                    ),
                    if (widget.isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        widget.isRead
                            ? Icons.done_all_rounded
                            : (widget.isDelivered
                                ? Icons.done_all_rounded
                                : Icons.done_rounded),
                        size: 13,
                        color: widget.isRead
                            ? const Color(0xFF34C759)
                            : Colors.white.withValues(alpha: 0.7),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              if (isVideo) {
                widget.onVideoCallTap?.call();
              } else {
                widget.onVoiceCallTap?.call();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: widget.isMe
                    ? Colors.white.withValues(alpha: 0.2)
                    : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                size: 18,
                color: widget.isMe
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandaloneContent(
    BuildContext context,
    bool isDark,
    String cleanMsg,
    bool isSticker,
    bool isGif,
    String? mediaUrl,
  ) {
    Widget mainBody;
    if (isSticker) {
      final stickerCode = (mediaUrl != null && mediaUrl.trim().isNotEmpty)
          ? mediaUrl.trim()
          : cleanMsg;
      mainBody = StickerDisplayWidget(
        stickerCode: stickerCode,
        size: 130,
      );
    } else if (isGif) {
      mainBody = StandaloneGifWidget(
        mediaUrl: mediaUrl,
        message: cleanMsg,
        secretKey: 'chat_key_${widget.chatId}',
        isDark: isDark,
      );
    } else {
      mainBody = JumboAnimatedEmoji(
        emoji: cleanMsg,
        fontSize: 56.0,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 12.0),
      child: Column(
        crossAxisAlignment:
            widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
          Align(
            alignment:
                widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: widget.isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: mainBody,
                ),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.45)
                        : Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _buildTimestampWidget(
                    isDark,
                    overrideTextColor: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubbleContent(
    BuildContext context,
    bool isDark,
    Color textColor,
    String? mediaUrl,
  ) {
    final cleanType = (widget.type ?? 'text').toLowerCase().trim();
    if (cleanType == 'call' ||
        widget.msgType == 'call' ||
        widget.callStatus != null ||
        widget.callId != null) {
      return _buildCallBubbleContent(context, isDark, textColor);
    }

    final cleanMsg = widget.message.trim();
    final isSticker = cleanType == 'sticker' ||
        widget.type == 'sticker' ||
        cleanMsg.startsWith('stk_');

    if (isSticker) {
      final stickerCode = (mediaUrl != null && mediaUrl.trim().isNotEmpty)
          ? mediaUrl.trim()
          : cleanMsg;
      return Column(
        crossAxisAlignment:
            widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: StickerDisplayWidget(
              stickerCode: stickerCode,
              size: 130,
            ),
          ),
          const SizedBox(height: 2),
          _buildTimestampWidget(isDark),
        ],
      );
    }

    final isTextType = cleanType == 'text' || cleanType == 'text/plain';
    final hasMedia =
        !isTextType && mediaUrl != null && mediaUrl.trim().isNotEmpty;
    final hasReply = widget.replyText != null;

    final isGenericLabel = cleanMsg == '[Attachment]' ||
        cleanMsg == 'Photo' ||
        cleanMsg == 'Video' ||
        cleanMsg == 'Voice message';
    final hasText = cleanMsg.isNotEmpty && !isGenericLabel;

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
              if ((_isImage || _isVideo) && !hasText)
                Positioned(
                  bottom: 6,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _buildTimestampWidget(
                      isDark,
                      overrideTextColor: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          if (hasText) const SizedBox(height: 2),
        ],
        if (widget.isDecrypting && !hasMedia) ...[
          const _DecryptionShimmer(),
        ] else if (hasText) ...[
          Padding(
            padding: EdgeInsets.only(
              left: hasMedia ? 10 : 0,
              right: hasMedia ? 10 : 0,
              top: hasMedia ? 4 : 0,
              bottom: hasMedia ? 6 : 0,
            ),
            child: _buildExpandableTextMessage(context, isDark, textColor),
          ),
        ] else if (!hasMedia && widget.message.isEmpty) ...[
          _buildTimestampWidget(isDark),
        ] else if (hasMedia && !_isImage && !_isVideo) ...[
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
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

    return ValueListenableBuilder<double>(
      valueListenable: FontSizeController.instance,
      builder: (context, fontScale, _) {
        final scaledFontSize = 17.0 * fontScale;

        Widget buildTextBody() {
          final emojiCount = getEmojiOnlyCount(text);
          if (emojiCount == 2) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  text.trim(),
                  style: TextStyle(
                    fontSize: 38.0 * fontScale,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2.0),
                  child: _buildTimestampWidget(isDark),
                ),
              ],
            );
          } else if (emojiCount == 3) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  text.trim(),
                  style: TextStyle(
                    fontSize: 32.0 * fontScale,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2.0),
                  child: _buildTimestampWidget(isDark),
                ),
              ],
            );
          }

          if (!isLongParagraph) {
            return RichText(
              text: TextSpan(
                style: TextStyle(
                  color: textColor,
                  fontSize: scaledFontSize,
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
                    fontSize: scaledFontSize,
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
                                fontSize: 14.0 * fontScale,
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
                    fontSize: scaledFontSize,
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
                              fontSize: 14.0 * fontScale,
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
      },
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
      final double maxW = MediaQuery.of(context).size.width * 0.74;

      final cleanMsg = widget.message.trim();
      final isGenericLabel = cleanMsg == '[Attachment]' ||
          cleanMsg == 'Photo' ||
          cleanMsg == 'Video' ||
          cleanMsg == 'Voice message';
      final hasText = cleanMsg.isNotEmpty && !isGenericLabel;
      final bool hasTopHeader = widget.isForwarded ||
          widget.replyText != null ||
          (widget.senderName != null && widget.senderName!.isNotEmpty);

      final imageRadius = hasTopHeader
          ? BorderRadius.circular(12)
          : BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: hasText
                  ? Radius.zero
                  : (widget.isMe ? const Radius.circular(16) : const Radius.circular(4)),
              bottomRight: hasText
                  ? Radius.zero
                  : (widget.isMe ? const Radius.circular(4) : const Radius.circular(16)),
            );

      return ClipRRect(
        borderRadius: imageRadius,
        child: GestureDetector(
          onTap: showFullImage ? _showImageViewer : _revealImage,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: maxW,
              minWidth: maxW,
              maxHeight: 420,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (showFullImage)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxW,
                      minWidth: maxW,
                      maxHeight: 420,
                    ),
                    child: RepaintBoundary(
                      child: Image.file(
                        File(_downloadedPath!),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        cacheWidth: 800,
                        filterQuality: FilterQuality.medium,
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
                              minWidth: maxW,
                              maxHeight: 220,
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
                else if (hasLocal)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxW,
                      minWidth: maxW,
                      maxHeight: 420,
                    ),
                    child: RepaintBoundary(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Image.file(
                          File(_downloadedPath!),
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          cacheWidth: 600,
                          filterQuality: FilterQuality.low,
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
                                minWidth: maxW,
                                maxHeight: 220,
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
                    ),
                  )
                else
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: maxW,
                      minWidth: maxW,
                      maxHeight: 220,
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
                  Positioned.fill(
                    child: Container(
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
      final double maxW = MediaQuery.of(context).size.width * 0.74;

      final cleanMsg = widget.message.trim();
      final isGenericLabel = cleanMsg == '[Attachment]' ||
          cleanMsg == 'Photo' ||
          cleanMsg == 'Video' ||
          cleanMsg == 'Voice message';
      final hasText = cleanMsg.isNotEmpty && !isGenericLabel;
      final bool hasTopHeader = widget.isForwarded ||
          widget.replyText != null ||
          (widget.senderName != null && widget.senderName!.isNotEmpty);

      final videoRadius = hasTopHeader
          ? BorderRadius.circular(12)
          : BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: hasText
                  ? Radius.zero
                  : (widget.isMe ? const Radius.circular(16) : const Radius.circular(4)),
              bottomRight: hasText
                  ? Radius.zero
                  : (widget.isMe ? const Radius.circular(4) : const Radius.circular(16)),
            );

      return GestureDetector(
        onTap: hasLocal
            ? _openAttachment
            : (_isDownloading ? null : _revealImage),
        child: ClipRRect(
          borderRadius: videoRadius,
          child: Container(
            width: maxW,
            constraints: BoxConstraints(
              maxWidth: maxW,
              minWidth: maxW,
              maxHeight: 420,
              minHeight: 180,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (videoSource.isNotEmpty)
                  VideoThumbnailCard(
                    mediaUrl: videoSource,
                    width: maxW,
                    height: 420,
                    borderRadius: videoRadius,
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

  Widget _buildQuickForwardButton(bool isDark) {
    if (widget.onShowMessageActions == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () {
        final box = context.findRenderObject() as RenderBox?;
        final globalPos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
        final size = box?.size ?? const Size(200, 200);
        final msg = ChatMessage(
          id: widget.timestamp.millisecondsSinceEpoch.toString(),
          senderId: widget.isMe ? 'user' : 'peer',
          content: widget.message,
          timestamp: widget.timestamp,
          type: widget.type ?? 'text',
          mediaUrl: widget.mediaUrl,
          fileName: widget.fileName,
        );
        widget.onShowMessageActions!(msg, globalPos, size);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          CupertinoIcons.reply_thick_solid,
          size: 15,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
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
              chatId: widget.chatId,
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
      final sentColor = AppPreferences.getChatBubbleColor(chatId: widget.chatId);
      final bubbleColor = widget.isMe
          ? sentColor.withValues(alpha: 0.8)
          : AppTheme.receivedBubble(isDark);
      final textColor = widget.isMe
          ? Colors.white.withValues(alpha: 0.85)
          : (isDark ? Colors.white70 : Colors.black54);
      const deletedText = 'This message was deleted';

      final Widget deletedBubbleContent = Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 12.0),
        child: Align(
          alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.block_rounded,
                    size: 16,
                    color: textColor.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      deletedText,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15.0,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _buildTimestampWidget(isDark),
                  ),
                ],
              ),
            ),
          ),
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
                Expanded(child: deletedBubbleContent),
              ],
            ),
          ),
        );
      }

      return GestureDetector(
        onLongPress: () {
          if (widget.onShowMessageActions != null) {
            final box = context.findRenderObject() as RenderBox?;
            final globalPos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
            final size = box?.size ?? const Size(200, 200);
            final deletedMsg = ChatMessage(
              id: widget.timestamp.millisecondsSinceEpoch.toString(),
              senderId: widget.isMe ? 'user' : 'peer',
              content: deletedText,
              timestamp: widget.timestamp,
              type: 'text',
              isDeleted: true,
            );
            widget.onShowMessageActions!(deletedMsg, globalPos, size);
          }
        },
        child: deletedBubbleContent,
      );
    }


    final cleanType = (widget.type ?? 'text').toLowerCase().trim();
    final cleanMsg = widget.message.trim();
    final rawMediaUrl = widget.mediaUrl?.trim();

    final isSticker = cleanType == 'sticker' ||
        widget.type == 'sticker' ||
        cleanMsg.startsWith('stk_');

    final isGif = cleanType == 'gif' ||
        cleanType == 'image/gif' ||
        cleanType == 'animation' ||
        (rawMediaUrl != null &&
            (rawMediaUrl.toLowerCase().contains('.gif') ||
                rawMediaUrl.toLowerCase().contains('giphy.com') ||
                rawMediaUrl.toLowerCase().contains('tenor.com')));

    final isTextType = cleanType == 'text' || cleanType == 'text/plain';
    final hasMedia = !isTextType && rawMediaUrl != null && rawMediaUrl.isNotEmpty;
    final hasReply = widget.replyText != null;

    final singleEmojiCount = (isTextType && !hasMedia && !hasReply && !widget.isForwarded)
        ? getEmojiOnlyCount(cleanMsg)
        : 0;

    final isStandaloneSingleEmoji = singleEmojiCount == 1;
    final isStandaloneItem = isSticker || isGif || isStandaloneSingleEmoji;

    if (isStandaloneItem && !widget.isDeleted) {
      final Widget standaloneBody = _buildStandaloneContent(
        context,
        isDark,
        cleanMsg,
        isSticker,
        isGif,
        widget.mediaUrl,
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
                Expanded(child: standaloneBody),
              ],
            ),
          ),
        );
      }

      return standaloneBody;
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (widget.isMe && mediaUrl != null && mediaUrl.trim().isNotEmpty)
                        _buildQuickForwardButton(isDark),
                      Container(
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
                              maxWidth: MediaQuery.of(context).size.width * 0.74,
                            ),
                            margin: EdgeInsets.only(
                              left: widget.isMe ? 0 : 6,
                              right: widget.isMe ? 6 : 0,
                            ),
                            padding: (_isImage || _isVideo) && mediaUrl != null && mediaUrl.trim().isNotEmpty
                                ? EdgeInsets.zero
                                : const EdgeInsets.symmetric(
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
                      if (!widget.isMe && mediaUrl != null && mediaUrl.trim().isNotEmpty)
                        _buildQuickForwardButton(isDark),
                    ],
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
  final String? chatId;
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
    this.chatId,
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
      chatId: chatId,
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
            chatId: chatId,
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
            chatId: chatId,
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
            chatId: chatId,
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
                chatId: chatId,
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
                chatId: chatId,
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
                chatId: chatId,
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
                chatId: chatId,
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
                chatId: chatId,
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
                    chatId: chatId,
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
  final String? chatId;
  final double? width;
  final double height;
  final VoidCallback onTap;
  final bool isSelectionMode;
  final VoidCallback? onToggleSelect;
  final Function(ChatMessage, Offset, Size)? onShowMessageActions;

  const _GridTileItem({
    required this.photoMessage,
    this.chatId,
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
            final secretKey = widget.chatId != null && widget.chatId!.isNotEmpty
                ? 'chat_key_${widget.chatId}'
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
      imageWidget = RepaintBoundary(
        child: Image.file(
          File(path),
          width: tileWidth,
          height: widget.height,
          cacheWidth: 600,
          filterQuality: FilterQuality.low,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image_rounded, color: Colors.white70),
          ),
        ),
      );
    } else {
      final headers = ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : null;
      imageWidget = RepaintBoundary(
        child: Image.network(
          path,
          key: ValueKey(path),
          headers: headers,
          width: tileWidth,
          height: widget.height,
          cacheWidth: 600,
          filterQuality: FilterQuality.low,
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

class BouncyMessageEntryAnimation extends StatefulWidget {
  final bool isMe;
  final bool animate;
  final Widget child;

  const BouncyMessageEntryAnimation({
    super.key,
    required this.isMe,
    required this.child,
    this.animate = true,
  });

  @override
  State<BouncyMessageEntryAnimation> createState() =>
      _BouncyMessageEntryAnimationState();
}

class _BouncyMessageEntryAnimationState
    extends State<BouncyMessageEntryAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  late final Animation<double> _scaleAnimation = Tween<double>(
    begin: 0.35,
    end: 1.0,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ),
  );

  late final Animation<Offset> _slideAnimation = Tween<Offset>(
    begin: widget.isMe ? const Offset(0.12, 0.18) : const Offset(-0.12, 0.18),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return widget.child;
    }
    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: widget.isMe ? Alignment.bottomRight : Alignment.bottomLeft,
        child: widget.child,
      ),
    );
  }
}

class StandaloneGifWidget extends StatefulWidget {
  final String? mediaUrl;
  final String message;
  final String secretKey;
  final bool isDark;

  const StandaloneGifWidget({
    super.key,
    required this.mediaUrl,
    required this.message,
    required this.secretKey,
    required this.isDark,
  });

  @override
  State<StandaloneGifWidget> createState() => _StandaloneGifWidgetState();
}

class _StandaloneGifWidgetState extends State<StandaloneGifWidget> {
  String? _resolvedPath;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _resolveAndInit();
  }

  @override
  void didUpdateWidget(covariant StandaloneGifWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl || oldWidget.message != widget.message) {
      _resolveAndInit();
    }
  }

  Future<void> _resolveAndInit() async {
    final targetUrl = (widget.mediaUrl != null && widget.mediaUrl!.trim().isNotEmpty)
        ? widget.mediaUrl!.trim()
        : widget.message.trim();

    if (targetUrl.isEmpty) return;

    // 1. Check if targetUrl is already a valid local file path
    if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
      final file = File(targetUrl);
      if (file.existsSync() && file.lengthSync() > 16) {
        if (mounted) {
          setState(() {
            _resolvedPath = file.path;
          });
        }
        return;
      }
    }

    // 2. Resolve via AttachmentCacheService
    final cached = await AttachmentCacheService.instance.resolveLocalPath(targetUrl);
    if (cached != null && File(cached).existsSync() && File(cached).lengthSync() > 16) {
      if (mounted) {
        setState(() {
          _resolvedPath = cached;
        });
      }
      return;
    }

    // 3. Download and decrypt from network if needed
    if (mounted) {
      unawaited(_downloadAndDecrypt(targetUrl));
    }
  }

  Future<void> _downloadAndDecrypt(String url) async {
    if (_isDownloading) return;
    if (mounted) {
      setState(() {
        _isDownloading = true;
      });
    }

    try {
      String downloadUrl = url;
      if (!downloadUrl.startsWith('http://') && !downloadUrl.startsWith('https://')) {
        String cleanPath = url;
        if (url.contains('uploads/')) {
          cleanPath = 'uploads/${url.split('uploads/').last}';
        } else if (url.contains('files/')) {
          cleanPath = 'files/${url.split('files/').last}';
        }
        final normalized = cleanPath.replaceFirst(RegExp(r'^/+'), '');
        final apiBase = ServerApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
        final filePath = normalized.startsWith('api/files/')
            ? normalized.substring('api/files/'.length)
            : normalized.startsWith('files/')
                ? normalized.substring('files/'.length)
                : normalized;
        final encodedPath = filePath.split('/').map(Uri.encodeComponent).join('/');
        downloadUrl = '$apiBase/files/$encodedPath';
      }

      final headers = ServerApiService.instance.authToken == null
          ? <String, String>{}
          : {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'};

      final response = await http.get(Uri.parse(downloadUrl), headers: headers).timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        var bytes = response.bodyBytes;
        final decrypted = E2eCryptoService.instance.decryptFileBytes(bytes, widget.secretKey);
        if (decrypted.length > 16) {
          bytes = decrypted;
        }

        final docsDir = await getApplicationDocumentsDirectory();
        final attachmentDir = Directory('${docsDir.path}${Platform.pathSeparator}chat_attachments');
        await attachmentDir.create(recursive: true);

        final safeKey = url.split('/').last.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final targetFile = File('${attachmentDir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_$safeKey');
        await targetFile.writeAsBytes(bytes, flush: true);

        AttachmentCacheService.instance.updateCache(url, targetFile.path);

        if (mounted) {
          setState(() {
            _resolvedPath = targetFile.path;
            _isDownloading = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('[STANDALONE GIF DOWNLOAD ERROR] $e');
    }

    if (mounted) {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    // Case 1: Resolved local file exists -> Render animated GIF via Image.file!
    if (_resolvedPath != null && File(_resolvedPath!).existsSync()) {
      return Container(
        constraints: BoxConstraints(
          maxWidth: screenSize.width * 0.70,
          maxHeight: 280,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: widget.isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(
          File(_resolvedPath!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildErrorCard(),
        ),
      );
    }

    // Case 2: Downloading in progress -> Show progress indicator
    if (_isDownloading) {
      return Container(
        width: 220,
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: widget.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF007AFF),
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Downloading GIF…',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Case 3: Direct HTTP link attempt
    final targetUrl = (widget.mediaUrl != null && widget.mediaUrl!.trim().isNotEmpty)
        ? widget.mediaUrl!.trim()
        : widget.message.trim();

    if (targetUrl.startsWith('http://') || targetUrl.startsWith('https://')) {
      return Container(
        constraints: BoxConstraints(
          maxWidth: screenSize.width * 0.70,
          maxHeight: 280,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: widget.isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          targetUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDownloadCard(targetUrl),
        ),
      );
    }

    return _buildDownloadCard(targetUrl);
  }

  Widget _buildDownloadCard(String url) {
    return GestureDetector(
      onTap: () => _downloadAndDecrypt(url),
      child: Container(
        width: 220,
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: widget.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF007AFF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.arrow_down,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tap to Download GIF',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: 220,
      height: 160,
      color: widget.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gif_rounded, size: 42, color: Colors.white54),
            SizedBox(height: 4),
            Text('GIF unavailable', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
