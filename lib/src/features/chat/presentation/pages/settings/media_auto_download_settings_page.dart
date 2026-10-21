import 'package:flutter/material.dart';

import '../../../../../core/config/app_preferences.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/app_toast.dart';
import '../../../../../core/widgets/compact_settings_header.dart';

class MediaAutoDownloadSettingsPage extends StatefulWidget {
  const MediaAutoDownloadSettingsPage({super.key});

  @override
  State<MediaAutoDownloadSettingsPage> createState() =>
      _MediaAutoDownloadSettingsPageState();
}

class _MediaAutoDownloadSettingsPageState
    extends State<MediaAutoDownloadSettingsPage> {
  late bool _mobilePhotos;
  late bool _mobileVideos;
  late bool _mobileDocs;

  late bool _wifiPhotos;
  late bool _wifiVideos;
  late bool _wifiDocs;

  @override
  void initState() {
    super.initState();
    _mobilePhotos = AppPreferences.getAutoMobilePhotos();
    _mobileVideos = AppPreferences.getAutoMobileVideos();
    _mobileDocs = AppPreferences.getAutoMobileDocs();

    _wifiPhotos = AppPreferences.getAutoWifiPhotos();
    _wifiVideos = AppPreferences.getAutoWifiVideos();
    _wifiDocs = AppPreferences.getAutoWifiDocs();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      body: SafeArea(
        child: Column(
          children: [
            const CompactSettingsHeader(title: 'Media Auto-Download'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      'Configure automatic media downloading based on your active network connection (Mobile Data vs Wi-Fi).',
                      style: TextStyle(fontSize: 13, color: AppTheme.subtitleGrey),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // SECTION 1: WHEN USING MOBILE DATA
                  _buildSectionTitle('WHEN USING MOBILE DATA'),
                  _buildGroupedCard(
                    isDark: isDark,
                    children: [
                      SwitchListTile(
                        secondary: const Icon(
                          Icons.photo_outlined,
                          color: AppTheme.primaryColor,
                        ),
                        activeTrackColor: AppTheme.onlineGreen,
                        title: const Text(
                          'Photos',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        value: _mobilePhotos,
                        onChanged: (val) async {
                          setState(() => _mobilePhotos = val);
                          await AppPreferences.setAutoMobilePhotos(val);
                          await AppPreferences.setAutoDownloadImages(_mobilePhotos || _wifiPhotos);
                          AppToast.show(
                            val
                                ? 'Mobile data photo auto-download enabled'
                                : 'Mobile data photo auto-download disabled',
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
                        value: _mobileVideos,
                        onChanged: (val) async {
                          setState(() => _mobileVideos = val);
                          await AppPreferences.setAutoMobileVideos(val);
                          await AppPreferences.setAutoDownloadVideos(_mobileVideos || _wifiVideos);
                          AppToast.show(
                            val
                                ? 'Mobile data video auto-download enabled'
                                : 'Mobile data video auto-download disabled',
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
                        value: _mobileDocs,
                        onChanged: (val) async {
                          setState(() => _mobileDocs = val);
                          await AppPreferences.setAutoMobileDocs(val);
                          await AppPreferences.setAutoDownloadDocs(_mobileDocs || _wifiDocs);
                          AppToast.show(
                            val
                                ? 'Mobile data doc auto-download enabled'
                                : 'Mobile data doc auto-download disabled',
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // SECTION 2: WHEN CONNECTED ON WI-FI
                  _buildSectionTitle('WHEN CONNECTED ON WI-FI'),
                  _buildGroupedCard(
                    isDark: isDark,
                    children: [
                      SwitchListTile(
                        secondary: const Icon(
                          Icons.wifi_outlined,
                          color: AppTheme.primaryColor,
                        ),
                        activeTrackColor: AppTheme.onlineGreen,
                        title: const Text(
                          'Photos',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        value: _wifiPhotos,
                        onChanged: (val) async {
                          setState(() => _wifiPhotos = val);
                          await AppPreferences.setAutoWifiPhotos(val);
                          await AppPreferences.setAutoDownloadImages(_mobilePhotos || _wifiPhotos);
                          AppToast.show(
                            val
                                ? 'Wi-Fi photo auto-download enabled'
                                : 'Wi-Fi photo auto-download disabled',
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
                        value: _wifiVideos,
                        onChanged: (val) async {
                          setState(() => _wifiVideos = val);
                          await AppPreferences.setAutoWifiVideos(val);
                          await AppPreferences.setAutoDownloadVideos(_mobileVideos || _wifiVideos);
                          AppToast.show(
                            val
                                ? 'Wi-Fi video auto-download enabled'
                                : 'Wi-Fi video auto-download disabled',
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
                        value: _wifiDocs,
                        onChanged: (val) async {
                          setState(() => _wifiDocs = val);
                          await AppPreferences.setAutoWifiDocs(val);
                          await AppPreferences.setAutoDownloadDocs(_mobileDocs || _wifiDocs);
                          AppToast.show(
                            val
                                ? 'Wi-Fi doc auto-download enabled'
                                : 'Wi-Fi doc auto-download disabled',
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.subtitleGrey,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildGroupedCard({
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
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
      child: Column(children: children),
    );
  }
}
