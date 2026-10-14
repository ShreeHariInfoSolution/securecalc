import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
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
import '../pages/image_preview_editor_page.dart';

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
    String? caption,
  }) onSendAttachment;
  final VoidCallback? onDisappearingTap;

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
    this.onDisappearingTap,
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

  DateTime? _lastTypingEmitted;

  void _onInputChanged(String val) {
    setState(() {}); // update UI for send icon
    
    if (_typingDebounce?.isActive ?? false) _typingDebounce!.cancel();
    final text = val.trim();
    if (text.isNotEmpty) {
      final now = DateTime.now();
      if (_lastTypingEmitted == null || now.difference(_lastTypingEmitted!) > const Duration(seconds: 2)) {
        _lastTypingEmitted = now;
        widget.onTypingChanged(true);
      }
      _typingDebounce = Timer(const Duration(milliseconds: 2500), () {
        _lastTypingEmitted = null;
        widget.onTypingChanged(false);
      });
    } else {
      _lastTypingEmitted = null;
      widget.onTypingChanged(false);
    }
  }

  String _attachmentType(String fileName) =>
      inferAttachmentType(fileName: fileName) ?? 'application/octet-stream';

  Future<bool> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted || status.isLimited) {
      return true;
    }

    status = await Permission.camera.request();
    if (status.isGranted || status.isLimited) {
      return true;
    }

    if (mounted) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Camera Access Required'),
          content: const Text(
            'Calnox Vault needs camera access so you can take and send photos. Please enable Camera in Settings.',
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('Settings'),
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
            ),
          ],
        ),
      );
    }
    return false;
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    AppPreferences.isPickerActive = true;
    try {
      final List<File> pickedFiles = [];
      if (source == ImageSource.camera) {
        final hasPermission = await _checkCameraPermission();
        if (!hasPermission) return;
        final picked = await _picker.pickImage(source: source, imageQuality: 90);
        if (picked == null) return;
        pickedFiles.add(File(picked.path));
      } else {
        final multi = await _picker.pickMultiImage(imageQuality: 90);
        if (multi.isEmpty) return;
        pickedFiles.addAll(multi.map((f) => File(f.path)));
      }

      if (pickedFiles.isEmpty || !mounted) return;

      // Open Image Editor Preview (WhatsApp Style)
      final editorResult = await Navigator.of(context).push<ImageEditorResult>(
        MaterialPageRoute(
          builder: (_) => ImagePreviewEditorPage(imageFiles: pickedFiles),
        ),
      );

      if (editorResult == null || editorResult.images.isEmpty) return;

      for (int i = 0; i < editorResult.images.length; i++) {
        final file = editorResult.images[i];
        final fileName = file.path.split(Platform.pathSeparator).last;
        final caption = (i == 0 && editorResult.caption.isNotEmpty)
            ? editorResult.caption
            : null;
        await widget.onSendAttachment(
          file: file,
          fileName: fileName,
          fileType: _attachmentType(fileName),
          caption: caption,
        );
      }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom + 62.0;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Attachments',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            alignment: Alignment.bottomLeft,
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, animation1, animation2) {
        return Stack(
          children: [
            // Subtle Frosted Glass Scrim
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(dialogContext),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),

            // Anchored Lower-Left Glass Attachment Panel
            Positioned(
              left: 16,
              bottom: bottomInset,
              width: 220,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1C1E).withValues(alpha: 0.88)
                            : Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppTheme.glassBorder(isDark),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildGlassAttachmentRow(
                            dialogContext,
                            icon: CupertinoIcons.camera_fill,
                            iconColor: const Color(0xFF007AFF),
                            label: 'Camera',
                            onTap: () {
                              Navigator.pop(dialogContext);
                              _pickAndSendImage(ImageSource.camera);
                            },
                            isDark: isDark,
                          ),
                          _buildGlassAttachmentRow(
                            dialogContext,
                            icon: CupertinoIcons.photo_fill,
                            iconColor: const Color(0xFFFF2D55),
                            label: 'Photos',
                            onTap: () {
                              Navigator.pop(dialogContext);
                              _pickAndSendImage(ImageSource.gallery);
                            },
                            isDark: isDark,
                          ),
                          _buildGlassAttachmentRow(
                            dialogContext,
                            icon: CupertinoIcons.videocam_fill,
                            iconColor: const Color(0xFF34C759),
                            label: 'Video',
                            onTap: () {
                              Navigator.pop(dialogContext);
                              _pickAndSendVideo();
                            },
                            isDark: isDark,
                          ),
                          _buildGlassAttachmentRow(
                            dialogContext,
                            icon: CupertinoIcons.doc_fill,
                            iconColor: const Color(0xFFFF9500),
                            label: 'Files',
                            onTap: () {
                              Navigator.pop(dialogContext);
                              _pickAndSendFile();
                            },
                            isDark: isDark,
                          ),
                          _buildGlassAttachmentRow(
                            dialogContext,
                            icon: CupertinoIcons.mic_fill,
                            iconColor: const Color(0xFFAF52DE),
                            label: 'Voice',
                            onTap: () {
                              Navigator.pop(dialogContext);
                              _toggleVoiceRecording();
                            },
                            isDark: isDark,
                          ),
                          _buildGlassAttachmentRow(
                            dialogContext,
                            icon: CupertinoIcons.timer,
                            iconColor: const Color(0xFF5856D6),
                            label: 'Disappearing',
                            onTap: () {
                              Navigator.pop(dialogContext);
                              widget.onDisappearingTap?.call();
                            },
                            isDark: isDark,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGlassAttachmentRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    bool showDivider = true,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(icon, color: iconColor, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.primaryText(isDark),
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 62),
            child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: AppTheme.listDivider(isDark),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.editingMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.pencil,
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
                  icon: const Icon(CupertinoIcons.xmark, size: 18),
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
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding > 0 ? bottomPadding + 4 : 12),
              decoration: BoxDecoration(
                color: AppTheme.composerSurface(isDark),
              ),
              child: Row(
                children: [
                  // Floating Plus Button
                  GestureDetector(
                    onTap: () => _showAttachmentOptions(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2C2C2E).withValues(alpha: 0.85)
                            : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.glassBorder(isDark),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.3 : 0.06,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          CupertinoIcons.add,
                          size: 20,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Rounded Pill Input Bar
                  Expanded(
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.only(left: 14, right: 6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : const Color(0xFFE5E5EA),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (_isRecordingVoice)
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(
                                    CupertinoIcons.circle_fill,
                                    color: Colors.redAccent,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatRecordingDuration(_recordingDuration),
                                    style: TextStyle(
                                      color: AppTheme.primaryText(isDark),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Recording voice message…',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppTheme.secondaryText(isDark),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: _cancelVoiceRecording,
                                    icon: Icon(
                                      CupertinoIcons.xmark,
                                      size: 16,
                                      color: AppTheme.secondaryText(isDark),
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
                                style: TextStyle(
                                  fontSize: 16,
                                  color: AppTheme.primaryText(isDark),
                                  letterSpacing: -0.2,
                                ),
                                decoration: InputDecoration(
                                  hintText: widget.editingMessage == null ? 'iMessage' : 'Edit message',
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                  hintStyle: TextStyle(
                                    color: AppTheme.secondaryText(isDark),
                                    fontSize: 16,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                onSubmitted: (_) => widget.onSendText(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: widget.isSending
                                  ? null
                                  : (widget.editingMessage != null || widget.inputController.text.trim().isNotEmpty
                                      ? widget.onSendText
                                      : _toggleVoiceRecording),
                              child: widget.isSending
                                  ? const SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: Padding(
                                        padding: EdgeInsets.all(4),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    )
                                  : widget.editingMessage != null || widget.inputController.text.trim().isNotEmpty
                                      ? Container(
                                          width: 28,
                                          height: 28,
                                          decoration: const BoxDecoration(
                                            color: AppTheme.primaryColor,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Icon(
                                              widget.editingMessage != null
                                                  ? CupertinoIcons.checkmark
                                                  : CupertinoIcons.arrow_up,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                        )
                                      : Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          child: Icon(
                                            CupertinoIcons.waveform,
                                            size: 20,
                                            color: AppTheme.secondaryText(isDark),
                                          ),
                                        ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
