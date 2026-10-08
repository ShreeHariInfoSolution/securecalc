import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../../core/config/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/models/server_models.dart';
import 'chat_reply_banner.dart';
import '../../domain/entities/chat_conversation.dart';

class ChatComposer extends StatefulWidget {
  final TextEditingController inputController;
  final FocusNode inputFocusNode;
  final ChatMessage? editingMessage;
  final ChatMessage? replyingMessage;
  final ChatConversation conversation;
  final String chatName;
  final Map<int, String> groupMemberNames;
  final bool isSending;
  final VoidCallback onCancelEditing;
  final VoidCallback onCancelReply;
  final void Function(bool) onTypingChanged;
  final Future<void> Function() onSendText;
  final Future<void> Function({
    required File file,
    required String fileName,
    required String fileType,
  }) onSendAttachment;

  const ChatComposer({
    super.key,
    required this.inputController,
    required this.inputFocusNode,
    required this.editingMessage,
    required this.replyingMessage,
    required this.conversation,
    required this.chatName,
    required this.groupMemberNames,
    required this.isSending,
    required this.onCancelEditing,
    required this.onCancelReply,
    required this.onTypingChanged,
    required this.onSendText,
    required this.onSendAttachment,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  
  bool _isRecordingVoice = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  Timer? _typingDebounce;

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _typingDebounce?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _onInputChanged(String val) {
    setState(() {}); // update UI for send icon
    
    if (_typingDebounce?.isActive ?? false) _typingDebounce!.cancel();
    if (val.trim().isNotEmpty) {
      widget.onTypingChanged(true);
      _typingDebounce = Timer(const Duration(seconds: 3), () {
        widget.onTypingChanged(false);
      });
    } else {
      widget.onTypingChanged(false);
    }
  }

  String _attachmentType(String fileName) =>
      inferAttachmentType(fileName: fileName) ?? 'application/octet-stream';

  Future<void> _pickAndSendImage(ImageSource source) async {
    AppPreferences.isPickerActive = true;
    try {
      if (source == ImageSource.camera &&
          !(await Permission.camera.request()).isGranted) {
        throw Exception('Camera permission is required.');
      }
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      await widget.onSendAttachment(
        file: File(picked.path),
        fileName: picked.name,
        fileType: _attachmentType(picked.name),
      );
    } catch (error) {
      debugPrint('[IMAGE PICK ERROR] $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to pick image: $error')),
        );
      }
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _pickAndSendVideo() async {
    AppPreferences.isPickerActive = true;
    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      await widget.onSendAttachment(
        file: File(picked.path),
        fileName: picked.name,
        fileType: _attachmentType(picked.name),
      );
    } catch (error) {
      debugPrint('[VIDEO PICK ERROR] $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to pick video: $error')),
        );
      }
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _pickAndSendFile() async {
    AppPreferences.isPickerActive = true;
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final picked = files.first;
      var path = picked.path;
      if (path == null || path.isEmpty) {
        final temporaryDirectory = await getTemporaryDirectory();
        final safeName = picked.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        path = '${temporaryDirectory.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
        await File(path).writeAsBytes(await picked.readAsBytes(), flush: true);
      }
      await widget.onSendAttachment(
        file: File(path),
        fileName: picked.name,
        fileType: _attachmentType(picked.name),
      );
    } catch (error) {
      debugPrint('[FILE PICK ERROR] $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to attach file: $error')),
        );
      }
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (widget.isSending) return;
    if (_isRecordingVoice) {
      await _finishVoiceRecording(send: true);
      return;
    }
    try {
      if (!await _audioRecorder.hasPermission()) {
        throw Exception('Microphone permission is required.');
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = true;
        _recordingDuration = Duration.zero;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordingDuration += const Duration(seconds: 1));
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to start recording: $error')),
        );
      }
    }
  }

  Future<void> _finishVoiceRecording({required bool send}) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final path = await _audioRecorder.stop();
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingDuration = Duration.zero;
      });
    }
    if (!send || path == null || path.isEmpty) return;
    await widget.onSendAttachment(
      file: File(path),
      fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      fileType: 'audio/mp4',
    );
  }

  Future<void> _cancelVoiceRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _audioRecorder.cancel();
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingDuration = Duration.zero;
      });
    }
  }

  String _formatRecordingDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showAttachmentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildOptionItem(Icons.image_rounded, 'Photo', Colors.purple, () {
                  Navigator.pop(context);
                  _pickAndSendImage(ImageSource.gallery);
                }),
                _buildOptionItem(Icons.camera_alt_rounded, 'Camera', Colors.blue, () {
                  Navigator.pop(context);
                  _pickAndSendImage(ImageSource.camera);
                }),
                _buildOptionItem(Icons.videocam_rounded, 'Video', Colors.teal, () {
                  Navigator.pop(context);
                  _pickAndSendVideo();
                }),
                _buildOptionItem(Icons.insert_drive_file_rounded, 'File', Colors.orange, () {
                  Navigator.pop(context);
                  _pickAndSendFile();
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.editingMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            color: isDark ? AppTheme.darkSurface : Colors.white,
            child: Row(
              children: [
                const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Editing message',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onCancelEditing,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Cancel edit',
                ),
              ],
            ),
          ),
        if (widget.replyingMessage != null)
          ChatReplyBanner(
            replyingMessage: widget.replyingMessage!,
            conversation: widget.conversation,
            chatName: widget.chatName,
            groupMemberNames: widget.groupMemberNames,
            onCancel: widget.onCancelReply,
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _showAttachmentOptions(context),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      if (_isRecordingVoice)
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.fiber_manual_record_rounded,
                                color: Colors.redAccent,
                                size: 12,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatRecordingDuration(_recordingDuration),
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Recording voice message…',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppTheme.subtitleGrey,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: _cancelVoiceRecording,
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: AppTheme.subtitleGrey,
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Expanded(
                          child: TextField(
                            controller: widget.inputController,
                            focusNode: widget.inputFocusNode,
                            onChanged: _onInputChanged,
                            decoration: InputDecoration(
                              hintText: widget.editingMessage == null ? 'iMessage' : 'Edit message',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              hintStyle: const TextStyle(
                                color: AppTheme.subtitleGrey,
                                fontSize: 15,
                              ),
                            ),
                            style: TextStyle(
                              fontSize: 15,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            onSubmitted: (_) => widget.onSendText(),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _pickAndSendImage(ImageSource.camera),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 18,
                            color: AppTheme.subtitleGrey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.isSending
                    ? null
                    : (widget.editingMessage != null || widget.inputController.text.trim().isNotEmpty
                        ? widget.onSendText
                        : _toggleVoiceRecording),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.editingMessage != null ||
                            _isRecordingVoice ||
                            widget.inputController.text.trim().isNotEmpty
                        ? AppTheme.primaryColor
                        : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
                    shape: BoxShape.circle,
                    boxShadow: widget.editingMessage != null ||
                            _isRecordingVoice ||
                            widget.inputController.text.trim().isNotEmpty
                        ? [
                            BoxShadow(
                              color: AppTheme.primaryColor.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: widget.isSending
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          widget.editingMessage != null
                              ? Icons.check_rounded
                              : widget.inputController.text.trim().isNotEmpty
                                  ? Icons.arrow_upward_rounded
                                  : _isRecordingVoice
                                      ? Icons.send_rounded
                                      : Icons.mic_rounded,
                          size: 18,
                          color: widget.editingMessage != null ||
                                  _isRecordingVoice ||
                                  widget.inputController.text.trim().isNotEmpty
                              ? Colors.white
                              : AppTheme.primaryColor,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
