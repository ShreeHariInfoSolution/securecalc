import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:securecalc/src/features/chat/domain/models/server_models.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:securecalc/src/features/chat/presentation/widgets/app_video_player.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';

class FilePreviewDialog extends StatefulWidget {
  final UploadItemModel item;
  final VoidCallback? onItemDeleted;

  const FilePreviewDialog({
    super.key,
    required this.item,
    this.onItemDeleted,
  });

  static void show(BuildContext context, UploadItemModel item, {VoidCallback? onItemDeleted}) {
    showCupertinoModalPopup(
      context: context,
      useRootNavigator: true,
      builder: (_) => FilePreviewDialog(
        item: item,
        onItemDeleted: onItemDeleted,
      ),
    );
  }

  @override
  State<FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<FilePreviewDialog> {
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  final ValueNotifier<Duration> _duration = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  bool _isLoadingFile = false;
  bool _isDownloading = false;
  String? _localDownloadedPath;

  @override
  void initState() {
    super.initState();
    if (widget.item.isAudio) {
      _initAudioPlayer();
      _downloadLocalFile();
    }
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    super.dispose();
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _audioPlayer!.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer!.onDurationChanged.listen((dur) {
      if (mounted) {
        _duration.value = dur;
      }
    });

    _audioPlayer!.onPositionChanged.listen((pos) {
      if (mounted) {
        _position.value = pos;
      }
    });
  }

  Future<String?> _downloadLocalFile() async {
    if (_localDownloadedPath != null && File(_localDownloadedPath!).existsSync()) {
      return _localDownloadedPath;
    }

    final url = widget.item.fullUrl;
    if (url.isEmpty) return null;

    if (mounted) setState(() => _isDownloading = true);
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: ServerApiService.instance.authToken != null
            ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
            : null,
      );

      if (res.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final sanitizeName = widget.item.fileName.replaceAll(RegExp(r'[^\w\.-]'), '_');
        final file = File('${tempDir.path}${Platform.pathSeparator}$sanitizeName');
        await file.writeAsBytes(res.bodyBytes);
        _localDownloadedPath = file.path;
        return file.path;
      } else {
        debugPrint('[Preview] Download status error: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('[Preview] Download error: $e');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
    return null;
  }

  Future<void> _saveFileToDevice() async {
    final tempPath = await _downloadLocalFile();
    if (tempPath == null || !File(tempPath).existsSync()) {
      AppToast.show('Failed to download file.', isError: true);
      return;
    }

    try {
      Directory? targetDir;
      if (Platform.isAndroid) {
        final downloadsDir = Directory('/storage/emulated/0/Download');
        if (downloadsDir.existsSync()) {
          targetDir = downloadsDir;
        } else {
          targetDir = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        targetDir = await getApplicationDocumentsDirectory();
      } else {
        targetDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      if (targetDir == null) {
        targetDir = await getApplicationDocumentsDirectory();
      }

      final sanitizeName = widget.item.fileName.replaceAll(RegExp(r'[^\w\.-]'), '_');
      String savePath = '${targetDir.path}${Platform.pathSeparator}$sanitizeName';

      int count = 1;
      final dotIndex = sanitizeName.lastIndexOf('.');
      final nameWithoutExt = dotIndex != -1 ? sanitizeName.substring(0, dotIndex) : sanitizeName;
      final ext = dotIndex != -1 ? sanitizeName.substring(dotIndex) : '';

      while (File(savePath).existsSync()) {
        savePath = '${targetDir.path}${Platform.pathSeparator}${nameWithoutExt}_$count$ext';
        count++;
      }

      await File(tempPath).copy(savePath);
      final finalFileName = savePath.split(Platform.pathSeparator).last;
      AppToast.show('File saved to Downloads: $finalFileName');
    } catch (e) {
      debugPrint('[Preview] Save file error: $e');
      AppToast.show('Failed to save file to device.', isError: true);
    }
  }

  Future<void> _toggleAudio() async {
    if (_audioPlayer == null) return;

    if (_isPlaying) {
      await _audioPlayer!.pause();
    } else {
      if (_position.value > Duration.zero && _position.value < _duration.value) {
        await _audioPlayer!.resume();
      } else {
        final path = await _downloadLocalFile();
        if (path != null && File(path).existsSync()) {
          await _audioPlayer!.play(DeviceFileSource(path));
        } else {
          AppToast.show('Failed to download audio file for preview.', isError: true);
        }
      }
    }
  }

  Future<void> _rewind10s() async {
    if (_audioPlayer == null) return;
    final newPos = _position.value - const Duration(seconds: 10);
    final target = newPos < Duration.zero ? Duration.zero : newPos;
    await _audioPlayer!.seek(target);
  }

  Future<void> _forward10s() async {
    if (_audioPlayer == null) return;
    final newPos = _position.value + const Duration(seconds: 10);
    final target = newPos > _duration.value ? _duration.value : newPos;
    await _audioPlayer!.seek(target);
  }

  Future<void> _openFileExternally() async {
    final path = await _downloadLocalFile();
    if (path != null) {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        AppToast.show('Cannot open file.', isError: true);
      }
    } else {
      AppToast.show('Failed to download file for viewing.', isError: true);
    }
  }

  Future<void> _renameFile() async {
    final controller = TextEditingController(text: widget.item.fileName);
    final newName = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Rename File'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Enter new name',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != widget.item.fileName) {
      setState(() => _isLoadingFile = true);
      final updated = await ServerApiService.instance.renameUpload(
        id: widget.item.id,
        newName: newName,
      );
      if (mounted) {
        setState(() => _isLoadingFile = false);
        if (updated != null) {
          AppToast.show('File renamed to "$newName"');
          Navigator.pop(context);
          widget.onItemDeleted?.call();
        } else {
          AppToast.show('Failed to rename file', isError: true);
        }
      }
    }
  }

  Future<void> _shareFile() async {
    final path = await _downloadLocalFile();
    if (path != null) {
      await Share.shareXFiles([XFile(path)], text: widget.item.fileName);
    } else {
      AppToast.show('Failed to prepare file for sharing.', isError: true);
    }
  }

  Future<void> _deleteFile() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to permanently delete "${widget.item.fileName}" from vault storage?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoadingFile = true);
      final ok = await ServerApiService.instance.deleteUploadFile(
        widget.item.id,
        filePath: widget.item.filePath,
      );
      if (mounted) {
        setState(() => _isLoadingFile = false);
        if (ok) {
          AppToast.show('File deleted successfully.');
          Navigator.pop(context);
          widget.onItemDeleted?.call();
        } else {
          AppToast.show('File deleted locally.');
          Navigator.pop(context);
          widget.onItemDeleted?.call();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = widget.item;

    return Material(
      color: Colors.transparent,
      child: DefaultTextStyle(
        style: TextStyle(
          decoration: TextDecoration.none,
          fontFamily: '.SF Pro Text',
          color: isDark ? Colors.white : const Color(0xFF1C1C1E),
        ),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // Drag Handle Bar
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD1D1D6),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                const SizedBox(height: 12),

                // Navigation Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(CupertinoIcons.xmark_circle_fill),
                        color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              item.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            Text(
                              '${item.formattedSize}  •  ${item.formattedDate}',
                              style: TextStyle(
                                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                                fontSize: 12,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.pencil, color: Color(0xFF007AFF)),
                        onPressed: _renameFile,
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.arrow_down_circle, color: Color(0xFF34C759)),
                        onPressed: _isDownloading ? null : _saveFileToDevice,
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.trash, color: CupertinoColors.destructiveRed),
                        onPressed: _deleteFile,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),

                // Content Area
                Expanded(
                  child: _isLoadingFile
                      ? const Center(child: CupertinoActivityIndicator(radius: 14))
                      : _buildMainPreviewContent(isDark),
                ),

                // Action Bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          borderRadius: BorderRadius.circular(14),
                          onPressed: _isDownloading ? null : _shareFile,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.share,
                                size: 18,
                                color: isDark ? Colors.white : const Color(0xFF007AFF),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Share',
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF007AFF),
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CupertinoButton(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          borderRadius: BorderRadius.circular(14),
                          onPressed: _isDownloading ? null : _saveFileToDevice,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.arrow_down_to_line,
                                size: 18,
                                color: isDark ? Colors.white : const Color(0xFF34C759),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Save',
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF34C759),
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CupertinoButton.filled(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          borderRadius: BorderRadius.circular(14),
                          onPressed: _isDownloading ? null : _openFileExternally,
                          child: _isDownloading
                              ? const CupertinoActivityIndicator(color: Colors.white, radius: 10)
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(CupertinoIcons.arrow_up_right_square, size: 18, color: Colors.white),
                                    SizedBox(width: 6),
                                    Text(
                                      'Open',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainPreviewContent(bool isDark) {
    final item = widget.item;

    if (item.isImage) {
      final url = item.fullUrl;
      final headers = ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : null;

      final localPath = _localDownloadedPath;
      final hasLocal = localPath != null && File(localPath).existsSync();

      return Container(
        color: Colors.black,
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: hasLocal
                ? Image.file(
                    File(localPath),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => _buildImageErrorView(),
                  )
                : Image.network(
                    url,
                    headers: headers,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CupertinoActivityIndicator(radius: 14, color: Colors.white),
                            SizedBox(height: 12),
                            Text(
                              'Loading high resolution image...',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => _buildImageErrorView(),
                  ),
          ),
        ),
      );
    } else if (item.isAudio) {
      const accentColor = Color(0xFFFF9500);

      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      accentColor,
                      accentColor.withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withOpacity(_isPlaying ? 0.45 : 0.2),
                      blurRadius: _isPlaying ? 24 : 12,
                      spreadRadius: _isPlaying ? 4 : 0,
                    ),
                  ],
                ),
                child: Center(
                  child: _isDownloading
                      ? const CupertinoActivityIndicator(radius: 18, color: Colors.white)
                      : Icon(
                          _isPlaying ? CupertinoIcons.waveform_path : CupertinoIcons.music_note_2,
                          color: Colors.white,
                          size: 48,
                        ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                item.fileName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder<Duration>(
                valueListenable: _position,
                builder: (context, pos, _) {
                  return ValueListenableBuilder<Duration>(
                    valueListenable: _duration,
                    builder: (context, dur, _) {
                      final maxSec = dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 1.0;
                      final curSec = pos.inSeconds.toDouble().clamp(0.0, maxSec);

                      return Column(
                        children: [
                          Text(
                            '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                            style: TextStyle(
                              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          if (_isDownloading)
                            const Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Text(
                                'Loading audio file...',
                                style: TextStyle(
                                  color: accentColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: CupertinoSlider(
                              value: curSec,
                              min: 0.0,
                              max: maxSec,
                              activeColor: accentColor,
                              onChanged: (val) {
                                _audioPlayer?.seek(Duration(seconds: val.toInt()));
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(CupertinoIcons.gobackward_10, color: accentColor),
                    onPressed: _isDownloading ? null : _rewind10s,
                  ),
                  const SizedBox(width: 16),
                  CupertinoButton(
                    color: accentColor,
                    padding: const EdgeInsets.all(18),
                    borderRadius: BorderRadius.circular(44),
                    onPressed: _isDownloading ? null : _toggleAudio,
                    child: _isDownloading
                        ? const CupertinoActivityIndicator(radius: 14, color: Colors.white)
                        : Icon(
                            _isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                            color: Colors.white,
                            size: 28,
                          ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(CupertinoIcons.goforward_10, color: accentColor),
                    onPressed: _isDownloading ? null : _forward10s,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else if (item.isVideo) {
      final url = item.fullUrl;

      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  AppVideoPlayerModal.open(
                    context,
                    mediaUrl: url,
                    title: item.fileName,
                  );
                },
                child: Container(
                  height: 230,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoThumbnailCard(
                          mediaUrl: url,
                          width: double.infinity,
                          height: 230,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF007AFF).withOpacity(0.4),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            CupertinoIcons.play_fill,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              CupertinoButton(
                color: const Color(0xFF007AFF),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                borderRadius: BorderRadius.circular(20),
                onPressed: () {
                  AppVideoPlayerModal.open(
                    context,
                    mediaUrl: url,
                    title: item.fileName,
                  );
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.play_circle_fill, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Play Fullscreen Video',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final ext = item.fileName.split('.').last.toUpperCase();
      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Center(
                  child: Text(
                    ext.length > 4 ? ext.substring(0, 4) : ext,
                    style: const TextStyle(
                      color: Color(0xFF34C759),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  item.fileName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.fileType,
                style: TextStyle(
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                  fontSize: 13,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildImageErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.amber, size: 44),
          const SizedBox(height: 12),
          const Text(
            'Failed to load image preview',
            style: TextStyle(color: Colors.white70, fontSize: 14, decoration: TextDecoration.none),
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            color: Colors.white24,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            borderRadius: BorderRadius.circular(20),
            onPressed: () {
              setState(() => _localDownloadedPath = null);
              _downloadLocalFile();
            },
            child: const Text('Retry Loading', style: TextStyle(color: Colors.white, fontSize: 13, decoration: TextDecoration.none)),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
