import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

class _ImgProfile {
  final int maxEdge; // long edge in px
  final int quality;
  final int skipBytes; // already-small JPEGs under this are kept as-is
  const _ImgProfile(this.maxEdge, this.quality, this.skipBytes);
}

class _VidProfile {
  final VideoQuality quality;
  final int maxEdge; // long edge in px
  final int maxBitrate; // bits/sec; below this we don't re-encode
  const _VidProfile(this.quality, this.maxEdge, this.maxBitrate);
}

class MediaCompressionService {
  MediaCompressionService._();
  static final MediaCompressionService instance = MediaCompressionService._();

  // ── WhatsApp-like profiles ────────────────────────────────────────────────
  static const _imgStd = _ImgProfile(1600, 75, 300 * 1024);
  static const _imgHd = _ImgProfile(3072, 85, 1200 * 1024);

  static const _vidStd =
  _VidProfile(VideoQuality.Res960x540Quality, 960, 2500000);
  static const _vidHd =
  _VidProfile(VideoQuality.Res1280x720Quality, 1280, 5000000);

  static const _processedPrefix = 'wa_';

  static const List<String> _imageExtensions = [
    'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp',
  ];
  static const List<String> _videoExtensions = [
    'mp4', 'mov', 'mkv', 'avi', '3gp', 'webm', 'm4v', '3g2', 'ts', 'flv',
  ];

  String _ext(String path) => path.split('.').last.toLowerCase();
  String _name(String path) => path.split(RegExp(r'[/\\]')).last;

  bool isImage(String filePath) => _imageExtensions.contains(_ext(filePath));
  bool isVideo(String filePath) => _videoExtensions.contains(_ext(filePath));

  /// Files produced by this service are never compressed a second time.
  bool _alreadyProcessed(String path) =>
      _name(path).startsWith(_processedPrefix);

  Future<File> compressMedia(
      File originalFile, {
        bool isHd = false,
        void Function(double progress)? onProgress,
      }) async {
    try {
      if (!originalFile.existsSync()) return originalFile;
      if (_alreadyProcessed(originalFile.path)) return originalFile;
      if (isImage(originalFile.path)) {
        return await compressImage(originalFile, isHd: isHd);
      } else if (isVideo(originalFile.path)) {
        return await compressVideo(originalFile,
            isHd: isHd, onProgress: onProgress);
      }
    } catch (e) {
      debugPrint('[MEDIA COMPRESS ERROR] $e');
    }
    return originalFile;
  }

  // ── IMAGE ─────────────────────────────────────────────────────────────────

  /// Reads width/height from the file header only (no pixel decode, no RAM spike).
  Future<ui.Size?> _readSize(String path) async {
    try {
      final buf = await ui.ImmutableBuffer.fromFilePath(path);
      final desc = await ui.ImageDescriptor.encoded(buf);
      final s = ui.Size(desc.width.toDouble(), desc.height.toDouble());
      desc.dispose();
      buf.dispose();
      return s.width > 0 && s.height > 0 ? s : null;
    } catch (_) {
      return null;
    }
  }

