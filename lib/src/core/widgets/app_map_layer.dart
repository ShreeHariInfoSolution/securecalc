import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

class AppTileLayer extends StatelessWidget {
  const AppTileLayer({super.key});

  static const _osmUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  // Dark mode filter matrix to convert light OSM tiles into sleek dark mode map tiles without API keys
  static const List<double> _darkMapMatrix = <double>[
    -0.2, -0.6, -0.1, 0, 220,
    -0.2, -0.6, -0.1, 0, 230,
    -0.1, -0.5, -0.1, 0, 245,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget tileLayer = TileLayer(
      key: ValueKey(isDark),
      urlTemplate: _osmUrl,
      subdomains: const ['a', 'b', 'c', 'd'],
      maxNativeZoom: 19,
      maxZoom: 19,
      keepBuffer: 3,
      panBuffer: 1,
      fallbackUrl: _osmUrl,
      userAgentPackageName: 'com.securecalc.chat',
    );

    if (isDark) {
      tileLayer = ColorFiltered(
        key: const ValueKey('dark_map_filtered'),
        colorFilter: const ColorFilter.matrix(_darkMapMatrix),
        child: tileLayer,
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: tileLayer,
    );
  }
}
