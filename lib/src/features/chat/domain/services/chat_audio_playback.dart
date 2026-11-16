import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

@immutable
class ChatAudioState {
  final String? key; // which bubble owns the player
  final bool isPlaying;
  final Duration position;
  final Duration duration;

  const ChatAudioState({
    this.key,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  ChatAudioState copyWith({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
  }) =>
      ChatAudioState(
        key: key,
        isPlaying: isPlaying ?? this.isPlaying,
        position: position ?? this.position,
        duration: duration ?? this.duration,
      );
}

class AudioDurationCache {
  static final Map<String, Duration> _cache = {};
  static final Set<String> _loading = {};

  static Duration? get(String key) => _cache[key];

  static void put(String key, Duration duration) {
    if (key.isNotEmpty && duration > Duration.zero) {
      _cache[key] = duration;
    }
  }

  static Future<Duration?> fetch(String key, String localPath) async {
    if (key.isEmpty || localPath.isEmpty) return null;
    if (_cache.containsKey(key)) return _cache[key];
    if (_loading.contains(key)) return null;
    _loading.add(key);

    AudioPlayer? tempPlayer;
    try {
      tempPlayer = AudioPlayer();
      await tempPlayer.setSource(DeviceFileSource(localPath));
      final d = await tempPlayer.getDuration();
      if (d != null && d > Duration.zero) {
        _cache[key] = d;
        return d;
      }
    } catch (e) {
      debugPrint('[AUDIO DURATION] Error fetching duration for $key: $e');
    } finally {
      try {
        await tempPlayer?.dispose();
      } catch (_) {}
      _loading.remove(key);
    }
    return null;
  }
}

/// One player for the whole app. It survives bubble rebuilds, list re-sorts
/// and local-id -> server-id message replacement.
class ChatAudioPlayback {
  ChatAudioPlayback._() {
    _player.setReleaseMode(ReleaseMode.stop); // keep source after completion

    _player.onPlayerStateChanged.listen((s) {
      final cur = state.value;
      if (s == PlayerState.completed) {
        // Reset to the start so the bubble is ready to play again.
        state.value = ChatAudioState(key: cur.key, duration: cur.duration);
        return;
      }
      state.value = cur.copyWith(isPlaying: s == PlayerState.playing);
    });

    _player.onPositionChanged.listen((p) {
      final cur = state.value;
      if (cur.isPlaying) state.value = cur.copyWith(position: p);
    });

    _player.onDurationChanged.listen((d) {
      if (d > Duration.zero && state.value.key != null) {
        AudioDurationCache.put(state.value.key!, d);
      }
      state.value = state.value.copyWith(duration: d);
    });
  }

  static final ChatAudioPlayback instance = ChatAudioPlayback._();

  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<ChatAudioState> state =
      ValueNotifier(const ChatAudioState());
  bool _busy = false;

  /// Play / pause / resume / restart, depending on the current state.
  Future<void> toggle({required String key, required String path}) async {
    if (_busy) return;
    _busy = true;
    try {
      final cur = state.value;
      final same = cur.key == key;

      if (same && cur.isPlaying) {
        await _player.pause();
        return;
      }
      if (same && cur.position > Duration.zero) {
        await _player.resume(); // paused mid-way
        return;
      }

      // New audio, or one that already finished: fresh start.
      await _player.stop();
      state.value = ChatAudioState(key: key);
      await _player.play(DeviceFileSource(path));
    } finally {
      _busy = false;
    }
  }

  Future<void> seek(String key, Duration position) async {
    if (state.value.key != key) return;
    await _player.seek(position);
    state.value = state.value.copyWith(position: position);
  }

  Future<void> stop() async {
    await _player.stop();
    state.value = const ChatAudioState();
  }
}
