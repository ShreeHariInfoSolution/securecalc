import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum AppMarkerStyle { avatar, redPin }

class AppMapMarker {
  const AppMapMarker({
    required this.id,
    required this.point,
    this.name = '',
    this.imagePath,
    this.color = Colors.blue,
    this.size = 44,
    this.style = AppMarkerStyle.avatar,
    this.pulse = false,
  });

  final String id;
  final LatLng point;
  final String name;
  final String? imagePath;
  final Color color;
  final double size;
  final AppMarkerStyle style;
  final bool pulse;
}

class AppMapCircle {
  const AppMapCircle(this.center, this.radiusMeters, this.color);

  final LatLng center;
  final double radiusMeters;
  final Color color;
}

/// Same API on both platforms. The view attaches its implementation.
class AppMapController {
  Future<void> Function(LatLng p, double zoom)? _animateTo;
  Future<void> Function(List<LatLng> pts, EdgeInsets pad, double maxZoom)? _fit;
  double Function()? _zoom;

  void attach({
    required Future<void> Function(LatLng, double) animateTo,
    required Future<void> Function(List<LatLng>, EdgeInsets, double) fit,
    required double Function() zoom,
  }) {
    _animateTo = animateTo;
    _fit = fit;
    _zoom = zoom;
  }

  void detach() => _animateTo = _fit = _zoom = null;

  Future<void> animateTo(LatLng p, {double zoom = 16}) async =>
      _animateTo?.call(p, zoom);

  Future<void> fit(
    List<LatLng> pts, {
    EdgeInsets padding = EdgeInsets.zero,
    double maxZoom = 17,
  }) async =>
      _fit?.call(pts, padding, maxZoom);

  double get zoom => _zoom?.call() ?? 16;
}
