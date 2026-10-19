import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/config/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/vault_page_route.dart';
import '../../../../core/utils/app_toast.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import '../widgets/chat_wallpaper_widget.dart';

class ChatWallpaperPage extends StatefulWidget {
  final ChatConversation conversation;

  const ChatWallpaperPage({
    super.key,
    required this.conversation,
  });

  static Future<void> open(
    BuildContext context, {
    required ChatConversation conversation,
  }) {
    return Navigator.of(context).push(
      VaultPageRoute<void>(
        builder: (context) => ChatWallpaperPage(conversation: conversation),
      ),
    );
  }

  @override
  State<ChatWallpaperPage> createState() => _ChatWallpaperPageState();
}

class _ChatWallpaperPageState extends State<ChatWallpaperPage> {
  final TransformationController _transformationController =
      TransformationController();

  late String _chatId;
  late String _selectedType;
  String? _customPath;
  String? _currentServerBg;
  late double _dimValue;

  File? _newUploadFile;
  bool _isUploading = false;
  bool _showChatOverlay = true;
  bool _isPanelCollapsed = false;

  final List<Map<String, String>> _presets = const [
    {'type': 'default', 'title': 'Default Canvas'},
    {'type': 'preset_1', 'title': 'Midnight Mesh'},
    {'type': 'preset_2', 'title': 'Sunset Glow'},
    {'type': 'preset_3', 'title': 'Emerald Forest'},
    {'type': 'preset_4', 'title': 'Cyber Neon'},
    {'type': 'preset_5', 'title': 'Royal Velvet'},
  ];

