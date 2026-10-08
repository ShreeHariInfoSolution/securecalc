import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AttachmentCacheService {
  static final AttachmentCacheService instance = AttachmentCacheService._();

  AttachmentCacheService._();

  final Map<String, String> _urlToPathCache = {};
  bool _initialized = false;
  late Directory _attachmentDirectory;

  Future<void> _initIfNeeded() async {
    if (_initialized) return;
    final documents = await getApplicationDocumentsDirectory();
    _attachmentDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}chat_attachments',
    );
    if (!await _attachmentDirectory.exists()) {
      await _attachmentDirectory.create(recursive: true);
    }
    _initialized = true;
  }

  Future<String?> resolveLocalPath(String? mediaUrl) async {
    if (mediaUrl == null || mediaUrl.isEmpty) return null;
    
    // Fast path: cached memory lookup
    if (_urlToPathCache.containsKey(mediaUrl)) {
      final cachedPath = _urlToPathCache[mediaUrl];
      if (cachedPath != null && await File(cachedPath).exists()) {
        return cachedPath;
      }
    }

    // Is it a local path already?
    if (!mediaUrl.startsWith('http://') && !mediaUrl.startsWith('https://')) {
      if (await File(mediaUrl).exists()) {
        _urlToPathCache[mediaUrl] = mediaUrl;
        return mediaUrl;
      }
    }

    await _initIfNeeded();

    final mediaKey = mediaUrl
        .split('/')
        .last
        .split('\\')
        .last
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        
    try {
      final files = await _attachmentDirectory.list().toList();
      for (var f in files) {
        if (f is File) {
          final name = f.path.split(Platform.pathSeparator).last;
          if (name.startsWith('${mediaKey}_')) {
            _urlToPathCache[mediaUrl] = f.path;
            return f.path;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  void updateCache(String mediaUrl, String localPath) {
    _urlToPathCache[mediaUrl] = localPath;
  }
}
