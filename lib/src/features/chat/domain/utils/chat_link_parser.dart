class ParsedMessageContent {
  final String originalMessage;
  final List<String> extractedUrls;
  final List<String> normalizedUrls;
  final String remainingText;
  final bool hasLinks;
  final bool isOnlyLinks;

  const ParsedMessageContent({
    required this.originalMessage,
    required this.extractedUrls,
    required this.normalizedUrls,
    required this.remainingText,
    required this.hasLinks,
    required this.isOnlyLinks,
  });

  String? get firstNormalizedUrl =>
      normalizedUrls.isNotEmpty ? normalizedUrls.first : null;
  String? get firstOriginalUrl =>
      extractedUrls.isNotEmpty ? extractedUrls.first : null;
}

class ChatLinkParser {
  static const Set<String> _fileExtensions = {
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'md',
    'csv',
    'zip',
    'rar',
    '7z',
    'tar',
    'gz',
    'apk',
    'dmg',
    'exe',
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'bmp',
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
    'mp3',
    'wav',
    'm4a',
    'aac',
    'ogg',
    'flac',
  };

  static final RegExp _urlRegex = RegExp(
    r'(?<![a-zA-Z0-9._%+-]+@)(?:(?:https?:\/\/)|(?:www\.))?[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(?::\d+)?(?:\/[^\s]*)?',
    caseSensitive: false,
  );

  static ParsedMessageContent parse(String rawMessage, {String? fileName}) {
    final trimmed = rawMessage.trim();
    if (trimmed.isEmpty) {
      return ParsedMessageContent(
        originalMessage: rawMessage,
        extractedUrls: const [],
        normalizedUrls: const [],
        remainingText: '',
        hasLinks: false,
        isOnlyLinks: false,
      );
    }

    final cleanFileName = (fileName ?? '').trim().toLowerCase();
    final cleanMsgLower = trimmed.toLowerCase();
    if (cleanFileName.isNotEmpty &&
        (cleanMsgLower == cleanFileName ||
            cleanMsgLower == cleanFileName.split('.').first)) {
      return ParsedMessageContent(
        originalMessage: rawMessage,
        extractedUrls: const [],
        normalizedUrls: const [],
        remainingText: rawMessage,
        hasLinks: false,
        isOnlyLinks: false,
      );
    }

    final extractedUrls = <String>[];
    final normalizedUrls = <String>[];
    final matches = _urlRegex.allMatches(rawMessage);

    var textWithoutUrls = rawMessage;

    for (final match in matches) {
      var rawUrl = match.group(0)?.trim() ?? '';
      if (rawUrl.isEmpty) continue;

      // Clean trailing punctuation without corrupting valid parameters/paths
      while (rawUrl.endsWith('.') ||
          rawUrl.endsWith(',') ||
          rawUrl.endsWith('!') ||
          rawUrl.endsWith('?') ||
          rawUrl.endsWith(';') ||
          rawUrl.endsWith(':') ||
          rawUrl.endsWith(')')) {
        if (rawUrl.endsWith(')')) {
          final openCount = '('.allMatches(rawUrl).length;
          final closeCount = ')'.allMatches(rawUrl).length;
          if (closeCount > openCount) {
            rawUrl = rawUrl.substring(0, rawUrl.length - 1).trim();
            continue;
          } else {
            break;
          }
        }
        rawUrl = rawUrl.substring(0, rawUrl.length - 1).trim();
      }

      if (rawUrl.isEmpty) continue;

      final lowerRaw = rawUrl.toLowerCase();
      final hasScheme =
          lowerRaw.startsWith('http://') || lowerRaw.startsWith('https://');
      final hasWww = lowerRaw.startsWith('www.');

      // If it has NO scheme and NO www, check if extension is a file extension
      if (!hasScheme && !hasWww) {
        final lastDotIndex = lowerRaw.lastIndexOf('.');
        if (lastDotIndex > 0) {
          final ext = lowerRaw
              .substring(lastDotIndex + 1)
              .split('/')
              .first
              .split('?')
              .first;
          if (_fileExtensions.contains(ext)) {
            // It's a file name like "RONINUserManual.pdf", NOT a website URL!
            continue;
          }
        }
      }

      var normalized = rawUrl;
      if (!normalized.startsWith('http://') &&
          !normalized.startsWith('https://')) {
        normalized = 'https://$normalized';
      }

      final uri = Uri.tryParse(normalized);
      if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
        continue;
      }

      final tld = uri.host.split('.').last.toLowerCase();
      if (tld.length < 2 || RegExp(r'^\d+$').hasMatch(tld)) {
        continue;
      }

      if (!extractedUrls.contains(rawUrl)) {
        extractedUrls.add(rawUrl);
        normalizedUrls.add(normalized);
      }

      textWithoutUrls = textWithoutUrls.replaceAll(rawUrl, '').trim();
    }

    textWithoutUrls = textWithoutUrls.trim();

    final hasLinks = extractedUrls.isNotEmpty;
    final isOnlyLinks = hasLinks && textWithoutUrls.isEmpty;

    return ParsedMessageContent(
      originalMessage: rawMessage,
      extractedUrls: extractedUrls,
      normalizedUrls: normalizedUrls,
      remainingText: textWithoutUrls,
      hasLinks: hasLinks,
      isOnlyLinks: isOnlyLinks,
    );
  }
}
