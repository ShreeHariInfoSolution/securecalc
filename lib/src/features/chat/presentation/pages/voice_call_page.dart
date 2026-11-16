import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/app_toast.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/services/call_service.dart';

class VoiceCallPage extends StatefulWidget {
  const VoiceCallPage({super.key});

  @override
  State<VoiceCallPage> createState() => _VoiceCallPageState();
}

class _VoiceCallPageState extends State<VoiceCallPage>
    with TickerProviderStateMixin {
  final _callService = CallService.instance;
  bool _showAudioRoutePopup = false;
  String? _switchingToDeviceId; // ID of device currently being switched to

  late final AnimationController _entrance;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod('TextInput.hide'));

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _callService.addListener(_onCallStateChanged);
    _callService.refreshAudioDevices().then((_) async {
      await _callService.getAudioRouteInfo();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _callService.removeListener(_onCallStateChanged);
    _entrance.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onCallStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  // ───────────────────────── helpers ─────────────────────────

  bool get _isEnded =>
      _callService.state == CallState.ended ||
          (_callService.endReasonMessage?.isNotEmpty ?? false);

  bool get _isActive => _callService.state == CallState.active;

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours.toString().padLeft(2, '0')}:$m:$s';
    }
    return '$m:$s';
  }

  String _statusText() {
    final reason = _callService.endReasonMessage;
    if (reason != null && reason.isNotEmpty) return reason;
    switch (_callService.state) {
      case CallState.outgoingRinging:
        return 'Calling…';
      case CallState.incomingRinging:
        return 'Incoming call…';
      case CallState.connecting:
        return 'Connecting…';
      case CallState.active:
        return _formatDuration(_callService.duration);
      case CallState.ended:
        return 'Call ended';
      case CallState.idle:
        return '';
    }
  }

  void _minimize() {
    HapticFeedback.lightImpact();
    _callService.setMinimized(true);
  }

  Future<void> _handleSpeakerTap() async {
    // Refresh both device list and route info so popup always shows current state
    await Future.wait([
      _callService.refreshAudioDevices(),
      _callService.getAudioRouteInfo(),
    ]);
    if (!mounted) return;
    if (_callService.hasConnectedHeadphones) {
      setState(() => _showAudioRoutePopup = !_showAudioRoutePopup);
    } else {
      final next = _callService.audioRoute == AudioRoute.speaker
          ? AudioRoute.earpiece
          : AudioRoute.speaker;
      await _callService.setAudioRoute(next, isUserAction: true);
      if (mounted) setState(() => _showAudioRoutePopup = false);
    }
  }

  bool _isSpeakerActive() =>
      _showAudioRoutePopup ||
          _callService.audioRoute == AudioRoute.speaker ||
          _callService.audioRoute == AudioRoute.bluetooth;

  IconData _speakerIcon() {
    switch (_callService.audioRoute) {
      case AudioRoute.bluetooth:
        if (_callService.activeDeviceType == 'CarAudio' ||
            _callService.connectedHeadsetName.toLowerCase().contains('car') ||
            _callService.connectedHeadsetName.toLowerCase().contains('carplay')) {
          return CupertinoIcons.car;
        }
        return CupertinoIcons.headphones;
      case AudioRoute.speaker:
        return CupertinoIcons.speaker_3_fill;
      case AudioRoute.earpiece:
        return CupertinoIcons.phone_fill;
    }
  }

  String _speakerLabel() {
    switch (_callService.audioRoute) {
      case AudioRoute.bluetooth:
        final name = _callService.connectedHeadsetName;
        if (name.isNotEmpty &&
            name != 'Speaker' &&
            name != 'Phone' &&
            name != 'Earpiece') {
          return name.length > 9 ? '${name.substring(0, 8)}…' : name;
        }
        return 'Headset';
      case AudioRoute.speaker:
        return 'Speaker';
      case AudioRoute.earpiece:
        return 'Phone';
    }
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final bottomPad = media.padding.bottom;

    // Adaptive sizing
    final orb = (width * 0.19).clamp(56.0, 72.0);
    final endOrb = orb + 6;
    final panelHeight = 20 + (orb + 8 + 16) + 18 + (endOrb + 8 + 16) + 20;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _callService.state != CallState.idle) {
          _callService.setMinimized(true);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0D10),
        body: Stack(
          children: [
            _buildBackground(),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(child: _buildAvatarSection()),
                  _buildControlPanel(orb, endOrb, bottomPad),
                ],
              ),
            ),
            if (_showAudioRoutePopup)
              _buildAudioRouteOverlay(bottomPad + panelHeight + 24),
            _buildVideoUpgradeOverlay(bottomPad),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF16222C), Color(0xFF0F1419), Color(0xFF0B0D10)],
              ),
            ),
          ),
          Positioned(
            top: -90,
            left: -60,
            child: _glow(280, const Color(0xFF2F6F8F), 0.28),
          ),
          Positioned(
            bottom: 140,
            right: -90,
            child: _glow(260, const Color(0xFF25D366), 0.10),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color, double alpha) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: alpha),
        ),
      ),
    );
  }

  // ───────────────────────── top bar ─────────────────────────

  Widget _buildTopBar() {
    final ended = _isEnded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          _BouncyTap(
            onTap: _minimize,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: const Icon(
                CupertinoIcons.chevron_down,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _callService.peerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.4),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    _statusText(),
                    key: ValueKey(_isActive ? 'timer' : _statusText()),
                    style: TextStyle(
                      color: ended
                          ? const Color(0xFFFF5A52)
                          : Colors.white.withValues(alpha: 0.7),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 44), // keeps the title perfectly centered
        ],
      ),
    );
  }

  // ───────────────────────── avatar ─────────────────────────

  Widget _buildAvatarSection() {
    return LayoutBuilder(
      builder: (context, c) {
        final avatar = (c.maxHeight * 0.55).clamp(100.0, 210.0).toDouble();
        final stageSize = avatar * 1.7;
        final ringIntensity = _isEnded
            ? 0.0
            : (_isActive ? 0.35 : 1.0);

        return Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _entrance,
              curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
            ),
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: _entrance,
                curve: Curves.easeOutBack,
              ),
              child: AnimatedScale(
                scale: _isEnded ? 0.9 : 1.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                child: SizedBox(
                  width: stageSize,
                  height: stageSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulse rings
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) {
                          return Stack(
                            alignment: Alignment.center,
                            children: List.generate(3, (i) {
                              final t = (_pulse.value + i / 3) % 1.0;
                              final scale = 1.0 + 0.65 * Curves.easeOut.transform(t);
                              final opacity = (1 - t) * 0.22 * ringIntensity;
                              return Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: avatar,
                                  height: avatar,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: opacity),
                                  ),
                                ),
                              );
                            }),
                          );
                        },
                      ),
                      // Avatar with border + shadow
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 30,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: IosAvatar(
                          name: _callService.peerName,
                          imagePath: _callService.peerAvatar,
                          size: avatar,
                          showOnline: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ───────────────────────── control panel ─────────────────────────

  Widget _buildControlPanel(double orb, double endOrb, double bottomPad) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));

    return SlideTransition(
      position: slide,
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _entrance,
          curve: const Interval(0.1, 0.8, curve: Curves.easeOut),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 14),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _ControlButton(
                                size: orb,
                                icon: CupertinoIcons.videocam_fill,
                                label: 'Video',
                                enabled: _isActive,
                                onTap: _callService.requestVideoCallUpgrade,
                              ),
                            ),
                            Expanded(
                              child: _ControlButton(
                                size: orb,
                                icon: _speakerIcon(),
                                label: _speakerLabel(),
                                active: _isSpeakerActive(),
                                onTap: _handleSpeakerTap,
                              ),
                            ),
                            Expanded(
                              child: _ControlButton(
                                size: orb,
                                icon: _callService.micOn
                                    ? CupertinoIcons.mic_fill
                                    : CupertinoIcons.mic_slash_fill,
                                label: _callService.micOn ? 'Mute' : 'Unmute',
                                active: !_callService.micOn,
                                onTap: _callService.toggleMute,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _ControlButton(
                          size: endOrb,
                          icon: CupertinoIcons.phone_down_fill,
                          label: 'End',
                          danger: true,
                          onTap: () async {
                            await _callService.hangUp();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── audio route popup ─────────────────────────

  Widget _buildAudioRouteOverlay(double bottomOffset) {
    final options = _callService.getAvailableAudioOptions();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _showAudioRoutePopup = false),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          bottom: bottomOffset,
          left: 24,
          right: 24,
          child: Center(
            child: _PopIn(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xEB2C2C2E),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'AUDIO OUTPUT',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                        for (final opt in options)
                          _AudioRouteTile(
                            icon: opt.icon,
                            title: opt.label,
                            subtitle: opt.subtitle,
                            isSelected: _callService.isAudioOptionSelected(opt),
                            isSwitching: _switchingToDeviceId == opt.id,
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              setState(() => _switchingToDeviceId = opt.id);
                              await _callService.selectAudioOption(opt);
                              if (mounted) {
                                setState(() {
                                  _switchingToDeviceId = null;
                                  _showAudioRoutePopup = false;
                                });
                              }
                            },
                          ),
                        if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            child: Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
                          ),
                          _AudioRouteTile(
                            icon: Icons.airplay,
                            title: 'AirPlay & Bluetooth…',
                            subtitle: 'Switch between audio devices',
                            isSelected: false,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _callService.showSystemRoutePicker();
                              AppToast.show('Select device or switch from Control Center');
                              if (mounted) {
                                setState(() => _showAudioRoutePopup = false);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────── video upgrade overlay ─────────────────────────

  Widget _buildVideoUpgradeOverlay(double bottomPad) {
    final pending = _callService.pendingUpgradeRequest != null;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !pending,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: pending
              ? _VideoUpgradeSheet(
            key: const ValueKey('video-upgrade'),
            name: _callService.peerName,
            avatar: _callService.peerAvatar,
            bottomPad: bottomPad,
            onAccept: _callService.acceptVideoCallUpgrade,
            onDecline: _callService.rejectVideoCallUpgrade,
          )
              : const SizedBox.expand(key: ValueKey('no-upgrade')),
        ),
      ),
    );
  }
}

// ═════════════════════════ reusable widgets ═════════════════════════

/// Spring press feedback: shrinks on touch, bounces back on release.
class _BouncyTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _BouncyTap({required this.child, this.onTap});

  @override
  State<_BouncyTap> createState() => _BouncyTapState();
}

