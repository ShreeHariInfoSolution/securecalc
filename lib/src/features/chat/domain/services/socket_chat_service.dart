import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../models/server_models.dart';
import 'call_service.dart';
import 'presence_store.dart';
import 'server_api_service.dart';

/// Manages real-time Socket.IO connection to https://synqerp.com/calculatorchat/
class SocketChatService {
  SocketChatService._();

  static final SocketChatService instance = SocketChatService._();

  IO.Socket? _socket;
  IO.Socket? get rawSocket => _socket;

  // Stream controllers for incoming server events
  final _messageStreamController =
      StreamController<ServerMessageModel>.broadcast();
  final _messageEditedStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messageDeletedStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messageSavedStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messageReactionStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _readStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _deliveredStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _typingStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _presenceStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<ServerMessageModel> get onNewMessage =>
      _messageStreamController.stream;
  Stream<Map<String, dynamic>> get onMessageEdited =>
      _messageEditedStreamController.stream;
  Stream<Map<String, dynamic>> get onMessageDeleted =>
      _messageDeletedStreamController.stream;
  Stream<Map<String, dynamic>> get onMessageSaved =>
      _messageSavedStreamController.stream;
  Stream<Map<String, dynamic>> get onMessageReaction =>
      _messageReactionStreamController.stream;
  Stream<Map<String, dynamic>> get onRead => _readStreamController.stream;
  Stream<Map<String, dynamic>> get onDelivered =>
      _deliveredStreamController.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingStreamController.stream;
  Stream<Map<String, dynamic>> get onPresence =>
      _presenceStreamController.stream;

  bool get isConnected => _socket?.connected == true;

  /// Connection state notifier for real-time online/offline UI updates
  final ValueNotifier<bool> connectionStateNotifier =
      ValueNotifier<bool>(false);

  /// Connects to the backend Socket.IO endpoint using the active JWT.
  void connect() {
    final token = ServerApiService.instance.authToken;
    if (token == null || token.isEmpty) {
      debugPrint('[SOCKET] No auth token found. Connection deferred.');
      disconnect();
      return;
    }

    if (_socket != null) {
      final currentSocketToken = _socket!.io.options?['auth']?['token'];
      if (currentSocketToken == token && _socket!.connected) {
        debugPrint('[SOCKET] Already connected with active user token. Re-emitting presence...');
        connectionStateNotifier.value = true;
        try {
          _socket!.emit('presence', {'status': 'online', 'is_online': true});
          _socket!.emit('user_online', {'is_online': true});
        } catch (_) {}
        return;
      }
      debugPrint(
        '[SOCKET] Token changed or socket inactive. Reconnecting socket for active user...',
      );
      disconnect();
    }

    debugPrint('[SOCKET] Connecting to http://synqerp.com:3000...');

    _socket = IO.io(
      'http://synqerp.com:3000',
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(2000)
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[SOCKET] Connected successfully! Socket ID: ${_socket!.id}');
      connectionStateNotifier.value = true;
      PresenceStore.instance.startTimer();
      try {
        _socket!.emit('presence', {'status': 'online', 'is_online': true});
        _socket!.emit('user_online', {'is_online': true});
      } catch (_) {}
      unawaited(CallService.instance.init().then((_) {
        if (_socket != null) CallService.instance.attachSocket(_socket!);
      }));
    });

    _socket!.onDisconnect((reason) {
      debugPrint('[SOCKET] Disconnected from server. Reason: $reason');
      connectionStateNotifier.value = false;
    });

    _socket!.onConnectError((error) {
      debugPrint('[SOCKET] Connection Error Details: $error');
      connectionStateNotifier.value = false;
    });

    _socket!.onError((err) {
      debugPrint('[SOCKET] General Socket Error Details: $err');
      connectionStateNotifier.value = false;
    });

    // ─── Server -> Client Event Listeners ────────────────────────────────────

