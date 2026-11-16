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
  Map<String, String>? _dirIndex; // fileName -> full path
  bool _initialized = false;
  late Directory _attachmentDirectory;
  SharedPreferences? _prefs;

  Timer? _persistTimer;
  bool _persisting = false;

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

  Future<void> _ensureDirIndex() async {
    if (_dirIndex != null) return;
    final idx = <String, String>{};
    try {
      await for (final f in _attachmentDirectory.list()) {
        if (f is File) idx[f.path.split(Platform.pathSeparator).last] = f.path;
      }
    } catch (_) {}
    _dirIndex = idx;
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), _flush);
  }

  Future<void> _flush() async {
    if (_persisting) {
      _schedulePersist();
      return;
    }
    _persisting = true;
    try {
      await _initIfNeeded();
      final snapshot = Map<String, String>.from(_urlToPathCache); // copy => no concurrent modification
      await _prefs?.setString(_cacheIndexKey, jsonEncode(snapshot));
    } catch (_) {
    } finally {
      _persisting = false;
    }
  }

  Future<String?> resolveLocalPath(String? mediaUrl) async {
    if (mediaUrl == null || mediaUrl.isEmpty) return null;

    final cached = _urlToPathCache[mediaUrl];
    if (cached != null && await File(cached).exists()) return cached;

    if (!mediaUrl.startsWith('http://') && !mediaUrl.startsWith('https://')) {
      if (await File(mediaUrl).exists()) {
        _urlToPathCache[mediaUrl] = mediaUrl;
        return mediaUrl;
      }
    }

    await _initIfNeeded();
    final hydrated = _urlToPathCache[mediaUrl];
    if (hydrated != null && await File(hydrated).exists()) return hydrated;

    final mediaKey = mediaUrl
        .split('/')
        .last
        .split('\\')
        .last
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    await _ensureDirIndex(); // one directory scan, ever
    for (final e in _dirIndex!.entries) { // in-memory only
      if (e.key == mediaKey || e.key.startsWith('${mediaKey}_')) {
        updateCache(mediaUrl, e.value);
        return e.value;
      }
    }
    return null;
  }

  String? resolveLocalPathSync(String? mediaUrl) {
    if (mediaUrl == null || mediaUrl.isEmpty) return null;

    if (_urlToPathCache.containsKey(mediaUrl)) {
      final p = _urlToPathCache[mediaUrl];
      if (p != null && File(p).existsSync()) return p;
    }

    final altKey = mediaUrl.startsWith('/') ? mediaUrl.substring(1) : '/$mediaUrl';
    if (_urlToPathCache.containsKey(altKey)) {
      final p = _urlToPathCache[altKey];
      if (p != null && File(p).existsSync()) return p;
    }

    final filename = mediaUrl.split('/').last.split('\\').last;
    if (_urlToPathCache.containsKey(filename)) {
      final p = _urlToPathCache[filename];
      if (p != null && File(p).existsSync()) return p;
    }

    if (!mediaUrl.startsWith('http://') && !mediaUrl.startsWith('https://')) {
      if (File(mediaUrl).existsSync()) return mediaUrl;
    }
    return null;
  }

  bool isCachedInMemory(String? mediaUrl) {
    if (mediaUrl == null || mediaUrl.isEmpty) return false;
    return resolveLocalPathSync(mediaUrl) != null;
  }

  void updateCache(String mediaUrl, String localPath) {
    if (mediaUrl.isEmpty || localPath.isEmpty) return;
    _urlToPathCache[mediaUrl] = localPath;
    _dirIndex?[localPath.split(Platform.pathSeparator).last] = localPath;
    if (mediaUrl.startsWith('/')) {
      _urlToPathCache[mediaUrl.substring(1)] = localPath;
    } else {
      _urlToPathCache['/$mediaUrl'] = localPath;
    }
    final filename = mediaUrl.split('/').last.split('\\').last;
    if (filename.isNotEmpty) _urlToPathCache[filename] = localPath;
    _schedulePersist(); // debounced, never parallel
  }
}
