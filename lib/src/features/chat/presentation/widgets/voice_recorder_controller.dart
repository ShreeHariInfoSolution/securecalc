import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// idle       -> normal text composer
/// holding    -> finger is down (slide left = cancel, slide up = lock)
/// locked     -> hands-free recording (also used by single tap)
/// cancelling -> bin animation is playing, then returns to idle
enum VoiceState { idle, holding, locked, cancelling }

typedef VoiceToast = void Function(String message, {bool isError});

class VoiceRecorderController extends ChangeNotifier {
  VoiceRecorderController({
    required this.onVoiceReady,
    required this.onToast,
  });

  /// Called with the finished .m4a file when the user sends.
  final Future<void> Function(File file) onVoiceReady;
  final VoiceToast onToast;

  // ── Tunables ──────────────────────────────────────────────────────────────
  static const Duration tapThreshold = Duration(milliseconds: 180);
  static const Duration minHoldDuration = Duration(milliseconds: 800);
  static const Duration minSendDuration = Duration(milliseconds: 600);
  static const double cancelDistance = 110.0;
  static const double lockDistance = 80.0;

  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _watch = Stopwatch();

  /// 0..1 loudness samples used to draw the waveform (newest last).
  final List<double> levels = [];
  int levelTick = 0;

  VoiceState state = VoiceState.idle;
  bool isPaused = false;
  double dragDx = 0; // <= 0
  double dragDy = 0; // <= 0

  Timer? _ticker;
  StreamSubscription<Amplitude>? _ampSub;
  Offset _downPos = Offset.zero;
  Axis? _axis;
  bool _pointerDown = false;
  bool _starting = false;
  bool _busy = false;
  bool _disposed = false;
  DateTime _downAt = DateTime.now();
  bool _pendingCancel = false;
  bool _hasPerm = false;
  String? _tmpDir;

  Duration get elapsed => _watch.elapsed;
  bool get isActive => state != VoiceState.idle;
  double get cancelProgress => (-dragDx / cancelDistance).clamp(0.0, 1.0);
  double get lockProgress => (-dragDy / lockDistance).clamp(0.0, 1.0);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> warmUp() async {
    try {
      _tmpDir ??= (await getTemporaryDirectory()).path;
    } catch (_) {}
  }

  // ── Pointer input (called from the mic button Listener) ───────────────────

  void pointerDown(Offset globalPosition) {
    if (state != VoiceState.idle || _starting) return;
    _pointerDown = true;
    _downPos = globalPosition;
    _downAt = DateTime.now();
    _begin(hold: true); // instant UI, recorder starts in background
  }

  void pointerMove(Offset globalPosition) {
    if (state != VoiceState.holding) return;
    final d = globalPosition - _downPos;
    // Lock to one axis after a small movement (like WhatsApp).
    _axis ??= d.distance > 14
        ? (d.dx.abs() > d.dy.abs() ? Axis.horizontal : Axis.vertical)
        : null;
    dragDx = _axis == Axis.vertical ? 0 : math.min(0.0, d.dx);
    dragDy = _axis == Axis.horizontal ? 0 : math.min(0.0, d.dy);

    if (-dragDx >= cancelDistance) {
      cancel();
      return;
    }
    if (-dragDy >= lockDistance) {
      _lock();
      return;
    }
    _notify();
  }

  void pointerUp() {
    final wasDown = _pointerDown;
    _pointerDown = false;
    if (!wasDown || state != VoiceState.holding) return;

    final held = DateTime.now().difference(_downAt);
    if (held < tapThreshold) {
      _lock(); // quick tap -> hands-free recording
    } else if (!_starting) {
      _finishHold();
    }
    // if still starting, _begin() finishes the hold once the recorder is up
  }

  void pointerCancel() {
    _pointerDown = false;
    if (state == VoiceState.holding) cancel();
  }

  // ── Start ─────────────────────────────────────────────────────────────────

  /// Used by the attachment menu "Voice" item.
  Future<void> startLocked() => _begin(hold: false);

  Future<void> _begin({required bool hold}) async {
    if (_starting || state != VoiceState.idle) return;
    _starting = true;
    _pendingCancel = false;

    // 1) UI first: no awaits before this point.
    levels.clear();
    levelTick = 0;
    isPaused = false;
    dragDx = 0;
    dragDy = 0;
    _axis = null;
    _watch
      ..reset()
      ..start();
    state = hold ? VoiceState.holding : VoiceState.locked;
    HapticFeedback.mediumImpact();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _notify());
    _notify();

