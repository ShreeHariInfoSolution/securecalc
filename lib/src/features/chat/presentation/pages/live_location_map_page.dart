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
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/features/chat/domain/models/location_share_model.dart';
import 'package:securecalc/src/features/chat/domain/services/live_location_tracker_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:securecalc/src/features/chat/domain/services/socket_chat_service.dart';
import 'package:securecalc/src/features/chat/presentation/widgets/live_location_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class LiveLocationMapPage extends StatefulWidget {
  final int chatHeadId;
  final LocationShareModel? initialLocation;

  const LiveLocationMapPage({
    super.key,
    required this.chatHeadId,
    this.initialLocation,
  });

  @override
  State<LiveLocationMapPage> createState() => _LiveLocationMapPageState();
}

class _LiveLocationMapPageState extends State<LiveLocationMapPage> {
  final _map = AppMapController();
  final Map<int, LocationShareModel> _locations = {};

  Position? _me;
  StreamSubscription<Position>? _meSub;
  StreamSubscription? _updateSub;
  StreamSubscription? _endedSub;
  bool _isLoading = true;

  int get _myId => ServerApiService.instance.currentUserId ?? -1;

  bool _isMine(LocationShareModel l) =>
      (l.userId != null && l.userId == _myId) ||
      LiveLocationTrackerService.instance.activeLocationId == l.id;

  List<LocationShareModel> get _latestPerUser {
    final m = <int, LocationShareModel>{};
    for (final l in _locations.values) {
      final k = l.userId ?? -l.id;
      final cur = m[k];
      if (cur == null ||
          (l.isActive && !cur.isActive) ||
          (l.isActive == cur.isActive && l.id > cur.id)) {
        m[k] = l;
      }
    }
    return m.values.toList();
  }

  List<LocationShareModel> get _others =>
      _latestPerUser.where((l) => !_isMine(l)).toList();

  @override
  void initState() {
    super.initState();
    final init = widget.initialLocation;
    if (init != null) {
      _locations[init.id] = init;
      if (init.isLive) {
        ServerApiService.instance.getLocationById(locationId: init.id).then((fresh) {
          if (fresh != null && mounted) {
            setState(() => _locations[fresh.id] = fresh);
            _fitAll();
          }
        });
      }
    }
    _loadActiveLocations();

    LiveLocationTrackerService.instance.getCurrentPosition().then((p) {
      if (!mounted || p == null) return;
      setState(() => _me = p);
      _fitAll();
    });

    _meSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((p) {
      if (mounted) setState(() => _me = p);
    });

    _updateSub = SocketChatService.instance.onLiveLocationUpdate.listen(_handleSocketUpdate);
    _endedSub = SocketChatService.instance.onLiveLocationEnded.listen(_handleSocketEnded);
  }

  @override
  void dispose() {
    _meSub?.cancel();
    _updateSub?.cancel();
    _endedSub?.cancel();
    super.dispose();
  }

