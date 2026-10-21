import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Data model representing website OpenGraph metadata.
class WebLinkMetadata {
  final String originalUrl;
  final String cleanUrl;
  final String domain;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? faviconUrl;

  WebLinkMetadata({
    required this.originalUrl,
    required this.cleanUrl,
    required this.domain,
    this.title,
    this.description,
    this.imageUrl,
    this.faviconUrl,
  });

  bool get hasDetails =>
      (title != null && title!.isNotEmpty) ||
      (description != null && description!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);
}

/// Singleton Service to fetch and cache website OpenGraph metadata.
class WebLinkMetadataService {
  WebLinkMetadataService._();

  static final WebLinkMetadataService instance = WebLinkMetadataService._();

  final Map<String, WebLinkMetadata> _cache = {};
  final Map<String, Future<WebLinkMetadata>> _inFlight = {};

  /// Retrieves cached metadata or fetches OpenGraph data from the website.
  Future<WebLinkMetadata> getMetadata(String urlStr) async {
    var cleanUrl = urlStr.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    if (_cache.containsKey(cleanUrl)) {
      return _cache[cleanUrl]!;
    }

    if (_inFlight.containsKey(cleanUrl)) {
      return _inFlight[cleanUrl]!;
    }

    final future = _fetch(cleanUrl, urlStr);
    _inFlight[cleanUrl] = future;
    final result = await future;
    _cache[cleanUrl] = result;
    _inFlight.remove(cleanUrl);
    return result;
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

    try {
      final response = await http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 WhatsApp/2.23.23',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final html = response.body;
        return _parseHtml(
          html,
          cleanUrl,
          originalUrl,
          uri,
          domain,
          fallbackFavicon,
        );
      }
    } catch (e) {
      debugPrint('[LINK METADATA FETCH ERROR] $e');
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

    if (imageUrl != null && imageUrl.isNotEmpty) {
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
