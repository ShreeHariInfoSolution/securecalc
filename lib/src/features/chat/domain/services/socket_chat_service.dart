import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/server_models.dart';
import 'server_api_service.dart';

/// Manages real-time Socket.IO connection to https://synqerp.com/calculatorchat/
class SocketChatService {
  SocketChatService._();

  static final SocketChatService instance = SocketChatService._();

  IO.Socket? _socket;

  // Stream controllers for incoming server events
  final _messageStreamController = StreamController<ServerMessageModel>.broadcast();
  final _messageEditedStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final _messageDeletedStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final _messageReactionStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final _readStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceStreamController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<ServerMessageModel> get onNewMessage => _messageStreamController.stream;
  Stream<Map<String, dynamic>> get onMessageEdited => _messageEditedStreamController.stream;
  Stream<Map<String, dynamic>> get onMessageDeleted => _messageDeletedStreamController.stream;
  Stream<Map<String, dynamic>> get onMessageReaction => _messageReactionStreamController.stream;
  Stream<Map<String, dynamic>> get onRead => _readStreamController.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingStreamController.stream;
  Stream<Map<String, dynamic>> get onPresence => _presenceStreamController.stream;

  bool get isConnected => _socket?.connected == true;

  /// Connects to the backend Socket.IO endpoint using the active JWT.
  void connect() {
    final token = ServerApiService.instance.authToken;
    if (token == null || token.isEmpty) {
      debugPrint('[SOCKET] No auth token found. Connection deferred.');
      return;
    }

    if (_socket != null) return;

    debugPrint('[SOCKET] Connecting to http://synqerp.com:3000...');

    _socket = IO.io(
      'http://synqerp.com:3000',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(2000)
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[SOCKET] Connected successfully! Socket ID: ${_socket!.id}');
    });

    _socket!.onDisconnect((reason) {
      debugPrint('[SOCKET] Disconnected from server. Reason: $reason');
    });

    _socket!.onConnectError((error) {
      debugPrint('[SOCKET] Connection Error Details: $error');
    });

    _socket!.onError((err) {
      debugPrint('[SOCKET] General Socket Error Details: $err');
    });

    // ─── Server -> Client Event Listeners ────────────────────────────────────

