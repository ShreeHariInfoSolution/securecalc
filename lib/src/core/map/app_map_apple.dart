import 'dart:async';

import 'package:apple_maps_flutter/apple_maps_flutter.dart' as am;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'app_map.dart';
import 'pin_renderer.dart';

am.LatLng _a(LatLng p) => am.LatLng(p.latitude, p.longitude);

class AppleMapImpl extends StatefulWidget {
  const AppleMapImpl({
    super.key,
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
    required this.markers,
    required this.circles,
    required this.bottomInset,
    required this.topInset,
    this.onUserGesture,
  });

  final AppMapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final List<AppMapMarker> markers;
  final List<AppMapCircle> circles;
  final double bottomInset;
  final double topInset;
  final VoidCallback? onUserGesture;

  @override
  State<AppleMapImpl> createState() => _AppleMapImplState();
}

class _AppleMapImplState extends State<AppleMapImpl> {
  am.AppleMapController? _c;
  Set<am.Annotation> _annotations = {};
  double _zoom = 16;
  bool _programmatic = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
    widget.controller.attach(
      animateTo: _animateTo,
      fit: _fit,
      zoom: () => _zoom,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildAnnotations();
  }

  @override
  void didUpdateWidget(covariant AppleMapImpl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildAnnotations();
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  Future<void> _rebuildAnnotations() async {
    final gen = ++_gen;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final set = <am.Annotation>{};
    for (final m in widget.markers) {
      final img = await PinRenderer.render(m, dpr);
      set.add(
        am.Annotation(
          annotationId: am.AnnotationId(m.id),
          position: _a(m.point),
          icon: am.BitmapDescriptor.fromBytes(img.bytes),
          anchor: const Offset(0.5, 1.0),
          zIndex: m.style == AppMarkerStyle.avatar ? 2 : 1,
        ),
      );
    }
    if (!mounted || gen != _gen) return;
    setState(() => _annotations = set);
  }

  Future<void> _animateTo(LatLng p, double zoom) async {
    _programmatic = true;
    _zoom = zoom;
    await _c?.animateCamera(am.CameraUpdate.newLatLngZoom(_a(p), zoom));
  }

  Future<void> _fit(List<LatLng> pts, EdgeInsets pad, double maxZoom) async {
    if (pts.isEmpty) return;
    _programmatic = true;
    if (pts.length == 1) return _animateTo(pts.first, 16);
    var minLat = pts.first.latitude;
    var maxLat = minLat;
    var minLng = pts.first.longitude;
    var maxLng = minLng;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    await _c?.animateCamera(
      am.CameraUpdate.newLatLngBounds(
        am.LatLngBounds(
          southwest: am.LatLng(minLat, minLng),
          northeast: am.LatLng(maxLat, maxLng),
        ),
        48,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return am.AppleMap(
      initialCameraPosition: am.CameraPosition(
        target: _a(widget.initialCenter),
        zoom: widget.initialZoom,
      ),
      onMapCreated: (c) => _c = c,
      annotations: _annotations,
      circles: {
        for (var i = 0; i < widget.circles.length; i++)
          am.Circle(
            circleId: am.CircleId('c$i'),
            center: _a(widget.circles[i].center),
            radius: widget.circles[i].radiusMeters,
            fillColor: widget.circles[i].color.withValues(alpha: 0.12),
            strokeColor: widget.circles[i].color.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
      },
      padding: EdgeInsets.only(
        top: widget.topInset,
        bottom: widget.bottomInset,
      ),
      myLocationEnabled: false,
      compassEnabled: false,
      pitchGesturesEnabled: false,
      onCameraMoveStarted: () {
        if (!_programmatic) widget.onUserGesture?.call();
      },
      onCameraIdle: () => _programmatic = false,
    );
  }
}
