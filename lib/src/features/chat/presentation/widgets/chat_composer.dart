import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/config/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_toast.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/models/server_models.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/server_chat_manager.dart';
import '../pages/app_camera_page.dart';
import '../pages/image_preview_editor_page.dart';
import '../pages/location_picker_page.dart';
import 'chat_reply_preview.dart';
import 'gif_picker_panel.dart';
import 'sticker_picker_panel.dart';
import 'voice_record_widgets.dart';
import 'voice_recorder_controller.dart';

class NoDoubleSpacePeriod extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    if (o.text.endsWith(' ') &&
        n.text.length == o.text.length + 1 &&
        n.text == '${o.text.substring(0, o.text.length - 1)}. ' &&
        n.selection.isCollapsed) {
      final t = '${o.text} ';
      return n.copyWith(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
        composing: TextRange.empty,
      );
    }
    return n;
  }
}

/// Lets the chat page close the GIF panel (scroll / back button) and know if it is open.
/// Owned by the page. It is tiny, so it is intentionally never disposed
/// (avoids "used after dispose" races when the composer is torn down).
class ChatComposerController {
  final ValueNotifier<bool> isPanelOpen = ValueNotifier<bool>(false);
  /// Total height the composer occupies (pill + GIF panel + keyboard),
  /// published synchronously every frame so the list never lags behind.
  final ValueNotifier<double?> bottomSpace = ValueNotifier<double?>(null);
  Future<void> Function()? _close;
  Future<void> closePanels() async => _close?.call();
}

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
    bool isHd,
  }) onSendAttachment;
  final Function(StickerItem sticker)? onSendSticker;
  final Function(GifItem gif)? onSendGif;
  final VoidCallback? onDisappearingTap;
  final ChatComposerController? controller;

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
    this.onSendSticker,
    this.onSendGif,
    this.onDisappearingTap,
    this.controller,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _ctl = 32;   // button size
  static const double _slot = 40;  // one-line row height
  static const double _pad = 4;    // pill padding

  static const _spring =
      SpringDescription(mass: 1, stiffness: 400, damping: 18); // lower damping = more bounce

  late final AnimationController _merge = AnimationController.unbounded(vsync: this);
  late final AnimationController _pop =
      AnimationController.unbounded(vsync: this, value: 1);
  bool _sendMode = false;

  // ───────── GIF panel state ─────────
  static double _kbH = AppPreferences.savedKeyboardHeight; // remembers real keyboard height from preferences
  double _lastInset = 0;
  bool _showGifPicker = false;
  bool _gifSearching = false;
  bool _closing = false;
  final ValueNotifier<double> _insetTick = ValueNotifier<double>(0);
  double _pillH = 48;
  DateTime _openedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _settle;
  Timer? _kbSave;

  /// 0 -> 1 : panel visible (slide up when the keyboard was closed)
  late final AnimationController _gifAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  /// 0 -> 1 : search mode (pill collapses, panel grows above the keyboard)
  late final AnimationController _searchAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  bool get _wantSend =>
      widget.editingMessage != null || widget.inputController.text.isNotEmpty;

  void _syncMode() {
    final want = _wantSend;
    if (want == _sendMode) return;
    _sendMode = want;
    // continue from current position + velocity so quick typing/deleting stays smooth
    _merge.animateWith(
        SpringSimulation(_spring, _merge.value, want ? 1.0 : 0.0, _merge.velocity));
    _pop.animateWith(SpringSimulation(_spring, 0.72, 1.0, 0));
    HapticFeedback.selectionClick();
  }

  @override
  void didUpdateWidget(covariant ChatComposer old) {
    super.didUpdateWidget(old);
    if (old.inputController != widget.inputController) {
      old.inputController.removeListener(_syncMode);
      widget.inputController.addListener(_syncMode);
    }
    if (old.controller != widget.controller) {
      old.controller?._close = null;
      widget.controller?._close = _closeGif;
      widget.controller?.isPanelOpen.value = _showGifPicker;
    }
    _syncMode(); // editingMessage may have changed
  }

  final ImagePicker _picker = ImagePicker();
  final GlobalKey _camKey = GlobalKey();
  final GlobalKey _plusKey = GlobalKey();
  final GlobalKey _pillKey = GlobalKey();
  final GlobalKey _gifKey = GlobalKey();

  /// Camera "genie" route: grows out of the camera icon, shrinks back into it on close.
  Route<File> _cameraRoute() {
    final size = MediaQuery.sizeOf(context);

    // origin = centre of the camera button (falls back to "+" button, then bottom-right)
    Offset origin = Offset(size.width - 50, size.height - 60);
    final box = (_camKey.currentContext ?? _plusKey.currentContext)
        ?.findRenderObject() as RenderBox?;
    if (box != null && box.attached) {
      origin = box.localToGlobal(box.size.center(Offset.zero));
    }
    final align = Alignment(
      (origin.dx / size.width) * 2 - 1,
      (origin.dy / size.height) * 2 - 1,
    );

    return PageRouteBuilder<File>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, a1, a2) => const AppCameraPage(),
      transitionsBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: const Interval(0, 0.45)),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.04, end: 1.0).animate(curved),
            alignment: align,
            child: AnimatedBuilder(
              animation: curved,
              child: child,
              builder: (_, c) => ClipRRect(
                // very round while small, square when full screen
                borderRadius:
                    BorderRadius.circular(lerpDouble(160, 0, curved.value)!),
                child: c,
              ),
            ),
          ),
        );
      },
    );
  }

  bool _menuOpen = false;

  late final VoiceRecorderController _voice;
  VoiceState _lastVoiceState = VoiceState.idle;

  Timer? _typingDebounce;
  DateTime? _lastTypingEmitted;

  @override
  void initState() {
    super.initState();
    _kbH = AppPreferences.savedKeyboardHeight;
    WidgetsBinding.instance.addObserver(this);
    widget.controller?._close = _closeGif;

    _sendMode = _wantSend;
    _merge.value = _sendMode ? 1 : 0;
    widget.inputController.addListener(_syncMode);

    _voice = VoiceRecorderController(
      onVoiceReady: _sendVoiceFile,
      onToast: AppToast.show,
    )..addListener(_onVoiceChanged);
    _voice.warmUp();

    _gifAnim.addListener(_publishSpace);
    _searchAnim.addListener(_publishSpace);
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishSpace());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final ctl = widget.controller;
    ctl?._close = null;
    if (_showGifPicker && ctl != null) {
      // reset after this frame so listeners are never notified mid-teardown
      WidgetsBinding.instance.addPostFrameCallback((_) => ctl.isPanelOpen.value = false);
    }
    if (ctl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ctl.bottomSpace.value = null);
    }
    _insetTick.dispose();
    _settle?.cancel();
    _kbSave?.cancel();
    _gifAnim.dispose();
    _searchAnim.dispose();
    widget.inputController.removeListener(_syncMode);
    _merge.dispose();
    _pop.dispose();
    _typingDebounce?.cancel();
    _voice
      ..removeListener(_onVoiceChanged)
      ..dispose();
    super.dispose();
  }

  // ───────────────────────── GIF panel logic ─────────────────────────

  double _kbInset() {
    final v = View.of(context);
    return v.viewInsets.bottom / v.devicePixelRatio;
  }

  void _setPanel(bool open) {
    _showGifPicker = open;
    widget.controller?.isPanelOpen.value = open;
  }

  /// Save the real keyboard height only after it has STOPPED moving.
  /// (Saving while it rises makes the panel height change mid-animation.)
  void _rememberKeyboard(double inset) {
    _lastInset = inset;
    _kbSave?.cancel();
    if (inset > 180) {
      _kbSave = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        final now = _kbInset();
        if (now > 180 && (now - inset).abs() < 1) {
          _kbH = now;
          AppPreferences.savedKeyboardHeight = now;
        }
      });
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final inset = _kbInset();
    _rememberKeyboard(inset);
    _insetTick.value = inset; // rebuilds only the layout wrapper, not the pill
    _publishSpace();
  }

  double _targetPanelHeight() {
    if (_kbH >= 180) return _kbH;
    // keyboard never measured yet: sensible guess until the user opens it once
    final h = MediaQuery.sizeOf(context).height;
    return (h * 0.36).clamp(260.0, 360.0).toDouble();
  }

  double _searchPanelHeight() {
    final v = View.of(context);
    final dpr = v.devicePixelRatio;
    final targetH = _targetPanelHeight();
    final h = v.physicalSize.height / dpr - targetH - v.padding.top / dpr - 96;
    return h.clamp(280.0, 480.0).toDouble();
  }

  /// Single source of truth for the bottom layout (used by build AND the list).
  ({double a, double s, double inset, double pad, double boxH, double panelH,
    double safeBottom, double pillBlock}) _layout() {
    final v = View.of(context);
    final dpr = v.devicePixelRatio;
    final inset = v.viewInsets.bottom / dpr;
    final safeBottom = v.padding.bottom / dpr;

    final a = Curves.easeOutCubic.transform(_gifAnim.value.clamp(0.0, 1.0));
    final s = Curves.easeOutCubic.transform(_searchAnim.value.clamp(0.0, 1.0));

    final normalPad = safeBottom > 14 ? safeBottom - 6 : 8.0;
    final pad = inset > 0 ? 8.0 : lerpDouble(normalPad, 8.0, a)!;

    final targetH = _targetPanelHeight();
    // keyboard + panel always add up to targetH, so the composer never jumps
    final base = _showGifPicker ? math.max(0.0, targetH * a - inset) : 0.0;
    final searchH = _searchPanelHeight();
    final boxH = _showGifPicker ? lerpDouble(base, searchH, s)! : 0.0;
    final panelH = lerpDouble(targetH, searchH, s)!;
    final pillBlock = (6 + _pillH + pad) * (1 - s);

    return (
      a: a, s: s, inset: inset, pad: pad, boxH: boxH, panelH: panelH,
      safeBottom: safeBottom, pillBlock: pillBlock,
    );
  }

  void _publishSpace() {
    if (!mounted) return;
    final ctl = widget.controller;
    if (ctl == null) return;
    final box = _pillKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) _pillH = box.size.height;
    final l = _layout();
    ctl.bottomSpace.value = l.pillBlock + l.boxH + l.inset;
  }

  void _openGif() {
    final inset = _kbInset();
    final keyboardUp = inset > 50;
    if (keyboardUp && inset > 180) {
      _kbH = inset;
      AppPreferences.savedKeyboardHeight = inset;
    }
    _settle?.cancel();
    _openedAt = DateTime.now();
    widget.inputFocusNode.unfocus();
    setState(() => _setPanel(true));
    if (keyboardUp) {
      _gifAnim.value = 1; // keyboard is already there: swap in place
    } else {
      _gifAnim.forward(from: 0); // slide up from the bottom
    }
  }

  void _gifToKeyboard() {
    widget.inputFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.show');
    // the panel collapses by itself once the keyboard stops moving (_trackSettle)
  }

  Future<void> _closeGif() async {
    if (!_showGifPicker || _closing) return;
    _closing = true;
    _settle?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    _gifSearching = false;
    await Future.wait([_gifAnim.reverse(), _searchAnim.reverse()]);
    if (mounted) setState(() => _setPanel(false));
    _closing = false;
  }

  void _onSearchFocus(bool focused) {
    if (_gifSearching == focused) return;
    _gifSearching = focused;
    if (focused) {
      _searchAnim.forward();
    } else if (!_closing) {
      _searchAnim.reverse();
    }
  }

  /// panel -> keyboard: once the keyboard stops moving, drop the panel.
  void _trackSettle(double inset, bool inputFocused) {
    if (_showGifPicker && inputFocused && inset > 150) {
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 150), () {
        if (!mounted || !_showGifPicker || !widget.inputFocusNode.hasFocus) return;
        if (DateTime.now().difference(_openedAt) <
            const Duration(milliseconds: 300)) {
          return;
        }
        final i = _kbInset();
        if (i <= 150) return;
        _kbH = i;
        AppPreferences.savedKeyboardHeight = i;
        _gifAnim.value = 0;
        _searchAnim.value = 0;
        _gifSearching = false;
        setState(() => _setPanel(false));
      });
    } else {
      _settle?.cancel();
    }
  }

  // ───────────────────────── voice / text ─────────────────────────

  void _onVoiceChanged() {
    // Recording just started -> hide keyboard + stop "typing..." indicator.
    if (_lastVoiceState == VoiceState.idle && _voice.state != VoiceState.idle) {
      widget.inputFocusNode.unfocus();
      widget.onTypingChanged(false);
      _closeGif();
    }
    _lastVoiceState = _voice.state;
  }

  Future<void> _sendVoiceFile(File file) {
    return widget.onSendAttachment(
      file: file,
      fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      fileType: 'audio/mp4',
    );
  }

  void _handleSendTap() {
    final editing = widget.editingMessage != null;
    // A space-only message is not sendable: just clear it and switch back to mic.
    if (!editing && widget.inputController.text.trim().isEmpty) {
      widget.inputController.clear();
      HapticFeedback.selectionClick();
      return;
    }
    HapticFeedback.lightImpact();
    widget.onSendText(); // not awaited: the page queues the send
  }

  void _onInputChanged(String val) {
    if (_typingDebounce?.isActive ?? false) _typingDebounce!.cancel();
    final text = val.trim();
    if (text.isNotEmpty) {
      final now = DateTime.now();
      if (_lastTypingEmitted == null ||
          now.difference(_lastTypingEmitted!) > const Duration(seconds: 2)) {
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

  Future<void> _pickAndSendMedia(ImageSource source) async {
    AppPreferences.isPickerActive = true;
    try {
      final List<File> pickedFiles = [];
      if (source == ImageSource.camera) {
        final hasPermission = await _checkCameraPermission();
        if (!hasPermission || !mounted) {
          AppPreferences.isPickerActive = false;
          return;
        }

        final File? captured = await Navigator.of(context).push<File>(_cameraRoute());

        if (captured == null) {
          AppPreferences.isPickerActive = false;
          return;
        }
        pickedFiles.add(captured);
      } else {
        final multi = await _picker.pickMultipleMedia();
        if (multi.isEmpty) {
          AppPreferences.isPickerActive = false;
          return;
        }
        pickedFiles.addAll(multi.map((f) => File(f.path)));
      }

      if (pickedFiles.isEmpty || !mounted) {
        AppPreferences.isPickerActive = false;
        return;
      }

      final existingText = widget.inputController.text.trim();

      // Open Image Editor Preview (WhatsApp Style)
      final editorResult = await ImagePreviewEditorPage.open(
        context,
        files: pickedFiles,
        recipientName: widget.chatName,
        initialCaption: existingText,
      );

      // System picker & preview editor closed -> clear picker active flag immediately
      AppPreferences.isPickerActive = false;

      if (editorResult == null || editorResult.images.isEmpty) return;

      if (existingText.isNotEmpty) {
        widget.inputController.clear();
      }

      for (int i = 0; i < editorResult.images.length; i++) {
        final rawFile = editorResult.images[i];
        final fileName = rawFile.path.split(Platform.pathSeparator).last;
        final itemCaption = (i < editorResult.captions.length && editorResult.captions[i].isNotEmpty)
            ? editorResult.captions[i]
            : (i == 0 && editorResult.caption.isNotEmpty
                ? editorResult.caption
                : (i == 0 && existingText.isNotEmpty ? existingText : null));

        await widget.onSendAttachment(
          file: rawFile,
          fileName: fileName,
          fileType: _attachmentType(fileName),
          caption: itemCaption,
          isHd: editorResult.isHd,
        );
      }
    } catch (error) {
      debugPrint('[MEDIA PICK ERROR] $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppToast.userFriendlyMessage('Unable to pick media: $error'),
            ),
          ),
        );
      }
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) => _pickAndSendMedia(source);

  Future<void> _openLocationPicker() async {
    final chatHeadId = int.tryParse(widget.conversation.id);
    if (chatHeadId == null || chatHeadId <= 0) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(chatHeadId: chatHeadId),
      ),
    );

    if (result != null && mounted) {
      unawaited(ServerChatManager.instance.syncChats());
    }
  }

  Future<void> _pickAndSendFile() async {
    AppPreferences.isPickerActive = true;
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      AppPreferences.isPickerActive = false;
      if (files.isEmpty) return;
      final caption = widget.inputController.text.trim();
      if (caption.isNotEmpty) {
        widget.inputController.clear();
      }
      for (final picked in files) {
        var path = picked.path;
        if (path == null || path.isEmpty) {
          final temporaryDirectory = await getTemporaryDirectory();
          final safeName = picked.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          path =
          '${temporaryDirectory.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
          await File(path)
              .writeAsBytes(await picked.readAsBytes(), flush: true);
        }
        final sendFile = File(path);
        await widget.onSendAttachment(
          file: sendFile,
          fileName: picked.name,
          fileType: _attachmentType(picked.name),
          caption: caption.isNotEmpty ? caption : null,
          isHd: false,
        );
      }
    } catch (error) {
      debugPrint('[FILE PICK ERROR] $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppToast.userFriendlyMessage('Unable to attach file: $error'),
            ),
          ),
        );
      }
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  /// Closes keyboard / GIF panel, waits until the layout stops moving,
  /// then opens the attachment menu on a stable layout.
  Future<void> _openAttachmentMenu() async {
    HapticFeedback.selectionClick();
    setState(() => _menuOpen = true); // + rotates right away

    if (_showGifPicker) await _closeGif();

    if (widget.inputFocusNode.hasFocus || _kbInset() > 1) {
      widget.inputFocusNode.unfocus();
      final deadline = DateTime.now().add(const Duration(milliseconds: 700));
      while (mounted && _kbInset() > 1 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      await WidgetsBinding.instance.endOfFrame; // let the final layout settle
    }

    if (!mounted) return;
    _showAttachmentOptions(context);
  }

  // ───────────────────────── Attachment menu ─────────────────────────

  void _showAttachmentOptions(BuildContext context) {
    final pillBox = _pillKey.currentContext?.findRenderObject() as RenderBox?;
    final plusBox = _plusKey.currentContext?.findRenderObject() as RenderBox?;
    if (pillBox == null || plusBox == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.sizeOf(context);
    final pillRect = pillBox.localToGlobal(Offset.zero) & pillBox.size;
    final plusCenter = plusBox.localToGlobal(plusBox.size.center(Offset.zero));

    const menuW = 220.0;
    final menuLeft = pillRect.left + 6;
    final menuBottom = screen.height - pillRect.top + 10; // sits right above the pill
    // scale origin = the + button, relative to the menu box
    final origin = Alignment(
      ((plusCenter.dx - menuLeft) / menuW) * 2 - 1,
      1.15,
    );
    final hole = RRect.fromRectAndRadius(pillRect.inflate(0.5), const Radius.circular(24));

    final items = <(IconData, Color, String, VoidCallback)>[
      (CupertinoIcons.camera_fill, const Color(0xFF007AFF), 'Camera',
          () => _pickAndSendImage(ImageSource.camera)),
      (CupertinoIcons.photo_fill_on_rectangle_fill, const Color(0xFFFF2D55), 'Gallery',
          () => _pickAndSendMedia(ImageSource.gallery)),
      (CupertinoIcons.location_fill, const Color(0xFFFF9500), 'Location', _openLocationPicker),
      (CupertinoIcons.doc_fill, const Color(0xFF5856D6), 'Files', _pickAndSendFile),
      (CupertinoIcons.mic_fill, const Color(0xFFAF52DE), 'Voice', () => _voice.startLocked()),
      if (widget.conversation.disappearType != 0)
        (CupertinoIcons.timer, const Color(0xFF5856D6), 'Disappearing',
            () => widget.onDisappearingTap?.call()),
    ];

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Attachments',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (ctx, a1, a2, child) => child,
      pageBuilder: (dialogContext, anim, _) {
        final fade = anim.drive(CurveTween(curve: const Interval(0, 0.5, curve: Curves.easeOut)));
        final pop = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );

        return AnimatedBuilder(
          animation: anim,
          builder: (ctx, _) {
            final v = Curves.easeOut.transform(anim.value.clamp(0.0, 1.0));

            return Stack(
              children: [
                // ── blur layer with a hole over the composer ──
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(dialogContext),
                    child: ClipPath(
                      clipper: _HoleClipper(hole),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6 * v + 0.001, sigmaY: 6 * v + 0.001),
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: (isDark ? 0.30 : 0.14) * v),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── menu popping out of the + button ──
                Positioned(
                  left: menuLeft,
                  bottom: menuBottom,
                  width: menuW,
                  child: FadeTransition(
                    opacity: fade,
                    child: ScaleTransition(
                      alignment: origin,
                      scale: Tween<double>(begin: 0.15, end: 1.0).animate(pop),
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
                                border: Border.all(color: AppTheme.glassBorder(isDark), width: 0.8),
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
                                  for (int i = 0; i < items.length; i++)
                                    _stagger(
                                      anim, i, items.length,
                                      _buildGlassAttachmentRow(
                                        dialogContext,
                                        icon: items[i].$1,
                                        iconColor: items[i].$2,
                                        label: items[i].$3,
                                        isDark: isDark,
                                        showDivider: i != items.length - 1,
                                        onTap: () {
                                          Navigator.pop(dialogContext);
                                          items[i].$4();
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
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
      },
    ).then((_) {
      if (mounted) setState(() => _menuOpen = false);
    });
  }

  /// Rows ripple in from the bottom (closest to the + button) upward.
  static Widget _stagger(Animation<double> a, int i, int n, Widget child) {
    final start = (0.05 * (n - 1 - i)).clamp(0.0, 0.5);
    final t = a.drive(CurveTween(
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    ));
    return FadeTransition(
      opacity: t,
      child: SlideTransition(
        position: t.drive(Tween(begin: const Offset(0, 0.25), end: Offset.zero)),
        child: child,
      ),
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
                  child: Center(child: Icon(icon, color: iconColor, size: 18)),
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

  // ───────────────────────── Composer bar ─────────────────────────

  /// Content inside the frosted pill. Swaps by voice state.
  Widget _barContent(bool isDark) {
    final v = _voice;
    final Widget child;
    switch (v.state) {
      case VoiceState.holding:
        child = Padding(
          padding: const EdgeInsets.only(right: _ctl + 8),
          child: VoiceHoldBar(
            elapsed: v.elapsed,
            dragDx: v.dragDx,
            cancelProgress: v.cancelProgress,
            isDark: isDark,
          ),
        );
      case VoiceState.locked:
        child = VoiceLockedPanel(
          elapsed: v.elapsed,
          levels: v.levels,
          levelTick: v.levelTick,
          isPaused: v.isPaused,
          isDark: isDark,
          onDelete: v.cancel,
          onPauseResume: v.togglePause,
          onSend: v.send,
        );
      case VoiceState.cancelling:
        child = Padding(
          padding: const EdgeInsets.only(right: _ctl + 8),
          child: VoiceCancelAnim(
              elapsed: v.elapsed, isDark: isDark, onDone: v.finishCancel),
        );
      case VoiceState.idle:
        child = _buildIdleRow(isDark);
    }
    return KeyedSubtree(key: ValueKey(v.state), child: child);
  }

  Widget _buildPlusButton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: (_slot - _ctl) / 2),
      child: GestureDetector(
        key: _plusKey,
        behavior: HitTestBehavior.opaque,
        onTap: _openAttachmentMenu,
        child: Container(
          width: _ctl,
          height: _ctl,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.20),
                      Colors.white.withValues(alpha: 0.08),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.95),
                      Colors.white.withValues(alpha: 0.55),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.black.withValues(alpha: 0.06),
              width: 0.6,
            ),
          ),
          child: AnimatedRotation(
            turns: _menuOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: Icon(Icons.add_rounded,
                size: 20, color: isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }

  /// GIF badge; turns into a keyboard icon while the panel is open.
  Widget _buildGifButton(bool isDark) {
    final c = isDark ? Colors.white70 : Colors.black54;
    final badge = Container(
      key: const ValueKey('gif'),
      width: 26,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: c, width: 1.5),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'GIF',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: c,
          height: 1,
        ),
      ),
    );

    return GestureDetector(
      key: _gifKey,
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        _showGifPicker ? _gifToKeyboard() : _openGif();
      },
      child: SizedBox(
        width: _ctl,
        height: _ctl,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: a, child: child),
            ),
            child: _showGifPicker
                ? Icon(CupertinoIcons.keyboard,
                    key: const ValueKey('kb'), size: 24, color: c)
                : badge,
          ),
        ),
      ),
    );
  }

  /// slot 1 = camera, slot 2 = GIF. Both slide onto the send/mic button,
  /// shrink and fade, with the same spring (_merge) as before.
  Widget _mergingButton({required int slot, required Widget child}) {
    return Positioned(
      right: _pad + 4 + (_ctl + 2) * slot,
      bottom: _pad + (_slot - _ctl) / 2,
      child: AnimatedOpacity(
        opacity: _voice.state == VoiceState.idle ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: AnimatedBuilder(
          animation: _merge,
          builder: (_, c) {
            final t = (_merge.value - (slot == 2 ? 0.04 : 0)).clamp(-0.2, 1.3);
            return IgnorePointer(
              ignoring: _voice.state != VoiceState.idle || t > 0.3,
              child: Transform.translate(
                offset: Offset((_ctl + 2) * slot * t, 0),
                child: Transform.scale(
                  scale: (1 - 0.6 * t).clamp(0.3, 1.2),
                  child: Opacity(
                    opacity: (1 - t * 1.8).clamp(0.0, 1.0),
                    child: c,
                  ),
                ),
              ),
            );
          },
          child: child,
        ),
      ),
    );
  }

  Widget _buildCameraButton(bool isDark) {
    return GestureDetector(
      key: _camKey,
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        widget.inputFocusNode.unfocus();
        _closeGif();
        _pickAndSendImage(ImageSource.camera);
      },
      child: SizedBox(
        width: _ctl,
        height: _ctl,
        child: Center(
          child: Icon(
            CupertinoIcons.camera_fill,
            size: 20,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _buildIdleRow(bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildPlusButton(isDark),
        const SizedBox(width: 6),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _slot, maxHeight: 145),
            child: TextField(
              controller: widget.inputController,
              focusNode: widget.inputFocusNode,
              onChanged: _onInputChanged,
              // no onTap here: tapping just opens the keyboard,
              // the GIF panel collapses itself (see _trackSettle)
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              inputFormatters: [NoDoubleSpacePeriod()],
              cursorColor: const Color(0xFF007AFF),
              style: TextStyle(
                fontSize: 16,
                height: 1.25,
                color: AppTheme.primaryText(isDark),
                letterSpacing: -0.2,
              ),
              decoration: InputDecoration(
                hintText:
                    widget.editingMessage == null ? 'Message' : 'Edit message',
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintStyle: TextStyle(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.38)
                      : Colors.black.withValues(alpha: 0.32),
                  fontSize: 16,
                  height: 1.25,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _merge,
          builder: (ctx, _) {
            final t = _merge.value.clamp(0.0, 1.0);
            // mic/send + camera + gif -> collapses to just send
            return SizedBox(width: _ctl + 8 + 2 * (_ctl + 2) * (1 - t));
          },
        ),
      ],
    );
  }

  Widget _buildTrailingAction(bool isDark) {
    final v = _voice;
    final holding = v.state == VoiceState.holding;
    final hidden =
        v.state == VoiceState.locked || v.state == VoiceState.cancelling;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.inputController, // rebuilds on EVERY keystroke
      builder: (context, value, _) {
        final editing = widget.editingMessage != null;
        final hasText = editing || value.text.isNotEmpty; // space/emoji count
        final sendMode = hasText && !holding;

        final Color? bg = sendMode
            ? null
            : (holding
                ? (isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA))
                : Colors.transparent);

        final Widget icon = sendMode
            ? Icon(
                editing ? CupertinoIcons.checkmark : CupertinoIcons.arrow_up,
                key: ValueKey(editing ? 'check' : 'send'),
                size: 18,
                color: Colors.white,
              )
            : Icon(
                CupertinoIcons.mic_fill,
                key: const ValueKey('mic'),
                size: 20,
                color: holding
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.white70 : Colors.black54),
              );

        final button = AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: _ctl,
          height: _ctl,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            gradient: sendMode
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF4AA3FF), Color(0xFF007AFF)],
                  )
                : null,
            border: sendMode
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.35), width: 0.6)
                : null,
            boxShadow: sendMode
                ? [
                    BoxShadow(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : (holding
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : const []),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(
                  scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                  child: c,
                ),
              ),
              child: icon, // no spinner, ever
            ),
          ),
        );

        return IgnorePointer(
          ignoring: hidden,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (!hasText) v.pointerDown(e.position);
            },
            onPointerMove: (e) {
              if (!hasText) v.pointerMove(e.position);
            },
            onPointerUp: (_) {
              if (!hasText) v.pointerUp();
            },
            onPointerCancel: (_) {
              if (!hasText) v.pointerCancel();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hasText ? _handleSendTap : null,
              child: AnimatedOpacity(
                opacity: hidden ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: Transform.translate(
                  offset: Offset(0, holding ? v.dragDy * 0.9 : 0),
                  child: AnimatedScale(
                    scale: holding ? 1.25 : 1.0,
                    duration: const Duration(milliseconds: 120),
                    child: AnimatedBuilder(
                      animation: _pop,
                      child: button,
                      builder: (_, c) =>
                          Transform.scale(scale: _pop.value.clamp(0.5, 1.35), child: c),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _replyTitle() {
    final m = widget.replyingMessage!;
    if (m.senderId == 'user') return 'Replying to You';
    final name = widget.conversation.isGroup
        ? widget.groupMemberNames[int.tryParse(m.senderId)]
        : null;
    return 'Replying to ${name ?? widget.chatName}';
  }

  String _replySubtitle() {
    final m = widget.replyingMessage!;
    if (m.isDeleted) return 'This message was deleted';
    final preview = m.previewText;
    return preview.isNotEmpty ? preview : m.content;
  }

  Widget? _replyThumbnail() {
    final m = widget.replyingMessage;
    if (m == null || !m.hasMedia) return null;
    final preview = m.previewText;
    final isImage = preview.contains('📷');
    final isVideo = preview.contains('🎥');

    if (isImage) {
      final p = AttachmentCacheService.instance.resolveLocalPathSync(m.mediaUrl);
      if (p != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(File(p),
              width: 40, height: 40, cacheWidth: 120, fit: BoxFit.cover),
        );
      }
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        isVideo
            ? Icons.play_circle_fill_rounded
            : (isImage ? Icons.photo_rounded : Icons.insert_drive_file_rounded),
        size: 20,
        color: AppTheme.primaryColor,
      ),
    );
  }

  Widget _buildComposerBar(bool isDark) {
    final v = _voice;
    final holding = v.state == VoiceState.holding;
    final locked = v.state == VoiceState.locked;

    final pill = DecoratedBox(
      key: _pillKey,
      // shadow lives OUTSIDE the clip, otherwise it gets cut off
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: _GlassRimPainter(radius: 24, isDark: isDark),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: const EdgeInsets.all(_pad),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? const [Color(0xB32C2C2E), Color(0x991C1C1E)]
                      : [
                          Colors.white.withValues(alpha: 0.74),
                          Colors.white.withValues(alpha: 0.50),
                        ],
                ),
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.editingMessage != null)
                      ChatReplyPreview(
                        isDark: isDark,
                        icon: CupertinoIcons.pencil,
                        title: 'Editing message',
                        subtitle: widget.editingMessage!.content,
                        onCancel: widget.onCancelEditing,
                      )
                    else if (widget.replyingMessage != null)
                      ChatReplyPreview(
                        isDark: isDark,
                        title: _replyTitle(),
                        subtitle: _replySubtitle(),
                        thumbnail: _replyThumbnail(),
                        onCancel: widget.onCancelReply,
                      ),
                    _barContent(isDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(width: double.infinity, child: pill),
        if (!locked)
          Positioned(
            right: 5,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: holding ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: VoiceLockPill(progress: v.lockProgress, isDark: isDark),
              ),
            ),
          ),
        _mergingButton(slot: 1, child: _buildCameraButton(isDark)),
        _mergingButton(slot: 2, child: _buildGifButton(isDark)),
        Positioned(
          right: _pad + 4,
          bottom: _pad + (_slot - _ctl) / 2,   // = 8, same gap as the + button
          child: _buildTrailingAction(isDark),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bar = ListenableBuilder(
      listenable: _voice,
      builder: (context, _) => _buildComposerBar(isDark),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_gifAnim, _searchAnim, _insetTick]),
      child: bar,
      builder: (context, bar) {
        final l = _layout();
        _rememberKeyboard(l.inset);
        _trackSettle(l.inset, widget.inputFocusNode.hasFocus);
        // catches pill height changes (multi-line text, reply bar...)
        WidgetsBinding.instance.addPostFrameCallback((_) => _publishSpace());

        final panelBottomPad =
            l.safeBottom * (1 - (l.inset / _targetPanelHeight()).clamp(0.0, 1.0));

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // pill collapses while the user searches GIFs (same widget, never rebuilt)
            ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: (1 - l.s).clamp(0.0, 1.0),
                child: IgnorePointer(
                  ignoring: l.s > 0.5,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(10, 6, 10, l.pad),
                    child: bar,
                  ),
                ),
              ),
            ),
            if (_showGifPicker)
              SizedBox(
                height: l.boxH,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: l.panelH,
                    maxHeight: l.panelH,
                    child: GifPickerPanel(
                      height: l.panelH,
                      bottomPadding: panelBottomPad,
                      onSearchFocusChanged: _onSearchFocus,
                      // panel stays open after sending: send as many as you like
                      onGifSelected: (gif) {
                        HapticFeedback.selectionClick();
                        widget.onSendGif?.call(gif);
                      },
                      onClose: _closeGif,
                    ),
                  ),
                ),
              ),
            // the keyboard space is now reserved by the composer itself
            SizedBox(height: l.inset),
          ],
        );
      },
    );
  }
}

/// Kept in case other files still reference it.
class VoiceBars extends StatelessWidget {
  const VoiceBars({super.key});

  @override
  Widget build(BuildContext context) {
    const heights = [8.0, 14.0, 22.0, 13.0, 18.0, 8.0];

    return SizedBox(
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: heights
            .map(
              (height) => Container(
            width: 2,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFAEB3BB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        )
            .toList(),
      ),
    );
  }
}

class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({required this.radius, required this.isDark});
  final double radius;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.4),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                Colors.white.withValues(alpha: 0.38),
                Colors.white.withValues(alpha: 0.04),
                Colors.white.withValues(alpha: 0.14),
              ]
            : [
                Colors.white.withValues(alpha: 0.95),
                Colors.black.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.70),
              ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_GlassRimPainter o) =>
      o.radius != radius || o.isDark != isDark;
}

/// Full-screen rect minus the composer pill, so the blur skips the composer.
class _HoleClipper extends CustomClipper<Path> {
  final RRect hole;
  const _HoleClipper(this.hole);

  @override
  Path getClip(Size size) => Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(hole),
      );

  @override
  bool shouldReclip(_HoleClipper old) => old.hole != hole;
}