    // 2) Recorder in the background.
    var ok = false;
    try {
      if (!_hasPerm) _hasPerm = await _recorder.hasPermission();
      if (!_hasPerm) {
        onToast('Microphone permission is required', isError: true);
      } else {
        _tmpDir ??= (await getTemporaryDirectory()).path;
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 64000,
            sampleRate: 44100,
          ),
          path: '$_tmpDir/voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        );
        ok = true;
      }
    } catch (e) {
      debugPrint('[VOICE] start error: $e');
      onToast('Unable to start recording', isError: true);
    }
    _starting = false;

    if (_disposed) {
      if (ok) {
        try {
          await _recorder.cancel();
        } catch (_) {}
      }
      return;
    }
    if (!ok) {
      _reset();
      return;
    }
    if (_pendingCancel) {
      // user slid away / cancelled while the recorder was starting
      _pendingCancel = false;
      try {
        await _recorder.cancel();
      } catch (_) {}
      return;
    }

    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) {
      if (isPaused) return;
      final db =
          a.current.isFinite ? a.current.clamp(-45.0, 0.0).toDouble() : -45.0;
      levels.add((db + 45.0) / 45.0);
      if (levels.length > 400) levels.removeAt(0);
      levelTick++;
    });

    // Finger was lifted (after a real hold) while the recorder was starting.
    if (state == VoiceState.holding && !_pointerDown) _finishHold();
  }

  void _lock() {
    if (state != VoiceState.holding) return;
    HapticFeedback.mediumImpact();
    state = VoiceState.locked;
    dragDx = 0;
    dragDy = 0;
    _notify();
  }

  void _finishHold() {
    if (state != VoiceState.holding) return;
    if (elapsed < minHoldDuration) {
      onToast('Hold to record, release to send');
      cancel();
    } else {
      send();
    }
  }

  // ── Locked controls ───────────────────────────────────────────────────────

  Future<void> togglePause() async {
    if (state != VoiceState.locked || _busy) return;
    try {
      if (isPaused) {
        await _recorder.resume();
        _watch.start();
      } else {
        await _recorder.pause();
        _watch.stop();
      }
      isPaused = !isPaused;
      HapticFeedback.selectionClick();
      _notify();
    } catch (e) {
      debugPrint('[VOICE] pause/resume error: $e');
    }
  }

  // ── Finish ────────────────────────────────────────────────────────────────

  Future<void> send() async {
    if (_busy || _starting || (state != VoiceState.holding && state != VoiceState.locked)) {
      return;
    }
    _busy = true;
    try {
      final d = elapsed;
      _ticker?.cancel();
      await _ampSub?.cancel();
      _watch.stop();

      String? path;
      try {
        path = await _recorder.stop();
      } catch (e) {
        debugPrint('[VOICE] stop error: $e');
      }
      _reset(); // composer + text field come back immediately

      if (path == null || path.isEmpty) return;
      final file = File(path);
      if (d < minSendDuration) {
        try {
          await file.delete();
        } catch (_) {}
        onToast('Recording too short');
        return;
      }
      await onVoiceReady(file);
    } finally {
      _busy = false;
    }
  }

  /// Starts the bin animation. The UI calls [finishCancel] when it ends.
  Future<void> cancel() async {
    if (_busy || (state != VoiceState.holding && state != VoiceState.locked)) {
      return;
    }
    if (_starting) {
      _pendingCancel = true; // the recorder isn't up yet; _begin() will cancel it
    }
    _ticker?.cancel();
    _ampSub?.cancel();
    _watch.stop();
    HapticFeedback.lightImpact();
    state = VoiceState.cancelling;
    isPaused = false;
    dragDx = 0;
    dragDy = 0;
    _notify();
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  /// Called by the bin animation when it finishes -> text field returns.
  void finishCancel() {
    if (state == VoiceState.cancelling) _reset();
  }

  void _reset() {
    _ticker?.cancel();
    _ampSub?.cancel();
    _ampSub = null;
    _watch
      ..stop()
      ..reset();
    state = VoiceState.idle;
    isPaused = false;
    dragDx = 0;
    dragDy = 0;
    _axis = null;
    _pointerDown = false;
    levels.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ampSub?.cancel();
    unawaited(() async {
      try {
        if (await _recorder.isRecording()) await _recorder.cancel();
      } catch (_) {}
      await _recorder.dispose();
    }());
    super.dispose();
  }
}
