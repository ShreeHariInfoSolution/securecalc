import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'app_map.dart';
import 'app_map_apple.dart';
import 'app_map_flutter.dart';

class AppMapView extends StatelessWidget {
  const AppMapView({
    super.key,
    required this.controller,
    required this.initialCenter,
    this.initialZoom = 16,
    this.markers = const [],
    this.circles = const [],
    this.bottomInset = 0,
    this.topInset = 0,
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
  Widget build(BuildContext context) {
    final systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final appDark = Theme.of(context).brightness == Brightness.dark;

    // Apple Map follows system theme; if app theme matches system theme on iOS, use Apple Map
    final useApple = Platform.isIOS && systemDark == appDark;

    return useApple
        ? AppleMapImpl(
            controller: controller,
            initialCenter: initialCenter,
            initialZoom: initialZoom,
            markers: markers,
            circles: circles,
            bottomInset: bottomInset,
            topInset: topInset,
            onUserGesture: onUserGesture,
          )
        : FlutterMapImpl(
            controller: controller,
            initialCenter: initialCenter,
            initialZoom: initialZoom,
            markers: markers,
            circles: circles,
            onUserGesture: onUserGesture,
          );
  }
}
