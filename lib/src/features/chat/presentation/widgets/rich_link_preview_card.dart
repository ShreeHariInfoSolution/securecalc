import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/services/web_link_metadata_service.dart';

class RichLinkPreviewCard extends StatefulWidget {
  final String url;
  final bool isMe;
  final bool isDark;
  final double width;

  const RichLinkPreviewCard({
    super.key,
    required this.url,
    required this.isMe,
    required this.isDark,
    required this.width,
  });

  @override
  State<RichLinkPreviewCard> createState() => _RichLinkPreviewCardState();
}

class _RichLinkPreviewCardState extends State<RichLinkPreviewCard> {
  WebLinkMetadata? _data;
  bool _isLoading = true;
  double? _resolvedAspect;
  String? _loadedImageUrl;

  void _resolveImageAspect(WebLinkMetadata d) {
    final localPath = d.localImagePath;
    final url = (d.imageUrl ?? '').replaceAll('&amp;', '&').trim();
    final key = localPath ?? url;
    if (_loadedImageUrl == key || key.isEmpty) return;
    _loadedImageUrl = key;

    try {
      final ImageProvider provider =
          (localPath != null && File(localPath).existsSync())
              ? FileImage(File(localPath))
              : NetworkImage(url) as ImageProvider;

      final stream = provider.resolve(const ImageConfiguration());
      stream.addListener(ImageStreamListener(
        (info, _) {
          if (mounted && _loadedImageUrl == key) {
            final w = info.image.width.toDouble();
            final h = info.image.height.toDouble();
            if (w > 0 && h > 0) {
              final aspect = (w / h).clamp(0.68, 1.91);
              if (_resolvedAspect != aspect) {
                setState(() {
                  _resolvedAspect = aspect;
                });
              }
            }
          }
        },
        onError: (exception, stackTrace) {
          debugPrint('[LINK PREVIEW IMAGE LOAD ERROR] $exception');
        },
      ));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(RichLinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _data = null;
      _isLoading = true;
      _resolvedAspect = null;
      _loadedImageUrl = null;
      _resolve();
    }
  }

  void _resolve() {
    final url = widget.url;
    final cached = WebLinkMetadataService.instance.peek(url);
    if (cached != null) {
      _data = cached;
      _isLoading = false;
      return;
    }

    _isLoading = true;
    WebLinkMetadataService.instance.getMetadata(url).then((d) {
      if (mounted && widget.url == url) {
        setState(() {
          _data = d;
          _isLoading = false;
        });
      }
    }).catchError((_) {
      if (mounted && widget.url == url) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _open() async {
    var u = (_data?.cleanUrl ?? widget.url).trim();
    if (!u.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      u = 'https://$u';
    }
    final uri = Uri.tryParse(u);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = (widget.isMe || widget.isDark) ? Colors.white : const Color(0xFF111B21);
    final bg = widget.isMe
        ? Colors.black.withValues(alpha: .18)
        : (widget.isDark
        ? Colors.white.withValues(alpha: .07)
        : Colors.black.withValues(alpha: .06));

    final uri = Uri.tryParse(
      widget.url.startsWith('http') ? widget.url : 'https://${widget.url}',
    );
    final domain = _data?.domain.isNotEmpty == true
        ? _data!.domain
        : (uri?.host.replaceAll('www.', '') ?? widget.url);
    final faviconUrl = _data?.faviconUrl ??
        (uri != null
            ? 'https://www.google.com/s2/favicons?domain=${uri.host}&sz=64'
            : null);

    Widget content;

    if (_isLoading && _data == null) {
      content = _buildLoadingCard(fg, bg, domain, faviconUrl);
    } else if (_data != null && _data!.hasContent) {
      content = _buildRichCard(_data!, fg, bg, domain, faviconUrl);
    } else {
      content = _buildFallbackCard(fg, bg, domain, faviconUrl);
    }

    return GestureDetector(
      onTap: _open,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: widget.width,
            color: bg,
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard(
      Color fg, Color bg, String domain, String? faviconUrl) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: fg.withValues(alpha: .7),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Fetching preview…',
                  style: TextStyle(
                    color: fg.withValues(alpha: .5),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackCard(
      Color fg, Color bg, String domain, String? faviconUrl) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: (faviconUrl != null && faviconUrl.isNotEmpty)
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                faviconUrl,
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.link_rounded,
                  color: fg.withValues(alpha: .7),
                  size: 20,
                ),
              ),
            )
                : Icon(
              Icons.link_rounded,
              color: fg.withValues(alpha: .7),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: .65),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_outward_rounded,
            size: 16,
            color: fg.withValues(alpha: .6),
          ),
        ],
      ),
    );
  }

  Widget _buildRichCard(WebLinkMetadata d, Color fg, Color bg, String domain,
      String? faviconUrl) {
    final title = (d.title ?? '').trim();
    final desc = (d.description ?? '').trim();
    final showTitle =
        title.isNotEmpty && title.toLowerCase() != domain.toLowerCase();
    final hasImage = (d.imageUrl ?? '').isNotEmpty;
    final compact = hasImage && d.imageWidth != null && d.imageWidth! < 300;

    final body = Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTitle)
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg.withValues(alpha: .65),
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.link_rounded, size: 14, color: fg.withValues(alpha: .7)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: .85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if ((d.faviconUrl ?? '').isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    d.faviconUrl!,
                    width: 16,
                    height: 16,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    Widget networkImageFallback() {
      final cleanUrl = (d.imageUrl ?? '').replaceAll('&amp;', '&').trim();
      return Image.network(
        cleanUrl,
        fit: BoxFit.cover,
        cacheWidth: 700,
        loadingBuilder: (_, child, p) =>
            p == null ? child : Container(color: fg.withValues(alpha: .08)),
        errorBuilder: (_, __, ___) => Container(
          color: fg.withValues(alpha: .08),
          child: Icon(Icons.link_rounded, color: fg.withValues(alpha: .4)),
        ),
      );
    }

    Widget image() {
      final localPath = d.localImagePath;
      if (localPath != null && File(localPath).existsSync()) {
        return Image.file(
          File(localPath),
          fit: BoxFit.cover,
          cacheWidth: 700,
          errorBuilder: (_, __, ___) => networkImageFallback(),
        );
      }
      return networkImageFallback();
    }

    if (hasImage && d.imageUrl != null) {
      _resolveImageAspect(d);
    }

    final double effectiveAspect = _resolvedAspect ??
        (d.imageAspect ?? (d.isVideo ? 0.8 : 1.3)).clamp(0.68, 1.91);

    return compact
        ? Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 80, height: 80, child: image()),
        Expanded(child: body),
      ],
    )
        : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasImage)
          AspectRatio(
            aspectRatio: effectiveAspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                image(),
                if (d.isVideo)
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .88),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 32,
                        color: Color(0xFF2C2C2E),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        body,
      ],
    );
  }
}
