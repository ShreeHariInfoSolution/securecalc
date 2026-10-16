import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';

import '../widgets/chat_wallpaper_widget.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/models/server_models.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import '../widgets/photo_gallery_viewer.dart';
import 'share/share_qr_page.dart';
import 'starred_messages_page.dart';

class ChatMediaItem {
  final String id;
  final String fileName;
  final String rawUrl;
  final String fileType;
  final int fileSize;
  final DateTime createdAt;
  final bool isMe; // true = Sent by me, false = Received
  final String senderName;
  final String folder; // 'image', 'video', 'audio', 'doc'

  ChatMediaItem({
    required this.id,
    required this.fileName,
    required this.rawUrl,
    required this.fileType,
    required this.fileSize,
    required this.createdAt,
    required this.isMe,
    required this.senderName,
    required this.folder,
  });

  String get fullUrl {
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://'))
      return rawUrl;
    if (File(rawUrl).existsSync()) return rawUrl;
    return resolveAvatarUrl(rawUrl) ?? rawUrl;
  }
}

class ChatInfoPage extends StatefulWidget {
  final ChatConversation conversation;

  const ChatInfoPage({super.key, required this.conversation});

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  ServerChatModel? _details;
  bool _loading = true;
  bool _clearingChat = false;
  bool _updatingMembers = false;
  String? _error;

  // Media state
  List<ChatMediaItem> _mediaItems = [];
  bool _loadingMedia = true;
  String _selectedFolder = 'image'; // 'image', 'video', 'audio', 'doc'
  String _directionFilter = 'all'; // 'all', 'sent', 'received'
  String _searchQuery = '';
  bool _isMediaExpanded = false;

  // Audio player state
  AudioPlayer? _audioPlayer;
  String? _currentlyPlayingAudioUrl;
  bool _isPlayingAudio = false;

  late int _disappearType;

  @override
  void initState() {
    super.initState();
    _disappearType = widget.conversation.disappearType;
    Future.microtask(() async {
      await _loadDetails();
      await _loadMedia();
    });
  }

  @override
  void dispose() {
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    super.dispose();
  }

  static const Map<int, String> _disappearingLabels = {
    0: 'off',
    1: '24 hours',
    2: '1 week',
    3: 'after read',
  };

