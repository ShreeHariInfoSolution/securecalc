import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

class DocPreview {
  final String thumbPath;
  final int pages;
  const DocPreview(this.thumbPath, this.pages);
}

class DocPreviewService {
  DocPreviewService._();
  static final instance = DocPreviewService._();
  final _mem = <String, DocPreview?>{};
  final _inflight = <String, Future<DocPreview?>>{};

  Future<DocPreview?> get(String pdfPath) {
    if (_mem.containsKey(pdfPath)) return Future.value(_mem[pdfPath]);
    return _inflight.putIfAbsent(
      pdfPath,
      () => _build(pdfPath).whenComplete(() => _inflight.remove(pdfPath)),
    );
  }

  Future<DocPreview?> _build(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return _mem[path] = null;

      final len = await file.length();
      if (len > 35 * 1024 * 1024) {
        return _mem[path] = null;
      }

      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(
        '${docs.path}${Platform.pathSeparator}chat_attachments${Platform.pathSeparator}thumbs',
      );
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      final key = path.hashCode.toUnsigned(32).toRadixString(16);
      final jpg = File('${dir.path}${Platform.pathSeparator}$key.jpg');
      final meta = File('${dir.path}${Platform.pathSeparator}$key.pages');

      if (jpg.existsSync() && meta.existsSync()) {
        final pagesStr = meta.readAsStringSync();
        final pages = int.tryParse(pagesStr) ?? 1;
        final preview = DocPreview(jpg.path, pages);
        _mem[path] = preview;
        return preview;
      }

      final doc = await PdfDocument.openFile(path);
      try {
        final pageCount = doc.pagesCount;
        final page = await doc.getPage(1);
        final pageImage = await page.render(
          width: 600,
          height: (600 * page.height / page.width).roundToDouble(),
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        await page.close();

        if (pageImage != null && pageImage.bytes.isNotEmpty) {
          await jpg.writeAsBytes(pageImage.bytes, flush: true);
          await meta.writeAsString('$pageCount', flush: true);
          final preview = DocPreview(jpg.path, pageCount);
          _mem[path] = preview;
          return preview;
        }

        final fallback = DocPreview('', pageCount);
        _mem[path] = fallback;
        return fallback;
      } finally {
        await doc.close();
      }
    } catch (e) {
      debugPrint('[PDF THUMBNAIL RENDER WARNING] $e');
      return _mem[path] = null;
    }
  }
}
