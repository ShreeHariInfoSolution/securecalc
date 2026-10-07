import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../../core/config/app_preferences.dart';
import '../../../../core/utils/app_logger.dart';
import '../entities/chat_message.dart';
import 'e2e_crypto_service.dart';
import 'local_chat_storage.dart';

/// Real-time Wi-Fi P2P Socket Chat Engine for device-to-device messaging.
class P2pChatService {
  P2pChatService._internal();
  static final P2pChatService instance = P2pChatService._internal();

  static const int p2pChatPort = 48232;

  /// Currently open active chat device ID (null if not in chat detail screen).
  static String? activeChatDeviceId;

  RawDatagramSocket? _socket;
  bool _isInitialized = false;

  final StreamController<Map<String, dynamic>> _incomingMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onMessageReceived =>
      _incomingMessageController.stream;

  /// Initialize local socket listener on port 48232.
  Future<void> initializeSocket() async {
    if (_isInitialized) return;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        p2pChatPort,
        reuseAddress: true,
      );
      _socket?.broadcastEnabled = true;

      _socket?.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              _handleIncomingPacket(datagram);
            }
          }
        },
        onError: (e) {
          AppLogger.error('[P2P CHAT] Socket error: $e');
        },
      );

      _isInitialized = true;
      AppLogger.info('[P2P CHAT] Socket initialized on port $p2pChatPort');
    } catch (e) {
      AppLogger.error('[P2P CHAT] Failed to bind chat socket: $e');
    }
  }

  void _handleIncomingPacket(Datagram datagram) async {
    try {
      final rawJson = utf8.decode(datagram.data);
      final jsonMap = jsonDecode(rawJson) as Map<String, dynamic>;

      final type = jsonMap['type'] as String?;
      final senderDeviceId = jsonMap['senderDeviceId'] as String?;
      final senderDisplayName =
          (jsonMap['senderDisplayName'] as String?) ?? senderDeviceId ?? 'Peer';
      final messageId =
          (jsonMap['messageId'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString();
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
          (jsonMap['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch);

      if (senderDeviceId == null || senderDeviceId == AppPreferences.getDeviceIdSync()) {
        return; // Ignore self or invalid
      }

      if (type == 'READ_ACK') {
        await LocalChatStorage.instance.markAllOutgoingMessagesAsRead(senderDeviceId);
        _incomingMessageController.add({
          'deviceId': senderDeviceId,
          'type': 'READ_ACK',
        });
        AppLogger.info('[P2P CHAT] Received READ_ACK from $senderDeviceId');
        return;
      }

      ChatMessage message;

      if (type == 'TEXT_MESSAGE') {
        final rawContent = (jsonMap['content'] as String?) ?? '';
        final decryptedContent = E2eCryptoService.instance.decryptText(
          rawContent,
          'p2p_key_$senderDeviceId',
        );
        message = ChatMessage(
          id: messageId,
          senderId: senderDeviceId,
          content: decryptedContent,
          timestamp: timestamp,
          type: 'text',
        );
      } else if (type == 'MEDIA_MESSAGE') {
        final mediaType = (jsonMap['mediaType'] as String?) ?? 'image';
        final base64Content = (jsonMap['mediaBase64'] as String?) ?? '';
        final rawCaption = (jsonMap['caption'] as String?) ?? '';
        final decryptedCaption = rawCaption.isNotEmpty
            ? E2eCryptoService.instance.decryptText(
                rawCaption,
                'p2p_key_$senderDeviceId',
              )
            : '';

        String? savedFilePath;
        if (base64Content.isNotEmpty) {
          final bytes = base64Decode(base64Content);
          final tempDir = await getTemporaryDirectory();
          final ext = mediaType == 'video' ? 'mp4' : 'jpg';
          final file = File(
              '${tempDir.path}/p2p_media_${DateTime.now().millisecondsSinceEpoch}.$ext');
          await file.writeAsBytes(bytes);
          savedFilePath = file.path;
        }

        message = ChatMessage(
          id: messageId,
          senderId: senderDeviceId,
          content: decryptedCaption.isNotEmpty ? decryptedCaption : '[Attachment]',
          timestamp: timestamp,
          type: mediaType,
          mediaUrl: savedFilePath,
        );
      } else {
        return;
      }

      // 1. Save to local storage
      await LocalChatStorage.instance.saveMessage(
        deviceId: senderDeviceId,
        peerName: senderDisplayName,
        message: message,
      );

      // 2. Broadcast to UI
      _incomingMessageController.add({
        'deviceId': senderDeviceId,
        'displayName': senderDisplayName,
        'message': message,
      });

      // 3. Send READ_ACK if active in chat
      if (activeChatDeviceId == senderDeviceId) {
        sendReadAck(peerIp: datagram.address.address);
      }

      AppLogger.info('[P2P CHAT] Received message from $senderDisplayName ($senderDeviceId)');
    } catch (e) {
      AppLogger.error('[P2P CHAT] Error parsing incoming packet: $e');
    }
  }

  /// Send READ_ACK packet to peer IP address.
  Future<void> sendReadAck({required String peerIp}) async {
    final myDeviceId = AppPreferences.getDeviceIdSync() ?? 'device_me';
    final payload = jsonEncode({
      'type': 'READ_ACK',
      'senderDeviceId': myDeviceId,
    });

    try {
      _socket?.send(utf8.encode(payload), InternetAddress(peerIp), p2pChatPort);
    } catch (_) {}
  }

  /// Send text message over Wi-Fi to target IP address.
  Future<bool> sendTextMessage({
    required String peerIp,
    required String peerDeviceId,
    required String peerDisplayName,
    required String content,
  }) async {
    final myDeviceId = AppPreferences.getDeviceIdSync() ?? 'device_me';
    final myDisplayName = AppPreferences.getDisplayName();
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final timestamp = DateTime.now();

    final encryptedContent = E2eCryptoService.instance.encryptText(
      content,
      'p2p_key_$peerDeviceId',
    );

    final payload = jsonEncode({
      'type': 'TEXT_MESSAGE',
      'messageId': messageId,
      'senderDeviceId': myDeviceId,
      'senderDisplayName': myDisplayName,
      'content': encryptedContent,
      'timestamp': timestamp.millisecondsSinceEpoch,
    });

    final bytes = utf8.encode(payload);

    try {
      _socket?.send(bytes, InternetAddress(peerIp), p2pChatPort);
    } catch (e) {
      AppLogger.error('[P2P CHAT] Error sending text packet to $peerIp: $e');
    }

    // Save locally (isRead = false, 2 gray ticks)
    final chatMsg = ChatMessage(
      id: messageId,
      senderId: 'user',
      content: content,
      timestamp: timestamp,
      type: 'text',
      isRead: false,
    );

    await LocalChatStorage.instance.saveMessage(
      deviceId: peerDeviceId,
      peerName: peerDisplayName,
      message: chatMsg,
    );

    return true;
  }

  /// Send photo/video attachment over Wi-Fi to target IP address.
  Future<bool> sendMediaMessage({
    required String peerIp,
    required String peerDeviceId,
    required String peerDisplayName,
    required String filePath,
    required String mediaType, // 'image' or 'video'
    String? caption,
  }) async {
    final myDeviceId = AppPreferences.getDeviceIdSync() ?? 'device_me';
    final myDisplayName = AppPreferences.getDisplayName();
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final timestamp = DateTime.now();

    final file = File(filePath);
    if (!await file.exists()) return false;

    final bytes = await file.readAsBytes();
    final base64Media = base64Encode(bytes);

    final payload = jsonEncode({
      'type': 'MEDIA_MESSAGE',
      'messageId': messageId,
      'senderDeviceId': myDeviceId,
      'senderDisplayName': myDisplayName,
      'mediaType': mediaType,
      'mediaBase64': base64Media,
      'caption': caption ?? '',
      'timestamp': timestamp.millisecondsSinceEpoch,
    });

    final payloadBytes = utf8.encode(payload);

    try {
      _socket?.send(payloadBytes, InternetAddress(peerIp), p2pChatPort);
    } catch (e) {
      AppLogger.error('[P2P CHAT] Error sending media packet to $peerIp: $e');
    }

    // Save locally (isRead = false, 2 gray ticks)
    final chatMsg = ChatMessage(
      id: messageId,
      senderId: 'user',
      content: (caption != null && caption.isNotEmpty) ? caption : '[Attachment]',
      timestamp: timestamp,
      type: mediaType,
      mediaUrl: filePath,
      isRead: false,
    );

    await LocalChatStorage.instance.saveMessage(
      deviceId: peerDeviceId,
      peerName: peerDisplayName,
      message: chatMsg,
    );

    return true;
  }
}
