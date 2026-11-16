import 'package:flutter/foundation.dart';

class UploadProgress {
  final String messageId;
  final int bytesSent;
  final int totalBytes;
  final double progress;
  final bool isCompleted;
  final bool isFailed;
  final String? error;

  UploadProgress({
    required this.messageId,
    required this.bytesSent,
    required this.totalBytes,
    required this.progress,
    this.isCompleted = false,
    this.isFailed = false,
    this.error,
  });
}

class AttachmentUploadService {
  AttachmentUploadService._();
  static final AttachmentUploadService instance = AttachmentUploadService._();

  final Map<String, ValueNotifier<UploadProgress>> _progressNotifiers = {};
  final Set<String> _cancelledMessageIds = {};
  final Map<String, VoidCallback> _retryActions = {};
  final Map<String, VoidCallback> _discardActions = {};

  ValueNotifier<UploadProgress> getProgressNotifier(String messageId) {
    return _progressNotifiers.putIfAbsent(
      messageId,
      () => ValueNotifier<UploadProgress>(
        UploadProgress(
          messageId: messageId,
          bytesSent: 0,
          totalBytes: 0,
          progress: 0.0,
        ),
      ),
    );
  }

  /// Lets the chat page expose Retry / Delete to the bubble without
  /// passing callbacks through the whole widget tree.
  void registerActions(
    String messageId, {
    required VoidCallback onRetry,
    required VoidCallback onDiscard,
  }) {
    _retryActions[messageId] = onRetry;
    _discardActions[messageId] = onDiscard;
  }

  VoidCallback? retryAction(String messageId) => _retryActions[messageId];
  VoidCallback? discardAction(String messageId) => _discardActions[messageId];

  void updateProgress(String messageId, int bytesSent, int totalBytes) {
    if (_cancelledMessageIds.contains(messageId)) return;
    final double p =
        totalBytes > 0 ? (bytesSent / totalBytes).clamp(0.0, 1.0) : 0.0;
    getProgressNotifier(messageId).value = UploadProgress(
      messageId: messageId,
      bytesSent: bytesSent,
      totalBytes: totalBytes,
      progress: p,
    );
  }

  void markCompleted(String messageId) {
    final notifier = getProgressNotifier(messageId);
    notifier.value = UploadProgress(
      messageId: messageId,
      bytesSent: notifier.value.totalBytes,
      totalBytes: notifier.value.totalBytes,
      progress: 1.0,
      isCompleted: true,
    );
  }

  void markFailed(String messageId, String error) {
    final notifier = getProgressNotifier(messageId);
    if (notifier.value.isCompleted) return;
    notifier.value = UploadProgress(
      messageId: messageId,
      bytesSent: notifier.value.bytesSent,
      totalBytes: notifier.value.totalBytes,
      progress: notifier.value.progress,
      isFailed: true,
      error: error,
    );
  }

  void cancelUpload(String messageId) {
    _cancelledMessageIds.add(messageId);
    markFailed(messageId, 'Upload cancelled');
  }

  /// Clears cancelled/failed state so the upload can run again.
  void resetForRetry(String messageId) {
    _cancelledMessageIds.remove(messageId);
    getProgressNotifier(messageId).value = UploadProgress(
      messageId: messageId,
      bytesSent: 0,
      totalBytes: 0,
      progress: 0.0,
    );
  }

  void clearActions(String messageId) {
    _retryActions.remove(messageId);
    _discardActions.remove(messageId);
  }

  bool isCancelled(String messageId) => _cancelledMessageIds.contains(messageId);
}
