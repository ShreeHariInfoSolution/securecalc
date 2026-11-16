import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../../core/config/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/app_video_player.dart';
import 'app_camera_page.dart';
import 'video_export_service.dart';
import 'video_preview_pane.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public result (unchanged API)
// ─────────────────────────────────────────────────────────────────────────────

class ImageEditorResult {
  final List<File> images;
  final List<String> captions;
  final String caption;
  final bool isHd;

  ImageEditorResult({
    required this.images,
    this.captions = const [],
    required this.caption,
    this.isHd = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit model
//
// All overlay coordinates (strokes / texts) are normalized (0..1) in the
// ROTATED, UNCROPPED image space. Stroke width and text size are fractions of
// that space's width. Because of that, changing the crop never moves overlays,
// and preview + export use the exact same paint routine (WYSIWYG).
// ─────────────────────────────────────────────────────────────────────────────

final Rect _kFull = Rect.fromLTWH(0, 0, 1, 1);

const List<Color> _kPalette = [
  Colors.white,
  Colors.black,
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFD60A),
  Color(0xFF34C759),
  Color(0xFF32ADE6),
  Color(0xFF007AFF),
  Color(0xFFAF52DE),
  Color(0xFFFF2D55),
];

class _Stroke {
  List<Offset> pts;
  final Color color;
  double width;
  final bool highlighter;
  _Stroke(this.pts, this.color, this.width, this.highlighter);
  _Stroke copy() => _Stroke(List.of(pts), color, width, highlighter);
}

class _TextItem {
  String text;
  Offset center;
  double size;
  double rotation;
  Color color;
  bool filled;
  _TextItem({
    required this.text,
    required this.center,
    this.size = 0.075,
    this.rotation = 0,
    this.color = Colors.white,
    this.filled = false,
  });
  _TextItem copy() => _TextItem(
    text: text,
    center: center,
    size: size,
    rotation: rotation,
    color: color,
    filled: filled,
  );
}

class _Snap {
  final int turns;
  final Rect crop;
  final List<_Stroke> strokes;
  final List<_TextItem> texts;
  _Snap(this.turns, this.crop, this.strokes, this.texts);
}

class _EditItem {
  final File file;
  final bool isVideo;
  ui.Image? image; // preview-resolution decode
  int turns = 0;
  Rect crop = _kFull;
  List<_Stroke> strokes = [];
  List<_TextItem> texts = [];
  String caption = '';
  VideoEdit? video;
  Uint8List? videoThumb;

  _EditItem(this.file, this.isVideo, {this.caption = ''});

  double get _iw => (image?.width ?? 1).toDouble();
  double get _ih => (image?.height ?? 1).toDouble();
  double get rotW => turns.isOdd ? _ih : _iw;
  double get rotH => turns.isOdd ? _iw : _ih;

  bool get isCropped =>
      crop.left > 0.001 ||
          crop.top > 0.001 ||
          crop.width < 0.999 ||
          crop.height < 0.999;

  bool get isEdited =>
      turns != 0 ||
      isCropped ||
      strokes.isNotEmpty ||
      texts.isNotEmpty ||
      (video?.isEdited ?? false);

  double get viewAspect => (crop.width * rotW) / (crop.height * rotH);

  _Snap snapshot() => _Snap(
    turns,
    crop,
    strokes.map((s) => s.copy()).toList(),
    texts.map((t) => t.copy()).toList(),
  );

  void restore(_Snap s) {
    turns = s.turns;
    crop = s.crop;
    strokes = s.strokes;
    texts = s.texts;
  }

  /// Rotates 90° clockwise and remaps everything.
  void rotateCw() {
    final k = rotW / rotH; // old width / old height
    Offset m(Offset p) => Offset(1 - p.dy, p.dx);
    for (final s in strokes) {
      s.pts = s.pts.map(m).toList();
      s.width *= k;
    }
    for (final t in texts) {
      t.center = m(t.center);
      t.size *= k;
      t.rotation += math.pi / 2;
    }
    crop = rotateRectCw(crop);
    turns = (turns + 1) % 4;
  }
}

Rect rotateRectCw(Rect r) =>
    Rect.fromLTWH(1 - (r.top + r.height), r.left, r.height, r.width);

// ─────────────────────────────────────────────────────────────────────────────
// Shared paint routine (preview + export)
// ─────────────────────────────────────────────────────────────────────────────

class _TextLayout {
  final TextPainter tp;
  final Size box;
  final double pad;
  _TextLayout(this.tp, this.box, this.pad);
}

_TextLayout _layoutText(_TextItem t, double fontPx, double maxW) {
  final fg = t.filled
      ? (t.color.computeLuminance() > 0.6 ? Colors.black : Colors.white)
      : t.color;
  final tp = TextPainter(
    text: TextSpan(
      text: t.text,
      style: TextStyle(
        color: fg,
        fontSize: fontPx,
        fontWeight: FontWeight.w700,
        height: 1.2,
        shadows: t.filled
            ? null
            : [
          Shadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: fontPx * 0.12,
          ),
        ],
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    textWidthBasis: TextWidthBasis.longestLine,
  )..layout(maxWidth: math.max(10, maxW));
  final pad = t.filled ? fontPx * 0.35 : fontPx * 0.08;
  return _TextLayout(tp, Size(tp.width + pad * 2, tp.height + pad * 2), pad);
}

void _paintEdit(
    Canvas canvas,
    Size out,
    ui.Image img,
    int turns,
    Rect crop,
    List<_Stroke> strokes,
    List<_TextItem> texts,
    ) {
  final iw = img.width.toDouble();
  final ih = img.height.toDouble();
  final rw = turns.isOdd ? ih : iw;
  final pxW = out.width / crop.width; // output px of the full rotated width
  final pxH = out.height / crop.height;
  final s = pxW / rw; // image px -> output px

  // 1) base image (rotated + cropped)
  canvas.save();
  canvas.clipRect(Offset.zero & out);
  canvas.scale(s);
  canvas.translate(-crop.left * rw, -crop.top * (turns.isOdd ? iw : ih));
  switch (turns % 4) {
    case 1:
      canvas.translate(ih, 0);
      canvas.rotate(math.pi / 2);
      break;
    case 2:
      canvas.translate(iw, ih);
      canvas.rotate(math.pi);
      break;
    case 3:
      canvas.translate(0, iw);
      canvas.rotate(math.pi * 1.5);
      break;
  }
  canvas.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, iw, ih),
    Rect.fromLTWH(0, 0, iw, ih),
    Paint()..filterQuality = FilterQuality.medium,
  );
  canvas.restore();

  Offset toOut(Offset p) =>
      Offset((p.dx - crop.left) * pxW, (p.dy - crop.top) * pxH);

  canvas.save();
  canvas.clipRect(Offset.zero & out);

  // 2) strokes
  for (final st in strokes) {
    if (st.pts.isEmpty) continue;
    final color =
    st.highlighter ? st.color.withValues(alpha: 0.4) : st.color;
    final w = st.width * pxW;
    if (st.pts.length == 1) {
      canvas.drawCircle(
        toOut(st.pts.first),
        w / 2,
        Paint()
          ..color = color
          ..isAntiAlias = true,
      );
      continue;
    }
    final pts = st.pts.map(toOut).toList();
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final mid = Offset(
        (pts[i - 1].dx + pts[i].dx) / 2,
        (pts[i - 1].dy + pts[i].dy) / 2,
      );
      path.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w
        ..isAntiAlias = true,
    );
  }