    // Normalize the known message event names into the same message stream.
    void handleNewMessage(dynamic data) {
      debugPrint('[SOCKET] Incoming message event: $data');
      final eventData = data is List && data.isNotEmpty ? data.first : data;
      if (eventData is Map) {
        try {
          var payload = eventData;
          // Unwrap common API/socket envelopes until we reach the message row.
          for (var depth = 0; depth < 4; depth++) {
            if (payload['id'] != null ||
                payload['message_id'] != null ||
                payload['messageId'] != null) {
              break;
            }
            if (payload['data'] is Map) {
              payload = payload['data'] as Map;
            } else if (payload['message'] is Map) {
              payload = payload['message'] as Map;
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
          _messageStreamController.add(
            ServerMessageModel.fromJson(Map<String, dynamic>.from(payload)),
          );
        } catch (error) {
          debugPrint('[SOCKET] Could not parse incoming message: $error');
        }
      }
    }

    _socket!.on('realtime.newMessage', handleNewMessage);
    _socket!.on('new_message', handleNewMessage);
    _socket!.on('newMessage', handleNewMessage);

    // Keep the named handlers above for the documented event names, and use
    // Socket.IO's catch-all as a compatibility path for backend message event
    // names that differ between deployments.
    _socket!.onAny((event, data) {
      final eventName = event.toString();
      final normalized = eventName.toLowerCase();
      debugPrint('[SOCKET] Server event: $eventName');
      final eventData = data is List && data.isNotEmpty ? data.first : data;
      if (eventData is Map &&
          normalized.contains('typing') &&
          eventName != 'typing') {
        _typingStreamController.add(Map<String, dynamic>.from(eventData));
      }
      if (eventData is Map &&
          (normalized.contains('presence') ||
              normalized.contains('online') ||
              normalized.contains('offline')) &&
          eventName != 'presence') {
        _presenceStreamController.add(Map<String, dynamic>.from(eventData));
      }
      if (normalized.contains('message') &&
          !normalized.contains('edit') &&
          !normalized.contains('delet') &&
          !normalized.contains('reaction') &&
          !normalized.contains('read') &&
          eventName != 'realtime.newMessage' &&
          eventName != 'new_message' &&
          eventName != 'newMessage') {
        handleNewMessage(data);
      }
    });

    // 2. Message Edited
    _socket!.on('message_edited', (data) {
      debugPrint('[SOCKET] Event message_edited: $data');
      if (data is Map<String, dynamic>) {
        _messageEditedStreamController.add(data);
      } else if (data is Map) {
        _messageEditedStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    // 3. Message Deleted
    _socket!.on('message_deleted', (data) {
      debugPrint('[SOCKET] Event message_deleted: $data');
      if (data is Map<String, dynamic>) {
        _messageDeletedStreamController.add(data);
      } else if (data is Map) {
        _messageDeletedStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    // 4. Message Reaction
    _socket!.on('message_reaction', (data) {
      debugPrint('[SOCKET] Event message_reaction: $data');
      if (data is Map<String, dynamic>) {
        _messageReactionStreamController.add(data);
      } else if (data is Map) {
        _messageReactionStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    // 5. Messages Read
    _socket!.on('messages_read', (data) {
      debugPrint('[SOCKET] Event messages_read: $data');
      if (data is Map<String, dynamic>) {
        _readStreamController.add(data);
      } else if (data is Map) {
        _readStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    // 6. Typing Indicator
    _socket!.on('typing', (data) {
      debugPrint('[SOCKET] Event typing: $data');
      if (data is Map<String, dynamic>) {
        _typingStreamController.add(data);
      } else if (data is Map) {
        _typingStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    // 7. User Presence
    _socket!.on('presence', (data) {
      debugPrint('[SOCKET] Event presence: $data');
      if (data is Map<String, dynamic>) {
        _presenceStreamController.add(data);
      } else if (data is Map) {
        _presenceStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.connect();
  }

  void disconnect() {
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
    Duration ackTimeout = const Duration(seconds: 15),
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
    final completer = Completer<Map<String, dynamic>?>();
    debugPrint('[SOCKET] Emitting send_message: $payload');
    _socket!.emitWithAck(
      'send_message',
      payload,
      ack: (response) {
        debugPrint('[SOCKET] send_message Ack Response: $response');
        if (response is Map) {
          completer.complete(Map<String, dynamic>.from(response));
        } else {
          completer.complete(null);
        }
      },
    );
    try {
      return await completer.future.timeout(ackTimeout);
    } on TimeoutException {
      debugPrint('[SOCKET] send_message acknowledgement timed out.');
      return null;
    }
  }

  /// edit_message: message_id, message
  Future<Map<String, dynamic>?> editMessage({
    required int messageId,
    required String message,
    Duration ackTimeout = const Duration(seconds: 15),
  }) async {
    if (!isConnected) {
      debugPrint('[SOCKET] Not connected. Cannot emit edit_message.');
      return null;
    }

    final payload = <String, dynamic>{
      'message_id': messageId,
      'id': messageId,
      'message': message,
      'ciphertext': message,
      'text': message,
      'content': message,
    };
    final completer = Completer<Map<String, dynamic>?>();
    _socket!.emitWithAck(
      'edit_message',
      payload,
      ack: (response) {
        if (response is Map) {
          completer.complete(Map<String, dynamic>.from(response));
        } else {
          completer.complete(null);
        }
      },
    );
    try {
      return await completer.future.timeout(ackTimeout);
    } on TimeoutException {
      debugPrint('[SOCKET] edit_message acknowledgement timed out.');
      return null;
    }
  }

  /// delete_message: message_id
  Future<Map<String, dynamic>?> deleteMessage({
    required int messageId,
    Duration ackTimeout = const Duration(seconds: 15),
  }) async {
    if (!isConnected) {
      debugPrint('[SOCKET] Not connected. Cannot emit delete_message.');
      return null;
    }

    final payload = <String, dynamic>{
      'message_id': messageId,
      'id': messageId,
    };
    final completer = Completer<Map<String, dynamic>?>();
    _socket!.emitWithAck(
      'delete_message',
      payload,
      ack: (response) {
        if (response is Map) {
          completer.complete(Map<String, dynamic>.from(response));
        } else {
          completer.complete(null);
        }
      },
    );
    try {
      return await completer.future.timeout(ackTimeout);
    } on TimeoutException {
      debugPrint('[SOCKET] delete_message acknowledgement timed out.');
      return null;
    }
  }

  /// react_message: message_id, chat_react
  Future<Map<String, dynamic>?> reactMessage({
    required int messageId,
    required String chatReact,
    Duration ackTimeout = const Duration(seconds: 15),
  }) async {
    if (!isConnected) {
      debugPrint('[SOCKET] Not connected. Cannot emit react_message.');
      return null;
    }

    final payload = <String, dynamic>{
      'message_id': messageId,
      'chat_react': chatReact,
      'reaction': chatReact,
    };
    final completer = Completer<Map<String, dynamic>?>();
    _socket!.emitWithAck(
      'react_message',
      payload,
      ack: (response) {
        if (response is Map) {
          completer.complete(Map<String, dynamic>.from(response));
        } else {
          completer.complete(null);
        }
      },
    );
    try {
      return await completer.future.timeout(ackTimeout);
    } on TimeoutException {
      debugPrint('[SOCKET] react_message acknowledgement timed out.');
      return null;
    }
  }

  /// mark_read: chat_head_id
  Future<Map<String, dynamic>?> markRead({
    required int chatHeadId,
    Duration ackTimeout = const Duration(seconds: 15),
  }) async {
    if (!isConnected) {
      debugPrint('[SOCKET] Not connected. Cannot emit mark_read.');
      return null;
    }

    final payload = <String, dynamic>{
      'chat_head_id': chatHeadId,
      'chat_id': chatHeadId,
    };
    final completer = Completer<Map<String, dynamic>?>();
    _socket!.emitWithAck(
      'mark_read',
      payload,
      ack: (response) {
        if (response is Map) {
          completer.complete(Map<String, dynamic>.from(response));
        } else {
          completer.complete(null);
        }
      },
    );
    try {
      return await completer.future.timeout(ackTimeout);
    } on TimeoutException {
      debugPrint('[SOCKET] mark_read acknowledgement timed out.');
      return null;
    }
  }

  /// typing: chat_head_id, is_typing
  Future<Map<String, dynamic>?> sendTyping({
    required int chatHeadId,
    required bool isTyping,
    Duration ackTimeout = const Duration(seconds: 15),
  }) async {
    if (!isConnected) {
      debugPrint('[SOCKET] Not connected. Cannot emit typing.');
      return null;
    }

    final payload = <String, dynamic>{
      'chat_head_id': chatHeadId,
      'chat_id': chatHeadId,
      'is_typing': isTyping,
      'typing': isTyping,
    };
    final completer = Completer<Map<String, dynamic>?>();
    _socket!.emitWithAck(
      'typing',
      payload,
      ack: (response) {
        if (response is Map) {
          completer.complete(Map<String, dynamic>.from(response));
        } else {
          completer.complete(null);
        }
      },
    );
    try {
      return await completer.future.timeout(ackTimeout);
    } on TimeoutException {
      debugPrint('[SOCKET] typing acknowledgement timed out.');
      return null;
    }
  }
}
