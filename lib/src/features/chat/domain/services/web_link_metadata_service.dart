import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Data model representing website OpenGraph metadata.
class WebLinkMetadata {
  final String originalUrl;
  final String cleanUrl;
  final String domain;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? localImagePath;
  final String? faviconUrl;
  final double? imageWidth;
  final double? imageHeight;
  final bool isVideo;

  WebLinkMetadata({
    required this.originalUrl,
    required this.cleanUrl,
    required this.domain,
    this.title,
    this.description,
    this.imageUrl,
    this.localImagePath,
    this.faviconUrl,
    this.imageWidth,
    this.imageHeight,
    this.isVideo = false,
  });

  bool get hasContent =>
      (title?.isNotEmpty ?? false) ||
          (description?.isNotEmpty ?? false) ||
          (imageUrl?.isNotEmpty ?? false);

  bool get hasDetails => hasContent;

  double? get imageAspect =>
      (imageWidth != null && imageHeight != null && imageHeight! > 0)
          ? imageWidth! / imageHeight!
          : null;

  WebLinkMetadata copyWith({
    String? originalUrl,
    String? cleanUrl,
    String? domain,
    String? title,
    String? description,
    String? imageUrl,
    String? localImagePath,
    String? faviconUrl,
    double? imageWidth,
    double? imageHeight,
    bool? isVideo,
  }) {
    return WebLinkMetadata(
      originalUrl: originalUrl ?? this.originalUrl,
      cleanUrl: cleanUrl ?? this.cleanUrl,
      domain: domain ?? this.domain,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      localImagePath: localImagePath ?? this.localImagePath,
      faviconUrl: faviconUrl ?? this.faviconUrl,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      isVideo: isVideo ?? this.isVideo,
    );
  }

  Map<String, dynamic> toJson() => {
    'originalUrl': originalUrl,
    'cleanUrl': cleanUrl,
    'domain': domain,
    'title': title,
    'description': description,
    'imageUrl': imageUrl,
    'localImagePath': localImagePath,
    'faviconUrl': faviconUrl,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'isVideo': isVideo,
  };

  factory WebLinkMetadata.fromJson(Map<String, dynamic> json) => WebLinkMetadata(
    originalUrl: json['originalUrl']?.toString() ?? '',
    cleanUrl: json['cleanUrl']?.toString() ?? '',
    domain: json['domain']?.toString() ?? '',
    title: json['title']?.toString(),
    description: json['description']?.toString(),
    imageUrl: json['imageUrl']?.toString(),
    localImagePath: json['localImagePath']?.toString(),
    faviconUrl: json['faviconUrl']?.toString(),
    imageWidth: double.tryParse(json['imageWidth']?.toString() ?? ''),
    imageHeight: double.tryParse(json['imageHeight']?.toString() ?? ''),
    isVideo: json['isVideo'] == true,
  );
}

/// Singleton Service to fetch and cache website OpenGraph metadata.
class WebLinkMetadataService {
  WebLinkMetadataService._() {
    _loadPersistedCache();
  }

  static final WebLinkMetadataService instance = WebLinkMetadataService._();

  static const _prefsKey = 'chat_web_link_metadata_cache_v3';
  final Map<String, WebLinkMetadata> _cache = {};
  final Map<String, Future<WebLinkMetadata>> _inFlight = {};
  final Map<String, DateTime> _failedUrls = {};