  // 3) texts
  for (final t in texts) {
    final fontPx = t.size * pxW;
    final l = _layoutText(t, fontPx, pxW * 0.85);
    canvas.save();
    canvas.translate(toOut(t.center).dx, toOut(t.center).dy);
    canvas.rotate(t.rotation);
    if (t.filled) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: l.box.width,
            height: l.box.height,
          ),
          Radius.circular(fontPx * 0.3),
        ),
        Paint()..color = t.color,
      );
    }
    l.tp.paint(canvas, Offset(-l.tp.width / 2, -l.tp.height / 2));
    canvas.restore();
  }
  canvas.restore();
}

class _EditPainter extends CustomPainter {
  final _EditItem item;
  final bool full; // ignore crop (used by crop screen)
  _EditPainter(this.item, {this.full = false});

  @override
  void paint(Canvas canvas, Size size) {
    final img = item.image;
    if (img == null) return;
    _paintEdit(
      canvas,
      size,
      img,
      item.turns,
      full ? _kFull : item.crop,
      item.strokes,
      item.texts,
    );
  }

  @override
  bool shouldRepaint(covariant _EditPainter old) => true;
}

Future<ui.Image?> _decodeImage(File f, int maxSide) async {
  try {
    final bytes = await f.readAsBytes();
    final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buf);
    final w = desc.width, h = desc.height;
    int? tw, th;
    if (math.max(w, h) > maxSide) {
      if (w >= h) {
        tw = maxSide;
      } else {
        th = maxSide;
      }
    }
    final codec = await desc.instantiateCodec(targetWidth: tw, targetHeight: th);
    final frame = await codec.getNextFrame();
    codec.dispose();
    desc.dispose();
    buf.dispose();
    return frame.image;
  } catch (e) {
    debugPrint('[EDITOR DECODE ERROR] $e');
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

enum _Mode { view, draw, crop }

class _AspectOption {
  final String label;
  final double? ratio; // w/h in pixels
  final bool original;
  const _AspectOption(this.label, this.ratio, {this.original = false});
}

const List<_AspectOption> _kAspects = [
  _AspectOption('Free', null),
  _AspectOption('Original', null, original: true),
  _AspectOption('1:1', 1),
  _AspectOption('3:4', 3 / 4),
  _AspectOption('4:3', 4 / 3),
  _AspectOption('9:16', 9 / 16),
  _AspectOption('16:9', 16 / 9),
];

class ImagePreviewEditorPage extends StatefulWidget {
  final List<File> imageFiles;
  final String? initialCaption;
  final String? recipientName;

  const ImagePreviewEditorPage({
    super.key,
    required this.imageFiles,
    this.initialCaption,
    this.recipientName,
  });

  static Future<ImageEditorResult?> open(
    BuildContext context, {
    required List<File> files,
    String? recipientName,
    String? initialCaption,
  }) {
    return Navigator.of(context).push<ImageEditorResult>(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => ImagePreviewEditorPage(
          imageFiles: files,
          recipientName: recipientName,
          initialCaption: initialCaption,
        ),
        transitionsBuilder: (_, a, __, child) {
          final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: c,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(c),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<ImagePreviewEditorPage> createState() =>
      _ImagePreviewEditorPageState();
}

class _ImagePreviewEditorPageState extends State<ImagePreviewEditorPage>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _caption = TextEditingController();
  final PageController _page = PageController();

  final List<_EditItem> _items = [];
  int _index = 0;
  _Mode _mode = _Mode.view;
  bool _isHd = false;
  bool _sending = false;
  bool _lockPaging = false;

  // draw
  Color _color = const Color(0xFFFF3B30);
  bool _highlighter = false;

  // crop
  Rect _draft = _kFull;
  double? _cropAspect;
  int _aspectIdx = 0;
  _Snap? _backup;

  // pointer state
  final Map<int, Offset> _ptrs = {};
  _Stroke? _liveStroke;
  int _activeText = -1;
  Offset _dragStart = Offset.zero;
  Offset _textStartCenter = Offset.zero;
  double _pinchDist = 1, _pinchAngle = 0, _textStartSize = 0, _textStartRot = 0;
  bool _tapCandidate = false;
  DateTime _downAt = DateTime.now();
  bool _overTrash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (int i = 0; i < widget.imageFiles.length; i++) {
      final f = widget.imageFiles[i];
      final item = _makeItem(f);
      if (i == 0 && widget.initialCaption != null && widget.initialCaption!.isNotEmpty) {
        item.caption = widget.initialCaption!;
      }
      _items.add(item);
    }
    if (_items.isNotEmpty) {
      _caption.text = _items[0].caption;
    }
  }

  void _onCaptionChanged(String text) {
    if (_index >= 0 && _index < _items.length) {
      _items[_index].caption = text;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _caption.dispose();
    _page.dispose();
    for (final i in _items) {
      i.image?.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      AppPreferences.isPickerActive = false;
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  bool _isVideoPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'mkv', 'avi', '3gp', 'webm', 'm4v', '3g2', 'ts', 'flv']
        .contains(ext);
  }

  _EditItem _makeItem(File f) {
    final item = _EditItem(f, _isVideoPath(f.path));
    if (item.isVideo) {
      item.video = VideoEdit();
      VideoThumbnail.thumbnailData(
        video: f.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 160,
        quality: 60,
      ).then((d) {
        if (mounted) setState(() => item.videoThumb = d);
      });
    } else {
      _decodeImage(f, 1600).then((img) {
        if (!mounted) {
          img?.dispose();
          return;
        }
        setState(() => item.image = img);
      });
    }
    return item;
  }

  bool get _anyEdited => _items.any((i) => i.isEdited);
  _EditItem get _cur => _items[_index];

  // ── crop mode ─────────────────────────────────────────────────────────────

  void _enterCrop() {
    final it = _cur;
    if (it.isVideo || it.image == null) return;
    _backup = it.snapshot();
    _draft = it.crop;
    _cropAspect = null;
    _aspectIdx = 0;
    setState(() => _mode = _Mode.crop);
  }

  void _applyCrop() {
    final it = _cur;
    var r = _draft;
    r = Rect.fromLTRB(
      r.left.clamp(0.0, 1.0),
      r.top.clamp(0.0, 1.0),
      r.right.clamp(0.0, 1.0),
      r.bottom.clamp(0.0, 1.0),
    );
    it.crop = r;
    _backup = null;
    setState(() => _mode = _Mode.view);
  }

  void _cancelCrop() {
    if (_backup != null) _cur.restore(_backup!);
    _backup = null;
    setState(() => _mode = _Mode.view);
  }

  void _rotateInCrop() {
    HapticFeedback.selectionClick();
    final it = _cur;
    it.rotateCw();
    setState(() {
      _draft = rotateRectCw(_draft);
      if (_cropAspect != null) _cropAspect = 1 / _cropAspect!;
    });
  }

  void _resetCrop() {
    final it = _cur;
    while (it.turns != 0) {
      it.rotateCw();
    }
    setState(() {
      it.crop = _kFull;
      _draft = _kFull;
      _cropAspect = null;
      _aspectIdx = 0;
    });
  }

  void _setAspect(int idx) {
    final opt = _kAspects[idx];
    final it = _cur;
    final rw = it.rotW, rh = it.rotH;
    double? a = opt.ratio;
    if (opt.original) a = rw / rh;
    setState(() {
      _aspectIdx = idx;
      _cropAspect = a;
      if (a != null) {
        double wn = 1;
        double hn = wn * rw / (a * rh);
        if (hn > 1) {
          hn = 1;
          wn = a * rh / rw;
        }
        _draft = Rect.fromCenter(
          center: const Offset(0.5, 0.5),
          width: wn,
          height: hn,
        );
      }
    });
  }

  // ── text ──────────────────────────────────────────────────────────────────

  Future<_TextItem?> _openTextEditor(_TextItem? initial) {
    return Navigator.of(context).push<_TextItem>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (_, __, ___) =>
            _TextEntryPage(initial: initial, startColor: _color),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  Future<void> _addText() async {
    final it = _cur;
    if (it.isVideo || it.image == null) return;
    final res = await _openTextEditor(null);
    if (res == null || res.text.trim().isEmpty || !mounted) return;
    res.center = it.crop.center;
    setState(() => it.texts.add(res));
  }

  Future<void> _editText(_EditItem it, int idx) async {
    if (idx < 0 || idx >= it.texts.length) return;
    final t = it.texts[idx];
    final res = await _openTextEditor(t);
    if (res == null || !mounted) return;
    setState(() {
      if (res.text.trim().isEmpty) {
        it.texts.removeAt(idx);
      } else {
        t.text = res.text;
        t.color = res.color;
        t.filled = res.filled;
      }
    });
  }

  // ── pointer handling (draw + text transform) ──────────────────────────────

  Offset _toNorm(_EditItem it, Size v, Offset p) => Offset(
    it.crop.left + (p.dx / v.width).clamp(0.0, 1.0) * it.crop.width,
    it.crop.top + (p.dy / v.height).clamp(0.0, 1.0) * it.crop.height,
  );

  int _hitText(_EditItem it, Size v, Offset p) {
    final pxW = v.width / it.crop.width;
    final pxH = v.height / it.crop.height;
    for (int i = it.texts.length - 1; i >= 0; i--) {
      final t = it.texts[i];
      final l = _layoutText(t, t.size * pxW, pxW * 0.85);
      final c = Offset(
        (t.center.dx - it.crop.left) * pxW,
        (t.center.dy - it.crop.top) * pxH,
      );
      final d = p - c;
      final cs = math.cos(-t.rotation), sn = math.sin(-t.rotation);
      final local = Offset(d.dx * cs - d.dy * sn, d.dx * sn + d.dy * cs);
      if (Rect.fromCenter(
        center: Offset.zero,
        width: l.box.width + 24,
        height: l.box.height + 24,
      ).contains(local)) {
        return i;
      }
    }
    return -1;
  }

  bool _inTrash(Offset p, Size v) => Rect.fromCenter(
    center: Offset(v.width / 2, v.height - 40),
    width: 100,
    height: 80,
  ).contains(p);

  void _onDown(PointerDownEvent e, _EditItem it, Size v) {
    _ptrs[e.pointer] = e.localPosition;
    if (_mode == _Mode.draw) {
      if (_ptrs.length == 1) {
        final st = _Stroke(
          [_toNorm(it, v, e.localPosition)],
          _color,
          _highlighter ? 0.035 : 0.011,
          _highlighter,
        );
        it.strokes.add(st);
        _liveStroke = st;
        setState(() {});
      }
      return;
    }
    if (_mode != _Mode.view) return;

    if (_ptrs.length == 1) {
      final h = _hitText(it, v, e.localPosition);
      if (h >= 0) {
        final t = it.texts.removeAt(h);
        it.texts.add(t); // bring to front
        _activeText = it.texts.length - 1;
        _dragStart = e.localPosition;
        _textStartCenter = t.center;
        _tapCandidate = true;
        _downAt = DateTime.now();
        setState(() => _lockPaging = true);
      }
    } else if (_ptrs.length == 2 && _activeText >= 0) {
      final t = it.texts[_activeText];
      final pts = _ptrs.values.toList();
      _pinchDist = math.max(1, (pts[0] - pts[1]).distance);
      _pinchAngle = (pts[1] - pts[0]).direction;
      _textStartSize = t.size;
      _textStartRot = t.rotation;
      _tapCandidate = false;
    }
  }

  void _onMove(PointerMoveEvent e, _EditItem it, Size v) {
    if (!_ptrs.containsKey(e.pointer)) return;
    _ptrs[e.pointer] = e.localPosition;

    if (_mode == _Mode.draw && _liveStroke != null && _ptrs.length == 1) {
      final p = _toNorm(it, v, e.localPosition);
      final last = _liveStroke!.pts.last;
      if ((p - last).distance > 0.0015) {
        setState(() => _liveStroke!.pts.add(p));
      }
      return;
    }

    if (_activeText >= 0 && _activeText < it.texts.length) {
      final t = it.texts[_activeText];
      if (_ptrs.length >= 2) {
        final pts = _ptrs.values.toList();
        final dist = math.max(1, (pts[0] - pts[1]).distance);
        final ang = (pts[1] - pts[0]).direction;
        t.size = (_textStartSize * dist / _pinchDist).clamp(0.02, 0.35);
        t.rotation = _textStartRot + (ang - _pinchAngle);
      } else {
        final d = e.localPosition - _dragStart;
        if (d.distance > 8) _tapCandidate = false;
        t.center = _textStartCenter +
            Offset(
              d.dx / v.width * it.crop.width,
              d.dy / v.height * it.crop.height,
            );
        _overTrash = _inTrash(e.localPosition, v);
      }
      setState(() {});
    }
  }

  void _onUp(PointerEvent e, _EditItem it, Size v, {bool cancel = false}) {
    _ptrs.remove(e.pointer);
    if (_ptrs.isNotEmpty) {
      if (_activeText >= 0 && _activeText < it.texts.length) {
        _dragStart = _ptrs.values.first;
        _textStartCenter = it.texts[_activeText].center;
        _tapCandidate = false;
      }
      return;
    }

    _liveStroke = null;
    int editIdx = -1;
    if (_activeText >= 0 && _activeText < it.texts.length) {
      final isTap = _tapCandidate &&
          !cancel &&
          DateTime.now().difference(_downAt).inMilliseconds < 400;
      if (_overTrash && !cancel) {
        it.texts.removeAt(_activeText);
        HapticFeedback.mediumImpact();
      } else if (isTap) {
        editIdx = _activeText;
      }
    }
    _activeText = -1;
    _overTrash = false;
    _tapCandidate = false;
    setState(() => _lockPaging = false);
    if (editIdx >= 0) _editText(it, editIdx);
  }

  // ── media list ────────────────────────────────────────────────────────────

  void _discardFile(int index) {
    if (index < 0 || index >= _items.length) return;
    if (_index >= 0 && _index < _items.length) {
      _items[_index].caption = _caption.text.trim();
    }
    setState(() {
      _items.removeAt(index).image?.dispose();
      if (_items.isEmpty) return;
      if (_index >= _items.length) _index = _items.length - 1;
      _caption.text = _items[_index].caption;
    });
    if (_items.isEmpty) {
      Navigator.pop(context);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_page.hasClients) _page.jumpToPage(_index);
    });
  }

  Future<void> _addMoreMedia() async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Add Media'),
        message: const Text('Take photo/video or choose from gallery'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'camera'),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.camera_fill, size: 20),
                SizedBox(width: 8),
                Text('Camera'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'gallery'),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.photo_fill, size: 20),
                SizedBox(width: 8),
                Text('Choose from Gallery'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (choice == null) return;

    AppPreferences.isPickerActive = true;
    try {
      if (choice == 'camera') {
        final File? captured = await Navigator.of(context).push<File>(
          MaterialPageRoute(builder: (_) => const AppCameraPage()),
        );
        if (captured != null && mounted) _addNewFile(captured);
      } else {
        final multi = await _picker.pickMultipleMedia();
        for (final f in multi) {
          if (!mounted) break;
          _addNewFile(File(f.path));
        }
      }
    } catch (e) {
      debugPrint('[ADD MEDIA ERROR] $e');
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  void _addNewFile(File file) {
    if (_index >= 0 && _index < _items.length) {
      _items[_index].caption = _caption.text.trim();
    }
    setState(() {
      _items.add(_makeItem(file));
      _index = _items.length - 1;
      _caption.text = _items[_index].caption;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_page.hasClients) {
        _page.animateToPage(
          _index,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // ── export ────────────────────────────────────────────────────────────────

  Future<File> _export(_EditItem it) async {
    if (it.isVideo) return VideoExportService.export(it.file, it.video!);
    if (!it.isEdited) return it.file;
    final img = await _decodeImage(it.file, 4096);
    if (img == null) return it.file;
    try {
      final iw = img.width.toDouble(), ih = img.height.toDouble();
      final rw = it.turns.isOdd ? ih : iw;
      final rh = it.turns.isOdd ? iw : ih;
      final outW = (it.crop.width * rw).round().clamp(1, 8192);
      final outH = (it.crop.height * rh).round().clamp(1, 8192);

      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      _paintEdit(
        canvas,
        Size(outW.toDouble(), outH.toDouble()),
        img,
        it.turns,
        it.crop,
        it.strokes,
        it.texts,
      );
      final pic = rec.endRecording();
      final out = await pic.toImage(outW, outH);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      pic.dispose();
      if (data == null) return it.file;

      final tmp = await getTemporaryDirectory();
      final f = File(
        '${tmp.path}${Platform.pathSeparator}edited_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}.png',
      );
      await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return f;
    } catch (e) {
      debugPrint('[EDITOR EXPORT ERROR] $e');
      return it.file;
    } finally {
      img.dispose();
    }
  }

  Future<void> _handleSend() async {
    if (_sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    if (_index >= 0 && _index < _items.length) {
      _items[_index].caption = _caption.text.trim();
    }
    final files = <File>[];
    final captions = <String>[];
    for (final it in _items) {
      files.add(await _export(it));
      captions.add(it.caption.trim());
    }
    if (!mounted) return;
    final globalCaption = captions.firstWhere((c) => c.isNotEmpty, orElse: () => '');
    Navigator.pop(
      context,
      ImageEditorResult(
        images: files,
        captions: captions,
        caption: globalCaption,
        isHd: _isHd,
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits will be lost.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  void _onBack() {
    if (_mode == _Mode.crop) {
      _cancelCrop();
    } else if (_mode == _Mode.draw) {
      setState(() => _mode = _Mode.view);
    } else if (_anyEdited) {
      _confirmDiscard();
    } else {
      Navigator.pop(context);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _mode == _Mode.view && !_anyEdited,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    if (_mode == _Mode.view) _buildTopBar(),
                    Expanded(
                      child: _mode == _Mode.crop
                          ? _buildCropView()
                          : _buildPager(),
                    ),
                    if (_mode == _Mode.view) ...[
                      _buildThumbs(),
                      _buildCaptionBar(),
                      _buildSendRow(),
                    ] else if (_mode == _Mode.draw)
                      _buildDrawBar()
                    else
                      _buildCropBar(),
                  ],
                ),
                if (_sending)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black54,
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, VoidCallback? onTap,
      {bool active = false, String? tooltip}) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 25,
        color: onTap == null
            ? Colors.white30
            : (active ? AppTheme.primaryColor : Colors.white),
      ),
    );
  }

  Widget _buildTopBar() {
    final it = _items.isEmpty ? null : _cur;
    final canEdit = it != null && !it.isVideo && it.image != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            onPressed: _onBack,
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() => _isHd = !_isHd);
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 1),
                  content: Text(
                    _isHd
                        ? 'Media quality set to HD (Full Quality)'
                        : 'Media quality set to Standard (Compressed)',
                  ),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isHd ? AppTheme.primaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isHd ? AppTheme.primaryColor : Colors.white70,
                  width: 1.5,
                ),
              ),
              child: Text(
                'HD',
                style: TextStyle(
                  color: _isHd ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          _toolBtn(Icons.crop_rotate_rounded, canEdit ? _enterCrop : null,
              tooltip: 'Crop & rotate'),
          _toolBtn(Icons.title_rounded, canEdit ? _addText : null,
              tooltip: 'Add text'),
          _toolBtn(
            Icons.edit_rounded,
            canEdit ? () => setState(() => _mode = _Mode.draw) : null,
            tooltip: 'Draw',
          ),
        ],
      ),
    );
  }

  // ── pager / editor canvas ────────────────────────────────────────────────

  Widget _buildPager() {
    return PageView.builder(
      controller: _page,
      physics: (_mode == _Mode.draw || _lockPaging)
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      itemCount: _items.length,
      onPageChanged: (i) {
        FocusManager.instance.primaryFocus?.unfocus();
        if (_index >= 0 && _index < _items.length) {
          _items[_index].caption = _caption.text.trim();
        }
        setState(() {
          _index = i;
          _caption.text = _items[i].caption;
          _caption.selection = TextSelection.fromPosition(
            TextPosition(offset: _caption.text.length),
          );
        });
      },
      itemBuilder: (_, i) => _buildPage(i),
    );
  }

  Widget _buildPage(int i) {
    final it = _items[i];
    if (it.isVideo) {
      return VideoPreviewPane(
        key: ValueKey(it.file.path),
        file: it.file,
        edit: it.video!,
        active: i == _index,
        onChanged: () {
          if (mounted) setState(() {});
        },
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        if (it.image == null) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        }

        final avail = Size(c.maxWidth - 12, c.maxHeight - 12);
        final v = applyBoxFit(BoxFit.contain, Size(it.viewAspect, 1), avail)
            .destination;
        final dragging =
            i == _index && _activeText >= 0 && _ptrs.length == 1 && !_tapCandidate;

        return Center(
          child: SizedBox(
            width: v.width,
            height: v.height,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _onDown(e, it, v),
              onPointerMove: (e) => _onMove(e, it, v),
              onPointerUp: (e) => _onUp(e, it, v),
              onPointerCancel: (e) => _onUp(e, it, v, cancel: true),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _EditPainter(it)),
                    ),
                  ),
                  if (dragging)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: _overTrash ? 58 : 48,
                          height: _overTrash ? 58 : 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _overTrash
                                ? const Color(0xFFFF3B30)
                                : Colors.black54,
                            border: Border.all(color: Colors.white54),
                          ),
                          child: const Icon(
                            CupertinoIcons.trash,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── crop screen ───────────────────────────────────────────────────────────

  static const double _cropInset = 24;

  Widget _buildCropView() {
    final it = _cur;
    return LayoutBuilder(
      builder: (context, c) {
        final avail = Size(
          c.maxWidth - 2 * _cropInset,
          c.maxHeight - 2 * _cropInset,
        );
        final fit =
            applyBoxFit(BoxFit.contain, Size(it.rotW, it.rotH), avail).destination;
        return Center(
          child: SizedBox(
            width: fit.width + 2 * _cropInset,
            height: fit.height + 2 * _cropInset,
            child: Stack(
              children: [
                Positioned(
                  left: _cropInset,
                  top: _cropInset,
                  width: fit.width,
                  height: fit.height,
                  child: CustomPaint(painter: _EditPainter(it, full: true)),
                ),
                Positioned.fill(
                  child: _CropOverlay(
                    inset: _cropInset,
                    rect: _draft,
                    aspect: _cropAspect,
                    onChanged: (r) => setState(() => _draft = r),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCropBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _kAspects.length,
              itemBuilder: (_, i) {
                final sel = i == _aspectIdx;
                return GestureDetector(
                  onTap: () => _setAspect(i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? Colors.white : const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      _kAspects[i].label,
                      style: TextStyle(
                        color: sel ? Colors.black : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _cancelCrop,
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              IconButton(
                onPressed: _rotateInCrop,
                tooltip: 'Rotate',
                icon: const Icon(Icons.rotate_90_degrees_cw_rounded,
                    color: Colors.white, size: 26),
              ),
              TextButton(
                onPressed: _resetCrop,
                child: const Text('Reset',
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
              TextButton(
                onPressed: _applyCrop,
                child: Text('Done',
                    style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── draw bar ──────────────────────────────────────────────────────────────

  Widget _buildDrawBar() {
    final it = _cur;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ColorRow(
            selected: _color,
            onPick: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                onPressed: it.strokes.isEmpty
                    ? null
                    : () => setState(() => it.strokes.removeLast()),
                icon: Icon(
                  Icons.undo_rounded,
                  color: it.strokes.isEmpty ? Colors.white30 : Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              _segment('Pen', !_highlighter,
                      () => setState(() => _highlighter = false)),
              const SizedBox(width: 6),
              _segment('Marker', _highlighter,
                      () => setState(() => _highlighter = true)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _mode = _Mode.view),
                child: Text('Done',
                    style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segment(String label, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? Colors.white : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── thumbnails + caption ──────────────────────────────────────────────────

  Widget _buildThumbs() {
    if (_items.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 66,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final it = _items[i];
          final sel = i == _index;
          return GestureDetector(
            onTap: () {
              if (sel) {
                HapticFeedback.mediumImpact();
                _discardFile(i); // tap the trash on the selected thumb
              } else {
                HapticFeedback.selectionClick();
                _items[_index].caption = _caption.text.trim();
                _page.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                );
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: sel ? 56 : 48,
              height: sel ? 56 : 48,
              margin: EdgeInsets.only(
                right: 6,
                top: sel ? 0 : 4,
                bottom: sel ? 0 : 4,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: sel ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (it.isVideo)
                      (it.videoThumb != null
                          ? Image.memory(
                              it.videoThumb!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : const ColoredBox(color: Color(0xFF2C2C2E)))
                    else
                      Image.file(it.file, cacheWidth: 150, fit: BoxFit.cover),
                    if (it.isVideo)
                      const Positioned(
                        left: 4,
                        bottom: 3,
                        child: Icon(
                          CupertinoIcons.videocam_fill,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    if (it.isEdited && !sel)
                      const Positioned(
                        right: 3,
                        bottom: 3,
                        child: Icon(
                          Icons.edit_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    if (sel)
                      Container(
                        color: Colors.black45,
                        child: const Icon(
                          CupertinoIcons.trash,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCaptionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: _addMoreMedia, // "+" media like WhatsApp
              icon: const Icon(
                CupertinoIcons.photo_on_rectangle,
                color: Colors.white70,
                size: 22,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _caption,
                onChanged: _onCaptionChanged,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Add a caption…',
                  hintStyle:
                      TextStyle(color: AppTheme.subtitleGrey, fontSize: 16),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: widget.recipientName == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.person_fill,
                              size: 14, color: Colors.white70),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.recipientName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _handleSend,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    color: Color(0xFF25D366),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x4025D366),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.send_rounded,
                      color: Colors.black, size: 24),
                ),
                if (_items.length > 1)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: _items.length > 9
                            ? BoxShape.rectangle
                            : BoxShape.circle,
                        borderRadius:
                            _items.length > 9 ? BorderRadius.circular(10) : null,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        '${_items.length}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color row
// ─────────────────────────────────────────────────────────────────────────────

class _ColorRow extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onPick;
  const _ColorRow({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: _kPalette.map((c) {
        final sel = c == selected;
        return GestureDetector(
          onTap: () => onPick(c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: sel ? 30 : 24,
            height: sel ? 30 : 24,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: sel ? Colors.white : Colors.white38,
                width: sel ? 3 : 1.5,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop overlay (drag corners / edges / move, optional aspect lock)
// ─────────────────────────────────────────────────────────────────────────────

enum _Handle { none, move, tl, tr, bl, br, left, right, top, bottom }

class _CropOverlay extends StatefulWidget {
  final Rect rect; // normalized (0..1) relative to the image area
  final double? aspect; // px w/h, null = free
  final double inset;
  final ValueChanged<Rect> onChanged;

  const _CropOverlay({
    required this.rect,
    required this.aspect,
    required this.inset,
    required this.onChanged,
  });

  @override
  State<_CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<_CropOverlay> {
  static const double _min = 56;
  static const double _grab = 32;

  _Handle _h = _Handle.none;
  Rect _start = Rect.zero;
  Offset _startPt = Offset.zero;
  Size _inner = Size.zero;

  Rect get _px => Rect.fromLTRB(
    widget.rect.left * _inner.width,
    widget.rect.top * _inner.height,
    widget.rect.right * _inner.width,
    widget.rect.bottom * _inner.height,
  );

  _Handle _hit(Offset p, Rect r) {
    bool near(Offset a) => (p - a).distance <= _grab;
    if (near(r.topLeft)) return _Handle.tl;
    if (near(r.topRight)) return _Handle.tr;
    if (near(r.bottomLeft)) return _Handle.bl;
    if (near(r.bottomRight)) return _Handle.br;
    if (widget.aspect == null) {
      final g = _grab / 2;
      final inY = p.dy >= r.top - g && p.dy <= r.bottom + g;
      final inX = p.dx >= r.left - g && p.dx <= r.right + g;
      if (inY && (p.dx - r.left).abs() <= g) return _Handle.left;
      if (inY && (p.dx - r.right).abs() <= g) return _Handle.right;
      if (inX && (p.dy - r.top).abs() <= g) return _Handle.top;
      if (inX && (p.dy - r.bottom).abs() <= g) return _Handle.bottom;
    }
    if (r.inflate(6).contains(p)) return _Handle.move;
    return _Handle.none;
  }

  Rect _corner(Rect s, _Handle h, Offset d) {
    final W = _inner.width, H = _inner.height;
    late final Offset fixed, moving0;
    switch (h) {
      case _Handle.tl:
        fixed = s.bottomRight;
        moving0 = s.topLeft;
        break;
      case _Handle.tr:
        fixed = s.bottomLeft;
        moving0 = s.topRight;
        break;
      case _Handle.bl:
        fixed = s.topRight;
        moving0 = s.bottomLeft;
        break;
      default:
        fixed = s.topLeft;
        moving0 = s.bottomRight;
    }
    final sx = moving0.dx >= fixed.dx ? 1.0 : -1.0;
    final sy = moving0.dy >= fixed.dy ? 1.0 : -1.0;
    final m = Offset(
      (moving0.dx + d.dx).clamp(0.0, W),
      (moving0.dy + d.dy).clamp(0.0, H),
    );
    final maxW = sx > 0 ? W - fixed.dx : fixed.dx;
    final maxH = sy > 0 ? H - fixed.dy : fixed.dy;

    double w = ((m.dx - fixed.dx) * sx).clamp(0.0, maxW);
    double hh = ((m.dy - fixed.dy) * sy).clamp(0.0, maxH);
    final a = widget.aspect;
    if (a != null) {
      if (w / math.max(hh, 1) > a) {
        w = hh * a;
      } else {
        hh = w / a;
      }
      if (w < _min) {
        w = _min;
        hh = w / a;
      }
      if (w > maxW) {
        w = maxW;
        hh = w / a;
      }
      if (hh > maxH) {
        hh = maxH;
        w = hh * a;
      }
    } else {
      w = math.min(math.max(w, _min), maxW);
      hh = math.min(math.max(hh, _min), maxH);
    }
    return Rect.fromPoints(fixed, Offset(fixed.dx + sx * w, fixed.dy + sy * hh));
  }

  void _update(Offset p) {
    final d = p - _startPt;
    final s = _start;
    final W = _inner.width, H = _inner.height;
    Rect r;
    switch (_h) {
      case _Handle.move:
        final dx = d.dx.clamp(-s.left, W - s.right);
        final dy = d.dy.clamp(-s.top, H - s.bottom);
        r = s.shift(Offset(dx, dy));
        break;
      case _Handle.left:
        r = Rect.fromLTRB(
            (s.left + d.dx).clamp(0.0, s.right - _min), s.top, s.right, s.bottom);
        break;
      case _Handle.right:
        r = Rect.fromLTRB(
            s.left, s.top, (s.right + d.dx).clamp(s.left + _min, W), s.bottom);
        break;
      case _Handle.top:
        r = Rect.fromLTRB(
            s.left, (s.top + d.dy).clamp(0.0, s.bottom - _min), s.right, s.bottom);
        break;
      case _Handle.bottom:
        r = Rect.fromLTRB(
            s.left, s.top, s.right, (s.bottom + d.dy).clamp(s.top + _min, H));
        break;
      case _Handle.none:
        return;
      default:
        r = _corner(s, _h, d);
    }
    widget.onChanged(Rect.fromLTRB(
      (r.left / W).clamp(0.0, 1.0),
      (r.top / H).clamp(0.0, 1.0),
      (r.right / W).clamp(0.0, 1.0),
      (r.bottom / H).clamp(0.0, 1.0),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _inner = Size(
          math.max(1, c.maxWidth - 2 * widget.inset),
          math.max(1, c.maxHeight - 2 * widget.inset),
        );
        final off = Offset(widget.inset, widget.inset);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            final p = d.localPosition - off;
            _start = _px;
            _startPt = p;
            _h = _hit(p, _start);
          },
          onPanUpdate: (d) => _update(d.localPosition - off),
          onPanEnd: (_) => _h = _Handle.none,
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _CropPainter(_px, _inner, widget.inset),
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  final Rect rect;
  final Size inner;
  final double inset;
  _CropPainter(this.rect, this.inner, this.inset);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(inset, inset);

    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & inner)
      ..addRect(rect);
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.6));

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    for (int i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), line);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), line);
    }

    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final cp = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square;
    const L = 22.0;
    void corner(Offset o, double sx, double sy) {
      canvas.drawLine(o, o + Offset(sx * L, 0), cp);
      canvas.drawLine(o, o + Offset(0, sy * L), cp);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.rect != rect || old.inner != inner;
}

// ─────────────────────────────────────────────────────────────────────────────
// Text entry screen
// ─────────────────────────────────────────────────────────────────────────────

class _TextEntryPage extends StatefulWidget {
  final _TextItem? initial;
  final Color startColor;
  const _TextEntryPage({required this.initial, required this.startColor});

  @override
  State<_TextEntryPage> createState() => _TextEntryPageState();
}

class _TextEntryPageState extends State<_TextEntryPage> {
  late final TextEditingController _c =
  TextEditingController(text: widget.initial?.text ?? '');
  late Color _color = widget.initial?.color ?? widget.startColor;
  late bool _filled = widget.initial?.filled ?? false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() {
    Navigator.pop(
      context,
      _TextItem(
        text: _c.text.trim(),
        center: widget.initial?.center ?? const Offset(0.5, 0.5),
        size: widget.initial?.size ?? 0.075,
        rotation: widget.initial?.rotation ?? 0,
        color: _color,
        filled: _filled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fg = _filled
        ? (_color.computeLuminance() > 0.6 ? Colors.black : Colors.white)
        : _color;
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.72),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _filled = !_filled),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _filled ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.6),
                      ),
                      child: Center(
                        child: Text(
                          'A',
                          style: TextStyle(
                            color: _filled ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _done,
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: IntrinsicWidth(
                    child: TextField(
                      controller: _c,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 6,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.sentences,
                      cursorColor: Colors.white,
                      style: TextStyle(
                        color: fg,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        filled: _filled,
                        fillColor: _color,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: _filled ? 14 : 0,
                          vertical: _filled ? 8 : 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _ColorRow(
                selected: _color,
                onPick: (c) => setState(() => _color = c),
              ),
            ),
          ],
        ),
      ),
    );
  }
}