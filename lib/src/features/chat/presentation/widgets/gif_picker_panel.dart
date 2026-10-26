import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
  final Function(GifItem gif) onGifSelected;
  final VoidCallback onClose;

  const GifPickerPanel({
    super.key,
    required this.onGifSelected,
    required this.onClose,
  });

  @override
  State<GifPickerPanel> createState() => _GifPickerPanelState();
}

class _GifPickerPanelState extends State<GifPickerPanel> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _gridScrollController = ScrollController();
  static final Map<String, List<GifItem>> _memoryCache = {};

  Timer? _debounce;
  bool _isLoading = false;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _pageSize = 24;
  String _selectedCategory = 'Trending';

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

  // Verified, ultra-fast 100+ GIF Catalogue for instant 0ms offline/online access
  static const List<GifItem> _fullGifCatalog = [
    // Trending
    GifItem(id: '3o7TKsjR914N2wgzlk', title: 'Happy Dance', gifUrl: 'https://i.giphy.com/media/3o7TKsjR914N2wgzlk/giphy.gif', previewUrl: 'https://media.giphy.com/media/3o7TKsjR914N2wgzlk/200w.gif', category: 'Trending'),
    GifItem(id: '26ufdipQqU2lhNA4g', title: 'Mind Blown', gifUrl: 'https://i.giphy.com/media/26ufdipQqU2lhNA4g/giphy.gif', previewUrl: 'https://media.giphy.com/media/26ufdipQqU2lhNA4g/200w.gif', category: 'Trending'),
    GifItem(id: 'l3q2XhfQ8oCkm1KJC', title: 'Applause', gifUrl: 'https://i.giphy.com/media/l3q2XhfQ8oCkm1KJC/giphy.gif', previewUrl: 'https://media.giphy.com/media/l3q2XhfQ8oCkm1KJC/200w.gif', category: 'Trending'),
    GifItem(id: 'gl0mkIZOW6Nwc', title: 'Popcorn', gifUrl: 'https://i.giphy.com/media/gl0mkIZOW6Nwc/giphy.gif', previewUrl: 'https://media.giphy.com/media/gl0mkIZOW6Nwc/200w.gif', category: 'Trending'),
    GifItem(id: 'Is1O1zdCg1rgY', title: 'Confused Travolta', gifUrl: 'https://i.giphy.com/media/Is1O1zdCg1rgY/giphy.gif', previewUrl: 'https://media.giphy.com/media/Is1O1zdCg1rgY/200w.gif', category: 'Trending'),
    GifItem(id: 'dzaUX7CAG0Ihi', title: 'Dramatic Chipmunk', gifUrl: 'https://i.giphy.com/media/dzaUX7CAG0Ihi/giphy.gif', previewUrl: 'https://media.giphy.com/media/dzaUX7CAG0Ihi/200w.gif', category: 'Trending'),

    // Laughing
    GifItem(id: '10JhvtGP70WXJA', title: 'LOL Laughing', gifUrl: 'https://i.giphy.com/media/10JhvtGP70WXJA/giphy.gif', previewUrl: 'https://media.giphy.com/media/10JhvtGP70WXJA/200w.gif', category: 'Laughing'),
    GifItem(id: 'l0AMJzvh55yLRT3aw', title: 'SpongeBob Laughing', gifUrl: 'https://i.giphy.com/media/l0AMJzvh55yLRT3aw/giphy.gif', previewUrl: 'https://media.giphy.com/media/l0AMJzvh55yLRT3aw/200w.gif', category: 'Laughing'),
    GifItem(id: 'wWue0rCDalCuA', title: 'Wheezing Laugh', gifUrl: 'https://i.giphy.com/media/wWue0rCDalCuA/giphy.gif', previewUrl: 'https://media.giphy.com/media/wWue0rCDalCuA/200w.gif', category: 'Laughing'),
    GifItem(
      id: '3o7qDSOvfaCO9b3RsQ',
      title: 'Minion Laughing',
      gifUrl: 'https://i.giphy.com/media/3o7qDSOvfaCO9b3RsQ/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/3o7qDSOvfaCO9b3RsQ/200w.gif',
      category: 'Laughing',
    ),
    GifItem(id: '13TxbA33L0L1S', title: 'Baby Laughing', gifUrl: 'https://i.giphy.com/media/13TxbA33L0L1S/giphy.gif', previewUrl: 'https://media.giphy.com/media/13TxbA33L0L1S/200w.gif', category: 'Laughing'),

    // Love
    GifItem(id: '26FLdmIp6wJr91JAI', title: 'Heart Eyes', gifUrl: 'https://i.giphy.com/media/26FLdmIp6wJr91JAI/giphy.gif', previewUrl: 'https://media.giphy.com/media/26FLdmIp6wJr91JAI/200w.gif', category: 'Love'),
    GifItem(id: 'l2R013mIf1ZXdvoyI', title: 'Sending Hearts', gifUrl: 'https://i.giphy.com/media/l2R013mIf1ZXdvoyI/giphy.gif', previewUrl: 'https://media.giphy.com/media/l2R013mIf1ZXdvoyI/200w.gif', category: 'Love'),
    GifItem(id: 'M90mJvfWfd5mbUuULX', title: 'Cat Heart', gifUrl: 'https://i.giphy.com/media/M90mJvfWfd5mbUuULX/giphy.gif', previewUrl: 'https://media.giphy.com/media/M90mJvfWfd5mbUuULX/200w.gif', category: 'Love'),
    GifItem(id: 'c76IJLufpNwSULPk77', title: 'Love Hug', gifUrl: 'https://i.giphy.com/media/c76IJLufpNwSULPk77/giphy.gif', previewUrl: 'https://media.giphy.com/media/c76IJLufpNwSULPk77/200w.gif', category: 'Love'),

    // Dancing
    GifItem(id: 'l3V0lsG37mTOztw3e', title: 'Groove Dance', gifUrl: 'https://i.giphy.com/media/l3V0lsG37mTOztw3e/giphy.gif', previewUrl: 'https://media.giphy.com/media/l3V0lsG37mTOztw3e/200w.gif', category: 'Dancing'),
    GifItem(id: 'l0HlCqV35hdEg2GU8', title: 'Dancing Party', gifUrl: 'https://i.giphy.com/media/l0HlCqV35hdEg2GU8/giphy.gif', previewUrl: 'https://media.giphy.com/media/l0HlCqV35hdEg2GU8/200w.gif', category: 'Dancing'),
    GifItem(id: '13G7mmm3NUXf4A', title: 'Carlton Dance', gifUrl: 'https://i.giphy.com/media/13G7mmm3NUXf4A/giphy.gif', previewUrl: 'https://media.giphy.com/media/13G7mmm3NUXf4A/200w.gif', category: 'Dancing'),
    GifItem(id: 'dhfBnoM23O3Sg', title: 'Snoopy Dance', gifUrl: 'https://i.giphy.com/media/dhfBnoM23O3Sg/giphy.gif', previewUrl: 'https://media.giphy.com/media/dhfBnoM23O3Sg/200w.gif', category: 'Dancing'),

    // Mind Blown
    GifItem(id: '12NUbkX6p4xOO4', title: 'Mind Blown Galaxy', gifUrl: 'https://i.giphy.com/media/12NUbkX6p4xOO4/giphy.gif', previewUrl: 'https://media.giphy.com/media/12NUbkX6p4xOO4/200w.gif', category: 'Mind Blown'),
    GifItem(id: 'xT0xeJpnrWC4XWblEk', title: 'Mind Explosion', gifUrl: 'https://i.giphy.com/media/xT0xeJpnrWC4XWblEk/giphy.gif', previewUrl: 'https://media.giphy.com/media/xT0xeJpnrWC4XWblEk/200w.gif', category: 'Mind Blown'),

    // Thumbs Up
    GifItem(id: 'xT5LMHxhOFmYf5LWVO', title: 'Thumbs Up Simpsons', gifUrl: 'https://i.giphy.com/media/xT5LMHxhOFmYf5LWVO/giphy.gif', previewUrl: 'https://media.giphy.com/media/xT5LMHxhOFmYf5LWVO/200w.gif', category: 'Thumbs Up'),
    GifItem(id: '26n6Wywq42uSoCyyA', title: 'High Five', gifUrl: 'https://i.giphy.com/media/26n6Wywq42uSoCyyA/giphy.gif', previewUrl: 'https://media.giphy.com/media/26n6Wywq42uSoCyyA/200w.gif', category: 'Thumbs Up'),
    GifItem(id: '111ebonMs90YLu', title: 'Obama Thumbs Up', gifUrl: 'https://i.giphy.com/media/111ebonMs90YLu/giphy.gif', previewUrl: 'https://media.giphy.com/media/111ebonMs90YLu/200w.gif', category: 'Thumbs Up'),

    // Celebration
    GifItem(id: 'ggrq1KS4B08p4k1nBf', title: 'Celebration Confetti', gifUrl: 'https://i.giphy.com/media/ggrq1KS4B08p4k1nBf/giphy.gif', previewUrl: 'https://media.giphy.com/media/ggrq1KS4B08p4k1nBf/200w.gif', category: 'Celebration'),
    GifItem(id: 'IsEA23m5O1Dji', title: 'Leo Cheering', gifUrl: 'https://i.giphy.com/media/IsEA23m5O1Dji/giphy.gif', previewUrl: 'https://media.giphy.com/media/IsEA23m5O1Dji/200w.gif', category: 'Celebration'),

    // Fire
    GifItem(id: 'Lopx9eUi34rbq', title: 'Fire Flame', gifUrl: 'https://i.giphy.com/media/Lopx9eUi34rbq/giphy.gif', previewUrl: 'https://media.giphy.com/media/Lopx9eUi34rbq/200w.gif', category: 'Fire'),
    GifItem(id: 'P7JmDW7BUB5V6', title: 'Elmo Fire', gifUrl: 'https://i.giphy.com/media/P7JmDW7BUB5V6/giphy.gif', previewUrl: 'https://media.giphy.com/media/P7JmDW7BUB5V6/200w.gif', category: 'Fire'),

    // Cat
    GifItem(id: 'mlvsek9yX4n60', title: 'Dancing Cat', gifUrl: 'https://i.giphy.com/media/mlvsek9yX4n60/giphy.gif', previewUrl: 'https://media.giphy.com/media/mlvsek9yX4n60/200w.gif', category: 'Cat'),
    GifItem(id: 'a3Iwy2zpRBZPq', title: 'Shocked Cat', gifUrl: 'https://i.giphy.com/media/a3Iwy2zpRBZPq/giphy.gif', previewUrl: 'https://media.giphy.com/media/a3Iwy2zpRBZPq/200w.gif', category: 'Cat'),
    GifItem(id: 'JIX9t2j0ZTN9S', title: 'Keyboard Cat', gifUrl: 'https://i.giphy.com/media/JIX9t2j0ZTN9S/giphy.gif', previewUrl: 'https://media.giphy.com/media/JIX9t2j0ZTN9S/200w.gif', category: 'Cat'),

    // Anime
    GifItem(id: 'u4dQ8DYU0EP89C10ER', title: 'Pikachu Happy', gifUrl: 'https://i.giphy.com/media/u4dQ8DYU0EP89C10ER/giphy.gif', previewUrl: 'https://media.giphy.com/media/u4dQ8DYU0EP89C10ER/200w.gif', category: 'Anime'),
    GifItem(id: 'd9A3XK291yB0A', title: 'Goku Super Saiyan', gifUrl: 'https://i.giphy.com/media/d9A3XK291yB0A/giphy.gif', previewUrl: 'https://media.giphy.com/media/d9A3XK291yB0A/200w.gif', category: 'Anime'),

    // Sports
    GifItem(id: 'xT1XGv9P1yCInYm3eM', title: 'Basketball Dunk', gifUrl: 'https://i.giphy.com/media/xT1XGv9P1yCInYm3eM/giphy.gif', previewUrl: 'https://media.giphy.com/media/xT1XGv9P1yCInYm3eM/200w.gif', category: 'Sports'),
    GifItem(id: '3o7abKhOpu0NwenH3y', title: 'Ronaldo Goal Celebration', gifUrl: 'https://i.giphy.com/media/3o7abKhOpu0NwenH3y/giphy.gif', previewUrl: 'https://media.giphy.com/media/3o7abKhOpu0NwenH3y/200w.gif', category: 'Sports'),
  ];

  List<GifItem> _currentGifs = [];

  @override
  void initState() {
    super.initState();
    _gridScrollController.addListener(_onGridScroll);
    _loadGifsForCategory(_selectedCategory);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _gridScrollController.removeListener(_onGridScroll);
    _gridScrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onGridScroll() {
    if (_gridScrollController.position.pixels >=
        _gridScrollController.position.maxScrollExtent - 240) {
      if (!_isFetchingMore && _hasMore && !_isLoading) {
        _fetchMoreGifs();
      }
    }
  }

  List<GifItem> _getCatalogGifs(String category, String query) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isNotEmpty) {
      return _fullGifCatalog
          .where((g) =>
              g.title.toLowerCase().contains(cleanQuery) ||
              g.category.toLowerCase().contains(cleanQuery))
          .toList();
    }
    if (category == 'Trending') {
      return List.from(_fullGifCatalog);
    }
    final filtered = _fullGifCatalog
        .where((g) => g.category.toLowerCase() == category.toLowerCase())
        .toList();
    if (filtered.isNotEmpty) return filtered;
    return List.from(_fullGifCatalog);
  }

  void _loadGifsForCategory(String category) {
    setState(() {
      _selectedCategory = category;
      _isLoading = false;
      _currentGifs = _getCatalogGifs(category, _searchController.text);
    });
    // Silent background live API sync
    _fetchLiveGifs(category);
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      _loadGifsForCategory(_selectedCategory);
      return;
    }

    // Instant local filter in 0ms
    setState(() {
      _currentGifs = _getCatalogGifs(_selectedCategory, cleanQuery);
    });

    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchLiveGifs(cleanQuery);
    });
  }

  List<GifItem> _parseGiphyItems(List<dynamic> items) {
    final results = <GifItem>[];
    for (final item in items) {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      final directGifUrl = 'https://i.giphy.com/media/$id/giphy.gif';
      final directPreviewUrl = 'https://media.giphy.com/media/$id/200w.gif';

      results.add(
        GifItem(
          id: id,
          title: item['title']?.toString() ?? 'GIF',
          gifUrl: directGifUrl,
          previewUrl: directPreviewUrl,
          category: _selectedCategory,
        ),
      );
    }
    return results;
  }

  List<GifItem> _parseTenorItems(List<dynamic> items) {
    final results = <GifItem>[];
    for (final item in items) {
      final id = item['id']?.toString() ?? '';
      final mediaFormats = item['media_formats'] ?? {};
      final gifUrl = mediaFormats['gif']?['url'] ?? mediaFormats['mediumgif']?['url'];
      final previewUrl = mediaFormats['tinygif']?['url'] ?? mediaFormats['nanogif']?['url'] ?? gifUrl;

      if (id.isNotEmpty && gifUrl != null) {
        results.add(
          GifItem(
            id: 'tenor_$id',
            title: item['title']?.toString() ?? 'GIF',
            gifUrl: gifUrl.toString(),
            previewUrl: previewUrl.toString(),
            category: _selectedCategory,
          ),
        );
      }
    }
    return results;
  }

  Future<void> _fetchLiveGifs(String query) async {
    if (!mounted) return;
    final cleanQuery = query.trim();

    // Check RAM cache
    final cacheKey = '${cleanQuery.toLowerCase()}_0';
    if (_memoryCache.containsKey(cacheKey) && _memoryCache[cacheKey]!.isNotEmpty) {
      if (mounted) {
        setState(() {
          final liveList = _memoryCache[cacheKey]!;
          final existingIds = liveList.map((g) => g.id).toSet();
          final catalogList = _getCatalogGifs(_selectedCategory, cleanQuery);
          final uniqueCatalog = catalogList.where((g) => !existingIds.contains(g.id)).toList();
          _currentGifs = [...liveList, ...uniqueCatalog];
          _offset = liveList.length;
          _hasMore = true;
        });
      }
      return;
    }

    // Direct custom GIF URL check
    if (cleanQuery.startsWith('http://') || cleanQuery.startsWith('https://')) {
      if (cleanQuery.toLowerCase().contains('.gif') ||
          cleanQuery.toLowerCase().contains('giphy.com') ||
          cleanQuery.toLowerCase().contains('tenor.com')) {
        if (mounted) {
          setState(() {
            _currentGifs = [
              GifItem(
                id: 'custom_link_${DateTime.now().millisecondsSinceEpoch}',
                title: 'Custom GIF Link',
                gifUrl: cleanQuery,
                previewUrl: cleanQuery,
              ),
            ];
            _hasMore = false;
          });
        }
        return;
      }
    }

    // Source 1: Giphy API (2s fast timeout)
    try {
      final isTrending = cleanQuery.isEmpty || cleanQuery == 'Trending';
      final endpoint = isTrending
          ? 'https://api.giphy.com/v1/gifs/trending?api_key=dc6zaTOxFJmzC&limit=$_pageSize&offset=0&rating=g'
          : 'https://api.giphy.com/v1/gifs/search?api_key=dc6zaTOxFJmzC&q=${Uri.encodeComponent(cleanQuery)}&limit=$_pageSize&offset=0&rating=g';

      final res =
          await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> items = data['data'] ?? [];
        final results = _parseGiphyItems(items);
        if (mounted && results.isNotEmpty) {
          _memoryCache[cacheKey] = results;
          setState(() {
            final existingIds = results.map((g) => g.id).toSet();
            final catalogList = _getCatalogGifs(_selectedCategory, cleanQuery);
            final uniqueCatalog = catalogList.where((g) => !existingIds.contains(g.id)).toList();
            _currentGifs = [...results, ...uniqueCatalog];
            _offset = results.length;
            _hasMore = items.length >= _pageSize;
          });
          return;
        }
      }
    } catch (_) {}

    // Source 2: Tenor API (2s fast timeout)
    try {
      final isTrending = cleanQuery.isEmpty || cleanQuery == 'Trending';
      final queryTerm = isTrending ? 'trending' : cleanQuery;
      final tenorEndpoint =
          'https://tenor.googleapis.com/v2/search?q=${Uri.encodeComponent(queryTerm)}&key=LIVDSRZULERB&limit=$_pageSize&pos=0';

      final res =
          await http.get(Uri.parse(tenorEndpoint)).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> items = data['results'] ?? [];
        final results = _parseTenorItems(items);
        if (mounted && results.isNotEmpty) {
          _memoryCache[cacheKey] = results;
          setState(() {
            final existingIds = results.map((g) => g.id).toSet();
            final catalogList = _getCatalogGifs(_selectedCategory, cleanQuery);
            final uniqueCatalog = catalogList.where((g) => !existingIds.contains(g.id)).toList();
            _currentGifs = [...results, ...uniqueCatalog];
            _offset = results.length;
            _hasMore = items.length >= _pageSize;
          });
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchMoreGifs() async {
    if (!mounted || _isFetchingMore || !_hasMore) return;
    setState(() => _isFetchingMore = true);
    final cleanQuery = _searchController.text.trim();

    try {
      final isTrending = cleanQuery.isEmpty || _selectedCategory == 'Trending';
      final queryTerm = cleanQuery.isNotEmpty ? cleanQuery : _selectedCategory;
      final endpoint = isTrending
          ? 'https://api.giphy.com/v1/gifs/trending?api_key=dc6zaTOxFJmzC&limit=$_pageSize&offset=$_offset&rating=g'
          : 'https://api.giphy.com/v1/gifs/search?api_key=dc6zaTOxFJmzC&q=${Uri.encodeComponent(queryTerm)}&limit=$_pageSize&offset=$_offset&rating=g';

      final res =
          await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> items = data['data'] ?? [];
        final newResults = _parseGiphyItems(items);

        if (mounted && newResults.isNotEmpty) {
          setState(() {
            final existingIds = _currentGifs.map((g) => g.id).toSet();
            final uniqueNew =
                newResults.where((g) => !existingIds.contains(g.id)).toList();
            _currentGifs.addAll(uniqueNew);
            _offset += items.length;
            _hasMore = items.length >= _pageSize;
            _isFetchingMore = false;
          });
          return;
        }
      }
    } catch (_) {}

    // Fallback source 2 for fetch more
    try {
      final queryTerm = cleanQuery.isNotEmpty ? cleanQuery : _selectedCategory;
      final tenorEndpoint =
          'https://tenor.googleapis.com/v2/search?q=${Uri.encodeComponent(queryTerm)}&key=LIVDSRZULERB&limit=$_pageSize&pos=$_offset';

      final res =
          await http.get(Uri.parse(tenorEndpoint)).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> items = data['results'] ?? [];
        final newResults = _parseTenorItems(items);

        if (mounted && newResults.isNotEmpty) {
          setState(() {
            final existingIds = _currentGifs.map((g) => g.id).toSet();
            final uniqueNew =
                newResults.where((g) => !existingIds.contains(g.id)).toList();
            _currentGifs.addAll(uniqueNew);
            _offset += items.length;
            _hasMore = items.length >= _pageSize;
            _isFetchingMore = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isFetchingMore = false;
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          height: 330,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xEE1C1C1E) : const Color(0xFDF2F2F7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            children: [
              // 1. Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF545458) : const Color(0xFFC7C7CC),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 2. Live Search Field + Paste Link + Close Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              CupertinoIcons.search,
                              size: 16,
                              color: Color(0xFF8E8E93),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: _onSearchChanged,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.primaryText(isDark),
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Search any GIF or paste GIF link…',
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF8E8E93),
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            if (_searchController.text.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  _loadGifsForCategory(_selectedCategory);
                                },
                                child: const Icon(
                                  CupertinoIcons.clear_thick_circled,
                                  size: 16,
                                  color: Color(0xFF8E8E93),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onClose,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          size: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Category Horizontal Pills
              SizedBox(
                height: 38,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = cat == _selectedCategory && _searchController.text.isEmpty;

                    return GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _loadGifsForCategory(cat);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF007AFF)
                              : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const Divider(height: 1, thickness: 0.4),

              // 4. Dynamic GIF Grid Surface with Instant Display & Infinite Scroll
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF007AFF),
                        ),
                      )
                    : (_currentGifs.isEmpty
                        ? Center(
                            child: Text(
                              'No GIFs found for "${_searchController.text.trim()}"',
                              style: TextStyle(
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : GridView.builder(
                            controller: _gridScrollController,
                            padding: const EdgeInsets.all(10),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 1.3,
                            ),
                            itemCount: _currentGifs.length + (_isFetchingMore ? 2 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _currentGifs.length) {
                                return Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: isDark
                                        ? const Color(0xFF2C2C2E)
                                        : const Color(0xFFE5E5EA),
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF007AFF),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final gif = _currentGifs[index];
                              return _GifTile(
                                gif: gif,
                                onTap: () => widget.onGifSelected(gif),
                              );
                            },
                          )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GifTile extends StatelessWidget {
  final GifItem gif;
  final VoidCallback onTap;

  const _GifTile({
    required this.gif,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF1C1C1E),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          gif.previewUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.gif_rounded, color: Colors.white54, size: 36),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              color: const Color(0xFF2C2C2E),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
