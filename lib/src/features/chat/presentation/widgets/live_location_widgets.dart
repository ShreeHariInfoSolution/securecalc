import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/features/chat/domain/models/location_share_model.dart';
import 'package:securecalc/src/features/chat/domain/services/local_chat_storage.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';

class LocationIdentity {
  static final Map<int, ({String name, String? avatar})> _cache = {};

  static Future<void> prefetch(int? userId) async {
    if (userId == null || _cache.containsKey(userId)) return;
    final u = await ServerApiService.instance.getUser(userId);
    if (u != null) _cache[userId] = (name: u.name, avatar: u.avatar);
  }

  static ({String name, String? avatar}) me() {
    final u = ServerApiService.instance.currentUser;
    final ok = u != null && u.name.isNotEmpty && !u.name.startsWith('User #');
    return (
      name: ok ? u.name : 'You',
      avatar: (u?.avatar?.isNotEmpty == true) ? u!.avatar : null,
    );
  }

  static ({String name, String? avatar}) of(
      LocationShareModel l, int chatHeadId, {required bool isMe}) {
    if (isMe) return me();
    var name = l.userName ?? '';
    var avatar = l.userAvatar;
    final convs = LocalChatStorage.instance.conversationsNotifier.value;
    for (final c in convs) {
      final byPeer = l.userId != null && c.peerUserId.toString() == l.userId.toString();
      final byChat = name.isEmpty && c.id == chatHeadId.toString(); // direct chats only
      if (byPeer || byChat) {
        if (name.isEmpty) name = c.name;
        if ((avatar ?? '').isEmpty && c.avatarUrl.isNotEmpty) avatar = c.avatarUrl;
        break;
      }
    }
    final cached = l.userId == null ? null : _cache[l.userId!];
    if (cached != null) {
      if (name.isEmpty) name = cached.name;
      if ((avatar ?? '').isEmpty) avatar = cached.avatar;
    }
    return (name: name.isEmpty ? 'User' : name, avatar: avatar);
  }
}

class AvatarMapPin extends StatelessWidget {
  const AvatarMapPin({
    super.key,
    required this.name,
    this.imagePath,
    required this.color,
    this.size = 44,
  });
  final String name;
  final String? imagePath;
  final Color color;
  final double size;

  /// The tip of the pin sits exactly on the coordinate.
  static Marker marker(
    LatLng p, {
    required String name,
    String? imagePath,
    required Color color,
    double size = 44,
  }) {
    final h = (size + 14) * 2.2;
    return Marker(
      point: p,
      width: size + 16,
      height: h,
      alignment: Alignment.center,
      child: SizedBox(
        width: size + 16,
        height: h,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: h / 2,
              child: Center(
                child: AvatarMapPin(
                  name: name,
                  imagePath: imagePath,
                  color: color,
                  size: size,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: IosAvatar(
                  name: name,
                  imagePath: imagePath,
                  size: size - 6,
                  showOnline: false,
                ),
              ),
              CustomPaint(size: const Size(12, 8), painter: _TipPainter(color)),
            ],
          ),
        ),
      );
}

class _TipPainter extends CustomPainter {
  _TipPainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) => canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(s.width, 0)
          ..lineTo(s.width / 2, s.height)
          ..close(),
        Paint()..color = c,
      );
  @override
  bool shouldRepaint(_TipPainter o) => o.c != c;
}

class PulsingAvatarPin extends StatefulWidget {
  const PulsingAvatarPin({
    super.key,
    required this.name,
    this.imagePath,
    required this.color,
    this.size = 44,
    this.pulse = true,
  });
  final String name;
  final String? imagePath;
  final Color color;
  final double size;
  final bool pulse;

  /// The tip of the pin sits exactly on the coordinate; the ripple is on the ground at the tip.
  static Marker marker(
    LatLng p, {
    required String name,
    String? imagePath,
    required Color color,
    double size = 44,
    bool pulse = true,
  }) {
    final box = (size + 14) * 2.2;
    return Marker(
      point: p,
      width: box,
      height: box,
      alignment: Alignment.center,
      child: PulsingAvatarPin(
        name: name,
        imagePath: imagePath,
        color: color,
        size: size,
        pulse: pulse,
      ),
    );
  }

  @override
  State<PulsingAvatarPin> createState() => _PulsingAvatarPinState();
}

class _PulsingAvatarPinState extends State<PulsingAvatarPin> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat();
  }

  @override
  void didUpdateWidget(PulsingAvatarPin o) {
    super.didUpdateWidget(o);
    if (widget.pulse && !_c.isAnimating) _c.repeat();
    if (!widget.pulse) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = (widget.size + 14) * 2.2;
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.pulse)
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Container(
                width: box * (0.30 + 0.60 * _c.value),
                height: box * (0.30 + 0.60 * _c.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.28 * (1 - _c.value)),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: box / 2,
            child: Center(
              child: AvatarMapPin(
                name: widget.name,
                imagePath: widget.imagePath,
                color: widget.color,
                size: widget.size,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LocationMessageResolver {
  static LocationShareModel? tryParse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      dynamic d = jsonDecode(s);
      if (d is String) d = jsonDecode(d); // double-encoded
      if (d is! Map) return null;
      var m = Map<String, dynamic>.from(d);
      for (var i = 0; i < 3; i++) {
        if (m['latitude'] != null || m['lat'] != null || m['location_lat'] != null) break;
        final inner = m['location'] ?? m['data'] ?? m['loc'];
        if (inner is Map) {
          m = Map<String, dynamic>.from(inner);
        } else {
          break;
        }
      }
      m['latitude'] ??= m['lat'] ?? m['location_lat'] ?? m['locationLat'];
      m['longitude'] ??= m['lng'] ?? m['lon'] ?? m['long'] ?? m['location_lng'] ?? m['locationLng'];

      final lat = double.tryParse('${m['latitude']}');
      final lng = double.tryParse('${m['longitude']}');
      if (lat != null && lng != null && (lat != 0.0 || lng != 0.0)) {
        m['latitude'] = lat;
        m['longitude'] = lng;
        return LocationShareModel.fromJson(m);
      }
    } catch (_) {}
    return null;
  }

  static int? tryId(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      final d = jsonDecode(s);
      if (d is Map) {
        final v = d['location_id'] ??
            d['locationId'] ??
            (d['location'] is Map ? d['location']['id'] : null) ??
            d['id'];
        final id = int.tryParse('$v');
        if (id != null) return id;
      } else if (d is int) {
        return d;
      }
    } catch (_) {}
    final m = RegExp(r'(\d{1,12})$').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }
}

class MapGlass extends StatelessWidget {
  const MapGlass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: isDark
                  ? const Color(0xE61C1C1E) // ~90% dark: text stays readable
                  : Colors.white.withValues(alpha: 0.78),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.70),
                width: 0.8,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

