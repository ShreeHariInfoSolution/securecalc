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
      AppToast.show('Failed to download file.');
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
      AppToast.show('Failed to save file to device.');
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
          AppToast.show('Failed to download audio file for preview.');
        }
      }
    }
  }

  Future<void> _openFileExternally() async {
    final path = await _downloadLocalFile();
    if (path != null) {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        AppToast.show('Cannot open file: ${result.message}');
      }
    } else {
      AppToast.show('Failed to download file for viewing.');
    }
  }

  Future<void> _shareFile() async {
    final path = await _downloadLocalFile();
    if (path != null) {
      await Share.shareXFiles([XFile(path)], text: widget.item.fileName);
    } else {
      AppToast.show('Failed to prepare file for sharing.');
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
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
                          ),
                        ),
                        Text(
                          '${item.formattedSize}  •  ${item.formattedDate}',
                          style: TextStyle(
                            color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
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
                                  style: TextStyle(fontWeight: FontWeight.w600),
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
    );
  }

  Widget _buildMainPreviewContent(bool isDark) {
    final item = widget.item;

    if (item.isImage) {
      final url = item.fullUrl;
      final headers = ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : null;

      return Container(
        color: Colors.black,
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.network(
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
                        'Loading image...',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.orange, size: 48),
                  SizedBox(height: 12),
                  Text('Failed to load image preview', style: TextStyle(color: Colors.white)),
                ],
              ),
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
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: _isDownloading
                    ? const CupertinoActivityIndicator(radius: 18, color: accentColor)
                    : const Icon(CupertinoIcons.waveform, color: accentColor, size: 48),
              ),
              const SizedBox(height: 20),
              Text(
                item.fileName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
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
              const SizedBox(height: 16),
              CupertinoButton(
                color: accentColor,
                padding: const EdgeInsets.all(16),
                borderRadius: BorderRadius.circular(40),
                onPressed: _isDownloading ? null : _toggleAudio,
                child: _isDownloading
                    ? const CupertinoActivityIndicator(radius: 13, color: Colors.white)
                    : Icon(
                        _isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                        color: Colors.white,
                        size: 26,
                      ),
              ),
            ],
          ),
        ),
      );
    } else if (item.isVideo) {
      final url = item.fullUrl;
      final headers = ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : null;

      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 220,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.network(
                          url,
                          headers: headers,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                              child: CupertinoActivityIndicator(radius: 12, color: Colors.white),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Icon(CupertinoIcons.videocam_fill, color: Color(0xFF007AFF), size: 56),
                          ),
                        ),
                      ),
                    Center(
                      child: GestureDetector(
                        onTap: _isDownloading ? null : _openFileExternally,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF007AFF).withOpacity(0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: _isDownloading
                              ? const CupertinoActivityIndicator(radius: 12, color: Colors.white)
                              : const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _isDownloading
                    ? 'Loading video file...'
                    : 'Tap play button to open video in media player',
                style: TextStyle(
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                  fontSize: 13,
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
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.fileType,
                style: TextStyle(
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
