import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'attachment_cache_service.dart';
import 'e2e_crypto_service.dart';
import 'server_api_service.dart';

enum MediaKind { image, video, other }

class MediaDecryptException implements Exception {
  final String message;
  MediaDecryptException([this.message = 'Could not decrypt this file']);
  @override
  String toString() => message;
}

class _Gate {
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

bool _isImg(Uint8List b) {
  if (b.length < 4) return false;
  return (b[0] == 0x89 && b[1] == 0x50) ||
      (b[0] == 0xFF && b[1] == 0xD8) ||
      (b[0] == 0x47 && b[1] == 0x49) ||
      (b[0] == 0x42 && b[1] == 0x4D) ||
      (b.length >= 12 && b[0] == 0x52 && b[8] == 0x57);
}

bool _isVid(Uint8List b) {
  if (b.length < 12) return false;
  if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) return true;
  if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) return true;
  if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) return true;
  return false;
}

// Background isolate. args = [tmpPath, outPath, secretKey, kind]
bool _decryptValidate(List<String> a) {
  try {
    final raw = File(a[0]).readAsBytesSync();
    var out = E2eCryptoService.instance.decryptFileBytes(raw, a[2]);
    bool ok(Uint8List b) => a[3] == 'image'
        ? _isImg(b)
        : a[3] == 'video'
            ? _isVid(b)
            : true;
    if (!ok(out)) {
      if (ok(raw)) {
        out = raw; // legacy unencrypted file
      } else {
        return false; // wrong key / corrupt
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

class ChatMediaDownloader {
  ChatMediaDownloader._();
  static final ChatMediaDownloader instance = ChatMediaDownloader._();

  final Map<String, Future<String>> _inFlight = {};

  static MediaKind kindOf({String? type, String? name, String? url}) {
    final t = (type ?? '').toLowerCase();
    final ext = (name?.isNotEmpty == true ? name! : url ?? '')
        .split('?')
        .first
        .split('.')
        .last
        .toLowerCase();
    if (t.startsWith('image') ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp']
            .contains(ext)) {
      return MediaKind.image;
    }
    if (t.startsWith('video') ||
        ['mp4', 'mov', 'webm', 'mkv', 'avi', '3gp', 'm4v'].contains(ext)) {
      return MediaKind.video;
    }
    return MediaKind.other;
  }

  /// Returns the path of a decrypted local copy. Deduplicated per file.
  Future<String> fetch({
    required String mediaUrl,
    required String chatId,
    required String fileName,
    required MediaKind kind,
    void Function(int got, int total)? onProgress,
  }) {
    final key = '$chatId|$mediaUrl';
    return _inFlight[key] ??=
        _run(mediaUrl, chatId, fileName, kind, onProgress)
            .whenComplete(() => _inFlight.remove(key));
  }

  String _remoteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    var clean = path;
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
        RegExp(r'^/(?:data|storage|private|var|tmp|Users)/').hasMatch(path)) {
      clean = path.contains('uploads/')
          ? 'uploads/${path.split('uploads/').last}'
          : path.contains('files/')
              ? 'files/${path.split('files/').last}'
              : path.split(RegExp(r'[/\\]')).last;
    }
    final n = clean.replaceFirst(RegExp(r'^/+'), '');
    final base = ServerApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final p = n.startsWith('api/files/')
        ? n.substring(10)
        : n.startsWith('files/')
            ? n.substring(6)
            : n.startsWith('calculatorchat/')
                ? n.substring(15)
                : n;
    return '$base/files/${p.split('/').map(Uri.encodeComponent).join('/')}';
  }

  Future<String> _run(String mediaUrl, String chatId, String fileName,
      MediaKind kind, void Function(int, int)? onProgress) async {
    final cached =
        await AttachmentCacheService.instance.resolveLocalPath(mediaUrl);
    if (cached != null) return cached;

    await _Gate.acquire();
    final client = http.Client();
    File? tmp;
    try {
      final headers = ServerApiService.instance.authToken == null
          ? <String, String>{}
          : {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'};
      final req = http.Request('GET', Uri.parse(_remoteUrl(mediaUrl)))
        ..headers.addAll(headers);
      final res = await client.send(req).timeout(const Duration(seconds: 45));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Download failed (${res.statusCode}).');
      }

      final tmpDir = await getTemporaryDirectory();
      tmp = File(
          '${tmpDir.path}${Platform.pathSeparator}dl_${DateTime.now().microsecondsSinceEpoch}.tmp');
      final sink = tmp.openWrite();
      var got = 0;
      final total = res.contentLength ?? 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        onProgress?.call(got, total);
      }
      await sink.close();

      // Same naming as ChatBubble so the cache entry is shared.
      final docs = await getApplicationDocumentsDirectory();
      final dir =
          Directory('${docs.path}${Platform.pathSeparator}chat_attachments');
      await dir.create(recursive: true);
      final mediaKey = mediaUrl
          .split('/')
          .last
          .split('\\')
          .last
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final out = '${dir.path}${Platform.pathSeparator}${mediaKey}_$safeName';

      final ok = await compute(
          _decryptValidate, [tmp.path, out, 'chat_key_$chatId', kind.name]);
      if (!ok) throw MediaDecryptException();

      AttachmentCacheService.instance.updateCache(mediaUrl, out);
      return out;
    } catch (e) {
      try {
        await tmp?.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
      _Gate.release();
    }
  }
}
