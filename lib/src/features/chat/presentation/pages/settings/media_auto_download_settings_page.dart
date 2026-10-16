import 'package:flutter/material.dart';

import '../../../../../core/config/app_preferences.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/app_toast.dart';

class MediaAutoDownloadSettingsPage extends StatefulWidget {
  const MediaAutoDownloadSettingsPage({super.key});

  @override
  State<MediaAutoDownloadSettingsPage> createState() =>
      _MediaAutoDownloadSettingsPageState();
}

class _MediaAutoDownloadSettingsPageState
    extends State<MediaAutoDownloadSettingsPage> {
  late bool _autoImages;
  late bool _autoVideos;
  late bool _autoDocs;

  @override
  void initState() {
    super.initState();
    _autoImages = AppPreferences.getAutoDownloadImages();
    _autoVideos = AppPreferences.getAutoDownloadVideos();
    _autoDocs = AppPreferences.getAutoDownloadDocs();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Media Auto-Download'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Automatically download incoming media files when received. If disabled, a download button will be displayed on each file.',
                style: TextStyle(fontSize: 13, color: AppTheme.subtitleGrey),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(
                      Icons.photo_outlined,
                      color: AppTheme.primaryColor,
                    ),
                    activeTrackColor: AppTheme.onlineGreen,
                    title: const Text(
                      'Photos / Images',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Automatically download incoming photos',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.subtitleGrey,
                      ),
                    ),
                    value: _autoImages,
                    onChanged: (val) async {
                      setState(() => _autoImages = val);
                      await AppPreferences.setAutoDownloadImages(val);
                      AppToast.show(
                        val
                            ? 'Auto-download for photos enabled'
                            : 'Auto-download for photos disabled',
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 52,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                  SwitchListTile(
                    secondary: const Icon(
                      Icons.videocam_outlined,
                      color: AppTheme.primaryColor,
                    ),
                    activeTrackColor: AppTheme.onlineGreen,
                    title: const Text(
                      'Videos',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Automatically download incoming videos',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.subtitleGrey,
                      ),
                    ),
                    value: _autoVideos,
                    onChanged: (val) async {
                      setState(() => _autoVideos = val);
                      await AppPreferences.setAutoDownloadVideos(val);
                      AppToast.show(
                        val
                            ? 'Auto-download for videos enabled'
                            : 'Auto-download for videos disabled',
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 52,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                  SwitchListTile(
                    secondary: const Icon(
                      Icons.insert_drive_file_outlined,
                      color: AppTheme.primaryColor,
                    ),
                    activeTrackColor: AppTheme.onlineGreen,
                    title: const Text(
                      'Documents & Audio',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Automatically download files and voice notes',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.subtitleGrey,
                      ),
                    ),
                    value: _autoDocs,
                    onChanged: (val) async {
                      setState(() => _autoDocs = val);
                      await AppPreferences.setAutoDownloadDocs(val);
                      AppToast.show(
                        val
                            ? 'Auto-download for documents enabled'
                            : 'Auto-download for documents disabled',
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
