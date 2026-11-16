import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../../core/theme/app_theme.dart';

class GifItem {
  final String id;
  final String title;
  final String gifUrl;
  final String previewUrl;
  final String category;

  const GifItem({
    required this.id,
    required this.title,
    required this.gifUrl,
    required this.previewUrl,
    this.category = 'Trending',
  });
}

class GifPickerPanel extends StatefulWidget {
  final ValueChanged<GifItem> onGifSelected;
  final VoidCallback onClose;

  /// Total height of the panel (the composer decides this).
  final double height;

  /// Home-indicator space so the last row is never covered.
  final double bottomPadding;

  /// Fired when the search field gains/loses focus (composer expands the panel).
  final ValueChanged<bool>? onSearchFocusChanged;

  const GifPickerPanel({
    super.key,
    required this.onGifSelected,
    required this.onClose,
    required this.height,
    this.bottomPadding = 0,
    this.onSearchFocusChanged,
  });

  @override
  State<GifPickerPanel> createState() => _GifPickerPanelState();
}

class _GifPickerPanelState extends State<GifPickerPanel>
    with WidgetsBindingObserver {
  // ───────── API keys (copy-paste from developers.giphy.com, never retype) ─────────
  static const String _androidKey = 'm5oUvjPuJ2bALjA2vnyTkhMb07Bsf5rJ';
  static const String _iosKey = 'wK6mK2wfosqpwq9Q2yjP7T1E1kiJIcq4';

  static String get _giphyKey =>
      defaultTargetPlatform == TargetPlatform.android ? _androidKey : _iosKey;

  static const int _pageSize = 24;

  static const List<String> _categories = [
    'Trending',
    'Laughing',
    'Love',
    'Dancing',
    'Mind Blown',
    'Thumbs Up',
    'Celebration',
    'Fire',
    'Cat',
    'Anime',
    'Sports',
  ];

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _grid = ScrollController();

  Timer? _debounce;
  List<GifItem> _gifs = [];
  String _category = 'Trending';
  String? _error;
  bool _loading = false;
  bool _fetchingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  int _reqId = 0;
  bool _sawKeyboard = false;

  String get _activeQuery {
    final q = _searchController.text.trim();
    if (q.isNotEmpty) return q;
    return _category == 'Trending' ? '' : _category;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFocus.addListener(_onSearchFocus);
    _grid.addListener(_onGridScroll);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchFocus.removeListener(_onSearchFocus); // before dispose: no callback into parent
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _grid
      ..removeListener(_onGridScroll)
      ..dispose();
    super.dispose();
  }

  // ───────── search focus / keyboard ─────────

  void _onSearchFocus() {
    if (!_searchFocus.hasFocus) _sawKeyboard = false;
    widget.onSearchFocusChanged?.call(_searchFocus.hasFocus);
    if (mounted) setState(() {});
  }

  /// If the keyboard is dismissed by the system (Android back / swipe),
  /// also drop the search focus so the panel returns to normal size.
  @override
  void didChangeMetrics() {
    if (!mounted || !_searchFocus.hasFocus) return;
    final v = View.of(context);
    final inset = v.viewInsets.bottom / v.devicePixelRatio;
    if (inset > 100) {
      _sawKeyboard = true;
    } else if (_sawKeyboard && inset < 40) {
      _sawKeyboard = false;
      _searchFocus.unfocus();
    }
  }

  // ───────── data ─────────

  void _onGridScroll() {
    if (!_grid.hasClients) return;
    final pos = _grid.position;
    if (pos.pixels >= pos.maxScrollExtent - 240 &&
        !_fetchingMore &&
        _hasMore &&
        !_loading &&
        _error == null) {
      _load(reset: false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
    setState(() {}); // refresh clear button + chip selection
  }

  List<GifItem> _parseGiphy(List<dynamic> items) {
    final out = <GifItem>[];
    for (final it in items) {
      final id = it['id']?.toString() ?? '';
      final images = (it['images'] as Map?) ?? const {};
      String? url(String k) => (images[k] as Map?)?['url']?.toString();
      final preview =
          url('fixed_width') ?? url('fixed_height') ?? url('original');
      final full = url('downsized') ?? url('original');
      if (id.isEmpty || preview == null || full == null) continue;
      out.add(GifItem(
        id: id,
        title: it['title']?.toString() ?? 'GIF',
        gifUrl: full,
        previewUrl: preview,
        category: _category,
      ));
    }
    return out;
  }

  Future<void> _load({bool reset = true}) async {
    final id = ++_reqId;
    final q = _activeQuery;

    // Pasted GIF link
    if (reset && (q.startsWith('http://') || q.startsWith('https://'))) {
      setState(() {
        _loading = false;
        _hasMore = false;
        _error = null;
        _gifs = [
          GifItem(
            id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
            title: 'Custom GIF Link',
            gifUrl: q,
            previewUrl: q,
          ),
        ];
      });
      return;
    }

    if (_giphyKey.startsWith('PASTE_')) {
      setState(() {
        _loading = false;
        _error = 'Giphy API key not set';
      });
      return;
    }

    final offset = reset ? 0 : _offset;
    setState(() {
      if (reset) {
        _loading = true;
        _hasMore = true;
        _error = null;
      } else {
        _fetchingMore = true;
      }
    });
    if (reset && _grid.hasClients) _grid.jumpTo(0);

    try {
      final uri = Uri.https(
        'api.giphy.com',
        q.isEmpty ? '/v1/gifs/trending' : '/v1/gifs/search',
        {
          'api_key': _giphyKey,
          'limit': '$_pageSize',
          'offset': '$offset',
          'rating': 'g',
          if (q.isNotEmpty) 'q': q,
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted || id != _reqId) return;

      if (res.statusCode != 200) {
        if (kDebugMode) debugPrint('[GIF] HTTP ${res.statusCode}: ${res.body}');
        throw res.statusCode == 401 || res.statusCode == 403
            ? 'Invalid Giphy API key'
            : res.statusCode == 429
                ? 'Giphy rate limit reached'
                : 'Giphy error (${res.statusCode})';
      }

      final raw = (jsonDecode(res.body)['data'] as List?) ?? const [];
      final items = _parseGiphy(raw);
      setState(() {
        if (reset) {
          _gifs = items;
        } else {
          final seen = _gifs.map((g) => g.id).toSet();
          _gifs.addAll(items.where((g) => !seen.contains(g.id)));
        }
        _offset = offset + raw.length;
        _hasMore = raw.length >= _pageSize;
        _loading = false;
        _fetchingMore = false;
      });
    } catch (e) {
      if (!mounted || id != _reqId) return;
      setState(() {
        _loading = false;
        _fetchingMore = false;
        _hasMore = false;
        if (reset) {
          _gifs = [];
          _error = e is String
              ? e
              : (e is TimeoutException
                  ? 'Request timed out'
                  : "Couldn't reach GIF service");
        }
      });
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        border: Border(
          top: BorderSide(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildSearchRow(isDark),
          _buildCategories(isDark),
          Expanded(child: _buildBody(isDark)),
        ],
      ),
    );
  }

  Widget _buildSearchRow(bool isDark) {
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.06);
    final searching = _searchFocus.hasFocus;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(19),
              ),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.search,
                      size: 16, color: Color(0xFF8E8E93)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      cursorColor: const Color(0xFF007AFF),
                      onSubmitted: (_) {
                        _debounce?.cancel();
                        _load(); // keep the keyboard, results show right above it
                      },
                      style: TextStyle(
                        fontSize: 15,
                        letterSpacing: -0.2,
                        color: AppTheme.primaryText(isDark),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search GIFs or paste link',
                        hintStyle:
                            TextStyle(fontSize: 15, color: Color(0xFF8E8E93)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _searchController.clear();
                        _debounce?.cancel();
                        setState(() {});
                        _load();
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(CupertinoIcons.clear_thick_circled,
                            size: 16, color: Color(0xFF8E8E93)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // searching  -> chevron: collapse keyboard, back to the normal panel
          // not searching -> X: close the panel
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              if (searching) {
                _searchFocus.unfocus();
              } else {
                widget.onClose();
              }
            },
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.20),
                          Colors.white.withValues(alpha: 0.08),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.95),
                          Colors.white.withValues(alpha: 0.55),
                        ],
                ),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.6,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: a, child: c),
                ),
                child: Icon(
                  searching ? CupertinoIcons.chevron_down : CupertinoIcons.xmark,
                  key: ValueKey(searching),
                  size: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategories(bool isDark) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final selected =
              cat == _category && _searchController.text.isEmpty;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _debounce?.cancel();
              _searchController.clear();
              _searchFocus.unfocus();
              setState(() => _category = cat);
              _load();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF4AA3FF), Color(0xFF007AFF)],
                      )
                    : null,
                color: selected
                    ? null
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: selected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    final subtle = isDark ? Colors.white60 : Colors.black54;
    final gridPad = EdgeInsets.fromLTRB(10, 6, 10, 10 + widget.bottomPadding);
    const delegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
    );

    if (_loading) {
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: gridPad,
        gridDelegate: delegate,
        itemCount: 12,
        itemBuilder: (_, __) => _PulseBox(isDark: isDark),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.exclamationmark_circle, size: 28, color: subtle),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(fontSize: 13, color: subtle)),
            const SizedBox(height: 10),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              minimumSize: const Size(0, 30),
              color: const Color(0xFF007AFF),
              borderRadius: BorderRadius.circular(16),
              onPressed: _load,
              child: const Text('Retry',
                  style: TextStyle(fontSize: 13, color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_gifs.isEmpty) {
      return Center(
        child: Text(
          'No GIFs found for "${_searchController.text.trim()}"',
          style: TextStyle(fontSize: 13, color: subtle),
        ),
      );
    }

    return GridView.builder(
      controller: _grid,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: gridPad,
      gridDelegate: delegate,
      itemCount: _gifs.length + (_fetchingMore ? 3 : 0),
      itemBuilder: (context, index) {
        if (index >= _gifs.length) return _PulseBox(isDark: isDark);
        final gif = _gifs[index];
        return _GifTile(
          key: ValueKey(gif.id),
          gif: gif,
          isDark: isDark,
          onTap: () => widget.onGifSelected(gif),
        );
      },
    );
  }
}

