import 'dart:io';
import 'package:flutter/material.dart';

String fileExtension(String name) {
  final i = name.lastIndexOf('.');
  return (i < 0 || i == name.length - 1) ? '' : name.substring(i + 1).toLowerCase();
}

class FileTypeVisual {
  final String label;
  final Color color;
  const FileTypeVisual(this.label, this.color);

  static FileTypeVisual of(String ext) {
    switch (ext) {
      case 'pdf':
        return const FileTypeVisual('PDF', Color(0xFFD7263D));
      case 'doc':
      case 'docx':
      case 'rtf':
      case 'odt':
        return const FileTypeVisual('DOC', Color(0xFF2B6CB0));
      case 'xls':
      case 'xlsx':
      case 'csv':
      case 'ods':
        return const FileTypeVisual('XLS', Color(0xFF1E8E4E));
      case 'ppt':
      case 'pptx':
      case 'key':
        return const FileTypeVisual('PPT', Color(0xFFD9622B));
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return const FileTypeVisual('ZIP', Color(0xFF8D6E63));
      case 'apk':
        return const FileTypeVisual('APK', Color(0xFF2E9E5B));
      case 'mp3':
      case 'm4a':
      case 'wav':
      case 'aac':
      case 'ogg':
        return const FileTypeVisual('AUD', Color(0xFF7E57C2));
      default:
        final l = ext.isEmpty ? 'FILE' : ext.toUpperCase();
        return FileTypeVisual(
          l.length > 4 ? l.substring(0, 4) : l,
          const Color(0xFF6B7780),
        );
    }
  }
}

class FileTypeBadge extends StatelessWidget {
  final String ext;
  final double size;
  const FileTypeBadge({super.key, required this.ext, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final v = FileTypeVisual.of(ext);
    return SizedBox(
      width: size * 0.82,
      height: size,
      child: CustomPaint(painter: _PagePainter(v.color, v.label)),
    );
  }
}

class _PagePainter extends CustomPainter {
  final Color color;
  final String label;
  _PagePainter(this.color, this.label);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height, f = w * 0.34, r = w * 0.12;
    final page = Path()
      ..moveTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(w - f, 0)
      ..lineTo(w, f)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..close();
    c.drawPath(page, Paint()..color = color);

    final fold = Path()
      ..moveTo(w - f, 0)
      ..lineTo(w - f, f)
      ..lineTo(w, f)
      ..close();
    c.drawPath(fold, Paint()..color = Colors.white.withValues(alpha: 0.4));

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: label.length > 3 ? h * 0.20 : h * 0.25,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: w);
    tp.paint(c, Offset((w - tp.width) / 2, h * 0.58));
  }

  @override
  bool shouldRepaint(_PagePainter o) => o.color != color || o.label != label;
}

class DocumentCard extends StatelessWidget {
  final String fileName;
  final double width;
  final bool isMe, isDark;
  final String? sizeText, thumbPath;
  final int? pages;
  final bool transferring, needsDownload;
  final double? progress;
  final VoidCallback? onTap, onCancel;

  const DocumentCard({
    super.key,
    required this.fileName,
    required this.width,
    required this.isMe,
    required this.isDark,
    this.sizeText,
    this.thumbPath,
    this.pages,
    this.transferring = false,
    this.needsDownload = false,
    this.progress,
    this.onTap,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final ext = fileExtension(fileName);
    final isPdf = ext == 'pdf';
    final fg = (isMe || isDark) ? Colors.white : const Color(0xFF111B21);
    final bg = isMe
        ? Colors.black.withValues(alpha: .22)
        : (isDark
            ? Colors.white.withValues(alpha: .09)
            : Colors.black.withValues(alpha: .06));

    final pageStr = pages != null && pages! > 0
        ? (pages == 1 ? '1 page' : '$pages pages')
        : null;

    final metaParts = <String>[
      ?pageStr,
      if (sizeText != null && sizeText!.isNotEmpty) sizeText!,
      if (ext.isNotEmpty) ext,
    ];
    final meta = metaParts.join(' • ');

    final Widget leading = transferring
        ? SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: (progress ?? 0) > 0 ? progress : null,
                  strokeWidth: 2.5,
                  color: fg,
                ),
                GestureDetector(
                  onTap: onCancel,
                  child: Icon(Icons.close_rounded, size: 18, color: fg),
                ),
              ],
            ),
          )
        : needsDownload
            ? Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fg.withValues(alpha: .16),
                ),
                child: Icon(Icons.arrow_downward_rounded, size: 22, color: fg),
              )
            : FileTypeBadge(ext: ext, size: 44);

    final hasThumb = isPdf &&
        thumbPath != null &&
        thumbPath!.isNotEmpty &&
        File(thumbPath!).existsSync();

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: width,
          color: bg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section A: PDF First-Page Preview
              if (isPdf)
                Container(
                  height: 200,
                  width: double.infinity,
                  color: isDark ? const Color(0xFF1A262C) : const Color(0xFFECEFF1),
                  child: hasThumb
                      ? Image.file(
                          File(thumbPath!),
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          cacheWidth: 800,
                          errorBuilder: (_, __, ___) => _buildPdfPlaceholder(fg, isDark),
                        )
                      : _buildPdfPlaceholder(fg, isDark),
                ),

              // Section B: File Information Panel
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    leading,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          if (meta.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                meta,
                                style: TextStyle(
                                  color: fg.withValues(alpha: .65),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPdfPlaceholder(Color fg, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.picture_as_pdf_rounded,
            size: 44,
            color: const Color(0xFFD7263D).withValues(alpha: 0.8),
          ),
          const SizedBox(height: 6),
          Text(
            'PDF Document',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
