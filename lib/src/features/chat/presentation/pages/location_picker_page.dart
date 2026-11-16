import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:securecalc/src/core/map/app_map.dart';
import 'package:securecalc/src/core/map/app_map_view.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/glass_kit.dart';
import 'package:securecalc/src/features/chat/domain/models/location_share_model.dart';
import 'package:securecalc/src/features/chat/domain/services/live_location_tracker_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:securecalc/src/features/chat/presentation/widgets/live_location_widgets.dart';

class LocationPickerPage extends StatefulWidget {
  final int chatHeadId;

  const LocationPickerPage({
    super.key,
    required this.chatHeadId,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final _map = AppMapController();
  Position? _currentPosition;
  bool _isLoadingPos = true;
  bool _isSending = false;
  StreamSubscription<Position>? _posSub;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    if (!mounted) return;
    setState(() => _isLoadingPos = true);
    final pos = await LiveLocationTrackerService.instance.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentPosition = pos;
        _isLoadingPos = false;
      });
      if (pos != null) {
        _map.animateTo(LatLng(pos.latitude, pos.longitude), zoom: 16.0);
        _posSub ??= Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((p) {
          if (!mounted) return;
          setState(() => _currentPosition = p);
          if (_follow) {
            _map.animateTo(
              LatLng(p.latitude, p.longitude),
              zoom: _map.zoom,
            );
          }
        });
      }
    }
  }

  Future<void> _sendCurrentLocation() async {
    if (_currentPosition == null || _isSending) return;

    setState(() => _isSending = true);
    try {
      final res = await ServerApiService.instance.shareLocation(
        chatHeadId: widget.chatHeadId,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        accuracy: _currentPosition!.accuracy,
        isLive: false,
      );

      if (res != null && mounted) {
        AppToast.show('Location shared successfully');
        Navigator.pop(context, res);
      } else if (mounted) {
        AppToast.show('Failed to share location', isError: true);
      }
    } catch (e) {
      debugPrint('[LOCATION PICKER] Send error: $e');
      if (mounted) AppToast.show('Error sharing location', isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _onShareLiveTap() async {
    final minutes = await showLiveDurationSheet(context);
    if (minutes != null) {
      _startLiveLocationShare(minutes);
    }
  }

  Future<void> _startLiveLocationShare(int durationMinutes) async {
    if (_currentPosition == null || _isSending) return;

    setState(() => _isSending = true);
    try {
      final res = await ServerApiService.instance.shareLocation(
        chatHeadId: widget.chatHeadId,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        accuracy: _currentPosition!.accuracy,
        isLive: true,
        durationMinutes: durationMinutes,
      );

      if (res != null) {
        final locData = res['location'] ?? res['data']?['location'];
        if (locData is Map<String, dynamic>) {
          final shareModel = LocationShareModel.fromJson(locData);
          await LiveLocationTrackerService.instance.startTracking(
            locationId: shareModel.id,
            chatHeadId: widget.chatHeadId,
            durationMinutes: durationMinutes,
            expiresAt: shareModel.expiresAt,
          );
        }

        if (mounted) {
          AppToast.show('Live location sharing started');
          Navigator.pop(context, res);
        }
      } else if (mounted) {
        AppToast.show('Failed to start live location', isError: true);
      }
    } catch (e) {
      debugPrint('[LOCATION PICKER] Live location error: $e');
      if (mounted) AppToast.show('Error starting live location', isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultLatLng = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(23.0225, 72.5714);

    return Scaffold(
      backgroundColor: AppTheme.chatCanvas(isDark),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: GlassCircleButton(
              icon: CupertinoIcons.chevron_left,
              size: 40,
              onTap: () => Navigator.pop(context),
            ),
          ),
        ),
        centerTitle: true,
        title: GlassPill(
          child: Text(
            'Send Location',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryText(isDark),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: GlassCircleButton(
                icon: CupertinoIcons.refresh,
                size: 40,
                onTap: _fetchCurrentLocation,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          AppMapView(
            controller: _map,
            initialCenter: defaultLatLng,
            initialZoom: 16.0,
            bottomInset: 190,
            onUserGesture: () => _follow = false,
            circles: [
              if (_currentPosition != null)
                AppMapCircle(
                  defaultLatLng,
                  _currentPosition!.accuracy,
                  AppTheme.primaryColor,
                ),
            ],
            markers: [
              if (_currentPosition != null)
                AppMapMarker(
                  id: 'me',
                  point: defaultLatLng,
                  name: LocationIdentity.me().name,
                  imagePath: LocationIdentity.me().avatar,
                  color: AppTheme.primaryColor,
                ),
            ],
          ),

          if (_isLoadingPos)
            Positioned(
              top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
              left: 0,
              right: 0,
              child: Center(
                child: GlassSurface(
                  radius: 20,
                  blurEnabled: false,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CupertinoActivityIndicator(radius: 8),
                      const SizedBox(width: 8),
                      Text(
                        'Locating GPS position...',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.primaryText(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_currentPosition == null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
              left: 16,
              right: 16,
              child: GlassSurface(
                radius: 18,
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                child: Row(
                  children: [
                    const Icon(Icons.location_off_rounded, color: Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Location is off or permission denied',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.primaryText(isDark),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final p = await Geolocator.checkPermission();
                        if (p == LocationPermission.deniedForever) {
                          await Geolocator.openAppSettings();
                        } else {
                          await Geolocator.openLocationSettings();
                        }
                      },
                      child: const Text('Turn on'),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: GlassCircleButton(
                    icon: CupertinoIcons.location_fill,
                    onTap: () {
                      _follow = true;
                      if (_currentPosition != null) {
                        _map.animateTo(
                          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                          zoom: 16,
                        );
                      } else {
                        _fetchCurrentLocation();
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                GlassSurface(
                  radius: 28,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlassActionRow(
                        leading: GlassIconBadge(
                          icon: Icons.location_on_rounded,
                          color: AppTheme.primaryColor,
                        ),
                        title: 'Send your current location',
                        subtitle: _currentPosition == null
                            ? 'Locating…'
                            : 'Accurate to ${_currentPosition!.accuracy.toStringAsFixed(0)} meters',
                        onTap: _currentPosition == null ? null : _sendCurrentLocation,
                        trailing: _isSending
                            ? const CupertinoActivityIndicator(radius: 10)
                            : Icon(
                                CupertinoIcons.chevron_right,
                                size: 16,
                                color: AppTheme.secondaryText(isDark),
                              ),
                      ),
                      Divider(
                        height: 1,
                        indent: 64,
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.08),
                      ),
                      ValueListenableBuilder<int?>(
                        valueListenable: LiveLocationTrackerService
                            .instance.activeLocationIdNotifier,
                        builder: (_, __, ___) {
                          final t = LiveLocationTrackerService.instance;
                          final sharing = t.isTracking &&
                              t.activeChatHeadId == widget.chatHeadId;

                          if (sharing) {
                            return GlassActionRow(
                              leading: const GlassIconBadge(
                                icon: CupertinoIcons.stop_circle_fill,
                                color: Colors.redAccent,
                              ),
                              title: 'Stop sharing live location',
                              titleColor: Colors.redAccent,
                              subtitle: 'Currently sharing your live movement',
                              onTap: () async => await t.stopTracking(),
                              trailing: const LiveDot(color: Colors.redAccent),
                            );
                          }

                          return GlassActionRow(
                            leading: const GlassIconBadge(
                              icon: CupertinoIcons.antenna_radiowaves_left_right,
                              color: Color(0xFFFF9500),
                            ),
                            title: 'Share live location…',
                            subtitle: 'Updates in real time until the timer ends',
                            onTap: _currentPosition == null ? null : _onShareLiveTap,
                            trailing: Icon(
                              CupertinoIcons.chevron_right,
                              size: 16,
                              color: AppTheme.secondaryText(isDark),
                            ),
                          );
                        },
                      ),
                    ],
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