  Future<void> _loadActiveLocations() async {
    try {
      final list = await ServerApiService.instance.getActiveLiveLocations(
        chatHeadId: widget.chatHeadId,
      );
      if (mounted) {
        setState(() {
          for (final loc in list) {
            _locations[loc.id] = loc;
            unawaited(LocationIdentity.prefetch(loc.userId));
          }
          _isLoading = false;
        });
        _fitAll();
      }
    } catch (e) {
      debugPrint('[LIVE MAP] Load active locations error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _fitAll() {
    final pts = <LatLng>[
      if (_me != null) LatLng(_me!.latitude, _me!.longitude),
      ..._others.map((l) => LatLng(l.latitude, l.longitude)),
    ];
    if (pts.isEmpty) return;
    final topPadding = kToolbarHeight + MediaQuery.paddingOf(context).top + 24;
    _map.fit(
      pts,
      padding: EdgeInsets.fromLTRB(60, topPadding, 60, 320),
      maxZoom: 17,
    );
  }

  void _handleSocketUpdate(Map<String, dynamic> data) {
    final raw = data['location'] is Map
        ? Map<String, dynamic>.from(data['location'] as Map)
        : data;
    final id = int.tryParse('${raw['location_id'] ?? raw['id']}');
    if (id == null || !mounted) return;
    setState(() {
      final old = _locations[id];
      if (old != null) {
        _locations[id] = old.mergeJson(raw);
      } else {
        try {
          final m = LocationShareModel.fromJson(raw);
          if (m.chatHeadId == widget.chatHeadId) {
            _locations[id] = m;
            unawaited(LocationIdentity.prefetch(m.userId));
          }
        } catch (_) {}
      }
    });
  }

  void _handleSocketEnded(Map<String, dynamic> data) {
    try {
      final locData = data['location'] is Map
          ? Map<String, dynamic>.from(data['location'] as Map)
          : data;
      final locId = int.tryParse('${locData['id'] ?? locData['location_id']}');
      if (locId != null && _locations.containsKey(locId) && mounted) {
        setState(() {
          final old = _locations[locId]!;
          final merged = locData['latitude'] != null ? old.mergeJson(locData) : old;
          _locations[locId] = merged.copyWith(
            status: 'ended',
            endedAt: merged.endedAt ?? DateTime.now(),
          );
        });
      }
    } catch (e) {
      debugPrint('[LIVE MAP] Socket ended error: $e');
    }
  }

  Future<void> _stopMySharing(int locationId) async {
    try {
      await LiveLocationTrackerService.instance.stopTracking();
      if (mounted) {
        setState(() {
          if (_locations.containsKey(locationId)) {
            final old = _locations[locationId]!;
            _locations[locationId] = old.copyWith(
              status: 'ended',
              endedAt: DateTime.now(),
            );
          }
        });
        AppToast.show('Live location sharing stopped');
      }
    } catch (e) {
      debugPrint('[LIVE MAP] Stop sharing error: $e');
    }
  }

  String _timeAgo(DateTime? time) {
    if (time == null) return 'recently';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 10) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  String _endsIn(LocationShareModel l) {
    final left = l.expiresAt?.difference(DateTime.now());
    if (left == null || left.isNegative) return '';
    if (left.inHours >= 1) return ' · ends in ${left.inHours}h ${left.inMinutes % 60}m';
    return left.inMinutes < 1 ? ' · ends in <1m' : ' · ends in ${left.inMinutes}m';
  }

  Widget _avatarRing(String name, String? img, Color c) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c, width: 2),
        ),
        child: IosAvatar(name: name, imagePath: img, size: 40, showOnline: false),
      );

  Widget _sharerRow(LocationShareModel l, bool isDark) {
    final id = LocationIdentity.of(l, widget.chatHeadId, isMe: false);
    final live = l.isLive && l.isActive;
    final sub = !l.isLive
        ? 'Shared location'
        : l.isActive
            ? 'Updated ${_timeAgo(l.lastUpdateAt ?? l.startedAt)}${_endsIn(l)}'
            : 'Sharing ended';
    return GlassActionRow(
      leading: _avatarRing(id.name, id.avatar, live ? const Color(0xFFFF9500) : Colors.grey),
      title: id.name,
      subtitle: sub,
      onTap: () => _map.animateTo(LatLng(l.latitude, l.longitude), zoom: 16),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[const LiveDot(), const SizedBox(width: 10)],
          GlassCircleButton(
            icon: Icons.directions_rounded,
            size: 38,
            blurEnabled: false,
            onTap: () => launchUrl(
              Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${l.latitude},${l.longitude}'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }

  Widget _meRow(bool isDark) {
    final me = LocationIdentity.me();
    return GlassActionRow(
      leading: _avatarRing(me.name, me.avatar, AppTheme.primaryColor),
      title: 'You',
      subtitle: _me != null ? 'Accurate to ${_me!.accuracy.round()} m' : 'Locating…',
      onTap: () {
        if (_me != null) {
          _map.animateTo(LatLng(_me!.latitude, _me!.longitude), zoom: 16);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final anyActive = _locations.values.any((l) => l.isActive) ||
        (LiveLocationTrackerService.instance.isTracking &&
            LiveLocationTrackerService.instance.activeChatHeadId == widget.chatHeadId);

    final initialCenter = _me != null
        ? LatLng(_me!.latitude, _me!.longitude)
        : widget.initialLocation != null
            ? LatLng(widget.initialLocation!.latitude, widget.initialLocation!.longitude)
            : const LatLng(23.0225, 72.5714);

    final isMyActiveShare = LiveLocationTrackerService.instance.isTracking &&
        LiveLocationTrackerService.instance.activeChatHeadId == widget.chatHeadId;

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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (anyActive) ...[const LiveDot(), const SizedBox(width: 7)],
              Text(
                anyActive ? 'Live Location' : 'Location',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryText(isDark),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          AppMapView(
            controller: _map,
            initialCenter: initialCenter,
            initialZoom: 15.0,
            bottomInset: 320,
            topInset: kToolbarHeight + MediaQuery.paddingOf(context).top,
            circles: [
              if (_me != null)
                AppMapCircle(
                  LatLng(_me!.latitude, _me!.longitude),
                  _me!.accuracy,
                  AppTheme.primaryColor,
                ),
            ],
            markers: [
              for (final l in _others)
                if (!l.isLive)
                  AppMapMarker(
                    id: 'p${l.id}',
                    point: LatLng(l.latitude, l.longitude),
                    style: AppMarkerStyle.redPin,
                  )
                else
                  () {
                    final id = LocationIdentity.of(l, widget.chatHeadId, isMe: false);
                    return AppMapMarker(
                      id: 'u${l.userId ?? -l.id}',
                      point: LatLng(l.latitude, l.longitude),
                      name: id.name,
                      imagePath: id.avatar,
                      color: l.isActive ? const Color(0xFFFF9500) : Colors.grey,
                      pulse: l.isActive,
                    );
                  }(),
              if (_me != null)
                AppMapMarker(
                  id: 'me',
                  point: LatLng(_me!.latitude, _me!.longitude),
                  name: LocationIdentity.me().name,
                  imagePath: LocationIdentity.me().avatar,
                  color: AppTheme.primaryColor,
                ),
            ],
          ),

          if (_isLoading)
            const Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: CupertinoActivityIndicator(radius: 12),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlassCircleButton(icon: Icons.fit_screen_rounded, onTap: _fitAll),
                      const SizedBox(height: 10),
                      GlassCircleButton(
                        icon: CupertinoIcons.location_fill,
                        onTap: () {
                          if (_me != null) {
                            _map.animateTo(LatLng(_me!.latitude, _me!.longitude), zoom: 16);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassSurface(
                  radius: 28,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.30,
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          children: [
                            for (final l in _others) _Tick(builder: (_) => _sharerRow(l, isDark)),
                            if (_me != null) _meRow(isDark),
                          ],
                        ),
                      ),
                      if (isMyActiveShare &&
                          LiveLocationTrackerService.instance.activeLocationId != null) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => _stopMySharing(
                            LiveLocationTrackerService.instance.activeLocationId!,
                          ),
                          child: const SizedBox(
                            width: double.infinity,
                            child: GlassSurface(
                              radius: 18,
                              tint: Colors.redAccent,
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    CupertinoIcons.stop_circle_fill,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Stop Sharing Live Location',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
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

class _Tick extends StatelessWidget {
  const _Tick({required this.builder});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
        stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
        builder: (c, _) => builder(c),
      );
}
