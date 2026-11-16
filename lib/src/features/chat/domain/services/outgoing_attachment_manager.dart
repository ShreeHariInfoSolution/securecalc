import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/utils/media_compression_service.dart';

import '../entities/chat_message.dart';
import 'attachment_cache_service.dart';
import 'attachment_upload_service.dart';
import 'e2e_crypto_service.dart';
import 'local_chat_storage.dart';
import 'server_api_service.dart';
import 'server_chat_manager.dart';

typedef _Up = ({String path, String? serverId, DateTime? serverTs});

Uint8List _encryptInIsolate((Uint8List, String) a) =>
    E2eCryptoService.instance.encryptFileBytes(a.$1, a.$2);

enum OutgoingEventType { sent, failed, discarded, retrying }

class OutgoingEvent {
  final OutgoingEventType type;
  final String chatId, localId;
  final ChatMessage? message;
  const OutgoingEvent(this.type, this.chatId, this.localId, [this.message]);
}

class OutgoingJob {
  final String localId, chatId, peerName, fileName, fileType, messageText, secretKey;
  final int? peerUserId, replyToId;
  final File file; // permanent staged copy, never deleted
  final DateTime localTimestamp;
  final bool isHd;
  int attempt = 0;
  OutgoingJob({
    required this.localId,
    required this.chatId,
    required this.peerName,
    required this.fileName,
    required this.fileType,
    required this.messageText,
    required this.secretKey,
    required this.file,
    required this.localTimestamp,
    this.peerUserId,
    this.replyToId,
    this.isHd = false,
  });
}

class OutgoingAttachmentManager {
  OutgoingAttachmentManager._();
  static final instance = OutgoingAttachmentManager._();
  static const _stall = Duration(seconds: 60);

  final _jobs = <String, OutgoingJob>{};
  final _active = <String>{}; // queued or running
  final _localToReal = <String, String>{};
  final _queue = <String>[];
  String? _current;
  bool _running = false;

  final _events = StreamController<OutgoingEvent>.broadcast();
  Stream<OutgoingEvent> get events => _events.stream;

  bool isActive(String id) => _active.contains(id);
  String? realIdFor(String id) => _localToReal[id];

  void enqueue(OutgoingJob j) {
    _jobs[j.localId] = j;
    _register(j.localId);
    AttachmentUploadService.instance.resetForRetry(j.localId);
    _push(j.localId);
  }

  /// For uploads left over from a killed app: show Retry/Delete, don't run.
  void adopt(OutgoingJob j) {
    if (_active.contains(j.localId)) return;
    _jobs[j.localId] = j;
    _register(j.localId);
    AttachmentUploadService.instance.markFailed(j.localId, 'Upload interrupted');
  }

  void _register(String id) => AttachmentUploadService.instance.registerActions(
        id,
        onRetry: () => retry(id),
        onDiscard: () => discard(id),
      );

  void retry(String id) {
    final j = _jobs[id];
    if (j == null || !j.file.existsSync()) {
      AppToast.show('The original file is no longer available.', isError: true);
      return;
    }
    if (_active.contains(id)) return;
    AttachmentUploadService.instance.resetForRetry(id);
    _events.add(OutgoingEvent(OutgoingEventType.retrying, j.chatId, id));
    _push(id);
  }

  Future<void> discard(String id) async {
    final svc = AttachmentUploadService.instance;
    final j = _jobs.remove(id);
    j?.attempt++; // orphan any in-flight work
    _queue.remove(id);
    _active.remove(id);
    svc.cancelUpload(id);
    if (_current == id) unawaited(MediaCompressionService.instance.cancelVideoCompression());
    svc.clearActions(id);
    if (j != null) {
      await LocalChatStorage.instance.deleteLocalMessage(j.chatId, id);
      _events.add(OutgoingEvent(OutgoingEventType.discarded, j.chatId, id));
    }
  }

  void _push(String id) {
    _active.add(id);
    _queue.add(id);
    _pump();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    while (_queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      final j = _jobs[id];
      if (j == null) {
        _active.remove(id);
        continue;
      }
      _current = id;
      try {
        await _run(j);
      } catch (e) {
        debugPrint('[OUTGOING] $e');
      }
      _current = null;
      _active.remove(id);
    }
    _running = false;
  }

