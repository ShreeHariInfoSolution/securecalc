import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';
import 'package:securecalc/src/core/widgets/app_map_layer.dart';
import 'package:securecalc/src/features/chat/presentation/widgets/live_location_widgets.dart';

import 'app_map.dart';

class FlutterMapImpl extends StatefulWidget {
  const FlutterMapImpl({
    super.key,
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
    required this.markers,
    required this.circles,
    this.onUserGesture,
  });

  final AppMapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final List<AppMapMarker> markers;
  final List<AppMapCircle> circles;
  final VoidCallback? onUserGesture;

  @override
  State<FlutterMapImpl> createState() => _FlutterMapImplState();
}

class _FlutterMapImplState extends State<FlutterMapImpl>
    with TickerProviderStateMixin {
  late final _anim = AnimatedMapController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    curve: Curves.easeInOutCubic,
  );

  @override
  void initState() {
    super.initState();
    widget.controller.attach(
      animateTo: (p, z) => _anim.animateTo(dest: p, zoom: z),
      fit: (pts, pad, maxZoom) => _anim.animatedFitCamera(
        cameraFit: CameraFit.coordinates(
          coordinates: pts,
          padding: pad,
          maxZoom: maxZoom,
        ),
      ),
      zoom: () => _anim.mapController.camera.zoom,
    );
  }

  @override
  void dispose() {
    widget.controller.detach();
    _anim.dispose();
    super.dispose();
  }

  Marker _toMarker(AppMapMarker m) {
    if (m.style == AppMarkerStyle.redPin) {
      return Marker(
        point: m.point,
        width: 40,
        height: 40,
        alignment: Alignment.topCenter,
        child: const Icon(
          Icons.location_on_rounded,
          size: 40,
          color: Color(0xFFEA4335),
        ),
      );
    }
    return PulsingAvatarPin.marker(
      m.point,
      name: m.name,
      imagePath: m.imagePath,
      color: m.color,
      size: m.size,
      pulse: m.pulse,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _anim.mapController,
      options: MapOptions(
        initialCenter: widget.initialCenter,
        initialZoom: widget.initialZoom,
        onPositionChanged: (_, hasGesture) {
          if (hasGesture) widget.onUserGesture?.call();
        },
      ),
      children: [
        const AppTileLayer(),
        CircleLayer(
          circles: [
            for (final c in widget.circles)
              CircleMarker(
                point: c.center,
                radius: c.radiusMeters,
                useRadiusInMeter: true,
                color: c.color.withValues(alpha: 0.12),
                borderColor: c.color.withValues(alpha: 0.4),
                borderStrokeWidth: 1,
              ),
          ],
        ),
        MarkerLayer(
          markers: widget.markers.map(_toMarker).toList(),
        ),
      ],
    );
  }
}
