import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AttachmentCacheService {
  static final AttachmentCacheService instance = AttachmentCacheService._();

  AttachmentCacheService._();

  static const _cacheIndexKey = 'chat_attachment_cache_index_v1';
  final Map<String, String> _urlToPathCache = {};
  bool _initialized = false;
  late Directory _attachmentDirectory;
  SharedPreferences? _prefs;

  Future<void> _initIfNeeded() async {
    if (_initialized) return;
    final documents = await getApplicationDocumentsDirectory();
    _attachmentDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}chat_attachments',
    );
    if (!await _attachmentDirectory.exists()) {
      await _attachmentDirectory.create(recursive: true);
    }

    _prefs = await SharedPreferences.getInstance();
    final encodedIndex = _prefs!.getString(_cacheIndexKey);
    if (encodedIndex != null) {
      try {
        final index = Map<String, dynamic>.from(
          jsonDecode(encodedIndex) as Map,
        );
        for (final entry in index.entries) {
          final path = entry.value as String?;
          if (path != null && await File(path).exists()) {
            _urlToPathCache[entry.key] = path;
          }
        }
      } catch (_) {
        // A damaged cache index is safe to ignore; files remain on disk.
      }
    }
    _initialized = true;
  }

  /// Restores the saved attachment index before a chat is displayed.
  Future<void> warmUp() => _initIfNeeded();

  Future<void> _persistCacheIndex() async {
    await _initIfNeeded();
    final index = <String, String>{};
    for (final entry in _urlToPathCache.entries) {
      if (await File(entry.value).exists()) index[entry.key] = entry.value;
    }
    await _prefs?.setString(_cacheIndexKey, jsonEncode(index));
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

    // The persistent index is loaded during initialization. Check it again
    // before walking the filesystem so cached avatars and attachments render
    // without a new network request after an app restart.
    final hydratedPath = _urlToPathCache[mediaUrl];
    if (hydratedPath != null && await File(hydratedPath).exists()) {
      return hydratedPath;
    }

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
          if (name == mediaKey || name.startsWith('${mediaKey}_')) {
            updateCache(mediaUrl, f.path);
            return f.path;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  String? resolveLocalPathSync(String? mediaUrl) {
    if (mediaUrl == null || mediaUrl.isEmpty) return null;
    if (_urlToPathCache.containsKey(mediaUrl)) {
      final cachedPath = _urlToPathCache[mediaUrl];
      if (cachedPath != null && File(cachedPath).existsSync()) {
        return cachedPath;
      }
    }
    if (!mediaUrl.startsWith('http://') && !mediaUrl.startsWith('https://')) {
      if (File(mediaUrl).existsSync()) {
        _urlToPathCache[mediaUrl] = mediaUrl;
        return mediaUrl;
      }
    }
    return null;
  }

  void updateCache(String mediaUrl, String localPath) {
    _urlToPathCache[mediaUrl] = localPath;
    unawaited(_persistCacheIndex());
  }
}