  Future<void> _run(OutgoingJob j) async {
    final svc = AttachmentUploadService.instance;
    if (svc.isCancelled(j.localId)) return;
    final attempt = ++j.attempt;
    bool stale() => j.attempt != attempt || svc.isCancelled(j.localId);

    final stalled = Completer<_Up>()..future.ignore();
    Timer? dog;
    void kick() {
      dog?.cancel();
      dog = Timer(_stall, () {
        if (!stalled.isCompleted) stalled.completeError(TimeoutException('Upload timed out'));
      });
    }

    final notifier = svc.getProgressNotifier(j.localId);
    void onNotify() {
      if (notifier.value.isFailed && !stalled.isCompleted) {
        stalled.completeError(StateError('cancelled'));
      }
    }

    notifier.addListener(onNotify);
    kick();
    var sentAll = false;

    Future<_Up> upload() async {
      var send = j.file;
      final ticker = Timer.periodic(const Duration(seconds: 10), (_) => kick());
      late final Uint8List enc;
      try {
        final mc = MediaCompressionService.instance;
        if (mc.isImage(send.path) || mc.isVideo(send.path)) {
          send = await mc.compressMedia(send, isHd: j.isHd, onProgress: (_) => kick());
        }
        if (stale()) throw StateError('cancelled');
        svc.updateProgress(j.localId, 0, await send.length());
        final raw = await send.readAsBytes();
        enc = await compute(_encryptInIsolate, (raw, j.secretKey));
        if (stale()) throw StateError('cancelled');
      } finally {
        ticker.cancel();
      }
      kick();

      final tmpDir = await getTemporaryDirectory();
      final tmp = File('${tmpDir.path}${Platform.pathSeparator}enc_${DateTime.now().microsecondsSinceEpoch}.tmp');
      await tmp.writeAsBytes(enc, flush: true);

      void onProgress(int s, int t) {
        kick();
        if (t > 0 && s >= t) sentAll = true;
        if (!stale()) svc.updateProgress(j.localId, s, t);
      }

      try {
        try {
          final sm = await ServerApiService.instance.sendMessageREST(
            chatId: int.tryParse(j.chatId) ?? 0,
            message: E2eCryptoService.instance.encryptText(j.messageText, j.secretKey),
            file: tmp,
            fileName: j.fileName,
            fileType: j.fileType,
            replyToId: j.replyToId,
            clientId: j.localId,
            onProgress: onProgress,
          );
          return (
            path: sm.filePath ?? '',
            serverId: sm.id.toString(),
            serverTs: DateTime.tryParse(sm.createdAt)?.toLocal()
          );
        } catch (e) {
          // never fall back once all bytes were sent: the server may already have the message
          if (stale() || e is TimeoutException || sentAll) rethrow;
          final uploaded = await ServerApiService.instance.uploadFile(
            tmp,
            filename: j.fileName,
            onProgress: onProgress,
          );
          if (uploaded == null || uploaded.isEmpty) throw Exception('The file could not be uploaded.');
          final fb = await ServerChatManager.instance.sendMessage(
            chatId: j.chatId,
            peerName: j.peerName,
            text: j.messageText,
            filePath: uploaded,
            fileName: j.fileName,
            fileType: j.fileType,
            peerUserId: j.peerUserId,
            replyToId: j.replyToId,
          );
          if (fb == null) throw Exception('The file message could not be sent.');
          return (path: uploaded, serverId: fb.id, serverTs: fb.timestamp);
        }
      } finally {
        try {
          await tmp.delete();
        } catch (_) {}
        if (send.path != j.file.path) {
          try {
            await send.delete();
          } catch (_) {}
        }
      }
    }

    try {
      final fut = upload()..ignore();
      final r = await Future.any<_Up>([fut, stalled.future]);
      if (j.attempt != attempt) return;
      if (r.path.isEmpty) throw Exception('The file could not be sent. Please try again.');

      svc.markCompleted(j.localId);
      final realId = (r.serverId?.isNotEmpty ?? false) ? r.serverId! : j.localId;

      // The staged file is permanent, so this mapping never goes stale.
      AttachmentCacheService.instance.updateCache(r.path, j.file.path);

      final sent = ChatMessage(
        id: realId,
        senderId: 'user',
        content: j.messageText,
        timestamp: r.serverTs ?? j.localTimestamp,
        type: j.fileType,
        mediaUrl: r.path,
        fileName: j.fileName,
        status: 'sent',
        replyToId: j.replyToId,
      );
      await LocalChatStorage.instance.saveMessage(
        deviceId: j.chatId,
        peerName: j.peerName,
        message: sent,
        peerUserId: j.peerUserId,
      );

      _localToReal[j.localId] = realId;
      _jobs.remove(j.localId);
      svc.clearActions(j.localId);
      _events.add(OutgoingEvent(OutgoingEventType.sent, j.chatId, j.localId, sent));
    } catch (error) {
      debugPrint('[OUTGOING] upload error: $error');
      if (j.attempt != attempt) return; // discarded or superseded
      final userCancelled = svc.isCancelled(j.localId);
      final timedOut = error is TimeoutException;
      svc.markFailed(j.localId, timedOut ? 'Upload timed out' : error.toString());
      _events.add(OutgoingEvent(OutgoingEventType.failed, j.chatId, j.localId));
      if (!userCancelled) {
        AppToast.show(
          timedOut ? 'Upload timed out. Tap Retry.' : 'Failed to send ${j.fileName}. Tap Retry.',
          isError: true,
        );
      }
    } finally {
      dog?.cancel();
      notifier.removeListener(onNotify);
    }
  }
}