  Future<File> compressImage(File originalFile, {bool isHd = false}) async {
    try {
      if (!originalFile.existsSync()) return originalFile;
      if (_alreadyProcessed(originalFile.path)) return originalFile;

      final p = isHd ? _imgHd : _imgStd;
      final before = await originalFile.length();
      final ext = _ext(originalFile.path);
      final isJpeg = ext == 'jpg' || ext == 'jpeg';

      final size = await _readSize(originalFile.path);
      final longEdge = size == null ? 0.0 : math.max(size.width, size.height);
      final shortEdge = size == null ? 0.0 : math.min(size.width, size.height);
      final needsResize = size != null && longEdge > p.maxEdge;

      // Already a small JPEG within the resolution cap: send as-is.
      if (isJpeg && !needsResize && before <= p.skipBytes) return originalFile;

      // flutter_image_compress limits the SHORT side (minWidth/minHeight),
      // so convert the long-edge cap into the equivalent short-side target.
      // The short side is the same whatever the EXIF rotation is.
      final int shortTarget = size == null
          ? (p.maxEdge * 0.75).round()
          : (needsResize
          ? shortEdge * (p.maxEdge / longEdge)
          : shortEdge)
          .round();

      final tmp = await getTemporaryDirectory();
      final target =
          '${tmp.path}${Platform.pathSeparator}$_processedPrefix${isHd ? 'hd' : 'std'}_'
          '${DateTime.now().microsecondsSinceEpoch}.jpg';

      final out = await FlutterImageCompress.compressAndGetFile(
        originalFile.absolute.path,
        target,
        quality: p.quality,
        minWidth: shortTarget,
        minHeight: shortTarget,
        format: CompressFormat.jpeg,
        keepExif: false, // orientation is applied, GPS/metadata dropped
        autoCorrectionAngle: true,
      );
      if (out == null) return originalFile;

      final outFile = File(out.path);
      final after = await outFile.length();
      debugPrint('[IMAGE] ${isHd ? 'HD' : 'STD'} '
          '${(before / 1024).round()}KB -> ${(after / 1024).round()}KB');

      // Keep the result if it's smaller, or if the original is a format
      // other people may not be able to open (HEIC / PNG / BMP).
      if (after < before || !isJpeg) return outFile;
      await outFile.delete();
    } catch (e) {
      debugPrint('[IMAGE COMPRESS ERROR] $e');
    }
    return originalFile;
  }

  // ── VIDEO ─────────────────────────────────────────────────────────────────

  // video_compress supports only one job at a time, so jobs are queued.
  Future<void> _videoLock = Future.value();

  Future<T> _serial<T>(Future<T> Function() task) {
    final prev = _videoLock;
    final done = Completer<void>();
    _videoLock = done.future;
    return prev.then((_) => task()).whenComplete(done.complete);
  }

  Future<File> compressVideo(
      File originalFile, {
        bool isHd = false,
        void Function(double progress)? onProgress,
      }) =>
      _serial(() => _compressVideo(originalFile, isHd, onProgress));

  /// Call when the user cancels/discards an upload that is still compressing.
  Future<void> cancelVideoCompression() async {
    try {
      await VideoCompress.cancelCompression();
    } catch (_) {}
  }

  Future<File> _compressVideo(
      File originalFile,
      bool isHd,
      void Function(double progress)? onProgress,
      ) async {
    Subscription? sub;
    try {
      if (!originalFile.existsSync()) return originalFile;
      if (_alreadyProcessed(originalFile.path)) return originalFile;

      final p = isHd ? _vidHd : _vidStd;
      final before = await originalFile.length();

      // Tiny clips are not worth re-encoding.
      if (before < 2 * 1024 * 1024) return originalFile;

      // WhatsApp-style decision: only re-encode when the video is above the
      // resolution OR bitrate budget. Already-light videos are left alone.
      try {
        final info = await VideoCompress.getMediaInfo(originalFile.path);
        final w = info.width ?? 0;
        final h = info.height ?? 0;
        final durMs = info.duration ?? 0; // milliseconds
        if (durMs > 0 && w > 0 && h > 0) {
          final bitrate = before * 8 / (durMs / 1000.0);
          final longEdge = math.max(w, h);
          if (longEdge <= p.maxEdge && bitrate <= p.maxBitrate) {
            debugPrint('[VIDEO] already light, skipping');
            return originalFile;
          }
        }
      } catch (_) {}

      if (onProgress != null) {
        sub = VideoCompress.compressProgress$.subscribe((v) {
          onProgress(v.clamp(0.0, 100.0));
        });
      }

      final info = await VideoCompress.compressVideo(
        originalFile.path,
        quality: p.quality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 30, // 60 fps clips are halved; big saving, barely visible
      );

      final compressed = info?.file;
      if (compressed == null) return originalFile;

      final after = await compressed.length();
      debugPrint('[VIDEO] ${isHd ? 'HD' : 'STD'} '
          '${(before / 1048576).toStringAsFixed(1)}MB -> '
          '${(after / 1048576).toStringAsFixed(1)}MB');

      if (after >= before) {
        try { await compressed.delete(); } catch (_) {}
        return originalFile;
      }
      return compressed; // no copy, no deleteAllCache
    } catch (e) {
      debugPrint('[VIDEO COMPRESS ERROR] $e');
      return originalFile;
    } finally {
      sub?.unsubscribe();
    }
  }
}