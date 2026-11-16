import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, kDebugMode;
import '../../domain/services/chat_audio_playback.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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

import 'location_chat_bubble.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/attachment_upload_service.dart';
import '../../domain/services/doc_preview_service.dart';
import '../../domain/utils/chat_link_parser.dart';
import 'file_type_visuals.dart';
import 'sticker_picker_panel.dart';
import '../../domain/models/server_models.dart';
import '../../domain/services/e2e_crypto_service.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/attachment_cache_service.dart';
import 'chat_media_viewer.dart';
import 'photo_gallery_viewer.dart';
import 'rich_link_preview_card.dart';
import 'app_video_player.dart';
import 'forwarded_tag.dart';
import '../../domain/services/chat_media_downloader.dart';

class _DownloadGate {
  static int _active = 0;
  static const _max = 2;
  static final _queue = <Completer<void>>[];

  static Future<void> acquire() async {
    if (_active < _max) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
  }

  static void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}

// runs in a background isolate
bool _decryptFileOnDisk(List<String> a) {
  // a = [tmpPath, outPath, secretKey, isImage('1'/'0')]
  try {
    final raw = File(a[0]).readAsBytesSync();
    var out = E2eCryptoService.instance.decryptFileBytes(raw, a[2]);
    if (a[3] == '1' && !_looksLikeImage(out)) {
      if (_looksLikeImage(raw)) {
        out = raw;
      } else {
        return false;
      }
    }
    File(a[1]).writeAsBytesSync(out, flush: true);
    try {
      File(a[0]).deleteSync();
    } catch (_) {}
    return true;
  } catch (_) {
    return false;
  }
}

