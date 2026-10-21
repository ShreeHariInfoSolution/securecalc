import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/services/web_link_metadata_service.dart';

/// WhatsApp-style Rich Link Preview Card with OpenGraph Image, Title, Description & Domain.
class RichLinkPreviewCard extends StatefulWidget {
  final String url;
  final bool isMe;
  final bool isDark;

  const RichLinkPreviewCard({
    super.key,
    required this.url,
    required this.isMe,
    required this.isDark,
  });

  @override
  State<RichLinkPreviewCard> createState() => _RichLinkPreviewCardState();
}

class _RichLinkPreviewCardState extends State<RichLinkPreviewCard> {
  late Future<WebLinkMetadata> _metadataFuture;

  @override
  void initState() {
    super.initState();
    _metadataFuture = WebLinkMetadataService.instance.getMetadata(widget.url);
  }

  @override
  void didUpdateWidget(RichLinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _metadataFuture =
          WebLinkMetadataService.instance.getMetadata(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WebLinkMetadata>(
      future: _metadataFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting && data == null;

        return _buildCardContent(context, data, isLoading);
      },
    );
  }

  Widget _buildCardContent(
    BuildContext context,
    WebLinkMetadata? data,
    bool isLoading,
  ) {
    final cleanUrl = data?.cleanUrl ?? widget.url;
    final domain = data?.domain ?? _extractDomain(widget.url);
    final title = data?.title ?? domain.toUpperCase();
    final description = data?.description;
    final imageUrl = data?.imageUrl;
    final faviconUrl = data?.faviconUrl;

    // WhatsApp style card colors
    final cardBg = widget.isMe
        ? const Color(0xFF025143).withValues(alpha: 0.88)
        : (widget.isDark
            ? const Color(0xFF1F2C34)
            : const Color(0xFFE9EDEF));

    final titleColor = widget.isMe
        ? Colors.white
        : (widget.isDark ? Colors.white : const Color(0xFF111B21));

    final descColor = widget.isMe
        ? Colors.white.withValues(alpha: 0.85)
        : (widget.isDark ? Colors.white70 : const Color(0xFF667781));

    final domainColor = widget.isMe
        ? Colors.white.withValues(alpha: 0.90)
        : AppTheme.primaryColor;

    return GestureDetector(
      onTap: () async {
        try {
          final uri = Uri.tryParse(cleanUrl);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } catch (e) {
          debugPrint('[LINK LAUNCH ERROR] $e');
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 2),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isMe
                ? Colors.white.withValues(alpha: 0.15)
                : (widget.isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08)),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: widget.isDark ? 0.25 : 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── 1. TOP PREVIEW IMAGE (WhatsApp Style) ──────────────────────
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              SizedBox(
                height: 185,
                width: double.infinity,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: widget.isDark ? Colors.white10 : Colors.black12,
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ] else if (isLoading) ...[
              // Shimmer placeholder loading header
              Container(
                height: 110,
                width: double.infinity,
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
            ],

            // ─── 2. TITLE & DESCRIPTION ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                      color: titleColor,
                    ),
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.32,
                        color: descColor,
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  // ─── 3. DOMAIN ROW (WhatsApp Style) ───────────────────────
                  Row(
                    children: [
                      Icon(
                        Icons.link_rounded,
                        size: 14,
                        color: domainColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          domain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: domainColor,
                          ),
                        ),
                      ),
                      if (faviconUrl != null && faviconUrl.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            faviconUrl,
                            width: 14,
                            height: 14,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.open_in_new_rounded,
                              size: 13,
                              color: domainColor,
                            ),
                          ),
                        ),
                      ] else ...[
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 13,
                          color: domainColor,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _extractDomain(String urlStr) {
    var clean = urlStr.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'https://$clean';
    }
    final uri = Uri.tryParse(clean);
    return uri?.host.replaceAll('www.', '') ?? clean;
  }
}