  @override
  void initState() {
    super.initState();
    _chatId = widget.conversation.id;
    _currentServerBg = widget.conversation.backgroundUrl;

    _selectedType = AppPreferences.getWallpaperType(chatId: _chatId);
    if (_currentServerBg != null && _currentServerBg!.isNotEmpty) {
      _selectedType = 'custom';
    }
    _customPath = AppPreferences.getWallpaperPath(chatId: _chatId);
    _dimValue = AppPreferences.getWallpaperDim(chatId: _chatId);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    AppPreferences.isPickerActive = true;
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isNotEmpty && files.first.path != null) {
        final path = files.first.path!;
        setState(() {
          _newUploadFile = File(path);
          _selectedType = 'custom';
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      debugPrint('[WALLPAPER PICK ERROR] $e');
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _saveWallpaper() async {
    setState(() => _isUploading = true);
    HapticFeedback.mediumImpact();

    try {
      final cid = int.tryParse(_chatId);
      if (cid != null) {
        if (_selectedType == 'custom' && _newUploadFile != null) {
          await ServerApiService.instance.uploadChatBackground(
            cid,
            _newUploadFile!,
          );
        } else if (_selectedType != 'custom' &&
            _currentServerBg != null &&
            _currentServerBg!.isNotEmpty) {
          await ServerApiService.instance.removeChatBackground(cid);
        } else if (_selectedType == 'default' &&
            _customPath == null &&
            _currentServerBg != null) {
          await ServerApiService.instance.removeChatBackground(cid);
        }
      }

      await AppPreferences.setChatWallpaper(
        type: _selectedType,
        customPath: _newUploadFile?.path ?? _customPath,
        dim: _dimValue,
        chatId: _chatId,
      );

      if (cid != null) {
        await ServerChatManager.instance.syncChats();
      }

      if (mounted) {
        AppToast.show('Wallpaper updated!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Wallpaper apply error: $e');
      if (mounted) {
        AppToast.show('Failed to update wallpaper');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Widget _buildWallpaperBackground(bool isDark) {
    Widget backgroundContent;

    if (_selectedType == 'custom') {
      if (_newUploadFile != null) {
        backgroundContent = Image.file(
          _newUploadFile!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      } else if (_customPath != null && File(_customPath!).existsSync()) {
        backgroundContent = Image.file(
          File(_customPath!),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      } else if (_currentServerBg != null && _currentServerBg!.isNotEmpty) {
        backgroundContent = ChatWallpaperWidget(
          chatId: _chatId,
          isDark: isDark,
          backgroundUrl: _currentServerBg,
        );
      } else {
        backgroundContent = ChatWallpaperWidget.buildPresetWallpaper(
          'default',
          isDark,
        );
      }
    } else {
      backgroundContent = ChatWallpaperWidget.buildPresetWallpaper(
        _selectedType,
        isDark,
      );
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _isPanelCollapsed = !_isPanelCollapsed);
      },
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 1.0,
        maxScale: 4.0,
        clipBehavior: Clip.none,
        child: Stack(
          fit: StackFit.expand,
          children: [
            backgroundContent,
            // Darkening / Dimming Overlay Layer
            Container(
              color: Colors.black.withValues(alpha: _dimValue),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : Colors.black,
      body: Stack(
        children: [
          // 1. Zoomable & Pannable Wallpaper Background
          Positioned.fill(
            child: _buildWallpaperBackground(isDark),
          ),

          // 2. Realistic Dummy Chat Overlay (Toggleable)
          if (_showChatOverlay)
            Positioned.fill(
              child: IgnorePointer(
                child: SafeArea(
                  child: Column(
                    children: [
                      // Dummy Chat Header
                      _buildDummyHeader(isDark),

                      const Spacer(),

                      // Dummy Date Chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.black87
                              : Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          'Today',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Incoming Dummy Bubble
                      _buildDummyBubble(
                        text: 'Hey! Check out this new wallpaper preview 🔥',
                        time: '10:42 AM',
                        isMe: false,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 8),

                      // Outgoing Dummy Bubble
                      _buildDummyBubble(
                        text: 'Looks amazing! End-to-end encrypted chat 🔐',
                        time: '10:43 AM',
                        isMe: true,
                        isDark: isDark,
                      ),

                      const SizedBox(height: 16),

                      // Dummy Input Composer Bar
                      _buildDummyInputComposer(isDark),

                      SizedBox(height: _isPanelCollapsed ? 20 : 180),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Top Navigation Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back Button
                    Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(10.0),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),

                    // Title
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          color: Colors.black.withValues(alpha: 0.35),
                          child: const Text(
                            'Chat Wallpaper',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Toggle Preview Overlay Button
                    Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          setState(() => _showChatOverlay = !_showChatOverlay);
                          HapticFeedback.lightImpact();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Icon(
                            _showChatOverlay
                                ? CupertinoIcons.eye_fill
                                : CupertinoIcons.eye_slash_fill,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Animated Bottom Control Panel (Presets + Dimming + Save)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            left: 0,
            right: 0,
            bottom: _isPanelCollapsed ? -420 : 0,
            child: _buildBottomPanel(isDark),
          ),

          // 5. Floating Expand Button (Shown when panel is collapsed)
          if (_isPanelCollapsed)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              left: 0,
              right: 0,
              child: Center(
                child: _buildExpandPanelButton(isDark),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDummyHeader(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.45)
            : Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          IosAvatar(
            name: widget.conversation.name,
            imagePath: widget.conversation.avatarUrl,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.conversation.name,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  'Online',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.greenAccent : Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDummyBubble({
    required String text,
    required String time,
    required bool isMe,
    required bool isDark,
  }) {
    final userBubbleColor = isDark
        ? const Color(0xFF1E3A2B)
        : const Color(0xFFDCF8C6);
    final peerBubbleColor = isDark
        ? const Color(0xFF2C2C2E)
        : Colors.white;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isMe ? userBubbleColor : peerBubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Spacer(),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.done_all_rounded,
                    size: 14,
                    color: Color(0xFF53BDEB),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDummyInputComposer(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.add,
            size: 20,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Type a message...',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ),
          Icon(
            CupertinoIcons.mic_fill,
            size: 18,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandPanelButton(bool isDark) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _isPanelCollapsed = false);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.70)
                  : Colors.black.withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.slider_horizontal_3,
                  size: 16,
                  color: Colors.white,
                ),
                SizedBox(width: 8),
                Text(
                  'Customize Wallpaper',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  CupertinoIcons.chevron_up,
                  size: 14,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel(bool isDark) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.of(context).padding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xEE1C1C1E)
                : const Color(0xF5FFFFFF),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Header Row with Hide Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Wallpaper Controls',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _isPanelCollapsed = true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : Colors.black12,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Hide',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            CupertinoIcons.chevron_down,
                            size: 14,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Presets Carousel + Add Custom Photo
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _presets.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, idx) {
                    if (idx == _presets.length) {
                      // Custom Photo Button
                      final isSelected = _selectedType == 'custom';
                      return GestureDetector(
                        onTap: _pickImageFromGallery,
                        child: Container(
                          width: 68,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFE5E5EA),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_rounded,
                                size: 24,
                                color: isSelected
                                    ? AppTheme.primaryColor
                                    : AppTheme.subtitleGrey,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Gallery',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? AppTheme.primaryColor
                                      : AppTheme.subtitleGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final preset = _presets[idx];
                    final type = preset['type']!;
                    final title = preset['title']!;
                    final isSelected = _selectedType == type;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedType = type;
                          _newUploadFile = null;
                        });
                        HapticFeedback.lightImpact();
                      },
                      child: Container(
                        width: 68,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ChatWallpaperWidget.buildPresetWallpaper(
                              type,
                              isDark,
                            ),
                            Container(
                              color: Colors.black.withValues(alpha: 0.25),
                            ),
                            Center(
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Positioned(
                                top: 4,
                                right: 4,
                                child: CircleAvatar(
                                  radius: 8,
                                  backgroundColor: AppTheme.primaryColor,
                                  child: Icon(
                                    Icons.check_rounded,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 14),

              // Dimming Slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.moon_fill,
                        size: 14,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Wallpaper Darkening',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${(_dimValue * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  activeTrackColor: AppTheme.primaryColor,
                  inactiveTrackColor: isDark
                      ? Colors.white24
                      : Colors.black12,
                ),
                child: Slider(
                  value: _dimValue,
                  min: 0.0,
                  max: 0.6,
                  divisions: 12,
                  onChanged: (val) => setState(() => _dimValue = val),
                ),
              ),

              const SizedBox(height: 8),

              // Action Buttons Row (Reset & Save)
              Row(
                children: [
                  // Reset Default Button
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedType = 'default';
                          _newUploadFile = null;
                          _customPath = null;
                          _dimValue = 0.15;
                        });
                        HapticFeedback.lightImpact();
                      },
                      child: Text(
                        'Reset',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Save & Apply Button
                  Expanded(
                    flex: 3,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isUploading ? null : _saveWallpaper,
                      child: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Save Wallpaper',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