    void handleNewMessage(dynamic data) {
      debugPrint('[SOCKET] Incoming message event: $data');
      final eventData = data is List && data.isNotEmpty ? data.first : data;
      if (eventData is Map) {
        try {
          var payload = Map<String, dynamic>.from(eventData);
          // Unwrap common API/socket envelopes until we reach the message row.
          for (var depth = 0; depth < 4; depth++) {
            if (payload['id'] != null ||
                payload['message_id'] != null ||
                payload['messageId'] != null) {
              break;
            }
            if (payload['data'] is Map) {
              payload = Map<String, dynamic>.from(payload['data'] as Map);
            } else if (payload['message'] is Map) {
              payload = Map<String, dynamic>.from(payload['message'] as Map);
            } else {
              break;
            }
          }
          if (payload['id'] == null &&
              payload['message_id'] == null &&
              payload['messageId'] == null) {
            debugPrint('[SOCKET] Incoming message payload has no message id.');
            return;
          }
          _messageStreamController.add(ServerMessageModel.fromJson(payload));
        } catch (error) {
          debugPrint('[SOCKET] Could not parse incoming message: $error');
        }
      }
    }

    _socket!.on('realtime.newMessage', handleNewMessage);
    _socket!.on('new_message', handleNewMessage);
    _socket!.on('newMessage', handleNewMessage);

    // Socket.IO catch-all listener for non-standard event names across backend deployments.
    _socket!.onAny((event, data) {
      final eventName = event.toString();
      final normalized = eventName.toLowerCase();
      debugPrint('[SOCKET] Server event: $eventName');
      final eventData = data is List && data.isNotEmpty ? data.first : data;
      if (eventData is Map) {
        final mapData = Map<String, dynamic>.from(eventData);
        if (normalized.contains('typing') && eventName != 'typing') {
          _typingStreamController.add(mapData);
        }
        if ((normalized.contains('presence') ||
                normalized.contains('online') ||
                normalized.contains('offline')) &&
            eventName != 'presence') {
          _presenceStreamController.add(mapData);
        }
        if (normalized.contains('message') &&
            !normalized.contains('edit') &&
            !normalized.contains('delet') &&
            !normalized.contains('reaction') &&
            !normalized.contains('read') &&
            !normalized.contains('save') &&
            !normalized.contains('saved') &&
            !normalized.contains('pin') &&
            !normalized.contains('mute') &&
            !normalized.contains('deliver') &&
            eventName != 'realtime.newMessage' &&
            eventName != 'new_message' &&
            eventName != 'newMessage') {
          handleNewMessage(data);
        }
      }
    });