/// Loading placeholder with a soft pulse.
class _PulseBox extends StatefulWidget {
  const _PulseBox({required this.isDark});
  final bool isDark;

  @override
  State<_PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<_PulseBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.isDark ? Colors.white : Colors.black;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: base.withValues(alpha: 0.05 + 0.05 * _c.value),
        ),
      ),
    );
  }
}

/// One GIF: press-scale feedback, fade-in, and a short ✓ flash after sending
/// (the panel stays open, so the user needs to see that it went through).
class _GifTile extends StatefulWidget {
  const _GifTile({
    super.key,
    required this.gif,
    required this.isDark,
    required this.onTap,
  });
  final GifItem gif;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_GifTile> createState() => _GifTileState();
}

class _GifTileState extends State<_GifTile> {
  bool _pressed = false;
  bool _sent = false;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _tap() {
    widget.onTap();
    _t?.cancel();
    setState(() => _sent = true);
    _t = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _sent = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.isDark ? Colors.white : Colors.black;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: _tap,
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: base.withValues(alpha: 0.07)),
              Image.network(
                widget.gif.previewUrl,
                fit: BoxFit.cover,
                cacheWidth: 360,
                gaplessPlayback: true,
                frameBuilder: (ctx, child, frame, sync) {
                  if (sync) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: child,
                  );
                },
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.gif_rounded,
                      color: Color(0xFF8E8E93), size: 30),
                ),
              ),
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _sent ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.38),
                    child: const Center(
                      child: Icon(CupertinoIcons.checkmark_alt_circle_fill,
                          size: 30, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