class _BouncyTapState extends State<_BouncyTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const _spring = SpringDescription(mass: 1, stiffness: 420, damping: 11);

  @override
  void initState() {
    super.initState();
    // Negative lower bound lets the spring overshoot past rest (the "bounce").
    _c = AnimationController(
      vsync: this,
      lowerBound: -0.25,
      upperBound: 1.0,
      value: 0.0,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) {
    _c.animateTo(1.0,
        duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
  }

  void _release() {
    _c.animateWith(SpringSimulation(_spring, _c.value, 0.0, 0.0));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? _down : null,
      onTapCancel: enabled ? _release : null,
      onTapUp: enabled ? (_) => _release() : null,
      onTap: enabled
          ? () {
        HapticFeedback.lightImpact();
        widget.onTap!();
      }
          : null,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) =>
            Transform.scale(scale: 1.0 - 0.14 * _c.value, child: child),
        child: widget.child,
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final String label;
  final bool active;
  final bool danger;
  final bool enabled;
  final VoidCallback onTap;

  const _ControlButton({
    required this.size,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;

    if (danger) {
      bg = const Color(0xFFE5383B);
      fg = Colors.white;
    } else if (active) {
      bg = Colors.white;
      fg = const Color(0xFF111418);
    } else {
      bg = Colors.white.withValues(alpha: 0.14);
      fg = Colors.white;
    }

    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 250),
      child: _BouncyTap(
        onTap: enabled ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                boxShadow: danger
                    ? [
                  BoxShadow(
                    color: const Color(0xFFE5383B).withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Icon(
                  icon,
                  key: ValueKey(icon.codePoint),
                  color: fg,
                  size: size * 0.42,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 16,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  label,
                  key: ValueKey(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fade + overshoot scale entrance for popups and dialogs.
class _PopIn extends StatelessWidget {
  final Widget child;
  const _PopIn({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.88 + 0.12 * t, child: child),
      ),
      child: child,
    );
  }
}

class _AudioRouteTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isSelected;
  final bool isSwitching;
  final VoidCallback onTap;

  const _AudioRouteTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.isSwitching = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: isSwitching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF25D366)),
                        ),
                      )
                    : AnimatedScale(
                        scale: isSelected ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutBack,
                        child: const Icon(
                          CupertinoIcons.checkmark_alt,
                          color: Color(0xFF25D366),
                          size: 18,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 15,
                        fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoUpgradeSheet extends StatefulWidget {
  final String name;
  final String? avatar;
  final double bottomPad;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _VideoUpgradeSheet({
    super.key,
    required this.name,
    required this.avatar,
    required this.bottomPad,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_VideoUpgradeSheet> createState() => _VideoUpgradeSheetState();
}

class _VideoUpgradeSheetState extends State<_VideoUpgradeSheet>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutBack));

    return SizedBox.expand(
      child: Stack(
        children: [
          // Dimmed backdrop (does not dismiss, to avoid accidental declines)
          Positioned.fill(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _enter, curve: Curves.easeOut),
              child: Container(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ),

          // Sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: slide,
              child: GestureDetector(
                // Swipe down fast = decline
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 700) {
                    HapticFeedback.lightImpact();
                    widget.onDecline();
                  }
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ClipRRect(
                    borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(34)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.fromLTRB(
                          24,
                          12,
                          24,
                          widget.bottomPad + 22,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xF21B1E23),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Grab handle
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 26),

                            _buildAvatarWithBadge(),

                            const SizedBox(height: 20),

                            const Text(
                              'Switch to video call?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${widget.name} wants to switch this call to video. '
                                  'Your camera will turn on when you accept.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 14.5,
                                height: 1.35,
                              ),
                            ),

                            const SizedBox(height: 26),

                            _SheetButton(
                              label: 'Switch to video',
                              icon: CupertinoIcons.videocam_fill,
                              background: const Color(0xFF25D366),
                              foreground: Colors.white,
                              glow: true,
                              onTap: widget.onAccept,
                            ),
                            const SizedBox(height: 12),
                            _SheetButton(
                              label: 'Decline',
                              background: Colors.white.withValues(alpha: 0.10),
                              foreground: Colors.white,
                              onTap: widget.onDecline,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarWithBadge() {
    const avatarSize = 84.0;
    const stage = 150.0;

    return SizedBox(
      width: stage,
      height: stage,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding green rings
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: List.generate(2, (i) {
                  final t = (_pulse.value + i * 0.5) % 1.0;
                  final scale = 1.0 + 0.7 * Curves.easeOut.transform(t);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF25D366)
                            .withValues(alpha: (1 - t) * 0.25),
                      ),
                    ),
                  );
                }),
              );
            },
          ),

          // Avatar
          IosAvatar(
            name: widget.name,
            imagePath: widget.avatar,
            size: avatarSize,
            showOnline: false,
          ),

          // Camera badge that pops in after the sheet settles
          Positioned(
            right: stage / 2 - avatarSize / 2 - 8,
            bottom: stage / 2 - avatarSize / 2 - 6,
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: _enter,
                curve: const Interval(0.55, 1.0, curve: Curves.elasticOut),
              ),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF25D366),
                  border: Border.all(
                    color: const Color(0xFF1B1E23),
                    width: 3,
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.videocam_fill,
                  color: Colors.white,
                  size: 17,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;
  final bool glow;
  final VoidCallback onTap;

  const _SheetButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.icon,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return _BouncyTap(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(27),
          boxShadow: glow
              ? [
            BoxShadow(
              color: background.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 16.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}