    // 2. Message Edited
    _socket!.on('message_edited', (data) {
      debugPrint('[SOCKET] Event message_edited: $data');
      if (data is Map) {
        _messageEditedStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    // 3. Message Deleted
    _socket!.on('message_deleted', (data) {
      debugPrint('[SOCKET] Event message_deleted: $data');
      if (data is Map) {
        _messageDeletedStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    // 3b. Message Saved
    _socket!.on('message_saved', (data) {
      debugPrint('[SOCKET] Event message_saved: $data');
      if (data is Map) {
        _messageSavedStreamController.add(Map<String, dynamic>.from(data));
      }
    });
    _socket!.on('message_unsaved', (data) {
      debugPrint('[SOCKET] Event message_unsaved: $data');
      if (data is Map) {
        _messageSavedStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    // 4. Message Reaction
    _socket!.on('message_reaction', (data) {
      debugPrint('[SOCKET] Event message_reaction: $data');
      if (data is Map) {
        _messageReactionStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    // 5. Messages Read
    _socket!.on('messages_read', (data) {
      debugPrint('[SOCKET] Event messages_read: $data');
      if (data is Map) {
        _readStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    // 5b. Messages Delivered
    void handleDelivered(dynamic data) {
      debugPrint('[SOCKET] Event messages_delivered: $data');
      if (data is Map) {
        _deliveredStreamController.add(Map<String, dynamic>.from(data));
      }
    }

    _socket!.on('messages_delivered', handleDelivered);
    _socket!.on('message_delivered', handleDelivered);
    _socket!.on('delivered', handleDelivered);
    _socket!.on('message:delivered', handleDelivered);
    _socket!.on('messages:delivered', handleDelivered);
    _socket!.on('delivery_status', handleDelivered);

    // 6. Typing Indicator
    _socket!.on('typing', (data) {
      debugPrint('[SOCKET] Event typing: $data');
      if (data is Map) {
        _typingStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    // 7. User Presence
    _socket!.on('presence', (data) {
      debugPrint('[SOCKET] Event presence: $data');
      if (data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        PresenceStore.instance.updatePresence(mapData);
        _presenceStreamController.add(mapData);
      }
    });

    _socket!.connect();
  }

  void disconnect() {
    connectionStateNotifier.value = false;
    if (_socket != null && _socket!.connected) {
      try {
        _socket!.emit('presence', {'status': 'offline', 'is_online': false});
        _socket!.emit('user_offline', {'is_online': false});
      } catch (_) {}
    }
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  // ─── Client -> Server Events ───────────────────────────────────────────────

  /// send_message: chat_head_id, message, reply_to_id?, client_id, file_path?, file_name?, file_type?
  Future<Map<String, dynamic>?> sendMessage({
    required int chatId,
    required String message,
    String? filePath,
    String? fileName,
    String? fileType,
    int? replyToId,
    String? clientId,
  }) async {
    if (!isConnected) {
      debugPrint('[SOCKET] Not connected. Cannot emit send_message.');
      return null;
    }

    final payload = <String, dynamic>{
      'chat_head_id': chatId,
      'chat_id': chatId,
      'message': message,
      'ciphertext': message,
      'text': message,
      'content': message,
      'client_id': clientId ?? 'local_${DateTime.now().millisecondsSinceEpoch}',
      if (replyToId != null) 'reply_to_id': replyToId,
      if (filePath != null) 'file_path': filePath,
      if (fileName != null) 'file_name': fileName,
      if (fileType != null) 'file_type': fileType,
    };
    debugPrint('[SOCKET] Emitting send_message: $payload');
    _socket!.emit('send_message', payload);
    return {'status': 'emitted', ...payload};
  }

  /// edit_message: message_id, message
  void editMessage({required int messageId, required String message}) {
    if (!isConnected) return;

    final payload = <String, dynamic>{
      'message_id': messageId,
      'id': messageId,
      'message': message,
      'ciphertext': message,
      'text': message,
      'content': message,
    };
    debugPrint('[SOCKET] Emitting edit_message: $payload');
    _socket!.emit('edit_message', payload);
  }

  /// delete_message: message_id
  void deleteMessage({required int messageId, int type = 1}) {
    if (!isConnected) return;

    final payload = <String, dynamic>{
      'message_id': messageId,
      'id': messageId,
      'type': type,
      'delete_type': type,
    };
    debugPrint('[SOCKET] Emitting delete_message: $payload');
    _socket!.emit('delete_message', payload);
  }

  /// react_message: message_id, chat_react
  void reactMessage({required int messageId, required String chatReact}) {
    if (!isConnected) return;

    final payload = <String, dynamic>{
      'message_id': messageId,
      'chat_react': chatReact,
      'reaction': chatReact,
    };
    debugPrint('[SOCKET] Emitting react_message: $payload');
    _socket!.emit('react_message', payload);
  }

  /// mark_read: chat_head_id
  void markRead({required int chatHeadId}) {
    if (!isConnected) return;

    final payload = <String, dynamic>{
      'chat_head_id': chatHeadId,
      'chat_id': chatHeadId,
    };
    debugPrint('[SOCKET] Emitting mark_read: $payload');
    _socket!.emit('mark_read', payload);
  }

  /// typing: chat_head_id, is_typing
  void sendTyping({required int chatHeadId, required bool isTyping}) {
    if (!isConnected) return;

    final payload = <String, dynamic>{
      'chat_head_id': chatHeadId,
      'chat_id': chatHeadId,
      'is_typing': isTyping,
      'typing': isTyping,
    };
    debugPrint('[SOCKET] Emitting typing: $payload');
    _socket!.emit('typing', payload);
  }
}