  void _showDisappearingPicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  'Disappearing Messages',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'When enabled, new messages sent in this chat will disappear after the selected duration.',
                  style: TextStyle(fontSize: 13, color: AppTheme.subtitleGrey),
                ),
              ),
              const SizedBox(height: 12),
              ..._disappearingLabels.entries.map((entry) {
                final typeKey = entry.key;
                final labelText = entry.value;
                final isSelected = _disappearType == typeKey;

                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(
                    typeKey == 0
                        ? Icons.timer_off_outlined
                        : Icons.timer_outlined,
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.subtitleGrey,
                  ),
                  title: Text(
                    labelText,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected ? AppTheme.primaryColor : null,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: AppTheme.primaryColor,
                        )
                      : null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final chatId = int.tryParse(widget.conversation.id);
                    if (chatId == null) return;
                    final res = await ServerApiService.instance
                        .setDisappearingMessagesREST(
                          chatId: chatId,
                          disappearType: typeKey,
                        );
                    if (res != null && mounted) {
                      setState(() {
                        _disappearType = typeKey;
                      });
                      await LocalChatStorage.instance.updateConversation(
                        widget.conversation.id,
                        (current) => current.copyWith(disappearType: typeKey),
                      );
                      AppToast.show(
                        'Disappearing messages set to ${_disappearingLabels[typeKey]}',
                      );
                    }
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _getBubbleColorName(Color color) {
    final val = color.toARGB32();
    switch (val) {
      case 0xFF007AFF:
        return 'iOS Blue (Default)';
      case 0xFF34C759:
        return 'Emerald Green';
      case 0xFFAF52DE:
        return 'Vibrant Purple';
      case 0xFFFF9500:
        return 'Sunset Orange';
      case 0xFF30B0C7:
        return 'Ocean Teal';
      case 0xFFFF2D55:
        return 'Neon Pink';
      case 0xFFFF3B30:
        return 'Crimson Red';
      case 0xFF3A3A3C:
        return 'Dark Charcoal';
      case 0xFF5856D6:
        return 'Royal Indigo';
      case 0xFFFFCC00:
        return 'Electric Gold';
      default:
        return 'Custom Color';
    }
  }

  String _getWallpaperTypeName(String type) {
    if (type == 'custom') return 'Custom Gallery Photo';
    switch (type) {
      case 'preset_1':
        return 'Midnight Mesh';
      case 'preset_2':
        return 'Sunset Glow';
      case 'preset_3':
        return 'Emerald Forest';
      case 'preset_4':
        return 'Cyberpunk Neon';
      case 'preset_5':
        return 'Royal Velvet';
      default:
        return 'Default Canvas';
    }
  }

  void _showBubbleColorPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatId = widget.conversation.id;
    final currentColor = AppPreferences.getChatBubbleColor(chatId: chatId);

    final colors = <Map<String, dynamic>>[
      {'name': 'iOS Blue', 'color': const Color(0xFF007AFF)},
      {'name': 'Emerald Green', 'color': const Color(0xFF34C759)},
      {'name': 'Vibrant Purple', 'color': const Color(0xFFAF52DE)},
      {'name': 'Sunset Orange', 'color': const Color(0xFFFF9500)},
      {'name': 'Ocean Teal', 'color': const Color(0xFF30B0C7)},
      {'name': 'Neon Pink', 'color': const Color(0xFFFF2D55)},
      {'name': 'Crimson Red', 'color': const Color(0xFFFF3B30)},
      {'name': 'Dark Charcoal', 'color': const Color(0xFF3A3A3C)},
      {'name': 'Royal Indigo', 'color': const Color(0xFF5856D6)},
      {'name': 'Electric Gold', 'color': const Color(0xFFFFCC00)},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        Color selectedColor = currentColor;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.subtitleGrey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Choose Bubble Color',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Select color for sent chat messages',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.subtitleGrey,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Live Bubble Preview Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.chatCanvas(isDark),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                        ),
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.receivedBubble(isDark),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                    bottomRight: Radius.circular(16),
                                    bottomLeft: Radius.circular(4),
                                  ),
                                ),
                                child: Text(
                                  'Hey! How does this look?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selectedColor,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                    bottomLeft: Radius.circular(16),
                                    bottomRight: Radius.circular(4),
                                  ),
                                ),
                                child: const Text(
                                  'Looks awesome!',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Color Palette Swatches
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: colors.map((c) {
                          final Color col = c['color'] as Color;
                          final bool isSelected =
                              (selectedColor.toARGB32() & 0x00FFFFFF) ==
                              (col.toARGB32() & 0x00FFFFFF);
                          return GestureDetector(
                            onTap: () {
                              setSheetState(() => selectedColor = col);
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: col,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: col.withValues(alpha: 0.4),
                                    blurRadius: isSelected ? 8 : 2,
                                    spreadRadius: isSelected ? 2 : 0,
                                  ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 18),

                      // Color Shade / Brightness Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Color Shade / Brightness',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${(HSLColor.fromColor(selectedColor).lightness * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.subtitleGrey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: HSLColor.fromColor(selectedColor).lightness
                            .clamp(0.25, 0.75),
                        min: 0.25,
                        max: 0.75,
                        divisions: 20,
                        activeColor: selectedColor,
                        onChanged: (val) {
                          setSheetState(() {
                            selectedColor = HSLColor.fromColor(selectedColor)
                                .withLightness(val)
                                .toColor();
                          });
                        },
                      ),

                      const SizedBox(height: 24),

                      // Apply Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: selectedColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () async {
                            await AppPreferences.setChatBubbleColor(
                              selectedColor,
                              chatId: chatId,
                            );
                            if (mounted) {
                              setState(() {});
                              Navigator.of(context).pop();
                              AppToast.show('Bubble color updated!');
                            }
                          },
                          child: const Text(
                            'Apply Bubble Color',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showWallpaperPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatId = widget.conversation.id;
    final currentServerBg =
        widget.conversation.backgroundUrl ?? _details?.backgroundUrl;

    String initialType = AppPreferences.getWallpaperType(chatId: chatId);
    if (currentServerBg != null && currentServerBg.isNotEmpty) {
      initialType = 'custom';
    }

    final currentDim = AppPreferences.getWallpaperDim(chatId: chatId);

    final presets = <Map<String, String>>[
      {'type': 'default', 'title': 'Default Canvas'},
      {'type': 'preset_1', 'title': 'Midnight Mesh'},
      {'type': 'preset_2', 'title': 'Sunset Glow'},
      {'type': 'preset_3', 'title': 'Emerald Forest'},
      {'type': 'preset_4', 'title': 'Cyber Neon'},
      {'type': 'preset_5', 'title': 'Royal Velvet'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        String selectedType = initialType;
        String? customPath = AppPreferences.getWallpaperPath(chatId: chatId);
        double dimValue = currentDim;
        File? newUploadFile;
        bool isUploading = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.subtitleGrey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Chat Wallpaper',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Customize background image for this chat screen',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.subtitleGrey,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Live preview of custom photo
                      if (selectedType == 'custom' &&
                          (newUploadFile != null ||
                              (customPath != null &&
                                  File(customPath!).existsSync()) ||
                              (currentServerBg != null &&
                                  currentServerBg.isNotEmpty)))
                        Container(
                          width: double.infinity,
                          height: 140,
                          margin: const EdgeInsets.only(bottom: 16),
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.subtitleGrey.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (newUploadFile != null)
                                Image.file(newUploadFile!, fit: BoxFit.cover)
                              else if (customPath != null &&
                                  File(customPath!).existsSync())
                                Image.file(File(customPath!), fit: BoxFit.cover)
                              else if (currentServerBg != null)
                                ChatWallpaperWidget(
                                  isDark: isDark,
                                  backgroundUrl: currentServerBg,
                                ),
                              Container(
                                color: Colors.black.withValues(alpha: dimValue),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  onPressed: () {
                                    setSheetState(() {
                                      newUploadFile = null;
                                      customPath = null;
                                      selectedType = 'default';
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Presets Horizontal Carousel
                      SizedBox(
                        height: 110,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: presets.length + 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, idx) {
                            if (idx == presets.length) {
                              // Custom Photo Option
                              final isSelected = selectedType == 'custom';
                              return GestureDetector(
                                onTap: () async {
                                  AppPreferences.isPickerActive = true;
                                  try {
                                    final files = await FilePicker.pickFiles(
                                      type: FileType.image,
                                    );
                                    if (files.isNotEmpty &&
                                        files.first.path != null) {
                                      final picked = files.first.path!;
                                      setSheetState(() {
                                        newUploadFile = File(picked);
                                        selectedType = 'custom';
                                      });
                                    }
                                  } catch (e) {
                                    debugPrint('[WALLPAPER PICK ERROR] $e');
                                  } finally {
                                    AppPreferences.isPickerActive = false;
                                  }
                                },
                                child: Container(
                                  width: 80,
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
                                        size: 28,
                                        color: isSelected
                                            ? AppTheme.primaryColor
                                            : AppTheme.subtitleGrey,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'From Gallery',
                                        textAlign: TextAlign.center,
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

                            final preset = presets[idx];
                            final type = preset['type']!;
                            final title = preset['title']!;
                            final isSelected = selectedType == type;

                            return GestureDetector(
                              onTap: () =>
                                  setSheetState(() => selectedType = type),
                              child: Container(
                                width: 80,
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
                                  children: [
                                    Positioned.fill(
                                      child:
                                          ChatWallpaperWidget.buildPresetWallpaper(
                                            type,
                                            isDark,
                                          ),
                                    ),
                                    Container(
                                      color: Colors.black.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                    Center(
                                      child: Text(
                                        title,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      const Positioned(
                                        top: 6,
                                        right: 6,
                                        child: CircleAvatar(
                                          radius: 10,
                                          backgroundColor:
                                              AppTheme.primaryColor,
                                          child: Icon(
                                            Icons.check_rounded,
                                            size: 12,
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

                      const SizedBox(height: 20),

                      // Dimming Slider
                      if (selectedType != 'default') ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Background Darkening',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${(dimValue * 100).round()}%',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: dimValue,
                          min: 0.0,
                          max: 0.6,
                          divisions: 12,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (val) =>
                              setSheetState(() => dimValue = val),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Apply Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: isUploading
                              ? null
                              : () async {
                                  setSheetState(() => isUploading = true);
                                  try {
                                    final cid = int.tryParse(chatId);
                                    if (cid != null) {
                                      if (selectedType == 'custom' &&
                                          newUploadFile != null) {
                                        // Upload new background to server
                                        await ServerApiService.instance
                                            .uploadChatBackground(
                                              cid,
                                              newUploadFile!,
                                            );
                                      } else if (selectedType != 'custom' &&
                                          currentServerBg != null &&
                                          currentServerBg.isNotEmpty) {
                                        // Remove server background if a preset or default is selected instead
                                        await ServerApiService.instance
                                            .removeChatBackground(cid);
                                      } else if (selectedType == 'default' &&
                                          customPath == null &&
                                          currentServerBg != null) {
                                        await ServerApiService.instance
                                            .removeChatBackground(cid);
                                      }
                                    }

                                    await AppPreferences.setChatWallpaper(
                                      type: selectedType,
                                      customPath:
                                          newUploadFile?.path ?? customPath,
                                      dim: dimValue,
                                      chatId: chatId,
                                    );

                                    if (mounted) {
                                      setState(() {});
                                      if (cid != null &&
                                          (newUploadFile != null ||
                                              selectedType != 'custom')) {
                                        await _loadDetails();
                                        await ServerChatManager.instance
                                            .syncChats();
                                      }
                                      if (context.mounted) {
                                        Navigator.of(context).pop();
                                        AppToast.show('Wallpaper updated!');
                                      }
                                    }
                                  } catch (e) {
                                    debugPrint('Wallpaper apply error: $e');
                                    AppToast.show('Failed to update wallpaper');
                                  } finally {
                                    setSheetState(() => isUploading = false);
                                  }
                                },
                          child: isUploading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Save Wallpaper',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final chatId = int.tryParse(widget.conversation.id);
    final details = chatId == null
        ? null
        : await ServerApiService.instance.getChatDetails(chatId);
    if (!mounted) return;
    setState(() {
      _details = details;
      if (details != null) {
        _disappearType = details.disappearType;
      }
      _loading = false;
      if (details == null) _error = 'Chat information could not be loaded.';
    });
  }

  Future<void> _loadMedia() async {
    if (!mounted) return;
    setState(() => _loadingMedia = true);

    final List<ChatMediaItem> items = [];
    final currentUserId = ServerApiService.instance.currentUserId;
    final chatIdStr = widget.conversation.id;
    final chatId = int.tryParse(chatIdStr);

    try {
      // 1. Fetch Chat Details from API (GET /api/chats/:chat_id)
      final details =
          _details ??
          (chatId == null
              ? null
              : await ServerApiService.instance.getChatDetails(chatId));

      if (details != null && details.media.isNotEmpty) {
        for (final m in details.media) {
          final isMe = m.senderId == currentUserId;
          final targetUrl = m.url.isNotEmpty ? m.url : m.filePath;
          final filename = m.fileName.isNotEmpty
              ? m.fileName
              : _basename(targetUrl);

          final inferred =
              inferAttachmentType(
                fileType: m.fileType,
                fileName: filename,
                filePath: targetUrl,
              ) ??
              m.fileType;
          final typeLower = inferred.toLowerCase();

          String folder = 'doc';
          if (typeLower.startsWith('image') || _isImageExt(filename)) {
            folder = 'image';
          } else if (typeLower.startsWith('video') || _isVideoExt(filename)) {
            folder = 'video';
          } else if (typeLower.startsWith('audio') || _isAudioExt(filename)) {
            folder = 'audio';
          }

          items.add(
            ChatMediaItem(
              id: m.id.toString(),
              fileName: filename,
              rawUrl: targetUrl,
              fileType: m.fileType,
              fileSize: 0,
              createdAt:
                  DateTime.tryParse(m.createdAt)?.toLocal() ?? DateTime.now(),
              isMe: isMe,
              senderName: isMe ? 'You' : widget.conversation.name,
              folder: folder,
            ),
          );
        }
      }

      // 2. Load local cached messages (for any unsynced offline items)
      final localMsgs = await LocalChatStorage.instance.loadMessages(chatIdStr);
      for (final m in localMsgs) {
        final url = m.mediaUrl;
        if (url != null && url.isNotEmpty) {
          final isMe = m.senderId == currentUserId?.toString();
          final typeLower = m.type.toLowerCase();
          final filename = m.fileName?.isNotEmpty == true
              ? m.fileName!
              : _basename(url);

          String folder = 'doc';
          if (typeLower.startsWith('image') || _isImageExt(filename)) {
            folder = 'image';
          } else if (typeLower.startsWith('video') || _isVideoExt(filename)) {
            folder = 'video';
          } else if (typeLower.startsWith('audio') || _isAudioExt(filename)) {
            folder = 'audio';
          }

          if (!items.any((x) => x.rawUrl == url || x.id == m.id)) {
            items.add(
              ChatMediaItem(
                id: m.id,
                fileName: filename,
                rawUrl: url,
                fileType: m.type,
                fileSize: 0,
                createdAt: m.timestamp,
                isMe: isMe,
                senderName: isMe ? 'You' : widget.conversation.name,
                folder: folder,
              ),
            );
          }
        }
      }

      // Sort newest first
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('[CHAT INFO] Load media error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _mediaItems = items;
          _loadingMedia = false;
        });
      }
    }
  }

  bool _isImageExt(String path) {
    final ext = path
        .split('?')
        .first
        .split('#')
        .first
        .split('.')
        .last
        .toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'].contains(ext);
  }

  bool _isVideoExt(String path) {
    final ext = path
        .split('?')
        .first
        .split('#')
        .first
        .split('.')
        .last
        .toLowerCase();
    return ['mp4', 'mov', 'webm', 'mkv', 'avi', '3gp'].contains(ext);
  }

  bool _isAudioExt(String path) {
    final ext = path
        .split('?')
        .first
        .split('#')
        .first
        .split('.')
        .last
        .toLowerCase();
    return ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac'].contains(ext);
  }

  String _basename(String path) {
    final clean = path.split('?').first.split('#').first;
    return clean.split('/').last;
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(count < 10 && i > 0 ? 1 : 0)} ${suffixes[i]}';
  }

  int get _imageCount => _mediaItems.where((x) => x.folder == 'image').length;
  int get _videoCount => _mediaItems.where((x) => x.folder == 'video').length;
  int get _audioCount => _mediaItems.where((x) => x.folder == 'audio').length;
  int get _docCount => _mediaItems.where((x) => x.folder == 'doc').length;

  List<ChatMediaItem> get _filteredMediaItems {
    return _mediaItems.where((item) {
      if (item.folder != _selectedFolder) return false;
      if (_directionFilter == 'sent' && !item.isMe) return false;
      if (_directionFilter == 'received' && item.isMe) return false;
      if (_searchQuery.trim().isNotEmpty) {
        return item.fileName.toLowerCase().contains(
          _searchQuery.trim().toLowerCase(),
        );
      }
      return true;
    }).toList();
  }

  Future<void> _clearChat() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'Are you sure you want to delete all messages in this chat? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear chat'),
          ),
        ],
      ),
    );
    if (shouldClear != true || !mounted) return;
    final chatId = int.tryParse(widget.conversation.id);
    if (chatId == null) return;
    setState(() => _clearingChat = true);
    final cleared = await ServerApiService.instance.clearChatREST(chatId);
    if (!mounted) return;
    if (!cleared) {
      setState(() => _clearingChat = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not clear this chat. Please try again.'),
        ),
      );
      return;
    }
    await LocalChatStorage.instance.cacheMessages(
      widget.conversation.id,
      const [],
    );
    await LocalChatStorage.instance.updateConversation(
      widget.conversation.id,
      (conversation) => conversation.copyWith(
        lastMessage: 'No messages yet',
        lastMessageTime: '',
        unreadCount: 0,
        messages: const [],
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _addMembers() async {
    final chatId = int.tryParse(widget.conversation.id);
    if (chatId == null || _details == null) return;
    setState(() => _updatingMembers = true);
    try {
      final allUsers = await ServerApiService.instance.getUsers();
      if (!mounted) return;
      final existingIds = _details!.members.map((member) => member.id).toSet();
      final candidates = allUsers
          .where(
            (user) =>
                user.id != ServerApiService.instance.currentUserId &&
                !existingIds.contains(user.id),
          )
          .toList();
      if (candidates.isEmpty) {
        setState(() => _updatingMembers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('There are no users available to add.')),
        );
        return;
      }
      final selectedIds = <int>{};
      final ids = await showModalBottomSheet<List<int>>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Add members',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => Navigator.pop(
                                  sheetContext,
                                  selectedIds.toList(),
                                ),
                          child: Text('Add (${selectedIds.length})'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (context, index) {
                        final user = candidates[index];
                        return CheckboxListTile(
                          value: selectedIds.contains(user.id),
                          title: Text(user.name),
                          subtitle: Text(user.phone ?? user.email ?? 'Member'),
                          secondary: IosAvatar(
                            name: user.name,
                            imagePath: user.avatar,
                            size: 42,
                          ),
                          onChanged: (checked) => setSheetState(() {
                            if (checked == true) {
                              selectedIds.add(user.id);
                            } else {
                              selectedIds.remove(user.id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (ids == null || ids.isEmpty || !mounted) {
        if (mounted) setState(() => _updatingMembers = false);
        return;
      }
      final added = await ServerApiService.instance.addGroupMembers(
        chatId: chatId,
        userIds: ids,
      );
      if (!mounted) return;
      if (!added) {
        setState(() => _updatingMembers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add group members.')),
        );
        return;
      }
      await ServerChatManager.instance.syncChats();
      if (mounted) setState(() => _updatingMembers = false);
      await _loadDetails();
    } catch (error) {
      if (mounted) {
        setState(() => _updatingMembers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add members: $error')),
        );
      }
    }
  }

  Future<void> _removeMember(UserModel member) async {
    final chatId = int.tryParse(widget.conversation.id);
    if (chatId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('Remove ${member.name} from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removed = await ServerApiService.instance.removeGroupMember(
      chatId: chatId,
      userId: member.id,
    );
    if (!mounted) return;
    if (removed) {
      await ServerChatManager.instance.syncChats();
      await _loadDetails();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove this member.')),
      );
    }
  }

  Future<void> _toggleAudio(ChatMediaItem item) async {
    _audioPlayer ??= AudioPlayer();

    if (_currentlyPlayingAudioUrl == item.fullUrl && _isPlayingAudio) {
      await _audioPlayer?.pause();
      setState(() => _isPlayingAudio = false);
      return;
    }

    try {
      await _audioPlayer?.stop();
      final url = item.fullUrl;
      if (url.startsWith('http://') || url.startsWith('https://')) {
        await _audioPlayer?.play(UrlSource(url));
      } else if (File(url).existsSync()) {
        await _audioPlayer?.play(DeviceFileSource(url));
      } else {
        final cached = await AttachmentCacheService.instance.resolveLocalPath(
          url,
        );
        if (cached != null && File(cached).existsSync()) {
          await _audioPlayer?.play(DeviceFileSource(cached));
        }
      }
      setState(() {
        _currentlyPlayingAudioUrl = item.fullUrl;
        _isPlayingAudio = true;
      });
      _audioPlayer?.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlayingAudio = false;
            _currentlyPlayingAudioUrl = null;
          });
        }
      });
    } catch (e) {
      debugPrint('[AUDIO PLAY ERROR] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play audio file.')),
        );
      }
    }
  }

  Future<void> _openDocument(ChatMediaItem item) async {
    final url = item.fullUrl;
    try {
      if (!url.startsWith('http://') &&
          !url.startsWith('https://') &&
          File(url).existsSync()) {
        await OpenFilex.open(url);
        return;
      }

      final cached = await AttachmentCacheService.instance.resolveLocalPath(
        url,
      );
      if (cached != null && File(cached).existsSync()) {
        await OpenFilex.open(cached);
        return;
      }

      // Download
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Opening ${item.fileName}...')));

      final headers = ServerApiService.instance.authToken != null
          ? {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'}
          : null;

      final res = await http.get(Uri.parse(url), headers: headers);
      if (res.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${item.fileName}');
        await file.writeAsBytes(res.bodyBytes);
        AttachmentCacheService.instance.updateCache(url, file.path);
        await OpenFilex.open(file.path);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to download document (${res.statusCode})'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[DOC OPEN ERROR] $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open file: $e')));
      }
    }
  }

  void _openImageGallery(ChatMediaItem selectedItem) {
    final imageItems = _mediaItems.where((x) => x.folder == 'image').toList();
    final initialIdx = imageItems
        .indexWhere((x) => x.id == selectedItem.id)
        .clamp(0, imageItems.length - 1);

    final photos = imageItems.map((item) {
      return ChatMessage(
        id: item.id,
        senderId: item.isMe
            ? (ServerApiService.instance.currentUserId?.toString() ?? 'me')
            : 'peer',
        content: item.fileName,
        timestamp: item.createdAt,
        type: 'image',
        mediaUrl: item.fullUrl,
        fileName: item.fileName,
      );
    }).toList();

    if (photos.isNotEmpty) {
      PhotoGalleryViewer.open(
        context,
        photos: photos,
        initialIndex: initialIdx,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? AppTheme.darkBackground
        : AppTheme.lightBackground;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final details = _details;
    final currentUserId = ServerApiService.instance.currentUserId;
    final peers =
        details?.members
            .where((member) => member.id != currentUserId)
            .toList() ??
        const <UserModel>[];
    final firstPeer = peers.isNotEmpty ? peers.first : null;
    final members = details?.members ?? const <UserModel>[];
    final creators = members
        .where((member) => member.id == details?.createdBy)
        .toList();
    final creatorName = creators.isEmpty ? 'Group admin' : creators.first.name;
    final displayName = details?.isGroup == true
        ? details?.groupName ?? widget.conversation.name
        : peers.isNotEmpty
        ? peers.first.name
        : widget.conversation.name;

    final avatar = details?.isGroup == true
        ? details?.groupAvatar ?? widget.conversation.avatarUrl
        : (peers.isNotEmpty &&
                  peers.first.avatar != null &&
                  peers.first.avatar!.isNotEmpty
              ? peers.first.avatar!
              : widget.conversation.avatarUrl);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        toolbarHeight: 56,
        title: Text(
          details?.isGroup == true ? 'Group info' : 'Contact info',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading && details == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadDetails();
                await _loadMedia();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                children: [
                  // Main Contact / Group Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        IosAvatar(
                          name: displayName,
                          imagePath: avatar,
                          isOnline: firstPeer?.isOnline ?? false,
                          size: 96,
                          showOnline: details?.isGroup != true,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          displayName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          details?.isGroup == true
                              ? '${details?.totalMembers ?? members.length} members'
                              : (firstPeer?.isOnline == true
                                    ? 'online'
                                    : firstPeer?.phone ??
                                          firstPeer?.email ??
                                          'Calculator Chat contact'),
                          style: const TextStyle(
                            color: AppTheme.subtitleGrey,
                            fontSize: 14,
                          ),
                        ),
                        if (_loading) ...[
                          const SizedBox(height: 14),
                          const LinearProgressIndicator(minHeight: 2),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: AppTheme.subtitleGrey,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _loadDetails,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Phone / Email Info Card
                  if (details?.isGroup != true && peers.isNotEmpty)
                    _InfoCard(
                      surface: surface,
                      children: [
                        if ((peers.first.phone ?? '').isNotEmpty)
                          _InfoRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone',
                            value: peers.first.phone!,
                          ),
                        if ((peers.first.email ?? '').isNotEmpty)
                          _InfoRow(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: peers.first.email!,
                          ),
                        if ((peers.first.phone ?? '').isEmpty &&
                            (peers.first.email ?? '').isEmpty)
                          const _InfoRow(
                            icon: Icons.person_outline_rounded,
                            label: 'Contact',
                            value: 'Calculator Chat user',
                            last: true,
                          ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // ─── MEDIA, DOCS & FILES SECTION ───────────────────────────
                  _buildMediaSection(surface, isDark),

                  const SizedBox(height: 16),

                  // Starred Messages & Disappearing Messages
                  _InfoCard(
                    surface: surface,
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                        ),
                        title: const Text('Starred Messages'),
                        subtitle: const Text(
                          'View starred messages in this chat',
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.subtitleGrey,
                        ),
                        onTap: () async {
                          final selectedId = await Navigator.of(context)
                              .push<String>(
                                MaterialPageRoute(
                                  builder: (_) => StarredMessagesPage(
                                    conversation: widget.conversation,
                                  ),
                                ),
                              );
                          if (selectedId != null && context.mounted) {
                            Navigator.of(context).pop(selectedId);
                          }
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(
                          Icons.timer_outlined,
                          color: AppTheme.primaryColor,
                        ),
                        title: const Text('Disappearing Messages'),
                        subtitle: Text(
                          _disappearingLabels[_disappearType] ?? 'off',
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.subtitleGrey,
                        ),
                        onTap: _showDisappearingPicker,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Chat Customization Section (Bubble Color & Wallpaper)
                  _InfoCard(
                    surface: surface,
                    children: [
                      ListTile(
                        leading: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppPreferences.getChatBubbleColor(
                              chatId: widget.conversation.id,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        title: const Text('Chat Bubble Color'),
                        subtitle: Text(
                          _getBubbleColorName(
                            AppPreferences.getChatBubbleColor(
                              chatId: widget.conversation.id,
                            ),
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.subtitleGrey,
                        ),
                        onTap: _showBubbleColorPicker,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(
                          Icons.wallpaper_rounded,
                          color: AppTheme.primaryColor,
                        ),
                        title: const Text('Chat Background Wallpaper'),
                        subtitle: Text(
                          _getWallpaperTypeName(
                            AppPreferences.getWallpaperType(
                              chatId: widget.conversation.id,
                            ),
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.subtitleGrey,
                        ),
                        onTap: _showWallpaperPicker,
                      ),
                    ],
                  ),

                  // Group Details Section
                  if (details?.isGroup == true) ...[
                    const SizedBox(height: 16),
                    _InfoCard(
                      surface: surface,
                      children: [
                        _InfoRow(
                          icon: Icons.groups_2_outlined,
                          label: 'Group name',
                          value: displayName,
                        ),
                        _InfoRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Created by',
                          value: creatorName,
                          last: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoCard(
                      surface: surface,
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.qr_code_2_rounded,
                            color: AppTheme.primaryColor,
                          ),
                          title: const Text(
                            'Share Group Link',
                            style: TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () {
                            if (details != null) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ShareQrPage(
                                    title: 'Invite to Group',
                                    subtitle:
                                        'Share this QR code or link to invite friends to join "$displayName".',
                                    shareLink:
                                        'securecalc://join?group_id=${details.id}',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Members · ${details?.totalMembers ?? members.length}',
                              style: const TextStyle(
                                color: AppTheme.subtitleGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _updatingMembers ? null : _addMembers,
                            icon: _updatingMembers
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.person_add_alt_1_rounded),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                    ),
                    _InfoCard(
                      surface: surface,
                      children: [
                        for (var i = 0; i < members.length; i++)
                          ListTile(
                            leading: IosAvatar(
                              name: members[i].name,
                              imagePath: members[i].avatar,
                              isOnline: members[i].isOnline,
                              size: 42,
                            ),
                            title: Text(members[i].name),
                            subtitle: Text(members[i].role ?? 'member'),
                            trailing: members[i].id == currentUserId
                                ? const Text(
                                    'You',
                                    style: TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : IconButton(
                                    tooltip: 'Remove member',
                                    onPressed: () => _removeMember(members[i]),
                                    icon: const Icon(
                                      Icons.remove_circle_outline_rounded,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 18),

                  // Clear Chat Card
                  _InfoCard(
                    surface: surface,
                    children: [
                      ListTile(
                        enabled: !_clearingChat,
                        leading: _clearingChat
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.delete_sweep_outlined,
                                color: Colors.redAccent,
                              ),
                        title: const Text(
                          'Clear chat',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                        subtitle: const Text('Remove messages from this chat'),
                        onTap: _clearingChat ? null : _clearChat,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  // ─── MEDIA BUILDER WIDGET ──────────────────────────────────────────────────
  Widget _buildMediaSection(Color surface, bool isDark) {
    final filteredItems = _filteredMediaItems;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              const Icon(
                Icons.perm_media_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Media, Docs & Files',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_mediaItems.length}',
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () =>
                    setState(() => _isMediaExpanded = !_isMediaExpanded),
                child: Row(
                  children: [
                    Text(
                      _isMediaExpanded ? 'View Less' : 'View All',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    Icon(
                      _isMediaExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 18,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (!_isMediaExpanded) ...[
            _buildCompactMediaRow(isDark),
          ] else ...[
            const SizedBox(height: 14),

            // Folder Category Selector Tabs (Images | Videos | Audio | Docs)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFolderTab(
                    'image',
                    'Images',
                    CupertinoIcons.photo,
                    _imageCount,
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildFolderTab(
                    'video',
                    'Videos',
                    CupertinoIcons.video_camera,
                    _videoCount,
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildFolderTab(
                    'audio',
                    'Audio',
                    CupertinoIcons.music_note,
                    _audioCount,
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildFolderTab(
                    'doc',
                    'Docs',
                    CupertinoIcons.doc_text,
                    _docCount,
                    isDark,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Direction Filter Chips (All | Sent 📤 | Received 📥)
            Row(
              children: [
                _buildFilterChip('all', 'All'),
                const SizedBox(width: 6),
                _buildFilterChip('sent', 'Sent 📤'),
                const SizedBox(width: 6),
                _buildFilterChip('received', 'Received 📥'),
              ],
            ),

            const SizedBox(height: 12),

            // Media Content Area
            if (_loadingMedia) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ] else if (filteredItems.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        _selectedFolder == 'image'
                            ? CupertinoIcons.photo_on_rectangle
                            : _selectedFolder == 'video'
                            ? CupertinoIcons.video_camera
                            : _selectedFolder == 'audio'
                            ? CupertinoIcons.music_note
                            : CupertinoIcons.doc,
                        size: 38,
                        color: AppTheme.subtitleGrey.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No ${_selectedFolder == 'doc' ? 'documents' : '${_selectedFolder}s'} ${_directionFilter == 'all'
                            ? 'found'
                            : _directionFilter == 'sent'
                            ? 'sent'
                            : 'received'}.',
                        style: const TextStyle(
                          color: AppTheme.subtitleGrey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Type-wise View Rendering
              if (_selectedFolder == 'image')
                _buildImagesGrid(filteredItems)
              else if (_selectedFolder == 'video')
                _buildVideosGrid(filteredItems)
              else if (_selectedFolder == 'audio')
                _buildAudioList(filteredItems, isDark)
              else
                _buildDocsList(filteredItems, isDark),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCompactMediaRow(bool isDark) {
    if (_loadingMedia) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_mediaItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.photo_on_rectangle,
              size: 20,
              color: AppTheme.subtitleGrey.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            const Text(
              'No media shared in this chat yet.',
              style: TextStyle(color: AppTheme.subtitleGrey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final recentItems = _mediaItems.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recentItems.length + (_mediaItems.length > 6 ? 1 : 0),
            separatorBuilder: (_, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == recentItems.length) {
                return GestureDetector(
                  onTap: () => setState(() => _isMediaExpanded = true),
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '+${_mediaItems.length - 6}',
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'View All',
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final item = recentItems[index];

              return GestureDetector(
                onTap: () {
                  if (item.folder == 'image' || item.folder == 'video') {
                    _openImageGallery(item);
                  } else {
                    setState(() {
                      _selectedFolder = item.folder;
                      _isMediaExpanded = true;
                    });
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 76,
                    height: 76,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.withValues(alpha: 0.1),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.folder == 'image' ||
                            item.folder == 'video') ...[
                          _ChatMediaThumbnail(rawUrl: item.rawUrl),
                          if (item.folder == 'video')
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                        ] else ...[
                          Container(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  item.folder == 'audio'
                                      ? CupertinoIcons.music_note
                                      : CupertinoIcons.doc_text,
                                  color: AppTheme.primaryColor,
                                  size: 22,
                                ),
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Text(
                                    item.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFolderTab(
    String key,
    String label,
    IconData icon,
    int count,
    bool isDark,
  ) {
    final isSelected = _selectedFolder == key;
    return InkWell(
      onTap: () => setState(() => _selectedFolder = key),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor
              : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : AppTheme.subtitleGrey,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white24
                      : AppTheme.subtitleGrey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : AppTheme.subtitleGrey,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _directionFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _directionFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : AppTheme.subtitleGrey.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppTheme.primaryColor : AppTheme.subtitleGrey,
          ),
        ),
      ),
    );
  }

  // 1. Image Grid
  Widget _buildImagesGrid(List<ChatMediaItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, index) {
        final item = items[index];

        return GestureDetector(
          onTap: () => _openImageGallery(item),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _ChatMediaThumbnail(rawUrl: item.rawUrl),

                // Direction Pill Tag (Sent / Received)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.isMe
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 10,
                          color: item.isMe
                              ? Colors.lightBlueAccent
                              : Colors.lightGreenAccent,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          item.isMe ? 'Sent' : 'Recv',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 2. Video Grid
  Widget _buildVideosGrid(List<ChatMediaItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return GestureDetector(
          onTap: () => _openDocument(item),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              color: Colors.black87,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.play_circle_fill,
                    size: 36,
                    color: Colors.white70,
                  ),
                  Positioned(
                    bottom: 4,
                    left: 4,
                    right: 4,
                    child: Text(
                      item.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.isMe ? 'Sent' : 'Recv',
                        style: TextStyle(
                          color: item.isMe
                              ? Colors.lightBlueAccent
                              : Colors.lightGreenAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 3. Audio List
  Widget _buildAudioList(List<ChatMediaItem> items, bool isDark) {
    return Column(
      children: [
        for (final item in items)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _toggleAudio(item),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      (_currentlyPlayingAudioUrl == item.fullUrl &&
                              _isPlayingAudio)
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            item.isMe
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 11,
                            color: item.isMe
                                ? AppTheme.primaryColor
                                : Colors.green,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            item.isMe
                                ? 'Sent by You'
                                : 'Received from ${item.senderName}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.subtitleGrey,
                            ),
                          ),
                          if (item.fileSize > 0) ...[
                            const Text(
                              ' · ',
                              style: TextStyle(
                                color: AppTheme.subtitleGrey,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              _formatFileSize(item.fileSize),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.subtitleGrey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // 4. Docs List
  Widget _buildDocsList(List<ChatMediaItem> items, bool isDark) {
    return Column(
      children: [
        for (final item in items)
          InkWell(
            onTap: () => _openDocument(item),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _buildDocTypeIcon(item.fileName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (item.isMe
                                            ? AppTheme.primaryColor
                                            : Colors.green)
                                        .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.isMe ? 'Sent' : 'Received',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: item.isMe
                                      ? AppTheme.primaryColor
                                      : Colors.green,
                                ),
                              ),
                            ),
                            if (item.fileSize > 0) ...[
                              const SizedBox(width: 6),
                              Text(
                                _formatFileSize(item.fileSize),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.subtitleGrey,
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            Text(
                              '${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.subtitleGrey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.download_for_offline_outlined,
                    color: AppTheme.primaryColor,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDocTypeIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    IconData iconData = CupertinoIcons.doc_fill;
    Color iconColor = Colors.blue;

    if (ext == 'pdf') {
      iconData = CupertinoIcons.doc_text_fill;
      iconColor = Colors.redAccent;
    } else if (['doc', 'docx'].contains(ext)) {
      iconData = CupertinoIcons.doc_richtext;
      iconColor = Colors.blueAccent;
    } else if (['xls', 'xlsx'].contains(ext)) {
      iconData = CupertinoIcons.table_fill;
      iconColor = Colors.green;
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      iconData = CupertinoIcons.archivebox_fill;
      iconColor = Colors.orange;
    } else if (['txt', 'rtf'].contains(ext)) {
      iconData = CupertinoIcons.doc_plaintext;
      iconColor = Colors.grey;
    }

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(iconData, color: iconColor, size: 22),
    );
  }
}

/// Resolves attachment-cache entries before falling back to the authenticated
/// network URL, so media thumbnails use the same source as the full viewer.
class _ChatMediaThumbnail extends StatefulWidget {
  final String rawUrl;

  const _ChatMediaThumbnail({required this.rawUrl});

  @override
  State<_ChatMediaThumbnail> createState() => _ChatMediaThumbnailState();
}

class _ChatMediaThumbnailState extends State<_ChatMediaThumbnail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;
  String? _resolvedPath;
  bool _isResolving = true;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _ChatMediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawUrl != widget.rawUrl) {
      _resolvedPath = null;
      _isResolving = true;
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _resolveImage() async {
    final rawUrl = widget.rawUrl.trim();
    if (rawUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _resolvedPath = null;
          _isResolving = false;
        });
      }
      return;
    }

    if (File(rawUrl).existsSync()) {
      if (mounted) {
        setState(() {
          _resolvedPath = rawUrl;
          _isResolving = false;
        });
      }
      return;
    }

    final networkUrl = resolveAvatarUrl(rawUrl);
    var cached = await AttachmentCacheService.instance.resolveLocalPath(rawUrl);
    cached ??= await AttachmentCacheService.instance.resolveLocalPath(
      networkUrl,
    );
    if (!mounted || rawUrl != widget.rawUrl.trim()) return;

    setState(() {
      _resolvedPath = cached ?? networkUrl;
      _isResolving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isResolving) {
      return _MediaThumbnailShimmer(controller: _shimmerController);
    }

    if (_resolvedPath == null) return const _MediaThumbnailUnavailable();

    final path = _resolvedPath!;
    final isLocal = !path.startsWith('http://') && !path.startsWith('https://');
    final image = isLocal
        ? Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: 240,
            errorBuilder: (_, __, ___) => const _MediaThumbnailUnavailable(),
          )
        : Image.network(
            path,
            headers: ServerApiService.instance.authToken != null
                ? {
                    'Authorization':
                        'Bearer ${ServerApiService.instance.authToken}',
                  }
                : null,
            fit: BoxFit.cover,
            cacheWidth: 240,
            gaplessPlayback: true,
            loadingBuilder: (_, child, loadingProgress) =>
                loadingProgress == null
                ? child
                : _MediaThumbnailShimmer(controller: _shimmerController),
            errorBuilder: (_, __, ___) => const _MediaThumbnailUnavailable(),
          );

    return SizedBox.expand(child: image);
  }
}

class _MediaThumbnailShimmer extends StatelessWidget {
  final Animation<double> controller;

  const _MediaThumbnailShimmer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(-1.5 + (controller.value * 3), -0.3),
          end: Alignment(-0.5 + (controller.value * 3), 0.3),
          colors: const [
            Color(0xFFE3E6EA),
            Color(0xFFF7F8FA),
            Color(0xFFE3E6EA),
          ],
          stops: const [0.0, 0.48, 1.0],
        ).createShader(bounds),
        child: const ColoredBox(color: Color(0xFFE3E6EA)),
      ),
    );
  }
}

class _MediaThumbnailUnavailable extends StatelessWidget {
  const _MediaThumbnailUnavailable();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFE9E9EF),
      child: Center(
        child: Icon(
          CupertinoIcons.photo,
          size: 22,
          color: AppTheme.subtitleGrey,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Color surface;
  final List<Widget> children;

  const _InfoCard({required this.surface, required this.children});

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool last;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        leading: Icon(icon, color: AppTheme.primaryColor),
        title: Text(
          label,
          style: const TextStyle(color: AppTheme.subtitleGrey, fontSize: 12),
        ),
        subtitle: Text(value, style: const TextStyle(fontSize: 15)),
      ),
      if (!last) const Divider(height: 1, indent: 56, endIndent: 16),
    ],
  );
}