  void _loadPersistedCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is Map) {
              _cache[entry.key.toString()] = WebLinkMetadata.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              );
            }
          }
        }
      }
    } catch (_) {}
  }

  void _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final export = <String, dynamic>{};
      for (final entry in _cache.entries.take(200)) {
        if (entry.value.hasContent) {
          export[entry.key] = entry.value.toJson();
        }
      }
      await prefs.setString(_prefsKey, jsonEncode(export));
    } catch (_) {}
  }

  String normalizeUrl(String rawUrl) {
    var u = rawUrl.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    return u;
  }

  /// Synchronous memory cache peek (prevents UI flicker).
  WebLinkMetadata? peek(String urlStr) {
    final cleanUrl = normalizeUrl(urlStr);
    final cached = _cache[cleanUrl] ?? _cache[urlStr.trim()];
    if (cached != null &&
        cached.imageUrl != null &&
        cached.imageUrl!.isNotEmpty &&
        (cached.localImagePath == null ||
            !File(cached.localImagePath!).existsSync())) {
      unawaited(ensureLocalImageCached(cached));
    }
    return cached;
  }

  /// Downloads and caches the banner image to local disk.
  Future<WebLinkMetadata> ensureLocalImageCached(WebLinkMetadata meta) async {
    final rawImg = meta.imageUrl;
    if (rawImg == null || rawImg.isEmpty) return meta;

    final cleanImgUrl = rawImg.replaceAll('&amp;', '&').trim();

    if (meta.localImagePath != null && File(meta.localImagePath!).existsSync()) {
      if (meta.imageUrl != cleanImgUrl) {
        final updated = meta.copyWith(imageUrl: cleanImgUrl);
        _cache[meta.cleanUrl] = updated;
        return updated;
      }
      return meta;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(
          '${dir.path}${Platform.pathSeparator}link_preview_cache');
      if (!cacheDir.existsSync()) {
        await cacheDir.create(recursive: true);
      }

      final hash = cleanImgUrl.hashCode.abs().toString();
      final localPath =
          '${cacheDir.path}${Platform.pathSeparator}banner_$hash.jpg';

      final file = File(localPath);
      if (file.existsSync() && file.lengthSync() > 0) {
        final updated = meta.copyWith(
          imageUrl: cleanImgUrl,
          localImagePath: localPath,
        );
        _cache[meta.cleanUrl] = updated;
        return updated;
      }

      final response = await http.get(Uri.parse(cleanImgUrl), headers: {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes);
        final updated = meta.copyWith(
          imageUrl: cleanImgUrl,
          localImagePath: localPath,
        );
        _cache[meta.cleanUrl] = updated;
        _persistCache();
        return updated;
      }
    } catch (e) {
      debugPrint('[LINK PREVIEW DISK CACHE WARNING] $e');
    }

    if (meta.imageUrl != cleanImgUrl) {
      final updated = meta.copyWith(imageUrl: cleanImgUrl);
      _cache[meta.cleanUrl] = updated;
      return updated;
    }

    return meta;
  }

  /// Retrieves cached metadata or fetches OpenGraph data from the website.
  Future<WebLinkMetadata> getMetadata(String urlStr) async {
    final cleanUrl = normalizeUrl(urlStr);

    if (_cache.containsKey(cleanUrl)) {
      final cached = _cache[cleanUrl]!;
      if (cached.hasContent &&
          cached.imageUrl != null &&
          cached.imageUrl!.isNotEmpty &&
          (cached.localImagePath == null ||
              !File(cached.localImagePath!).existsSync())) {
        unawaited(ensureLocalImageCached(cached));
      }
      return cached;
    }

    if (_failedUrls.containsKey(cleanUrl)) {
      final failedAt = _failedUrls[cleanUrl]!;
      if (DateTime.now().difference(failedAt).inMinutes < 10) {
        // Return clean fallback metadata during negative cache window
        final uri = Uri.tryParse(cleanUrl);
        final domain = uri?.host.replaceAll('www.', '') ?? cleanUrl;
        return WebLinkMetadata(
          originalUrl: urlStr,
          cleanUrl: cleanUrl,
          domain: domain,
          faviconUrl: uri != null
              ? 'https://www.google.com/s2/favicons?domain=${uri.host}&sz=64'
              : null,
        );
      } else {
        _failedUrls.remove(cleanUrl);
      }
    }

    if (_inFlight.containsKey(cleanUrl)) {
      return _inFlight[cleanUrl]!;
    }

    final future = _fetchWithCleanup(cleanUrl, urlStr);
    _inFlight[cleanUrl] = future;
    return future;
  }

  Future<WebLinkMetadata> _fetchWithCleanup(
      String cleanUrl, String originalUrl) async {
    try {
      var result = await _fetch(cleanUrl, originalUrl);
      if (result.imageUrl != null && result.imageUrl!.isNotEmpty) {
        result = await ensureLocalImageCached(result);
      }
      _cache[cleanUrl] = result;
      if (!result.hasContent) {
        _failedUrls[cleanUrl] = DateTime.now();
      }
      _persistCache();
      return result;
    } catch (e) {
      _failedUrls[cleanUrl] = DateTime.now();
      final uri = Uri.tryParse(cleanUrl);
      final domain = uri?.host.replaceAll('www.', '') ?? cleanUrl;
      return WebLinkMetadata(
        originalUrl: originalUrl,
        cleanUrl: cleanUrl,
        domain: domain,
        faviconUrl: uri != null
            ? 'https://www.google.com/s2/favicons?domain=${uri.host}&sz=64'
            : null,
      );
    } finally {
      _inFlight.remove(cleanUrl);
    }
  }

  Future<WebLinkMetadata> _fetch(String cleanUrl, String originalUrl) async {
    final uri = Uri.tryParse(cleanUrl);
    final domain = uri?.host.replaceAll('www.', '') ?? cleanUrl;
    final fallbackFavicon = uri != null
        ? 'https://www.google.com/s2/favicons?domain=${uri.host}&sz=64'
        : null;

    if (uri == null) {
      return WebLinkMetadata(
        originalUrl: originalUrl,
        cleanUrl: cleanUrl,
        domain: domain,
      );
    }

    if (domain.contains('instagram.com') || domain.contains('instagr.am')) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final isReel = cleanUrl.contains('/reel/') ||
          cleanUrl.contains('/reels/') ||
          cleanUrl.contains('/tv/');
      final isPost = cleanUrl.contains('/p/');
      final isProfile =
          segments.length == 1 && !isReel && !isPost && !segments.first.contains('.');

      // 1. Try public DDInstagram proxy (safe Uri host replacement)
      try {
        final proxyUri = uri.replace(host: 'ddinstagram.com');
        final response = await http.get(
          proxyUri,
          headers: {
            'User-Agent':
                'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
            'Accept': 'text/html,application/xhtml+xml',
          },
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final html = response.body;
          final meta = _parseHtml(
            html,
            cleanUrl,
            originalUrl,
            uri,
            'instagram.com',
            'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
          );
          if (meta.hasContent &&
              meta.imageUrl != null &&
              !meta.imageUrl!.contains('favicon') &&
              !meta.imageUrl!.contains('ddinstagram')) {
            return meta;
          }
        }
      } catch (e) {
        debugPrint('[INSTAGRAM DDINSTAGRAM WARNING] $e');
      }

      // 2. Try native Instagram Embed page (/embed/captioned/)
      if (segments.length >= 2 &&
          (isReel || isPost || segments.first == 'p' || segments.first == 'reel')) {
        try {
          final type = isReel ? 'reel' : 'p';
          final shortcode = segments.length > 1 ? segments[1] : segments.first;
          final embedUri =
              Uri.parse('https://www.instagram.com/$type/$shortcode/embed/captioned/');

          final response = await http.get(
            embedUri,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
              'Accept': 'text/html',
            },
          ).timeout(const Duration(seconds: 4));

          if (response.statusCode == 200) {
            final html = response.body;
            final imgMatch = RegExp(
                  r'class="EmbeddedMediaImage"[^>]*src="([^"]+)"',
                  caseSensitive: false,
                ).firstMatch(html) ??
                RegExp(
                  r'<img[^>]*class="[^"]*EmbeddedMediaImage[^"]*"[^>]*src="([^"]+)"',
                  caseSensitive: false,
                ).firstMatch(html) ??
                RegExp(
                  r'https://scontent[^\s"&<]+',
                  caseSensitive: false,
                ).firstMatch(html);

            final authorMatch = RegExp(
              r'class="UsernameText"[^>]*>([^<]+)<',
              caseSensitive: false,
            ).firstMatch(html);

            final captionMatch = RegExp(
              r'class="Caption"[^>]*>([\s\S]*?)</div>',
              caseSensitive: false,
            ).firstMatch(html);

            String? imgUrl = imgMatch?.group(1) ?? imgMatch?.group(0);
            if (imgUrl != null) {
              imgUrl = imgUrl.replaceAll('&amp;', '&');
            }
            final author = authorMatch?.group(1)?.trim();
            final caption = _cleanText(captionMatch?.group(1));

            if (imgUrl != null && imgUrl.startsWith('http')) {
              return WebLinkMetadata(
                originalUrl: originalUrl,
                cleanUrl: cleanUrl,
                domain: 'instagram.com',
                title: isReel
                    ? (author != null ? 'Instagram Reel by @$author' : 'Instagram Reel')
                    : (author != null ? 'Instagram Post by @$author' : 'Instagram Post'),
                description: (caption != null && caption.isNotEmpty)
                    ? caption
                    : (author != null ? 'Watch on Instagram (@$author)' : 'Watch on Instagram'),
                imageUrl: imgUrl,
                faviconUrl:
                    'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
                isVideo: isReel,
              );
            }
          }
        } catch (e) {
          debugPrint('[INSTAGRAM EMBED WARNING] $e');
        }
      }

      // 3. Instagram Profile Sharing Handling
      if (isProfile) {
        final username = segments.first;

        // Strategy 1: Instagram Web Profile Info API
        try {
          final apiUri = Uri.parse(
            'https://www.instagram.com/api/v1/users/web_profile_info/?username=$username',
          );
          final res = await http.get(
            apiUri,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
              'X-IG-App-ID': '936619743392459',
              'Accept': 'application/json',
            },
          ).timeout(const Duration(seconds: 4));

          if (res.statusCode == 200 && res.body.trim().startsWith('{')) {
            final json = jsonDecode(res.body);
            final user = json['data']?['user'];
            if (user is Map) {
              final fullName = user['full_name']?.toString().trim();
              final bio = user['biography']?.toString().trim();
              final picHd = user['profile_pic_url_hd']?.toString() ??
                  user['profile_pic_url']?.toString();
              final followers = user['edge_followed_by']?['count'];

              String desc = bio ?? '';
              if (followers != null && followers is num) {
                final fStr = followers > 1000000
                    ? '${(followers / 1000000).toStringAsFixed(1)}M'
                    : (followers > 1000
                        ? '${(followers / 1000).toStringAsFixed(1)}K'
                        : '$followers');
                desc = '$fStr followers • ${desc.isNotEmpty ? desc : "Instagram profile"}';
              }

              final title = (fullName != null && fullName.isNotEmpty)
                  ? '$fullName (@$username)'
                  : 'Instagram Profile (@$username)';

              if (picHd != null && picHd.startsWith('http')) {
                return WebLinkMetadata(
                  originalUrl: originalUrl,
                  cleanUrl: cleanUrl,
                  domain: 'instagram.com',
                  title: title,
                  description: desc.isNotEmpty
                      ? desc
                      : 'See photos and videos from @$username on Instagram',
                  imageUrl: picHd,
                  faviconUrl:
                      'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
                  imageWidth: 640,
                  imageHeight: 640,
                );
              }
            }
          }
        } catch (e) {
          debugPrint('[INSTAGRAM PROFILE API WARNING] $e');
        }

        // Strategy 2: Facebook Externalhit OpenGraph Scrape
        try {
          final profileUri = Uri.parse('https://www.instagram.com/$username/');
          final response = await http.get(
            profileUri,
            headers: {
              'User-Agent':
                  'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
              'Accept': 'text/html,application/xhtml+xml',
            },
          ).timeout(const Duration(seconds: 4));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final html = response.body;
            final meta = _parseHtml(
              html,
              cleanUrl,
              originalUrl,
              profileUri,
              'instagram.com',
              'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
            );
            if (meta.hasContent &&
                meta.imageUrl != null &&
                meta.imageUrl!.isNotEmpty &&
                !meta.imageUrl!.contains('favicon')) {
              return WebLinkMetadata(
                originalUrl: originalUrl,
                cleanUrl: cleanUrl,
                domain: 'instagram.com',
                title: (meta.title != null && meta.title!.trim().isNotEmpty)
                    ? meta.title!.trim()
                    : 'Instagram Profile (@$username)',
                description: (meta.description != null && meta.description!.trim().isNotEmpty)
                    ? meta.description!.trim()
                    : 'View photos, reels, and videos from @$username on Instagram',
                imageUrl: meta.imageUrl,
                faviconUrl:
                    'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
                imageWidth: meta.imageWidth ?? 640,
                imageHeight: meta.imageHeight ?? 640,
              );
            }
          }
        } catch (e) {
          debugPrint('[INSTAGRAM PROFILE FETCH WARNING] $e');
        }

        // Strategy 3: DDInstagram Profile Proxy
        try {
          final proxyUri = Uri.parse('https://ddinstagram.com/$username/');
          final response = await http.get(
            proxyUri,
            headers: {
              'User-Agent':
                  'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
            },
          ).timeout(const Duration(seconds: 4));

          if (response.statusCode == 200) {
            final html = response.body;
            final meta = _parseHtml(
              html,
              cleanUrl,
              originalUrl,
              proxyUri,
              'instagram.com',
              'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
            );
            if (meta.imageUrl != null && meta.imageUrl!.startsWith('http')) {
              return WebLinkMetadata(
                originalUrl: originalUrl,
                cleanUrl: cleanUrl,
                domain: 'instagram.com',
                title: meta.title ?? 'Instagram Profile (@$username)',
                description: meta.description ?? 'View profile on Instagram',
                imageUrl: meta.imageUrl,
                faviconUrl:
                    'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
              );
            }
          }
        } catch (_) {}

        // Fallback: Safe Instagram Logo (No Unsplash timeouts)
        return WebLinkMetadata(
          originalUrl: originalUrl,
          cleanUrl: cleanUrl,
          domain: 'instagram.com',
          title: 'Instagram Profile (@$username)',
          description:
              'View photos, reels, and videos from @$username on Instagram',
          imageUrl:
              'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
          faviconUrl:
              'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
        );
      }

      // 4. General Fallback Card
      final username = isProfile ? segments.first : null;
      return WebLinkMetadata(
        originalUrl: originalUrl,
        cleanUrl: cleanUrl,
        domain: 'instagram.com',
        title: isProfile
            ? 'Instagram Profile (@$username)'
            : (isReel ? 'Instagram Reel' : 'Instagram Post'),
        description: isProfile
            ? 'View photos, reels, and videos from @$username on Instagram'
            : 'Watch on Instagram',
        imageUrl:
            'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
        faviconUrl:
            'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
        isVideo: isReel,
      );
    }

    const agents = [
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148',
      'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
      'WhatsApp/2.24.1 A',
    ];

    for (final agent in agents) {
      try {
        final response = await http.get(
          uri,
          headers: {
            'User-Agent': agent,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
          },
        ).timeout(const Duration(seconds: 6));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final html = response.body;
          final meta = _parseHtml(
            html,
            cleanUrl,
            originalUrl,
            uri,
            domain,
            fallbackFavicon,
          );
          if (meta.hasContent) {
            return meta;
          }
        }
      } catch (e) {
        debugPrint('[LINK METADATA FETCH WARNING] agent=$agent: $e');
      }
    }

    return WebLinkMetadata(
      originalUrl: originalUrl,
      cleanUrl: cleanUrl,
      domain: domain,
      faviconUrl: fallbackFavicon,
    );
  }

  WebLinkMetadata _parseHtml(
      String html,
      String cleanUrl,
      String originalUrl,
      Uri uri,
      String domain,
      String? fallbackFavicon,
      ) {
    String? title =
    _extractMeta(html, ['og:title', 'twitter:title', 'title']);
    if (title == null || title.isEmpty) {
      final titleMatch = RegExp(
        r'<title[^>]*>([^<]+)</title>',
        caseSensitive: false,
      ).firstMatch(html);
      if (titleMatch != null) {
        title = titleMatch.group(1);
      }
    }

    String? description = _extractMeta(
      html,
      ['og:description', 'twitter:description', 'description'],
    );

    String? imageUrl = _extractMeta(
      html,
      [
        'og:image',
        'og:image:secure_url',
        'twitter:image',
        'twitter:image:src',
      ],
    );

    final widthStr = _extractMeta(html, ['og:image:width', 'twitter:image:width']);
    final heightStr = _extractMeta(html, ['og:image:height', 'twitter:image:height']);
    final imgW = double.tryParse(widthStr ?? '');
    final imgH = double.tryParse(heightStr ?? '');

    final ogType = _extractMeta(html, ['og:type'])?.toLowerCase() ?? '';
    final isVideo = ogType.contains('video') ||
        cleanUrl.contains('/reel/') ||
        cleanUrl.contains('/tv/') ||
        cleanUrl.contains('youtube.com') ||
        cleanUrl.contains('youtu.be');

    if (imageUrl != null && imageUrl.isNotEmpty) {
      imageUrl = imageUrl.replaceAll('&amp;', '&').trim();
      if (imageUrl.startsWith('//')) {
        imageUrl = '${uri.scheme}:$imageUrl';
      } else if (imageUrl.startsWith('/')) {
        imageUrl = '${uri.scheme}://${uri.host}$imageUrl';
      } else if (!imageUrl.startsWith('http://') &&
          !imageUrl.startsWith('https://')) {
        imageUrl = '${uri.scheme}://${uri.host}/$imageUrl';
      }
    }

    String? faviconUrl = _extractFavicon(html, uri) ?? fallbackFavicon;

    title = _cleanText(title);
    description = _cleanText(description);

    return WebLinkMetadata(
      originalUrl: originalUrl,
      cleanUrl: cleanUrl,
      domain: domain,
      title: title,
      description: description,
      imageUrl: imageUrl,
      faviconUrl: faviconUrl,
      imageWidth: imgW,
      imageHeight: imgH,
      isVideo: isVideo,
    );
  }

  String? _extractMeta(String html, List<String> propertyNames) {
    for (final name in propertyNames) {
      final escapedName = RegExp.escape(name);

      final p1 = '<meta\\s+[^>]*?(?:property|name)=["\']'
          '$escapedName'
          '["\']\\s+[^>]*?content=["\']([^"\']+)["\']';
      final pattern1 = RegExp(p1, caseSensitive: false, dotAll: true);
      var match = pattern1.firstMatch(html);
      if (match != null && match.group(1)?.isNotEmpty == true) {
        return match.group(1);
      }

      final p2 = '<meta\\s+[^>]*?content=["\']([^"\']+)["\']\\s+[^>]*?(?:property|name)=["\']'
          '$escapedName'
          '["\']';
      final pattern2 = RegExp(p2, caseSensitive: false, dotAll: true);
      match = pattern2.firstMatch(html);
      if (match != null && match.group(1)?.isNotEmpty == true) {
        return match.group(1);
      }
    }
    return null;
  }

  String? _extractFavicon(String html, Uri baseUri) {
    const p = '<link\\s+[^>]*?rel=["\'](?:shortcut )?icon["\']\\s+[^>]*?href=["\']([^"\']+)["\']';
    final iconRegex = RegExp(p, caseSensitive: false);
    final match = iconRegex.firstMatch(html);
    if (match != null) {
      var href = match.group(1);
      if (href != null && href.isNotEmpty) {
        if (href.startsWith('//')) {
          return '${baseUri.scheme}:$href';
        } else if (href.startsWith('/')) {
          return '${baseUri.scheme}://${baseUri.host}$href';
        } else if (!href.startsWith('http://') &&
            !href.startsWith('https://')) {
          return '${baseUri.scheme}://${baseUri.host}/$href';
        }
        return href;
      }
    }
    return null;
  }

  String? _cleanText(String? input) {
    if (input == null || input.isEmpty) return null;
    var cleaned = input.replaceAll(RegExp(r'<[^>]*>'), '');
    cleaned = cleaned
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/')
        .replaceAll('&nbsp;', ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
