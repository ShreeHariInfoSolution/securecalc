import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/app_map_layer.dart';
import 'package:securecalc/src/core/widgets/glass_kit.dart';
import 'package:securecalc/src/features/chat/domain/models/location_share_model.dart';
import 'package:securecalc/src/features/chat/domain/services/live_location_tracker_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:securecalc/src/features/chat/domain/services/socket_chat_service.dart';
import 'package:securecalc/src/features/chat/presentation/pages/live_location_map_page.dart';
import 'package:securecalc/src/features/chat/presentation/widgets/live_location_widgets.dart';

class LocationMessageBubble extends StatefulWidget {
  final String rawMessage;
  final String? messageId;
  final bool isMe, isDark;
  final int chatHeadId;
  final Widget timestamp;

  const LocationMessageBubble({
    super.key,
    required this.rawMessage,
    required this.messageId,
    required this.isMe,
    required this.isDark,
    required this.chatHeadId,
    required this.timestamp,
  });

  @override
  State<LocationMessageBubble> createState() => _LocationMessageBubbleState();
}

class _LocationMessageBubbleState extends State<LocationMessageBubble> {
  LocationShareModel? _model;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _model = LocationMessageResolver.tryParse(widget.rawMessage);
    if (_model == null) _load();
  }

  @override
  void didUpdateWidget(LocationMessageBubble old) {
    super.didUpdateWidget(old);
    if (old.rawMessage != widget.rawMessage) {
      _model = LocationMessageResolver.tryParse(widget.rawMessage);
      if (_model == null) _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    LocationShareModel? m;
    try {
      var id = LocationMessageResolver.tryId(widget.rawMessage);
      if (id == null && widget.messageId != null) {
        id = int.tryParse(widget.messageId!);
      }
      if (id != null) {
        m = await ServerApiService.instance.getLocationById(locationId: id);
      }
    } catch (e) {
      debugPrint('[LOC BUBBLE] Load error: $e');
    }
    if (!mounted) return;
    setState(() {
      _model = m;
      _loading = false;
      _failed = m == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_model != null) {
      return LocationChatBubble(
        key: ValueKey(_model!.id),
        location: _model!,
        isMe: widget.isMe,
        isDark: widget.isDark,
        chatHeadId: widget.chatHeadId,
        timestamp: widget.timestamp,
      );
    }
    final bg = widget.isMe
        ? AppPreferences.getChatBubbleColor(chatId: widget.chatHeadId.toString())
        : AppTheme.receivedBubble(widget.isDark);
    final fg = bg.computeLuminance() < 0.5 ? Colors.white : Colors.black87;
    return Material(
      color: Colors.transparent,
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Container(
            width: 240,
            height: 130,
            color: bg,
            child: Center(
              child: _failed
                  ? GlassSurface(
                      radius: 18,
                      blurEnabled: false,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_off_rounded, color: fg, size: 22),
                          const SizedBox(height: 4),
                          Text(
                            'Location unavailable',
                            style: TextStyle(color: fg, fontSize: 13, decoration: TextDecoration.none),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 28),
                            onPressed: _load,
                            child: const Text(
                              'Retry',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const CupertinoActivityIndicator(),
            ),
          ),
        ),
      ),
    );
  }
}

class LocationChatBubble extends StatefulWidget {
  final LocationShareModel location;
  final bool isMe;
  final bool isDark;
  final int chatHeadId;
  final Widget timestamp;

  const LocationChatBubble({
    super.key,
    required this.location,
    required this.isMe,
    required this.isDark,
    required this.chatHeadId,
    required this.timestamp,
  });

  @override
  State<LocationChatBubble> createState() => _LocationChatBubbleState();
}

