import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/features/chat/domain/services/attachment_cache_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';

import 'app_map.dart';

class PinImage {
  const PinImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final double width;
  final double height;
}

class PinRenderer {
  PinRenderer._();

  static final Map<String, PinImage> _cache = {};

  static Future<PinImage> render(AppMapMarker m, double dpr) async {
    final key =
        '${m.style}|${m.name}|${m.imagePath}|${m.color.toARGB32()}|${m.size}|$dpr';
    final hit = _cache[key];
    if (hit != null) return hit;

    final s = m.size;
    const tip = 9.0;
    const pad = 8.0;
    final w = s + pad * 2;
    final h = s + tip + pad * 2;

    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(dpr);
    final center = Offset(w / 2, pad + s / 2);

    if (m.style == AppMarkerStyle.redPin) {
      // Red teardrop pin
      final p = Paint()..color = const Color(0xFFEA4335);
      c.drawCircle(center, s * 0.38, p);
      c.drawPath(
        Path()
          ..moveTo(center.dx - 7, center.dy + s * 0.28)
          ..lineTo(center.dx + 7, center.dy + s * 0.28)
          ..lineTo(center.dx, center.dy + s * 0.5 + tip)
          ..close(),
        p,
      );
      c.drawCircle(center, s * 0.14, Paint()..color = Colors.white);
    } else {
      // Shadow under avatar
      c.drawCircle(
        center.translate(0, 2),
        s / 2,
        Paint()
          ..color = Colors.black26
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      // Coloured ring
      c.drawCircle(center, s / 2, Paint()..color = m.color);

      // Avatar image or initial fallback
      final r = s / 2 - 3;
      final img = await _loadAvatar(m.imagePath, (r * 2 * dpr).round());

      c.save();
      c.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));

      if (img != null) {
        c.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromCircle(center: center, radius: r),
          Paint()..filterQuality = FilterQuality.high,
        );
      } else {
        // Fallback initials or person icon matching IosAvatar styling
        c.drawRect(
          Rect.fromCircle(center: center, radius: r),
          Paint()..color = m.color.withValues(alpha: 0.85),
        );

        final cleanName = m.name.trim();
        final initialText = cleanName.isNotEmpty ? cleanName[0].toUpperCase() : '?';

        final tp = TextPainter(
          text: TextSpan(
            text: initialText,
            style: TextStyle(
              color: Colors.white,
              fontSize: s * 0.42,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
      }
      c.restore();

      // Bottom tip pointer
      c.drawPath(
        Path()
          ..moveTo(center.dx - 6, center.dy + s / 2 - 1)
          ..lineTo(center.dx + 6, center.dy + s / 2 - 1)
          ..lineTo(center.dx, center.dy + s / 2 + tip)
          ..close(),
        Paint()..color = m.color,
      );
    }

    final image = await rec
        .endRecording()
        .toImage((w * dpr).round(), (h * dpr).round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = PinImage(data!.buffer.asUint8List(), w, h);
    _cache[key] = out;
    return out;
  }

  static Future<ui.Image?> _loadAvatar(String? rawPath, int px) async {
    if (rawPath == null || rawPath.trim().isEmpty) return null;

    final resolved = resolveAvatarUrl(rawPath);
    if (resolved == null || resolved.trim().isEmpty) return null;

    try {
      Uint8List? bytes;

      if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
        final cachedPath =
            AttachmentCacheService.instance.resolveLocalPathSync(resolved) ??
                await AttachmentCacheService.instance.resolveLocalPath(resolved);

        if (cachedPath != null && File(cachedPath).existsSync()) {
          bytes = await File(cachedPath).readAsBytes();
        } else {
          final token = ServerApiService.instance.authToken;
          final headers = token != null
              ? {'Authorization': 'Bearer $token'}
              : <String, String>{};
          final response =
              await http.get(Uri.parse(resolved), headers: headers);

          if (response.statusCode >= 200 && response.statusCode < 300) {
            bytes = response.bodyBytes;
            try {
              final dir = await getApplicationDocumentsDirectory();
              final avatarsDir =
                  Directory('${dir.path}${Platform.pathSeparator}avatars');
              if (!avatarsDir.existsSync()) {
                await avatarsDir.create(recursive: true);
              }
              final safeName = resolved
                  .split('/')
                  .last
                  .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
              final file = File(
                '${avatarsDir.path}${Platform.pathSeparator}$safeName',
              );
              await file.writeAsBytes(bytes, flush: true);
              AttachmentCacheService.instance.updateCache(resolved, file.path);
            } catch (_) {}
          }
        }
      } else {
        final file = File(resolved);
        if (file.existsSync()) {
          bytes = await file.readAsBytes();
        }
      }

      if (bytes == null || bytes.isEmpty) return null;

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: px > 0 ? px : null,
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
}
