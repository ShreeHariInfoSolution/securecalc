import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../entities/chat_conversation.dart';
import '../entities/chat_message.dart';
import '../utils/forward_marker.dart';
import 'attachment_cache_service.dart';
import 'chat_media_downloader.dart';
import 'e2e_crypto_service.dart';
import 'local_chat_storage.dart';
import 'server_api_service.dart';
import 'server_chat_manager.dart';

Uint8List _encIso((Uint8List, String) a) =>
    E2eCryptoService.instance.encryptFileBytes(a.$1, a.$2);

class ForwardService {
  ForwardService._();

  /// Returns the number of failed (target, message) pairs.
  static Future<int> forward({
    required List<ChatMessage> messages,
    required String sourceChatId,
    required List<ChatConversation> targets,
  }) async {
    var failures = 0;
    final ordered = [...messages]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (final t in targets) {
      for (final m in ordered) {
        if (m.isDeleted || m.type == 'call' || m.msgType == 'call') continue;
        try {
          if (_isFileBacked(m)) {
            await _forwardFile(m, sourceChatId, t);
          } else {
            await _forwardPlain(m, t);
          }
        } catch (e) {
          failures++;
          debugPrint('[FORWARD] ${t.id} / ${m.id} failed: $e');
        }
      }
    }
    unawaited(ServerChatManager.instance.syncChats());
    return failures;
  }

  static bool _isSticker(ChatMessage m) =>
      m.type == 'sticker' || m.content.trim().startsWith('stk_');

  static bool _isRemoteLink(ChatMessage m) =>
      (m.mediaUrl ?? '').startsWith('http://') ||
      (m.mediaUrl ?? '').startsWith('https://');

  // Files stored on OUR server are encrypted with the source chat key.
  static bool _isFileBacked(ChatMessage m) =>
      m.hasMedia && !_isSticker(m) && !_isRemoteLink(m);

  static Future<void> _forwardPlain(ChatMessage m, ChatConversation t) async {
    final sticker = _isSticker(m);
    final link = _isRemoteLink(m);
    final sent = await ServerChatManager.instance.sendMessage(
      chatId: t.id,
      peerName: t.name,
      text: m.content,
      filePath: (sticker || link) ? (m.mediaUrl ?? m.content) : null,
      fileType: sticker ? 'sticker' : (link ? m.type : null),
      peerUserId: t.peerUserId,
      forwarded: true,
    );
    if (sent == null) throw Exception('send failed');
  }

  static Future<File> _plainFile(ChatMessage m, String sourceChatId) async {
    final url = m.mediaUrl!;
    final cached = await AttachmentCacheService.instance.resolveLocalPath(url);
    if (cached != null) return File(cached);
    final name =
        (m.fileName?.isNotEmpty == true) ? m.fileName! : url.split('/').last;
    final p = await ChatMediaDownloader.instance.fetch(
      mediaUrl: url,
      chatId: sourceChatId, // decrypt with the SOURCE chat key
      fileName: name,
      kind: ChatMediaDownloader.kindOf(type: m.type, name: m.fileName, url: url),
    );
    return File(p);
  }

  static Future<void> _forwardFile(
      ChatMessage m, String sourceChatId, ChatConversation t) async {
    final plain = await _plainFile(m, sourceChatId);
    final targetKey = 'chat_key_${t.id}';
    final fileName = (m.fileName?.isNotEmpty == true)
        ? m.fileName!
        : plain.path.split(RegExp(r'[/\\]')).last;

    // Re-encrypt with the TARGET chat key.
    final enc = await compute(_encIso, (await plain.readAsBytes(), targetKey));
    final tmpDir = await getTemporaryDirectory();
    final tmp = File(
        '${tmpDir.path}${Platform.pathSeparator}fwd_${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsBytes(enc, flush: true);

    try {
      final sm = await ServerApiService.instance.sendMessageREST(
        chatId: int.parse(t.id),
        // marker travels inside the encrypted text
        message: E2eCryptoService.instance
            .encryptText(addFwdMarker(m.content), targetKey),
        file: tmp,
        fileName: fileName,
        fileType: m.type,
        clientId: 'fwd_${DateTime.now().microsecondsSinceEpoch}',
      );
      final serverPath = sm.filePath ?? '';

      // Decrypted local copy so the sender sees it instantly.
      final docs = await getApplicationDocumentsDirectory();
      final dir =
          Directory('${docs.path}${Platform.pathSeparator}chat_attachments');
      await dir.create(recursive: true);
      final key = serverPath
          .split('/')
          .last
          .split('\\')
          .last
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final local = '${dir.path}${Platform.pathSeparator}${key}_$safe';
      await plain.copy(local);
      if (serverPath.isNotEmpty) {
        AttachmentCacheService.instance.updateCache(serverPath, local);
      }

      await LocalChatStorage.instance.saveMessage(
        deviceId: t.id,
        peerName: t.name,
        markUnread: false,
        peerUserId: t.peerUserId,
        message: ChatMessage(
          id: sm.id.toString(),
          senderId: 'user',
          content: m.content,
          timestamp:
              DateTime.tryParse(sm.createdAt)?.toLocal() ?? DateTime.now(),
          type: m.type,
          mediaUrl: serverPath,
          fileName: fileName,
          status: 'sent',
          isForwarded: true,
        ),
      );
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}