class _LocationChatBubbleState extends State<LocationChatBubble> {
  late LocationShareModel _loc = widget.location;
  final MapController _map = MapController();
  bool _mapReady = false;
  StreamSubscription? _upSub;
  StreamSubscription? _endSub;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (_loc.isLive) {
      if (widget.isMe) {
        LiveLocationTrackerService.instance.positionNotifier.addListener(_onMyPos);
      }
      _upSub = SocketChatService.instance.onLiveLocationUpdate.listen(_onUpdate);
      _endSub = SocketChatService.instance.onLiveLocationEnded.listen(_onEnded);
      _tick = Timer.periodic(const Duration(seconds: 20), (_) {
        if (mounted) setState(() {});
      });
    }
    _refresh();
    SocketChatService.instance.connectionStateNotifier.addListener(_onConn);
    LocationIdentity.prefetch(_loc.userId).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _refresh() async {
    if (!_loc.isLive) return;
    final fresh = await ServerApiService.instance.getLocationById(locationId: _loc.id);
    if (fresh != null && mounted) {
      setState(() => _loc = fresh.copyWith(
          userName: fresh.userName ?? _loc.userName,
          userAvatar: fresh.userAvatar ?? _loc.userAvatar));
    }
  }

  void _onConn() {
    if (SocketChatService.instance.connectionStateNotifier.value && _loc.isLive) {
      _refresh();
    }
  }

  void _onMyPos() {
    final t = LiveLocationTrackerService.instance;
    final p = t.positionNotifier.value;
    if (p == null || t.activeLocationId != _loc.id || !mounted) return;
    final dist = const Distance().distance(LatLng(_loc.latitude, _loc.longitude), LatLng(p.latitude, p.longitude));
    setState(() => _loc = _loc.copyWith(
        latitude: p.latitude, longitude: p.longitude, lastUpdateAt: DateTime.now()));
    if (_mapReady && dist >= 5.0) _map.move(LatLng(p.latitude, p.longitude), 15);
  }

  @override
  void didUpdateWidget(LocationChatBubble old) {
    super.didUpdateWidget(old);
    if (old.location.id != widget.location.id) _loc = widget.location;
  }