bool _looksLikeImage(Uint8List b) {
  if (b.length < 4) return false;
  return (b[0] == 0x89 && b[1] == 0x50) ||
      (b[0] == 0xFF && b[1] == 0xD8) ||
      (b[0] == 0x47 && b[1] == 0x49) ||
      (b[0] == 0x42 && b[1] == 0x4D) ||
      (b.length >= 12 && b[0] == 0x52 && b[8] == 0x57);
}

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
  final Function(ChatMessage message, Offset pos, Size size, {bool reactionsOnly})? onShowMessageActions;
  final String? msgType;
  final int? callId;
  final String? callType;
  final String? callStatus;
  final int? callDuration;
  final VoidCallback? onVoiceCallTap;
  final VoidCallback? onVideoCallTap;
  final VoidCallback? onFailedTap;
  final String? status;
  final String? id;
  final bool showTail;
  final ChatMessage? sourceMessage;
  final ValueChanged<ChatMessage>? onReplyToMessage;
  final ValueChanged<ChatMessage>? onForwardMessage;
  final void Function(ChatMessage, String emoji)? onReactMessage;
  final Future<bool> Function(ChatMessage)? onToggleStarMessage;
  final ValueChanged<ChatMessage>? onDeleteMessage;

  const ChatBubble({
    super.key,
    this.id,
    this.sourceMessage,
    this.onReplyToMessage,
    this.onForwardMessage,
    this.onReactMessage,
    this.onToggleStarMessage,
    this.onDeleteMessage,
    this.onFailedTap,
    required this.message,
    required this.isMe,
    required this.timestamp,
    this.isRead = false,
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
    this.status,
    this.showTail = true,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble>
    with AutomaticKeepAliveClientMixin<ChatBubble> {
  static final Map<String, double> _aspectRatioCache = <String, double>{};

  @override
  bool get wantKeepAlive => false;

  String get _audioKey => '${widget.chatId ?? ''}|$_attachmentName';

  String? _downloadedPath;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  int _downloadedBytes = 0;
  int _totalDownloadBytes = 0;
  bool _isMediaRevealed = false;
  bool _downloadFailed = false;
  bool _isExpanded = false;
  bool _localOk = false;

  double? _imageAspectRatio;
  double? _videoAspectRatio;
  Duration? _videoDuration;
  Duration? _audioDuration;

  void _loadAudioDurationIfNeeded() {
    if (!_isAudio) return;
    if (_audioDuration != null && _audioDuration! > Duration.zero) return;
    final cached = AudioDurationCache.get(_audioKey);
    if (cached != null && cached > Duration.zero) {
      _audioDuration = cached;
      return;
    }
    final path = _effectiveLocalPath ?? _downloadedPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      AudioDurationCache.fetch(_audioKey, path).then((dur) {
        if (dur != null && dur > Duration.zero && mounted) {
          setState(() {
            _audioDuration = dur;
          });
        }
      });
    }
  }

  void _refreshLocalOk() {
    final p = _downloadedPath ?? widget.mediaUrl;
    _localOk = p != null && p.isNotEmpty && !p.startsWith('http') && File(p).existsSync();
  }

  @override
  void initState() {
    super.initState();
    final syncPath = AttachmentCacheService.instance.resolveLocalPathSync(widget.mediaUrl);
    if (syncPath != null) {
      _downloadedPath = syncPath;
      _isMediaRevealed = true;
      _imageAspectRatio = _aspectRatioCache[syncPath];
    } else if (widget.mediaUrl != null &&
        !widget.mediaUrl!.startsWith('http') &&
        File(widget.mediaUrl!).existsSync()) {
      _downloadedPath = widget.mediaUrl;
      _isMediaRevealed = true;
      _imageAspectRatio = _aspectRatioCache[widget.mediaUrl!];
    } else if (widget.mediaUrl?.isNotEmpty == true) {
      unawaited(_restoreDownloadedAttachment());
    }
    _refreshLocalOk();
    _resolveImageAspectRatio();
    unawaited(_loadFileMeta());
  }

  @override
  void didUpdateWidget(ChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      final syncPath = AttachmentCacheService.instance.resolveLocalPathSync(widget.mediaUrl);
      final sameFile = syncPath != null && syncPath == _downloadedPath;
      if (!sameFile) {
        _imageAspectRatio = null;
        _videoAspectRatio = null;
        _videoDuration = null;
        _audioDuration = null;
      }
      if (syncPath != null) {
        _downloadedPath = syncPath;
        _isMediaRevealed = true;
        _imageAspectRatio = _aspectRatioCache[syncPath];
      } else if (widget.mediaUrl != null &&
          !widget.mediaUrl!.startsWith('http') &&
          File(widget.mediaUrl!).existsSync()) {
        _downloadedPath = widget.mediaUrl;
        _isMediaRevealed = true;
        _imageAspectRatio = _aspectRatioCache[widget.mediaUrl!];
      } else if (widget.mediaUrl?.isNotEmpty == true) {
        unawaited(_restoreDownloadedAttachment());
      }
      _refreshLocalOk();
      _resolveImageAspectRatio();
      unawaited(_loadFileMeta());
    }
  }

  Future<double?> _readAspect(String path) async {
    try {
      final buf = await ui.ImmutableBuffer.fromFilePath(path);
      final desc = await ui.ImageDescriptor.encoded(buf);
      final ar = desc.width > 0 && desc.height > 0 ? desc.width / desc.height : null;
      desc.dispose();
      buf.dispose();
      return ar;
    } catch (_) {
      return null;
    }
  }

  void _resolveImageAspectRatio() {
    final path = _downloadedPath ?? widget.mediaUrl;
    if (path == null || path.isEmpty) return;

    final hit = _aspectRatioCache[path];
    if (hit != null) {
      _imageAspectRatio = hit;
      return;
    }

    if (!_isImage || !File(path).existsSync()) return;
    _readAspect(path).then((ar) {
      if (ar == null) return;
      _aspectRatioCache[path] = ar;
      if (mounted && _imageAspectRatio != ar) {
        setState(() => _imageAspectRatio = ar);
      }
    });
  }

  Size _getAdaptiveMediaSize(BuildContext context, double? aspectRatio) {
    final screenW = MediaQuery.of(context).size.width;
    final maxW = math.min(screenW * 0.72, 290.0);
    const maxH = 280.0;
    const minH = 150.0;

    if (aspectRatio == null || aspectRatio <= 0) {
      return Size(maxW, 240.0);
    }

    double targetH;
    if (aspectRatio < 0.85) {
      targetH = maxH;
    } else if (aspectRatio > 1.3) {
      targetH = (maxW / aspectRatio).clamp(minH, 220.0);
    } else {
      targetH = (maxW / aspectRatio).clamp(minH, maxH);
    }

    return Size(maxW, targetH);
  }

  String _formatMediaDuration(Duration duration) {
    if (duration.inHours > 0) {
      final h = duration.inHours;
      final m = (duration.inMinutes % 60).toString().padLeft(2, '0');
      final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
      return '$h:$m:$s';
    } else {
      final m = duration.inMinutes;
      final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }
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

  static const _genericLabels = {
    '[Attachment]',
    'Photo',
    'Video',
    'Voice message',
    'Document',
    'GIF',
  };

  static final _linkRegex =
  RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);

  int? _fileBytes;
  DocPreview? _docPreview;

  bool _hasCaptionText(String msg) {
    final parsed = ChatLinkParser.parse(msg);
    if (parsed.isOnlyLinks) return false;
    final t = parsed.remainingText.trim().toLowerCase();
    if (t.isEmpty || _genericLabels.map((e) => e.toLowerCase()).contains(t)) {
      return false;
    }
    final fileName = (widget.fileName ?? '').trim().toLowerCase();
    final attName = _attachmentName.trim().toLowerCase();
    if (t == fileName || t == attName) return false;

    final baseFileName = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.')).trim()
        : fileName;
    final baseAttName = attName.contains('.')
        ? attName.substring(0, attName.lastIndexOf('.')).trim()
        : attName;

    if (t == baseFileName || t == baseAttName) return false;

    return true;
  }

  Future<void> _loadFileMeta() async {
    if (_isImage || _isVideo || _isAudio) return;
    final path = _effectiveLocalPath;
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) {
        final bytes = await file.length();
        final preview = fileExtension(_attachmentName) == 'pdf'
            ? await DocPreviewService.instance.get(path)
            : null;
        if (mounted) {
          setState(() {
            _fileBytes = bytes;
            _docPreview = preview;
          });
        }
      }
    } catch (_) {}
  }

  bool get _hasValidLocalFile => _localOk;
  String? get _effectiveLocalPath => _localOk ? (_downloadedPath ?? widget.mediaUrl) : null;

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
      if (mediaPath != null && mediaPath.isNotEmpty && File(mediaPath).existsSync()) {
        if (mounted) {
          setState(() {
            _downloadedPath = mediaPath;
            _isMediaRevealed = true;
            _downloadFailed = false;
          });
          _resolveImageAspectRatio();
          unawaited(_loadFileMeta());
        }
        return;
      }
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
          _resolveImageAspectRatio();
          unawaited(_loadFileMeta());
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
        _resolveImageAspectRatio();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
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

  String? get _audioSenderAvatar {
    if (widget.isMe) {
      final user = ServerApiService.instance.currentUser;
      if (user?.avatar?.isNotEmpty == true) {
        return user!.avatar!;
      }
      return null;
    }
    final chatId = widget.chatId;
    final convs = LocalChatStorage.instance.conversationsNotifier.value;
    if (chatId != null && chatId.isNotEmpty) {
      for (final c in convs) {
        if (c.id == chatId || c.peerUserId.toString() == chatId) {
          if (c.avatarUrl.isNotEmpty) return c.avatarUrl;
        }
      }
    }
    if (widget.senderName != null && widget.senderName!.isNotEmpty) {
      for (final c in convs) {
        if (c.name.toLowerCase() == widget.senderName!.toLowerCase()) {
          if (c.avatarUrl.isNotEmpty) return c.avatarUrl;
        }
      }
    }
    return null;
  }

  String get _audioSenderName {
    if (widget.isMe) {
      final user = ServerApiService.instance.currentUser;
      if (user != null && user.name.isNotEmpty && !user.name.startsWith('User #')) {
        return user.name;
      }
      return 'You';
    }
    if (widget.senderName != null && widget.senderName!.isNotEmpty) {
      return widget.senderName!;
    }
    final chatId = widget.chatId;
    if (chatId != null && chatId.isNotEmpty) {
      final convs = LocalChatStorage.instance.conversationsNotifier.value;
      for (final c in convs) {
        if (c.id == chatId || c.peerUserId.toString() == chatId) {
          if (c.name.isNotEmpty) return c.name;
        }
      }
    }
    return 'User';
  }

  Future<String> _downloadAttachment() async {
    if (_hasValidLocalFile) {
      return _effectiveLocalPath ?? _downloadedPath!;
    }
    final mediaUrl = widget.mediaUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) {
      throw Exception('This attachment has no download URL.');
    }
    if (mounted) {
      setState(() {
        _isDownloading = true;
        _downloadFailed = false;
        _downloadProgress = 0.0;
        _downloadedBytes = 0;
        _totalDownloadBytes = 0;
      });
    }

    await _DownloadGate.acquire();
    final client = http.Client();
    File? tmp;
    try {
      if (_isAbsoluteFilePath(mediaUrl) && File(mediaUrl).existsSync()) {
        _downloadedPath = mediaUrl;
        _isMediaRevealed = true;
        _downloadFailed = false;
        _refreshLocalOk();
        if (mounted) setState(() => _isDownloading = false);
        return mediaUrl;
      }

      final remoteUrl = _resolveRemoteMediaUrl(mediaUrl);
      final headers = ServerApiService.instance.authToken == null
          ? <String, String>{}
          : {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'};

      final request = http.Request('GET', Uri.parse(remoteUrl));
      if (headers.isNotEmpty) request.headers.addAll(headers);

      final streamedRes =
          await client.send(request).timeout(const Duration(seconds: 45));

      if (streamedRes.statusCode < 200 || streamedRes.statusCode >= 300) {
        throw Exception('Download failed (${streamedRes.statusCode}).');
      }

      final total = streamedRes.contentLength ?? 0;
      final tmpDir = await getTemporaryDirectory();
      tmp = File(
          '${tmpDir.path}${Platform.pathSeparator}dl_${DateTime.now().microsecondsSinceEpoch}.tmp');
      final sink = tmp.openWrite();
      var downloaded = 0, lastUi = 0;
      await for (final chunk in streamedRes.stream) {
        sink.add(chunk); // straight to disk, no List<int>
        downloaded += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (mounted && now - lastUi > 120) {
          lastUi = now;
          setState(() {
            _downloadProgress =
                total > 0 ? (downloaded / total).clamp(0.0, 1.0) : 0.0;
            _downloadedBytes = downloaded;
            _totalDownloadBytes = total;
          });
        }
      }
      await sink.close();

      final outputPath = await _getLocalAttachmentPath();
      final secretKey = widget.chatId != null && widget.chatId!.isNotEmpty
          ? 'chat_key_${widget.chatId}'
          : '';

      final ok = await compute(_decryptFileOnDisk, [
        tmp.path,
        outputPath,
        secretKey,
        _isImage ? '1' : '0',
      ]);
      if (!ok) throw Exception('Decrypted image payload is invalid.');

      _downloadedPath = outputPath;
      _isMediaRevealed = true;
      _refreshLocalOk();
      AttachmentCacheService.instance.updateCache(mediaUrl, outputPath);
      final ar = await _readAspect(outputPath);
      if (ar != null) _aspectRatioCache[outputPath] = ar;
      _downloadFailed = false;
      return outputPath;
    } catch (e) {
      try {
        await tmp?.delete();
      } catch (_) {}
      if (mounted) setState(() => _downloadFailed = true);
      rethrow;
    } finally {
      client.close();
      _DownloadGate.release();
      if (mounted) setState(() => _isDownloading = false);
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
        _resolveImageAspectRatio();
      }
    } catch (error) {
      AppToast.show(AppToast.userFriendlyMessage('Could not download photo: $error'), isError: true);
    }
  }

  Future<void> _showImageViewer() async {
    final ctl = ChatMediaScope.maybeOf(context);
    final mid = widget.sourceMessage?.id ?? widget.id;
    final live = (ctl != null && mid != null) ? ctl.byId(mid) : null;
    if (ctl != null && live != null) {
      ChatMediaViewer.openPager(context, ctl, live);
      return;
    }

    final src = widget.sourceMessage;
    final localPath = _effectiveLocalPath ?? widget.mediaUrl;
    final base = src ??
        ChatMessage(
          id: widget.id ?? widget.timestamp.millisecondsSinceEpoch.toString(),
          senderId: widget.isMe ? 'user' : 'peer',
          content: widget.message,
          timestamp: widget.timestamp,
          type: widget.type ?? 'image/jpeg',
          fileName: widget.fileName,
        );
    final viewerMsg = base.copyWith(mediaUrl: localPath);

    PhotoGalleryViewer.open(
      context,
      photos: [viewerMsg],
      onReply: widget.onReplyToMessage == null
          ? null
          : (_) => widget.onReplyToMessage!(base), // reply with the ORIGINAL message
    );
  }

  Future<void> _openAttachment() async {
    try {
      final path = await _downloadAttachment();
      if (_isVideo) {
        if (!mounted) return;
        final ctl = ChatMediaScope.maybeOf(context);
        final mid = widget.sourceMessage?.id ?? widget.id;
        final live = (ctl != null && mid != null) ? ctl.byId(mid) : null;
        if (ctl != null && live != null) {
          ChatMediaViewer.openPager(context, ctl, live);
        } else {
          AppVideoPlayerModal.open(context, mediaUrl: path, title: widget.fileName ?? 'Video');
        }
        return;
      }
      await OpenFilex.open(path);
    } catch (error) {
      AppToast.show(
          AppToast.userFriendlyMessage('Could not open attachment: $error'),
          isError: true);
    }
  }

  String _formatAudioDuration(Duration d) {
    if (d.inHours > 0) {
      final h = d.inHours;
      final m = (d.inMinutes % 60).toString().padLeft(2, '0');
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$h:$m:$s';
    } else {
      final m = d.inMinutes;
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }
  }

  Future<void> _toggleAudioPlayback() async {
    try {
      final path = await _downloadAttachment(); // returns instantly if already local
      await ChatAudioPlayback.instance.toggle(key: _audioKey, path: path);
    } catch (error) {
      AppToast.show(
        AppToast.userFriendlyMessage('Could not play voice message: $error'),
        isError: true,
      );
    }
  }

  String _formattedTime() {
    final time = widget.timestamp.toLocal();
    final h24 = time.hour;
    final h = h24 > 12 ? h24 - 12 : (h24 == 0 ? 12 : h24);
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m ${h24 >= 12 ? 'PM' : 'AM'}';
  }

  Color get _fwdColor {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return widget.isMe
        ? Colors.white.withValues(alpha: 0.8)
        : (dark ? Colors.white60 : Colors.black54);
  }

  Widget _fwdPlain() => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ForwardedTag(color: _fwdColor));

  Widget _fwdPill() => const ForwardedTag(color: Colors.white, pill: true);

  double get _fwdLeft => (!widget.isMe && widget.showTail) ? 16.0 : 10.0;

  bool get _isHdMedia =>
      (widget.fileName ?? '').startsWith('hd_') && (_isImage || _isVideo);

  Widget _hdBadge(Color color) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 0.9),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          'HD',
          style: TextStyle(
            color: color,
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      );

  String? _memoizedTimestampKey;
  double? _memoizedTimestampWidthValue;

  /// Width reserved at the end of the last text line for the timestamp.
  double _timestampWidth() {
    final key =
        '${_formattedTime()}_${widget.isEdited}_${widget.isSaved}_${widget.isMe}_$_isHdMedia';
    if (_memoizedTimestampKey == key && _memoizedTimestampWidthValue != null) {
      return _memoizedTimestampWidthValue!;
    }

    double measure(String s, double size, {bool italic = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontSize: size,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    }

    var w = measure(_formattedTime(), 11);
    if (widget.isEdited) w += measure('edited ', 10, italic: true);
    if (widget.isSaved) w += 54;
    if (_isHdMedia) w += 22;
    if (widget.isMe) w += 17; // tick + gap
    final result = w + 8;
    _memoizedTimestampKey = key;
    _memoizedTimestampWidthValue = result;
    return result;
  }

  Widget _buildTimestampWidget(bool isDark, {Color? overrideTextColor}) {
    final formattedTime = _formattedTime();

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
        if (_isHdMedia) _hdBadge(textStyleColor),
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

  String _getDeliveryStatusText() {
    if ((widget.status ?? '').toLowerCase() == 'failed') return 'Not sent';
    final s = (widget.status ?? '').toLowerCase().trim();
    if (s == 'sending' || (widget.id != null && widget.id!.startsWith('local_'))) {
      return 'Sending...';
    }
    if (widget.isRead || s == 'read' || s == 'seen') {
      return 'Seen';
    }
    if (widget.isDelivered || s == 'delivered') {
      return 'Delivered';
    }
    return 'Sent';
  }

  Widget _buildStatusTick(bool isDark) {
    final s = (widget.status ?? '').toLowerCase().trim();

    if (s == 'failed') {
      return const Icon(Icons.error_outline_rounded,
          size: 14, color: Color(0xFFFF453A));
    }

    if (s == 'sending' || (widget.id != null && widget.id!.startsWith('local_'))) {
      return Icon(
        Icons.access_time_rounded,
        size: 12,
        color: widget.isMe
            ? Colors.white.withValues(alpha: 0.7)
            : (isDark ? Colors.white54 : AppTheme.subtitleGrey),
      );
    }

    if (widget.isRead || s == 'read' || s == 'seen') {
      return const Icon(
        Icons.done_all_rounded,
        size: 14,
        color: Color(0xFF53BDEB),
      );
    }

    if (widget.isDelivered || s == 'delivered') {
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
      final cachedSync = AttachmentCacheService.instance.resolveLocalPathSync(url);
      if (cachedSync != null && File(cachedSync).existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: RepaintBoundary(
            child: Image.file(
              File(cachedSync),
              width: 32,
              height: 32,
              cacheWidth: 96,
              cacheHeight: 96,
              fit: BoxFit.cover,
            ),
          ),
        );
      }

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
              child: Image.network(
                resolved,
                width: 32,
                height: 32,
                cacheWidth: 96,
                cacheHeight: 96,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
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
          ? Colors.white.withValues(alpha: 0.22)
          : (isDark ? const Color(0x2634C759) : const Color(0x1A34C759));
      iconColor = widget.isMe ? Colors.white : const Color(0xFF34C759);
      callIcon = isVideo ? Icons.videocam_rounded : Icons.call_made_rounded;
    } else {
      iconBgColor = widget.isMe
          ? Colors.white.withValues(alpha: 0.22)
          : (isDark ? const Color(0x2634C759) : const Color(0x1A34C759));
      iconColor = widget.isMe ? Colors.white : const Color(0xFF34C759);
      callIcon = isVideo ? Icons.videocam_rounded : Icons.call_received_rounded;
    }

    final rawTitle = widget.message.isNotEmpty
        ? widget.message
        : (isMissed
        ? (isVideo ? 'Missed video call' : 'Missed voice call')
        : (isOutgoing
        ? (isVideo ? 'Outgoing video call' : 'Outgoing voice call')
        : (isVideo ? 'Incoming video call' : 'Incoming voice call')));

    String displayTitle = rawTitle;
    String? durationStr;

    if (rawTitle.contains('(') && rawTitle.endsWith(')')) {
      final startIndex = rawTitle.lastIndexOf('(');
      displayTitle = rawTitle.substring(0, startIndex).trim();
      durationStr = rawTitle.substring(startIndex + 1, rawTitle.length - 1).trim();
    } else if (widget.callDuration != null && widget.callDuration! > 0) {
      final dur = widget.callDuration!;
      final m = dur ~/ 60;
      final s = dur % 60;
      durationStr = '$m:${s.toString().padLeft(2, '0')}';
    }

    final time = widget.timestamp.toLocal();
    final hour24 = time.hour;
    final hour = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final timeStr =
        '$hour:${time.minute.toString().padLeft(2, '0')} $period';

    final subInfo = durationStr != null && durationStr.isNotEmpty
        ? '$durationStr • $timeStr'
        : timeStr;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              callIcon,
              color: iconColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayTitle,
                  style: TextStyle(
                    fontSize: 13.5,
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
                    Flexible(
                      child: Text(
                        subInfo,
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.isMe
                              ? Colors.white.withValues(alpha: 0.75)
                              : (isDark ? Colors.white60 : Colors.black45),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.isMe) ...[
                      const SizedBox(width: 3),
                      _buildStatusTick(isDark),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
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
                size: 17,
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
                if (widget.isForwarded) _fwdPlain(),
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

    if (cleanType == 'location' ||
        cleanType == 'live_location' ||
        widget.msgType == 'location' ||
        widget.msgType == 'live_location' ||
        cleanMsg.contains('"latitude":') ||
        cleanMsg.contains('"longitude":')) {
      if (kDebugMode) {
        debugPrint('[LOC BUBBLE] type=$cleanType msgType=${widget.msgType} id=${widget.id} raw="$cleanMsg"');
      }
      return LocationMessageBubble(
        rawMessage: cleanMsg,
        messageId: widget.id,
        isMe: widget.isMe,
        isDark: isDark,
        chatHeadId: int.tryParse(widget.chatId ?? '') ?? 0,
        timestamp: _buildTimestampWidget(isDark, overrideTextColor: Colors.white),
      );
    }
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

    final parsedContent = ChatLinkParser.parse(cleanMsg);
    final hasText = _hasCaptionText(cleanMsg) || parsedContent.hasLinks;

    if ((_isImage || _isVideo) &&
        mediaUrl != null &&
        mediaUrl.trim().isNotEmpty) {
      final mediaSize = _getAdaptiveMediaSize(
        context,
        _isImage ? _imageAspectRatio : _videoAspectRatio,
      );

      // No caption: borderless media, time is overlaid on the media.
      if (!_hasCaptionText(cleanMsg)) {
        return _buildAttachment(isDark, mediaUrl);
      }

      // Caption: media + caption in ONE bubble. Width is locked to the media,
      // only the bottom grows when the caption is long.
      return SizedBox(
        width: mediaSize.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasReply)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: _buildReplyPreview(isDark, textColor),
              ),
            _buildAttachment(isDark, mediaUrl),
            _buildMediaCaption(isDark, textColor),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final fontScale = FontSizeController.instance.value;
        final w = hasReply && !hasMedia
            ? _measureReplyBubbleWidth(c.maxWidth, fontScale)
            : null; // media/doc cards keep their own width

        return SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isForwarded) _fwdPlain(),
              if (hasReply)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _buildReplyPreview(isDark, textColor),
                ),
              if (hasMedia) ...[
                _buildAttachment(isDark, mediaUrl),
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
                  child: _buildExpandableTextMessage(
                    context, isDark, textColor,
                    fill: hasReply && !hasMedia, // time stays at right edge
                  ),
                ),
              ] else if (!hasMedia && widget.message.isEmpty) ...[
                _buildTimestampWidget(isDark),
              ] else if (hasMedia && !_isImage && !_isVideo && !_isAudio) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: _buildTimestampWidget(isDark),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<InlineSpan> _buildHighlightedTextSpans(
      String text,
      Color textColor,
      bool isDark,
      ) {
    final spans = <InlineSpan>[];
    final linkColor = widget.isMe
        ? Colors.white
        : (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0066CC));

    final matches = _linkRegex.allMatches(text);
    final baseStyle = TextStyle(color: textColor);

    if (matches.isEmpty) {
      return buildEmojiSpans(text, textStyle: baseStyle);
    }

    int lastIndex = 0;
    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.addAll(buildEmojiSpans(
          text.substring(lastIndex, match.start),
          textStyle: baseStyle,
        ));
      }

      final urlText = text.substring(match.start, match.end);
      spans.add(
        TextSpan(
          text: urlText,
          style: TextStyle(
            color: linkColor,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
            decorationThickness: 1.2,
          ),
        ),
      );

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.addAll(buildEmojiSpans(
        text.substring(lastIndex),
        textStyle: baseStyle,
      ));
    }

    return spans;
  }

  Widget _buildMediaCaption(bool isDark, Color textColor) {
    final text = normalizeChatMessageText(widget.message);
    return ValueListenableBuilder<double>(
      valueListenable: FontSizeController.instance,
      builder: (context, fontScale, _) => Padding(
        padding: const EdgeInsets.fromLTRB(7, 6, 7, 3),
        child: BubbleTextBody(
          spans: _buildHighlightedTextSpans(text, textColor, isDark),
          style: TextStyle(
            color: textColor,
            fontSize: 16.0 * fontScale,
            height: 1.25,
          ),
          timestamp: _buildTimestampWidget(isDark),
          timestampWidth: _timestampWidth(),
          moreColor: widget.isMe
              ? Colors.white.withValues(alpha: 0.95)
              : AppTheme.primaryColor,
          fontScale: fontScale,
          fillWidth: true, // time stays at the bubble's right edge
        ),
      ),
    );
  }

  double _measureReplyBubbleWidth(double maxW, double fontScale) {
    double measure(String s, TextStyle st, {int lines = 1, required double w}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: st),
        textDirection: TextDirection.ltr,
        maxLines: lines,
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout(maxWidth: w);
      return tp.width;
    }

    // reply quote block
    final hasThumb = widget.repliedMessage?.hasMedia == true;
    final chrome = 9.0 * 2 + 3 + (hasThumb ? 38 : 0); // padding + border + thumb
    final inner = (maxW - chrome).clamp(40.0, maxW);
    final senderW = measure(widget.replySender ?? 'Reply',
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        w: inner);
    final quoteW = measure(widget.replyText ?? '',
        const TextStyle(fontSize: 12),
        lines: 2, w: inner);
    final replyW = math.max(senderW, quoteW) + chrome;

    // actual message text + timestamp
    final tsW = _timestampWidth();
    final tp = TextPainter(
      text: TextSpan(
        text: normalizeChatMessageText(widget.message),
        style: TextStyle(fontSize: 17.0 * fontScale, height: 1.22),
      ),
      textDirection: TextDirection.ltr,
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: maxW);
    final lines = tp.computeLineMetrics();
    final lastW = lines.isEmpty ? 0.0 : lines.last.width;
    final textW = math.max(tp.width, lastW + tsW);

    return math.max(replyW, textW).clamp(110.0, maxW).toDouble();
  }

  Widget _buildReplyPreview(bool isDark, Color textColor) {
    final hasThumb = widget.repliedMessage?.hasMedia == true;
    return GestureDetector(
      onTap: () {
        if (widget.onTapReply != null && widget.replyToId != null) {
          widget.onTapReply!(widget.replyToId!);
        }
      },
      child: Container(
        width: double.infinity, // fills the SizedBox from step 3, not the screen
        padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.replySender ?? 'Reply',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.isMe ? Colors.white : AppTheme.primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.replyText ?? '',
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
            if (hasThumb) ...[
              const SizedBox(width: 6),
              _buildReplyMediaThumbnail(widget.repliedMessage!, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLinkPreviewCard(String urlStr, bool isDark, double cardWidth) {
    return RichLinkPreviewCard(
      url: urlStr,
      isMe: widget.isMe,
      isDark: isDark,
      width: cardWidth,
    );
  }

  double _cardWidth(BuildContext context) =>
      MediaQuery.of(context).size.width * 0.74 - 8 - 6;

  Widget _buildExpandableTextMessage(
    BuildContext context,
    bool isDark,
    Color textColor, {
    bool fill = false,
  }) {
    final text = normalizeChatMessageText(widget.message);
    final parsed = ChatLinkParser.parse(text);

    return ValueListenableBuilder<double>(
      valueListenable: FontSizeController.instance,
      builder: (context, fontScale, _) {
        final moreColor = widget.isMe
            ? Colors.white.withValues(alpha: 0.95)
            : AppTheme.primaryColor;

        Widget body(String t, double size, {bool fill = false}) => BubbleTextBody(
              spans: _buildHighlightedTextSpans(t, textColor, isDark),
              style: TextStyle(
                color: textColor,
                fontSize: size,
                height: 1.22,
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
              ),
              timestamp: _buildTimestampWidget(isDark),
              timestampWidth: _timestampWidth(),
              moreColor: moreColor,
              fontScale: fontScale,
              fillWidth: fill,
            );

        if (!parsed.hasLinks) return body(text, 17.0 * fontScale, fill: fill);

        final cardWidth = _cardWidth(context);
        final previewCards = parsed.normalizedUrls.take(2).map((url) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: RichLinkPreviewCard(
              url: url,
              isMe: widget.isMe,
              isDark: isDark,
              width: cardWidth,
            ),
          );
        }).toList();

        if (parsed.isOnlyLinks) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...previewCards,
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, right: 2),
                  child: _buildTimestampWidget(isDark),
                ),
              ),
            ],
          );
        }

        return SizedBox(
          width: cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...previewCards,
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                child: body(parsed.remainingText, 16.0 * fontScale, fill: true),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttachment(bool isDark, String? mediaUrl) {
    if (mediaUrl == null || mediaUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasLocal = _hasValidLocalFile;

    final cleanMsg = widget.message.trim();
    final hasText = _hasCaptionText(cleanMsg);

    // ─── 1. IMAGE ATTACHMENT ────────────────────────────────────────────────
    if (_isImage) {
      final showFullImage = hasLocal &&
          (_isMediaRevealed ||
              widget.isMe ||
              (widget.status ?? '').toLowerCase() == 'sending' ||
              (widget.id != null && widget.id!.startsWith('local_')));
      final localPath = _effectiveLocalPath;
      final mediaSize = _getAdaptiveMediaSize(context, _imageAspectRatio);

      final Widget imageContent = Container(
        width: mediaSize.width,
        height: mediaSize.height,
        color: isDark ? const Color(0xFF1F2A30) : const Color(0xFFCFD8DC),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showFullImage && localPath != null)
              RepaintBoundary(
                child: Image.file(
                  File(localPath),
                  fit: BoxFit.cover,
                  width: mediaSize.width,
                  height: mediaSize.height,
                  alignment: Alignment.topCenter,
                  cacheWidth:
                  (mediaSize.width * 2.0).round().clamp(400, 600),
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
                      width: mediaSize.width,
                      height: mediaSize.height,
                      color: isDark ? const Color(0xFF1F2A30) : const Color(0xFFCFD8DC),
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
              RepaintBoundary(
                child: Image.file(
                  File(_downloadedPath!),
                  fit: BoxFit.cover,
                  width: mediaSize.width,
                  height: mediaSize.height,
                  alignment: Alignment.topCenter,
                  cacheWidth: 600,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
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
                          _localOk = false;
                        });
                      }
                    });
                    return Container(
                      width: mediaSize.width,
                      height: mediaSize.height,
                      color: isDark ? const Color(0xFF1F2A30) : const Color(0xFFCFD8DC),
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
            else
              Container(
                width: mediaSize.width,
                height: mediaSize.height,
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

            if (widget.isForwarded)
              Positioned(top: 8, left: _fwdLeft, child: _fwdPill()),

            // Blur Overlay with Download / Download again button
            if (!showFullImage)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.38),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isDownloading)
                        _buildDownloadProgressOverlay()
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
              ),

            // Bottom Gradient Overlay for readability
            if (showFullImage)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                ),
              ),

            // Timestamp Overlay (when no text caption)
            if (!hasText && showFullImage)
              Positioned(
                bottom: 6,
                right: (widget.isMe && widget.showTail) ? 14 : 8,
                child: _buildTimestampWidget(
                  isDark,
                  overrideTextColor: Colors.white,
                ),
              ),

            // Active Upload Progress Overlay
            if (widget.id != null &&
                ((widget.status ?? '').toLowerCase() == 'sending' ||
                    widget.id!.startsWith('local_')))
              _buildUploadProgressOverlay(widget.id!),
          ],
        ),
      );

      final Widget styledImage = !hasText
          ? ClipPath(
        clipper: IMessageBubbleClipper(isOutgoing: widget.isMe, showTail: widget.showTail),
        child: imageContent,
      )
          : ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(13),
          topRight: Radius.circular(13),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
        child: imageContent,
      );

      return GestureDetector(
        onTap: showFullImage ? _showImageViewer : _revealImage,
        child: styledImage,
      );
    }

    // ─── 2. VIDEO ATTACHMENTS ─────────────────
    if (_isVideo) {
      final showFullVideo = hasLocal &&
          (_isMediaRevealed ||
              widget.isMe ||
              (widget.status ?? '').toLowerCase() == 'sending' ||
              (widget.id != null && widget.id!.startsWith('local_')));
      final videoSource = _effectiveLocalPath ?? _downloadedPath ?? widget.mediaUrl ?? '';
      final mediaSize = _getAdaptiveMediaSize(context, _videoAspectRatio);

      Widget videoContent;
      if (videoSource.isNotEmpty && showFullVideo) {
        videoContent = VideoThumbnailCard(
          mediaUrl: videoSource,
          width: mediaSize.width,
          height: mediaSize.height,
          onInfoResolved: (aspectRatio, duration) {
            if (_videoAspectRatio != aspectRatio || _videoDuration != duration) {
              if (mounted) {
                setState(() {
                  _videoAspectRatio = aspectRatio;
                  _videoDuration = duration;
                });
              }
            }
          },
          bottomLeading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.videocam_fill,
                color: Colors.white,
                size: 13,
              ),
              if (_videoDuration != null && _videoDuration! > Duration.zero) ...[
                const SizedBox(width: 4),
                Text(
                  _formatMediaDuration(_videoDuration!),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          bottomTrailing: !hasText
              ? _buildTimestampWidget(
            isDark,
            overrideTextColor: Colors.white,
          )
              : null,
        );
      } else {
        videoContent = Container(
          width: mediaSize.width,
          height: mediaSize.height,
          color: const Color(0xFF1C1C1E),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Center(
                child: Icon(
                  CupertinoIcons.videocam_fill,
                  size: 44,
                  color: Colors.white38,
                ),
              ),
              Container(color: Colors.black.withValues(alpha: 0.45)),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isDownloading)
                    _buildDownloadProgressOverlay()
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
              if (!hasText)
                Positioned(
                  bottom: 6,
                  right: (widget.isMe && widget.showTail) ? 14 : 8,
                  child: _buildTimestampWidget(
                    isDark,
                    overrideTextColor: Colors.white,
                  ),
                ),
            ],
          ),
        );
      }

      final isUploadingVideo = widget.id != null &&
          ((widget.status ?? '').toLowerCase() == 'sending' ||
              widget.id!.startsWith('local_'));

      final Widget baseVideo = isUploadingVideo
          ? Stack(
        alignment: Alignment.center,
        children: [
          videoContent,
          _buildUploadProgressOverlay(widget.id!),
        ],
      )
          : videoContent;

      final Widget wrappedVideoContent = widget.isForwarded
          ? Stack(
              children: [
                baseVideo,
                Positioned(top: 8, left: _fwdLeft, child: _fwdPill()),
              ],
            )
          : baseVideo;

      final Widget styledVideo = !hasText
          ? ClipPath(
        clipper: IMessageBubbleClipper(isOutgoing: widget.isMe, showTail: widget.showTail),
        child: wrappedVideoContent,
      )
          : ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(13),
          topRight: Radius.circular(13),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
        child: wrappedVideoContent,
      );

      return GestureDetector(
        onTap: hasLocal
            ? _openAttachment
            : (_isDownloading ? null : _revealImage),
        child: styledVideo,
      );
    }

    if (_isAudio) {
      final iconColor = widget.isMe ? Colors.white : AppTheme.primaryColor;
      final trackColor = widget.isMe
          ? Colors.white
          : (isDark ? Colors.white70 : AppTheme.primaryColor);
      final subtitleColor = widget.isMe
          ? Colors.white.withValues(alpha: 0.8)
          : AppTheme.secondaryText(isDark);

      _loadAudioDurationIfNeeded();

      return ValueListenableBuilder<ChatAudioState>(
        valueListenable: ChatAudioPlayback.instance.state,
        builder: (context, s, _) {
          final isActive = s.key == _audioKey;
          final isPlaying = isActive && s.isPlaying;
          final cachedDur = AudioDurationCache.get(_audioKey);
          final totalDuration = (isActive && s.duration > Duration.zero)
              ? s.duration
              : (_audioDuration ?? cachedDur ?? Duration.zero);

          final position = isActive ? s.position : Duration.zero;
          final maxDur =
              totalDuration.inMilliseconds > 0 ? totalDuration.inMilliseconds.toDouble() : 1.0;
          final curPos = position.inMilliseconds.toDouble().clamp(0.0, maxDur);
          final shownTime = (isActive && (isPlaying || position > Duration.zero))
              ? position
              : totalDuration;

          return Container(
            width: MediaQuery.of(context).size.width * 0.72,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: Colors.transparent,
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IosAvatar(
                      name: _audioSenderName,
                      imagePath: _audioSenderAvatar,
                      size: 40,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.mic_fill,
                          size: 11,
                          color: widget.isMe
                              ? AppTheme.primaryColor
                              : const Color(0xFF34C759),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isDownloading ? null : _toggleAudioPlayback,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: _isDownloading
                        ? Padding(
                            padding: const EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: iconColor,
                            ),
                          )
                        : Icon(
                            isPlaying
                                ? CupertinoIcons.pause_fill
                                : CupertinoIcons.play_fill,
                            color: iconColor,
                            size: 20,
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 10),
                          activeTrackColor: trackColor,
                          inactiveTrackColor: trackColor.withValues(alpha: 0.3),
                          thumbColor: trackColor,
                        ),
                        child: Slider(
                          min: 0.0,
                          max: maxDur,
                          value: curPos,
                          onChanged: (hasLocal && isActive)
                              ? (v) => ChatAudioPlayback.instance.seek(
                                    _audioKey,
                                    Duration(milliseconds: v.toInt()),
                                  )
                              : null,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              hasLocal
                                  ? (shownTime > Duration.zero
                                      ? _formatAudioDuration(shownTime)
                                      : '0:00')
                                  : (_downloadFailed ? 'Failed' : 'Downloading...'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: subtitleColor,
                              ),
                            ),
                            _buildTimestampWidget(isDark),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    // ─── 3. OTHER ATTACHMENTS (Document/File) ─────────────────
    final uploadingDoc = widget.id != null &&
        ((widget.status ?? '').toLowerCase() == 'sending' ||
            widget.id!.startsWith('local_'));
    final cardWidth = _cardWidth(context);

    Widget card({double? progress, bool uploading = false}) => DocumentCard(
      fileName: _attachmentName,
      width: cardWidth,
      isMe: widget.isMe,
      isDark: isDark,
      sizeText: _fileBytes == null ? null : _formatBytes(_fileBytes!),
      pages: _docPreview?.pages,
      thumbPath: _docPreview?.thumbPath,
      transferring: uploading || _isDownloading,
      progress: uploading ? progress : _downloadProgress,
      needsDownload: !hasLocal && !_isDownloading && !uploading,
      onCancel: uploading
          ? () =>
          AttachmentUploadService.instance.cancelUpload(widget.id!)
          : null,
      onTap: (_isDownloading || uploading)
          ? null
          : (hasLocal ? _openAttachment : _downloadAttachment),
    );

    if (uploadingDoc) {
      return ValueListenableBuilder<UploadProgress>(
        valueListenable:
        AttachmentUploadService.instance.getProgressNotifier(widget.id!),
        builder: (_, p, __) {
          if (p.isFailed) {
            final svc = AttachmentUploadService.instance;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                card(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 16, color: Color(0xFFFF453A)),
                      const SizedBox(width: 4),
                      const Text('Not sent',
                          style: TextStyle(
                              color: Color(0xFFFF453A),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => svc.retryAction(widget.id!)?.call(),
                        child: const Text('Retry',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 14),
                      GestureDetector(
                        onTap: () => svc.discardAction(widget.id!)?.call(),
                        child: const Text('Delete',
                            style: TextStyle(
                                color: Color(0xFFFF453A),
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return card(progress: p.progress, uploading: !p.isCompleted);
        },
      );
    }
    return card();
  }

  Widget _buildDownloadProgressOverlay() {
    final double p = _downloadProgress;
    final int percent = (p * 100).toInt();
    final String percentText = '$percent%';
    final String sizeText = _totalDownloadBytes > 0
        ? '${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalDownloadBytes)}'
        : _formatBytes(_downloadedBytes);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(
            value: p > 0 ? p : null,
            strokeWidth: 3.5,
            color: Colors.white,
            backgroundColor: Colors.white24,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$percentText • $sizeText',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadProgressOverlay(String messageId) {
    return ValueListenableBuilder<UploadProgress>(
      valueListenable:
      AttachmentUploadService.instance.getProgressNotifier(messageId),
      builder: (context, progress, child) {
        if (progress.isCompleted) return const SizedBox.shrink();
        if (progress.isFailed) return _buildFailedOverlay(messageId);

        final double p = progress.progress;
        final String percentText = '${(p * 100).toInt()}%';
        final String sizeText = progress.totalBytes > 0
            ? '${_formatBytes(progress.bytesSent)} / ${_formatBytes(progress.totalBytes)}'
            : _formatBytes(progress.bytesSent);

        return Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.65),
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        value: p > 0 ? p : null,
                        strokeWidth: 3.5,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 20),
                      onPressed: () => AttachmentUploadService.instance
                          .cancelUpload(messageId),
                      tooltip: 'Cancel Upload',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$percentText • $sizeText',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFailedOverlay(String messageId) {
    final svc = AttachmentUploadService.instance;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.68),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFFF453A), size: 28),
            const SizedBox(height: 4),
            const Text('Not sent',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                _failedActionButton(
                  icon: Icons.refresh_rounded,
                  label: 'Retry',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    svc.retryAction(messageId)?.call();
                  },
                ),
                _failedActionButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  destructive: true,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    svc.discardAction(messageId)?.call();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _failedActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: destructive
              ? const Color(0x33FF453A)
              : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: destructive ? const Color(0xFFFF453A) : Colors.white),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color:
                    destructive ? const Color(0xFFFF453A) : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
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
        final msg = widget.sourceMessage ??
            ChatMessage(
              id: widget.timestamp.millisecondsSinceEpoch.toString(),
              senderId: widget.isMe ? 'user' : 'peer',
              content: widget.message,
              timestamp: widget.timestamp,
              type: widget.type ?? 'text',
              mediaUrl: widget.mediaUrl,
              fileName: widget.fileName,
              isForwarded: widget.isForwarded,
            );
        widget.onShowMessageActions!(msg, globalPos, size, reactionsOnly: false);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0x60000000)
              : const Color(0x35000000),
          shape: BoxShape.circle,
        ),
        child: Transform.scale(
          scaleX: -1,
          child: const Icon(
            CupertinoIcons.reply_thick_solid,
            size: 14,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (widget.groupedImages != null && widget.groupedImages!.isNotEmpty) {
      final cleanText = widget.message.trim();
      final hasCaption = _hasCaptionText(cleanText);
      final hasReplyQuote = widget.replyText != null;
      final textColor = widget.isMe
          ? Colors.white
          : (isDark ? Colors.white : Colors.black);

      final gridBody = Padding(
        padding: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 12.0),
        child: Column(
          crossAxisAlignment:
              widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (widget.senderName != null && widget.senderName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
                child: Text(widget.senderName!,
                    style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            GroupedPhotoGrid(
              groupedImages: widget.groupedImages!,
              chatId: widget.chatId,
              isMe: widget.isMe,
              timestamp: widget.timestamp,
              isRead: widget.isRead,
              isDelivered: widget.isDelivered,
              status: widget.status,
              isEdited: widget.isEdited,
              isSaved: widget.isSaved,
              isForwarded: widget.isForwarded,
              isSelectionMode: widget.isSelectionMode,
              isSelected: widget.isSelected,
              onToggleSelect: widget.onToggleSelect,
              onShowMessageActions: widget.onShowMessageActions,
              showTail: widget.showTail,
              onReplyToMessage: widget.onReplyToMessage,
              replyPreview:
                  hasReplyQuote ? _buildReplyPreview(isDark, textColor) : null,
              caption: hasCaption ? _buildMediaCaption(isDark, textColor) : null,
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
            child: Row(children: [
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
            ]),
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
          child: Padding(
            padding: EdgeInsets.only(
              left: widget.isMe ? 0 : (widget.showTail ? 0 : 6),
              right: widget.isMe ? (widget.showTail ? 0 : 6) : 0,
            ),
            child: CustomPaint(
              painter: IMessageBubblePainter(
                color: bubbleColor,
                isOutgoing: widget.isMe,
                showTail: widget.showTail,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.76,
                ),
                padding: EdgeInsets.fromLTRB(
                  14 + ((!widget.isMe && widget.showTail) ? 6 : 0),
                  9,
                  14 + ((widget.isMe && widget.showTail) ? 6 : 0),
                  9,
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
            widget.onShowMessageActions!(deletedMsg, globalPos, size, reactionsOnly: false);
          }
        },
        child: deletedBubbleContent,
      );
    }


    final cleanType = (widget.type ?? 'text').toLowerCase().trim();
    final cleanMsg = normalizeChatMessageText(widget.message.trim());
    final rawMediaUrl = widget.mediaUrl?.trim();

    final bool isLocation = cleanType == 'location' ||
        cleanType == 'live_location' ||
        widget.msgType == 'location' ||
        widget.msgType == 'live_location' ||
        cleanMsg.contains('"latitude":') ||
        cleanMsg.contains('"longitude":');

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
    final parsedContent = ChatLinkParser.parse(cleanMsg);
    final isDocument = hasMedia && !_isImage && !_isVideo && !_isAudio;
    final hasLinkCard = isTextType && !hasMedia && parsedContent.hasLinks;

    final bool isMediaWithCaption = (_isImage || _isVideo) &&
        mediaUrl != null &&
        mediaUrl.trim().isNotEmpty &&
        _hasCaptionText(cleanMsg);
    final double captionBubbleMaxW = isMediaWithCaption
        ? _getAdaptiveMediaSize(
      context,
      _isImage ? _imageAspectRatio : _videoAspectRatio,
    ).width +
        12.0
        : 0;

    final double tailL = (!widget.isMe && widget.showTail) ? 6.0 : 0.0;
    final double tailR = (widget.isMe && widget.showTail) ? 6.0 : 0.0;
    EdgeInsets withTail(EdgeInsets e) =>
        EdgeInsets.fromLTRB(e.left + tailL, e.top, e.right + tailR, e.bottom);

    final bool failedText = widget.isMe &&
        (widget.status ?? '').toLowerCase() == 'failed' &&
        !hasMedia; // attachments keep their own retry overlay

    final Widget bubbleBody = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 12.0),
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
                      Flexible(
                        fit: FlexFit.loose,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: failedText ? widget.onFailedTap : null,
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
                            child: Padding(
                              // margin lives OUTSIDE the painter
                              padding: EdgeInsets.only(
                                left: widget.isMe ? 0 : (widget.showTail ? 0 : 6.0),
                                right: widget.isMe ? (widget.showTail ? 0 : 6.0) : 0,
                              ),
                              child: CustomPaint(
                                painter: IMessageBubblePainter(
                                  color: ((_isImage || _isVideo) && !isMediaWithCaption)
                                      ? Colors.transparent
                                      : bubbleColor,
                                  isOutgoing: widget.isMe,
                                  showTail: widget.showTail,
                                ),
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth: isMediaWithCaption
                                        ? captionBubbleMaxW
                                        : (widget.callStatus != null ||
                                                widget.callType != null ||
                                                widget.callId != null ||
                                                cleanMsg.contains('voice call') ||
                                                cleanMsg.contains('video call'))
                                            ? (MediaQuery.of(context).size.width * 0.82)
                                                .clamp(260.0, 320.0)
                                            : MediaQuery.of(context).size.width * 0.74,
                                  ),
                                  padding: isLocation
                                      ? withTail(const EdgeInsets.all(3))
                                      : isMediaWithCaption
                                          ? withTail(const EdgeInsets.all(3))
                                          : ((_isImage || _isVideo || _isAudio) &&
                                                  mediaUrl != null &&
                                                  mediaUrl.trim().isNotEmpty)
                                              ? EdgeInsets.zero
                                              : (isDocument || hasLinkCard)
                                                  ? withTail(const EdgeInsets.all(4))
                                                  : withTail(const EdgeInsets.fromLTRB(14, 9, 14, 9)),
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
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topRight,
            child: failedText
                ? GestureDetector(
                    onTap: widget.onFailedTap,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 3, right: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded,
                              size: 14, color: Color(0xFFFF453A)),
                          SizedBox(width: 4),
                          Text(
                            'Not sent · Tap to retry',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFF453A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : (widget.isMe && widget.showDeliveryStatus)
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2, right: 6),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            _getDeliveryStatusText(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
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

String _viewerDate(DateTime t) {
  final l = t.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${(l.year % 100).toString().padLeft(2, '0')}, '
      '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour >= 12 ? 'PM' : 'AM'}';
}

class GroupedPhotoGrid extends StatelessWidget {
  final List<ChatMessage> groupedImages;
  final String? chatId;
  final bool isMe;
  final DateTime timestamp;
  final bool isRead;
  final bool isDelivered;
  final String? status;
  final bool isEdited;
  final bool isSaved;
  final bool isForwarded;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final Function(ChatMessage message, Offset pos, Size size, {bool reactionsOnly})? onShowMessageActions;
  final bool showTail;
  final ValueChanged<ChatMessage>? onReplyToMessage;
  final ValueChanged<ChatMessage>? onForwardMessage;
  final void Function(ChatMessage, String emoji)? onReactMessage;
  final Future<bool> Function(ChatMessage)? onToggleStarMessage;
  final ValueChanged<ChatMessage>? onDeleteMessage;
  final Widget? replyPreview; // quote of replied message (inside the bubble)
  final Widget? caption;      // BubbleTextBody wrapped caption (inside the bubble)

  const GroupedPhotoGrid({
    super.key,
    required this.groupedImages,
    this.chatId,
    required this.isMe,
    required this.timestamp,
    required this.isRead,
    this.isDelivered = false,
    this.status,
    required this.isEdited,
    this.isSaved = false,
    this.isForwarded = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onShowMessageActions,
    this.showTail = true,
    this.onReplyToMessage,
    this.onForwardMessage,
    this.onReactMessage,
    this.onToggleStarMessage,
    this.onDeleteMessage,
    this.replyPreview,
    this.caption,
  });

  // ---------- status / time ----------
  Widget _buildGroupStatusTick() {
    final st = (status ?? '').toLowerCase();
    final sending = st == 'sending' ||
        groupedImages.any((m) =>
            m.status.toLowerCase() == 'sending' || m.id.startsWith('local_'));
    final read = !sending &&
        (st == 'read' || st == 'seen' ||
            (isRead && groupedImages.every((m) =>
                m.isRead ||
                m.status.toLowerCase() == 'read' ||
                m.status.toLowerCase() == 'seen')));
    final delivered = !sending &&
        (read || st == 'delivered' || isDelivered ||
            groupedImages.every((m) =>
                m.isDelivered || m.isRead ||
                m.status.toLowerCase() == 'delivered'));

    if (sending) {
      return const Icon(Icons.access_time_rounded, size: 11, color: Colors.white70);
    }
    if (read) {
      return const Icon(Icons.done_all_rounded, size: 12, color: Color(0xFF53BDEB));
    }
    if (delivered) {
      return const Icon(Icons.done_all_rounded, size: 12, color: Colors.white70);
    }
    return const Icon(Icons.done_rounded, size: 12, color: Colors.white70);
  }

  String _formatTime(DateTime t) {
    final h24 = t.toLocal().hour;
    final h = h24 > 12 ? h24 - 12 : (h24 == 0 ? 12 : h24);
    final m = t.toLocal().minute.toString().padLeft(2, '0');
    return '$h:$m ${h24 >= 12 ? 'PM' : 'AM'}';
  }

  Widget _timePill() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSaved)
              const Padding(
                padding: EdgeInsets.only(right: 3),
                child: Icon(Icons.bookmark_rounded, size: 10, color: Colors.white),
              ),
            if (isEdited)
              const Text('edited ',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 9, fontStyle: FontStyle.italic)),
            if (groupedImages.any((m) => (m.fileName ?? '').startsWith('hd_')))
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 0.9),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'HD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            Text(_formatTime(timestamp),
                style: const TextStyle(
                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
            if (isMe) ...[
              const SizedBox(width: 3),
              _buildGroupStatusTick(),
            ],
          ],
        ),
      );

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final w = math.min(MediaQuery.sizeOf(context).width * 0.72, 290.0);
    final hasInnerText = caption != null || replyPreview != null;

    final tailL = (!isMe && showTail) ? 6.0 : 0.0;
    final tailR = (isMe && showTail) ? 6.0 : 0.0;
    final margin = EdgeInsets.only(
      left: isMe ? 0 : (showTail ? 0 : 6.0),
      right: isMe ? (showTail ? 0 : 6.0) : 0,
    );

    Widget gridWithPill(double gw) => Stack(
          children: [
            _buildGrid(context, gw),
            if (isForwarded)
              Positioned(
                top: 8,
                left: (!isMe && showTail && !hasInnerText) ? 16 : 10,
                child: const ForwardedTag(color: Colors.white, pill: true),
              ),
            if (caption == null)
              Positioned(
                right: (isMe && showTail && !hasInnerText) ? 14 : 8,
                bottom: 6,
                child: _timePill(),
              ),
          ],
        );

    // Borderless album
    if (!hasInnerText) {
      return Padding(
        padding: margin,
        child: SizedBox(
          width: w,
          child: ClipPath(
            clipper: IMessageBubbleClipper(isOutgoing: isMe, showTail: showTail),
            child: gridWithPill(w),
          ),
        ),
      );
    }

    // Album with caption / reply: content width is identical on both sides
    final iw = w - 12; // 3 + 3 padding + 6 tail strip (or 6 margin when no tail)
    final bubbleColor = isMe
        ? AppPreferences.getChatBubbleColor(chatId: chatId)
        : AppTheme.receivedBubble(isDark);

    return Padding(
      padding: margin,
      child: CustomPaint(
        painter: IMessageBubblePainter(
          color: bubbleColor,
          isOutgoing: isMe,
          showTail: showTail,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(3 + tailL, 3, 3 + tailR, 3),
          child: SizedBox(
            width: iw,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyPreview != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: replyPreview),
                ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(replyPreview != null ? 8 : 13),
                    topRight: Radius.circular(replyPreview != null ? 8 : 13),
                    bottomLeft: const Radius.circular(6),
                    bottomRight: const Radius.circular(6),
                  ),
                  child: gridWithPill(iw),
                ),
                caption ?? const SizedBox(height: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- tiles ----------
  void _openTileMedia(BuildContext context, List<ChatMessage> photos, int index) {
    if (isSelectionMode) {
      onToggleSelect?.call();
      return;
    }
    final ctl = ChatMediaScope.maybeOf(context);
    if (ctl != null) {
      ChatMediaViewer.openAlbum(context, ctl, photos);
      return;
    }
    final m = photos[index];
    final type = m.type.toLowerCase().trim();
    final url = (m.mediaUrl ?? '').toLowerCase().trim();
    final name = (m.fileName ?? '').toLowerCase().trim();
    final isVideo = type.contains('video') ||
        ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v']
            .any((e) => url.contains('.$e') || name.endsWith('.$e')) ||
        m.previewText.contains('Video');

    if (isVideo) {
      AppVideoPlayerModal.open(
        context,
        mediaUrl: m.mediaUrl ?? '',
        title: m.senderId == 'user' ? 'You' : 'Contact',
        subtitle: _viewerDate(m.timestamp),
        actions: VideoViewerActions(
          isStarred: m.isSaved,
          onReply: onReplyToMessage == null ? null : () => onReplyToMessage!(m),
          onForward: onForwardMessage == null ? null : () => onForwardMessage!(m),
          onReact: onReactMessage == null ? null : (e) => onReactMessage!(m, e),
          onDelete: onDeleteMessage == null ? null : () => onDeleteMessage!(m),
        ),
      );
    } else {
      PhotoGalleryViewer.open(
        context,
        photos: photos,
        initialIndex: index,
        onReply: onReplyToMessage,
      );
    }
  }

  Widget _tile(BuildContext context, int i, double h) => _GridTileItem(
        photoMessage: groupedImages[i],
        chatId: chatId,
        height: h,
        onTap: () => _openTileMedia(context, groupedImages, i),
        isSelectionMode: isSelectionMode,
        onToggleSelect: onToggleSelect,
        onShowMessageActions: onShowMessageActions,
      );

  Widget _buildGrid(BuildContext context, double gw) {
    final k = gw / 270.0;
    final n = groupedImages.length;
    const gap = 2.0;

    if (n == 2) {
      return Row(children: [
        Expanded(child: _tile(context, 0, 150 * k)),
        const SizedBox(width: gap),
        Expanded(child: _tile(context, 1, 150 * k)),
      ]);
    }
    if (n == 3) {
      return Row(children: [
        Expanded(flex: 5, child: _tile(context, 0, 180 * k)),
        const SizedBox(width: gap),
        Expanded(
          flex: 5,
          child: Column(children: [
            _tile(context, 1, 89 * k),
            const SizedBox(height: gap),
            _tile(context, 2, 89 * k),
          ]),
        ),
      ]);
    }

    final extra = n - 4;
    final h = 110 * k;
    return Column(children: [
      Row(children: [
        Expanded(child: _tile(context, 0, h)),
        const SizedBox(width: gap),
        Expanded(child: _tile(context, 1, h)),
      ]),
      const SizedBox(height: gap),
      Row(children: [
        Expanded(child: _tile(context, 2, h)),
        const SizedBox(width: gap),
        Expanded(
          child: Stack(fit: StackFit.passthrough, children: [
            _tile(context, 3, h),
            if (extra > 0)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => _openTileMedia(context, groupedImages, 3),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.58),
                    alignment: Alignment.center,
                    child: Text('+$extra',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    ]);
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
  final Function(ChatMessage message, Offset pos, Size size, {bool reactionsOnly})? onShowMessageActions;

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

class _GridTileItemState extends State<_GridTileItem>
    with AutomaticKeepAliveClientMixin<_GridTileItem> {
  String? _resolvedPath;
  bool _isLoading = true;
  bool _isDownloading = false;
  bool _downloadFailed = false;
  bool _decryptFailed = false;
  int _loadGeneration = 0;

  bool get _isVideoMsg {
    final m = widget.photoMessage;
    return ChatMediaDownloader.kindOf(
                type: m.type, name: m.fileName, url: m.mediaUrl) ==
            MediaKind.video ||
        m.previewText.contains('Video');
  }

  @override
  bool get wantKeepAlive => false;

  @override
  void initState() {
    super.initState();
    final rawUrl = widget.photoMessage.mediaUrl;
    if (rawUrl != null && rawUrl.isNotEmpty) {
      final cachedSync =
      AttachmentCacheService.instance.resolveLocalPathSync(rawUrl);
      if (cachedSync != null && File(cachedSync).existsSync()) {
        _resolvedPath = cachedSync;
        _isLoading = false;
      } else if (!rawUrl.startsWith('http://') &&
          !rawUrl.startsWith('https://') &&
          File(rawUrl).existsSync()) {
        _resolvedPath = rawUrl;
        _isLoading = false;
      }
    }
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

    // 1. Check synchronous memory cache first
    final cachedSync = AttachmentCacheService.instance.resolveLocalPathSync(rawUrl);
    if (cachedSync != null && File(cachedSync).existsSync()) {
      if (_resolvedPath != cachedSync || _isLoading) {
        if (mounted && generation == _loadGeneration) {
          setState(() {
            _resolvedPath = cachedSync;
            _isLoading = false;
            _downloadFailed = false;
            _isDownloading = false;
          });
        }
      }
      return;
    }

    // 2. Check if current _resolvedPath or rawUrl is a valid local file
    if (_resolvedPath != null && File(_resolvedPath!).existsSync()) {
      AttachmentCacheService.instance.updateCache(rawUrl, _resolvedPath!);
      if (_isLoading) {
        if (mounted && generation == _loadGeneration) {
          setState(() {
            _isLoading = false;
            _downloadFailed = false;
            _isDownloading = false;
          });
        }
      }
      return;
    }

    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      if (File(rawUrl).existsSync()) {
        AttachmentCacheService.instance.updateCache(rawUrl, rawUrl);
        if (mounted && generation == _loadGeneration) {
          setState(() {
            _resolvedPath = rawUrl;
            _isLoading = false;
            _downloadFailed = false;
            _isDownloading = false;
          });
        }
        return;
      }
    }

    // 3. Check async cache lookup
    final cached = await AttachmentCacheService.instance.resolveLocalPath(
      rawUrl,
    );
    if (cached != null && File(cached).existsSync()) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _resolvedPath = cached;
          _isLoading = false;
          _downloadFailed = false;
          _isDownloading = false;
        });
      }
      return;
    }

    // 4. Only if not found locally anywhere, initiate download
    final autoDownload = await AppPreferences.shouldAutoDownload(
      mediaType: _isVideoMsg ? 'video' : 'image',
    );
    if (autoDownload) {
      await _downloadAndCacheTilePhoto(generation);
    } else {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _resolvedPath = null;
          _isLoading = false;
          _downloadFailed = false;
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _downloadAndCacheTilePhoto([int? generation]) async {
    final gen = generation ?? _loadGeneration;
    final m = widget.photoMessage;
    final rawUrl = m.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) return;

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isDownloading = true;
        _downloadFailed = false;
        _decryptFailed = false;
      });
    }
    try {
      final name = (m.fileName?.isNotEmpty == true)
          ? m.fileName!
          : rawUrl.split('/').last;
      final path = await ChatMediaDownloader.instance.fetch(
        mediaUrl: rawUrl,
        chatId: widget.chatId ?? '',
        fileName: name,
        kind: _isVideoMsg ? MediaKind.video : MediaKind.image,
      );
      if (mounted && gen == _loadGeneration) {
        setState(() => _resolvedPath = path);
      }
    } on MediaDecryptException {
      if (mounted && gen == _loadGeneration) {
        setState(() => _decryptFailed = true);
      }
    } catch (e) {
      debugPrint('[GRID TILE DOWNLOAD ERROR] $e');
      if (mounted && gen == _loadGeneration) {
        setState(() => _downloadFailed = true);
      }
    } finally {
      if (mounted && gen == _loadGeneration) {
        setState(() => _isDownloading = false);
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
    super.build(context);
    return _withUploadOverlay(_buildTile(context));
  }

  Widget _withUploadOverlay(Widget child) {
    final m = widget.photoMessage;
    final uploading = m.id.startsWith('local_') || m.status.toLowerCase() == 'sending';
    if (!uploading) return child;
    return Stack(fit: StackFit.passthrough, children: [
      child,
      Positioned.fill(
        child: ValueListenableBuilder<UploadProgress>(
          valueListenable: AttachmentUploadService.instance.getProgressNotifier(m.id),
          builder: (_, p, __) {
            if (p.isCompleted) return const SizedBox.shrink();
            if (p.isFailed) {
              final svc = AttachmentUploadService.instance;
              return Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Retry',
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 26),
                      onPressed: () => svc.retryAction(m.id)?.call(),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Color(0xFFFF453A), size: 24),
                      onPressed: () => svc.discardAction(m.id)?.call(),
                    ),
                  ],
                ),
              );
            }
            return Container(
              color: Colors.black45,
              alignment: Alignment.center,
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: p.progress > 0 ? p.progress : null,
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildTile(BuildContext context) {
    final tileWidth = widget.width ?? double.infinity;
    final tileWidthValue =
    tileWidth.isFinite && tileWidth > 0 ? tileWidth : 200.0;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final computedCacheWidth = (tileWidthValue * dpr).round();

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
                        _decryptFailed
                            ? 'Unavailable'
                            : (_downloadFailed ? 'Retry' : 'Download'),
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

    final isVideo = widget.photoMessage.type.toLowerCase().contains('video') ||
        ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'].any(
              (ext) =>
          (widget.photoMessage.mediaUrl ?? '').toLowerCase().contains('.$ext') ||
              (widget.photoMessage.fileName ?? '').toLowerCase().endsWith('.$ext'),
        ) ||
        widget.photoMessage.previewText.contains('Video');

    if (isVideo) {
      final videoSource = path;
      return GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: () {
          if (widget.onShowMessageActions != null) {
            HapticFeedback.lightImpact();
            final box = context.findRenderObject() as RenderBox?;
            final globalPos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
            final size = box?.size ?? const Size(200, 200);
            widget.onShowMessageActions!(widget.photoMessage, globalPos, size, reactionsOnly: true);
          }
        },
        onLongPress: () {
          if (widget.isSelectionMode) {
            widget.onToggleSelect?.call();
          } else if (widget.onShowMessageActions != null) {
            final box = context.findRenderObject() as RenderBox?;
            final globalPos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
            final size = box?.size ?? const Size(200, 200);
            widget.onShowMessageActions!(widget.photoMessage, globalPos, size, reactionsOnly: false);
          } else {
            _sharePhoto();
          }
        },
        child: SizedBox(
          width: tileWidth,
          height: widget.height,
          child: VideoThumbnailCard(
            mediaUrl: videoSource,
            width: tileWidth,
            height: widget.height,
            showDefaultOverlay: true,
          ),
        ),
      );
    }

    Widget imageWidget;
    if (isLocal) {
      imageWidget = RepaintBoundary(
        child: Image.file(
          File(path),
          width: tileWidth,
          height: widget.height,
          cacheWidth: computedCacheWidth,
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
          cacheWidth: computedCacheWidth,
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
      onDoubleTap: () {
        if (widget.onShowMessageActions != null) {
          HapticFeedback.lightImpact();
          final box = context.findRenderObject() as RenderBox?;
          final globalPos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
          final size = box?.size ?? const Size(200, 200);
          widget.onShowMessageActions!(widget.photoMessage, globalPos, size, reactionsOnly: true);
        }
      },
      onLongPress: () {
        if (widget.isSelectionMode) {
          widget.onToggleSelect?.call();
        } else if (widget.onShowMessageActions != null) {
          final box = context.findRenderObject() as RenderBox?;
          final globalPos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
          final size = box?.size ?? const Size(200, 200);
          widget.onShowMessageActions!(widget.photoMessage, globalPos, size, reactionsOnly: false);
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
  const IMessageBubblePainter({
    required this.color,
    required this.isOutgoing,
    this.showTail = true,
  });

  final Color color;
  final bool isOutgoing;
  final bool showTail;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final double w = size.width;
    final double h = size.height;
    const double r = 16.0;

    if (!showTail) {
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(r),
      );
      canvas.drawRRect(rrect, paint);
      return;
    }

    final path = Path();
    if (isOutgoing) {
      // Outgoing (Me / Right Tail)
      final double mainW = w - 6.0;
      path.moveTo(r, 0);
      path.lineTo(mainW - r, 0);
      path.quadraticBezierTo(mainW, 0, mainW, r);
      path.lineTo(mainW, h - 12);
      path.quadraticBezierTo(mainW, h - 2, w, h);
      path.quadraticBezierTo(mainW - 2, h, mainW - 14, h);
      path.lineTo(r, h);
      path.quadraticBezierTo(0, h, 0, h - r);
      path.lineTo(0, r);
      path.quadraticBezierTo(0, 0, r, 0);
    } else {
      // Incoming (Peer / Left Tail)
      const double startX = 6.0;
      path.moveTo(startX + r, 0);
      path.lineTo(w - r, 0);
      path.quadraticBezierTo(w, 0, w, r);
      path.lineTo(w, h - r);
      path.quadraticBezierTo(w, h, w - r, h);
      path.lineTo(startX + 14, h);
      path.quadraticBezierTo(startX - 2, h, 0, h);
      path.quadraticBezierTo(startX, h - 2, startX, h - 12);
      path.lineTo(startX, r);
      path.quadraticBezierTo(startX, 0, startX + r, 0);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant IMessageBubblePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isOutgoing != isOutgoing ||
        oldDelegate.showTail != showTail;
  }
}

class IMessageBottomCaptionPainter extends CustomPainter {
  const IMessageBottomCaptionPainter({
    required this.color,
    required this.isOutgoing,
    this.showTail = true,
  });

  final Color color;
  final bool isOutgoing;
  final bool showTail;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final double w = size.width;
    final double h = size.height;
    const double r = 16.0;

    if (!showTail) {
      final rrect = RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, w, h),
        bottomLeft: const Radius.circular(r),
        bottomRight: const Radius.circular(r),
      );
      canvas.drawRRect(rrect, paint);
      return;
    }

    final path = Path();
    if (isOutgoing) {
      // Outgoing (Me / Right Tail on bottom, FLAT on top)
      final double mainW = w - 6.0;
      path.moveTo(0, 0);
      path.lineTo(mainW, 0);
      path.lineTo(mainW, h - 12);
      path.quadraticBezierTo(mainW, h - 2, w, h);
      path.quadraticBezierTo(mainW - 2, h, mainW - 14, h);
      path.lineTo(r, h);
      path.quadraticBezierTo(0, h, 0, h - r);
      path.lineTo(0, 0);
    } else {
      // Incoming (Peer / Left Tail on bottom, FLAT on top)
      const double startX = 6.0;
      path.moveTo(startX, 0);
      path.lineTo(w, 0);
      path.lineTo(w, h - r);
      path.quadraticBezierTo(w, h, w - r, h);
      path.lineTo(startX + 14, h);
      path.quadraticBezierTo(startX - 2, h, 0, h);
      path.quadraticBezierTo(startX, h - 2, startX, h - 12);
      path.lineTo(startX, 0);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant IMessageBottomCaptionPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isOutgoing != isOutgoing ||
        oldDelegate.showTail != showTail;
  }
}

class IMessageBubbleClipper extends CustomClipper<Path> {
  final bool isOutgoing;
  final double radius;
  final bool showTail;

  const IMessageBubbleClipper({
    required this.isOutgoing,
    this.radius = 16.0,
    this.showTail = true,
  });

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height, r = radius;
    if (!showTail) {
      return Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, w, h), Radius.circular(r)));
    }
    final path = Path();
    if (isOutgoing) {
      final mainW = w - 6.0;
      path.moveTo(r, 0);
      path.lineTo(mainW - r, 0);
      path.quadraticBezierTo(mainW, 0, mainW, r);
      path.lineTo(mainW, h - 12);
      path.quadraticBezierTo(mainW, h - 2, w, h);
      path.quadraticBezierTo(mainW - 2, h, mainW - 14, h);
      path.lineTo(r, h);
      path.quadraticBezierTo(0, h, 0, h - r);
      path.lineTo(0, r);
      path.quadraticBezierTo(0, 0, r, 0);
    } else {
      const startX = 6.0;
      path.moveTo(startX + r, 0);
      path.lineTo(w - r, 0);
      path.quadraticBezierTo(w, 0, w, r);
      path.lineTo(w, h - r);
      path.quadraticBezierTo(w, h, w - r, h);
      path.lineTo(startX + 14, h);
      path.quadraticBezierTo(startX - 2, h, 0, h);
      path.quadraticBezierTo(startX, h - 2, startX, h - 12);
      path.lineTo(startX, r);
      path.quadraticBezierTo(startX, 0, startX + r, 0);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant IMessageBubbleClipper o) =>
      o.isOutgoing != isOutgoing || o.radius != radius || o.showTail != showTail;
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
  State<BouncyMessageEntryAnimation> createState() => _BouncyEntryState();
}

class _BouncyEntryState extends State<BouncyMessageEntryAnimation>
    with SingleTickerProviderStateMixin {
  late final bool _animate = widget.animate;

  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: _animate ? 0.0 : 1.0,
  );

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 21,
  );

  @override
  void initState() {
    super.initState();
    if (_animate) {
      _c.animateWith(SpringSimulation(_spring, 0, 1, 0));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    final me = widget.isMe;

    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final p = t.clamp(0.0, 1.0);
        return Align(
          alignment: Alignment.bottomCenter,
          heightFactor: p,
          child: Opacity(
            opacity: Curves.easeOut.transform(p),
            child: Transform.translate(
              offset: Offset((1 - t) * (me ? 36 : -36), (1 - t) * 18),
              child: Transform.scale(
                scale: 0.55 + 0.45 * t,
                alignment: me ? Alignment.bottomRight : Alignment.bottomLeft,
                child: child,
              ),
            ),
          ),
        );
      },
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

class _StandaloneGifWidgetState extends State<StandaloneGifWidget>
    with AutomaticKeepAliveClientMixin<StandaloneGifWidget> {
  String? _resolvedPath;
  bool _isDownloading = false;

  @override
  bool get wantKeepAlive => false;

  @override
  void initState() {
    super.initState();
    final targetUrl =
    (widget.mediaUrl != null && widget.mediaUrl!.trim().isNotEmpty)
        ? widget.mediaUrl!.trim()
        : widget.message.trim();
    if (targetUrl.isNotEmpty) {
      final syncCached =
      AttachmentCacheService.instance.resolveLocalPathSync(targetUrl);
      if (syncCached != null &&
          File(syncCached).existsSync() &&
          File(syncCached).lengthSync() > 16) {
        _resolvedPath = syncCached;
      } else if (!targetUrl.startsWith('http://') &&
          !targetUrl.startsWith('https://')) {
        final f = File(targetUrl);
        if (f.existsSync() && f.lengthSync() > 16) {
          _resolvedPath = f.path;
        }
      }
    }
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

    await _DownloadGate.acquire();
    final client = http.Client();
    File? tmp;
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

      final request = http.Request('GET', Uri.parse(downloadUrl));
      if (headers.isNotEmpty) request.headers.addAll(headers);

      final streamedRes = await client.send(request).timeout(const Duration(seconds: 15));
      if (streamedRes.statusCode >= 200 && streamedRes.statusCode < 300) {
        final tmpDir = await getTemporaryDirectory();
        tmp = File(
            '${tmpDir.path}${Platform.pathSeparator}gif_${DateTime.now().microsecondsSinceEpoch}.tmp');
        final sink = tmp.openWrite();
        await for (final chunk in streamedRes.stream) {
          sink.add(chunk);
        }
        await sink.close();

        final docsDir = await getApplicationDocumentsDirectory();
        final attachmentDir =
            Directory('${docsDir.path}${Platform.pathSeparator}chat_attachments');
        await attachmentDir.create(recursive: true);

        final safeKey = url.split('/').last.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final targetPath =
            '${attachmentDir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_$safeKey';

        final ok = await compute(_decryptFileOnDisk, [
          tmp.path,
          targetPath,
          widget.secretKey,
          '0',
        ]);

        if (ok) {
          AttachmentCacheService.instance.updateCache(url, targetPath);
          if (mounted) {
            setState(() {
              _resolvedPath = targetPath;
              _isDownloading = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      try {
        await tmp?.delete();
      } catch (_) {}
      debugPrint('[STANDALONE GIF DOWNLOAD ERROR] $e');
    } finally {
      client.close();
      _DownloadGate.release();
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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

class BubbleTextBody extends StatefulWidget {
  final List<InlineSpan> spans;
  final TextStyle style;
  final Widget timestamp;
  final double timestampWidth;
  final Color moreColor;
  final double fontScale;
  final int collapsedLines;
  final bool fillWidth;

  const BubbleTextBody({
    super.key,
    required this.spans,
    required this.style,
    required this.timestamp,
    required this.timestampWidth,
    required this.moreColor,
    this.fontScale = 1.0,
    this.collapsedLines = 6,
    this.fillWidth = false,
  });

  @override
  State<BubbleTextBody> createState() => _BubbleTextBodyState();
}

class _BubbleTextBodyState extends State<BubbleTextBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite
            ? c.maxWidth
            : MediaQuery.sizeOf(context).width * 0.7;
        final span = TextSpan(style: widget.style, children: widget.spans);

        final probe = TextPainter(
          text: span,
          textDirection: TextDirection.ltr,
          maxLines: widget.collapsedLines,
        )..layout(maxWidth: maxW);

        // ── Long text: "More / Less" ──
        if (probe.didExceedMaxLines) {
          final linkStyle = TextStyle(
            color: widget.moreColor,
            fontSize: 14.0 * widget.fontScale,
            fontWeight: FontWeight.bold,
          );
          return SizedBox(
            width: maxW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: span,
                  maxLines: _expanded ? null : widget.collapsedLines,
                  overflow:
                      _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_expanded ? 'Less' : 'More', style: linkStyle),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: widget.moreColor,
                          ),
                        ],
                      ),
                    ),
                    widget.timestamp,
                  ],
                ),
              ],
            ),
          );
        }

        // ── Normal text: time sits on the last line, or the bubble grows down ──
        final withGap = TextSpan(
          style: widget.style,
          children: [
            ...widget.spans,
            WidgetSpan(
              alignment: PlaceholderAlignment.bottom,
              child: SizedBox(width: widget.timestampWidth, height: 1),
            ),
          ],
        );

        final stack = Stack(
          children: [
            RichText(
              text: withGap,
              textWidthBasis: TextWidthBasis.longestLine, // shrink-wrap
            ),
            Positioned(right: 0, bottom: 0, child: widget.timestamp),
          ],
        );

        return widget.fillWidth ? SizedBox(width: maxW, child: stack) : stack;
      },
    );
  }
}