  @override
  void dispose() {
    LiveLocationTrackerService.instance.positionNotifier.removeListener(_onMyPos);
    SocketChatService.instance.connectionStateNotifier.removeListener(_onConn);
    _upSub?.cancel();
    _endSub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  int? _idOf(Map<String, dynamic> d) {
    final raw = d['location'] is Map ? d['location'] as Map : d;
    return int.tryParse('${raw['location_id'] ?? raw['id']}');
  }

  void _onUpdate(Map<String, dynamic> d) {
    final raw = d['location'] is Map ? Map<String, dynamic>.from(d['location'] as Map) : d;
    if (_idOf(d) != _loc.id || !mounted) return;
    final newLat = double.tryParse('${raw['latitude'] ?? raw['lat']}') ?? _loc.latitude;
    final newLng = double.tryParse('${raw['longitude'] ?? raw['lng'] ?? raw['lon']}') ?? _loc.longitude;
    final dist = const Distance().distance(LatLng(_loc.latitude, _loc.longitude), LatLng(newLat, newLng));
    setState(() => _loc = _loc.mergeJson(raw).copyWith(lastUpdateAt: DateTime.now()));
    if (_mapReady && dist >= 5.0) _map.move(LatLng(newLat, newLng), 15);
  }

  void _onEnded(Map<String, dynamic> d) {
    if (_idOf(d) != _loc.id || !mounted) return;
    final raw = d['location'] is Map ? Map<String, dynamic>.from(d['location'] as Map) : null;
    setState(() {
      final m = raw != null ? _loc.mergeJson(raw) : _loc;
      _loc = m.copyWith(status: 'ended', endedAt: m.endedAt ?? DateTime.now());
    });
  }

  String _until(DateTime? t) {
    if (t == null) return 'Live location';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return 'Live until $h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  double? get _progress {
    final s = _loc.startedAt;
    final e = _loc.expiresAt;
    if (s == null || e == null) return null;
    final total = e.difference(s).inSeconds;
    if (total <= 0) return null;
    return (e.difference(DateTime.now()).inSeconds / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final w = math.min(MediaQuery.sizeOf(context).width * 0.70, 270.0);
    final live = _loc.isLive;
    final active = _loc.isActive;
    final point = LatLng(_loc.latitude, _loc.longitude);
    final id = LocationIdentity.of(_loc, widget.chatHeadId, isMe: widget.isMe);
    const orange = Color(0xFFFF9500);
    final pinColor = active ? orange : Colors.grey;
    final bubbleBg = _bgForBubble;

    return Material(
      color: Colors.transparent,
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: SizedBox(
          width: w,
          child: Container(
            decoration: BoxDecoration(
              color: bubbleBg,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: widget.isDark ? 0.25 : 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 150,
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _map,
                          options: MapOptions(
                            initialCenter: point,
                            initialZoom: 15,
                            onMapReady: () => _mapReady = true,
                            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                          ),
                          children: [
                            const AppTileLayer(),
                            MarkerLayer(
                              markers: [
                                live
                                    ? PulsingAvatarPin.marker(
                                        point,
                                        name: id.name,
                                        imagePath: id.avatar,
                                        size: 34,
                                        color: pinColor,
                                        pulse: active,
                                      )
                                    : Marker(
                                        point: point,
                                        width: 40,
                                        height: 40,
                                        alignment: Alignment.topCenter,
                                        child: const Icon(
                                          Icons.location_on_rounded,
                                          size: 40,
                                          color: Color(0xFFEA4335),
                                        ),
                                      ),
                              ],
                            ),
                          ],
                        ),
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(onTap: _openMapViewer),
                          ),
                        ),
                        // top-left LIVE glass chip
                        if (live)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: GlassSurface(
                              radius: 12,
                              blurEnabled: false,
                              tint: widget.isDark
                                  ? Colors.black.withValues(alpha: 0.50)
                                  : Colors.white.withValues(alpha: 0.85),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  active
                                      ? const LiveDot(size: 7)
                                      : const Icon(Icons.location_off_rounded, size: 11, color: Colors.grey),
                                  const SizedBox(width: 5),
                                  Text(
                                    active ? 'LIVE' : 'ENDED',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                      color: active ? orange : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // bottom-right glass time pill (no blur: list item)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: widget.isDark
                                  ? Colors.black.withValues(alpha: 0.65)
                                  : Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: widget.isDark ? 0.25 : 0.18),
                                width: 0.6,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: widget.timestamp,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (live) _liveFooter(active, id),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color get _bgForBubble {
    if (widget.isMe) {
      return AppPreferences.getChatBubbleColor(chatId: widget.chatHeadId.toString());
    }
    return AppTheme.receivedBubble(widget.isDark);
  }

  Color get _fgForBubble {
    final bg = _bgForBubble;
    return bg.computeLuminance() < 0.5 ? Colors.white : Colors.black87;
  }

  Color get _fg2ForBubble {
    final bg = _bgForBubble;
    return bg.computeLuminance() < 0.5 ? Colors.white70 : Colors.black54;
  }

  Widget _liveFooter(bool active, ({String name, String? avatar}) id) {
    final fg = _fgForBubble;
    final fg2 = _fg2ForBubble;
    final isDarkBg = _bgForBubble.computeLuminance() < 0.5;
    final p = _progress;
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: (isDarkBg ? Colors.white : Colors.black)
            .withValues(alpha: isDarkBg ? 0.14 : 0.06),
        border: Border.all(
          color: (isDarkBg ? Colors.white : Colors.black).withValues(alpha: 0.10),
          width: 0.6,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.sensors_rounded : Icons.location_off_rounded,
                size: 18,
                color: active ? const Color(0xFFFF9500) : fg2,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? 'Live location' : 'Live location ended',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    Text(
                      active ? _until(_loc.expiresAt) : 'Sharing has stopped',
                      style: TextStyle(fontSize: 12, color: fg2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (active && p != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: p,
                minHeight: 3,
                backgroundColor: fg2.withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFF9500)),
              ),
            ),
          ],
          ValueListenableBuilder<int?>(
            valueListenable: LiveLocationTrackerService.instance.activeLocationIdNotifier,
            builder: (ctx, activeId, child) {
              if (!(active && widget.isMe && activeId == _loc.id)) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: GestureDetector(
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    await LiveLocationTrackerService.instance.stopTracking();
                    if (mounted) {
                      setState(() => _loc = _loc.copyWith(status: 'ended', endedAt: DateTime.now()));
                    }
                  },
                  child: const SizedBox(
                    width: double.infinity,
                    child: GlassSurface(
                      radius: 12,
                      blurEnabled: false,
                      tint: Colors.redAccent,
                      padding: EdgeInsets.symmetric(vertical: 9),
                      child: Center(
                        child: Text(
                          'Stop sharing',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openMapViewer() => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LiveLocationMapPage(
            chatHeadId: widget.chatHeadId,
            initialLocation: _loc,
          ),
        ),
      );
}
