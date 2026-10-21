import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/compact_settings_header.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/features/calling/domain/services/device_identity_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_chat_manager.dart';

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  String? _deviceId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeviceKey();
  }

  Future<void> _loadDeviceKey() async {
    try {
      final key = await DeviceIdentityService.instance.getDeviceId();
      if (mounted) {
        setState(() {
          _deviceId = key;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _deviceId = 'Unavailable';
          _isLoading = false;
        });
      }
    }
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.redAccent : AppTheme.primaryColor,
      ),
    );
  }

  /// Glassmorphic Warning Dialog Widget
  Future<bool?> _showGlassWarningDialog({
    required BuildContext context,
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
    required String confirmButtonText,
    Color confirmButtonColor = AppTheme.primaryColor,
    Widget? extraContent,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.88,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xEE1C1C1E)
                      : const Color(0xF5FFFFFF),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.12),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 32,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: iconColor.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 32,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: iconColor.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 20,
                            color: iconColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.9)
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (extraContent != null) ...[
                      const SizedBox(height: 14),
                      extraContent,
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: confirmButtonColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(true),
                            child: Text(
                              confirmButtonText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
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
          ),
        );
      },
    );
  }

  /// Feature 1: Export / Download Backup Key File
  Future<void> _exportBackupFile() async {
    if (_deviceId == null || _deviceId!.isEmpty || _deviceId == 'Unavailable') {
      _showToast('Device key unavailable', isError: true);
      return;
    }

    final confirmed = await _showGlassWarningDialog(
      context: context,
      title: 'Security Warning',
      message:
          'If you send or share this backup key file with someone else, they can access your account and secret data on their device!\n\nPlease DO NOT share this file with anyone.',
      icon: Icons.shield_outlined,
      iconColor: Colors.amber,
      confirmButtonText: 'I Understand & Export',
      confirmButtonColor: AppTheme.primaryColor,
    );

    if (confirmed != true) return;

    AppPreferences.isPickerActive = true;
    try {
      final backupData = {
        'app': 'SecureCalc',
        'backup_type': 'device_identity',
        'old_device_key': _deviceId,
        'device_key': _deviceId,
        'exported_at': DateTime.now().toIso8601String(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      final tempDir = await getTemporaryDirectory();
      final keyShort =
          _deviceId!.length >= 8 ? _deviceId!.substring(0, 8) : _deviceId;
      final file = File('${tempDir.path}/securecalc_backup_$keyShort.json');
      await file.writeAsString(jsonString);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'SecureCalc Device Key Backup File',
      );

      _showToast('Backup key file generated! Keep it private.');
    } catch (e) {
      _showToast('Failed to export backup file: $e', isError: true);
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  /// Feature 2: Pick File to Restore Old Device Backup
  Future<void> _restoreBackupFromFile() async {
    if (_deviceId == null || _deviceId!.isEmpty || _deviceId == 'Unavailable') {
      _showToast('Current device key unavailable', isError: true);
      return;
    }

    AppPreferences.isPickerActive = true;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.any,
      );

      if (files.isEmpty) return;

      final picked = files.first;
      var filePath = picked.path;

      if (filePath == null || filePath.isEmpty) {
        final temporaryDirectory = await getTemporaryDirectory();
        final safeName = picked.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        filePath =
            '${temporaryDirectory.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
        await File(filePath)
            .writeAsBytes(await picked.readAsBytes(), flush: true);
      }

      final fileContent = await File(filePath).readAsString();
      String? extractedOldKey;

      try {
        final decoded = jsonDecode(fileContent);
        if (decoded is Map<String, dynamic>) {
          extractedOldKey = decoded['old_device_key']?.toString() ??
              decoded['device_key']?.toString();
        }
      } catch (_) {
        final trimmed = fileContent.trim();
        if (trimmed.length >= 16) {
          extractedOldKey = trimmed;
        }
      }

      if (extractedOldKey == null || extractedOldKey.trim().length < 16) {
        _showToast(
          'Invalid backup file. Could not find a valid old device key (min 16 characters).',
          isError: true,
        );
        return;
      }

      await _proceedWithDeviceSwap(extractedOldKey.trim());
    } catch (e) {
      _showToast('Error reading backup file: $e', isError: true);
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  /// Executes swap-device API after glass warning confirmation
  Future<void> _proceedWithDeviceSwap(String oldDeviceKey) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final extraInfoWidget = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Old Device Key (Source):',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.subtitleGrey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            oldDeviceKey,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'New Device Key (Current Target):',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.subtitleGrey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _deviceId ?? 'Unknown',
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );

    final confirmed = await _showGlassWarningDialog(
      context: context,
      title: 'Overwrite Local Data Warning',
      message:
          'Restoring backup data from your old device will overwrite and erase current data on this device!\n\nIf you want old backup, proceed below. New data on this device will be gone.',
      icon: Icons.swap_horiz_rounded,
      iconColor: Colors.deepOrangeAccent,
      confirmButtonText: 'Confirm & Restore Data',
      confirmButtonColor: Colors.deepOrangeAccent,
      extraContent: extraInfoWidget,
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await ServerApiService.instance.swapDevice(
        oldDeviceKey: oldDeviceKey,
        newDeviceKey: _deviceId!,
      );

      await ServerChatManager.instance.init();
      _showToast('Device backup data successfully restored!');
    } catch (e) {
      String cleanMessage = e.toString().replaceAll('Exception: ', '');
      _showToast(cleanMessage, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor: isDark
            ? AppTheme.darkBackground
            : AppTheme.lightBackground,
        body: SafeArea(
          child: Column(
            children: [
              const CompactSettingsHeader(title: 'Help & Support & Backup'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  children: [
                    // Backup & Restore Section
                    _buildSectionHeader('BACKUP & RESTORE DATA'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.cloud_sync_rounded,
                                  color: Colors.amber,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Device Backup & Swap',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Export key file or restore data from old device',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.subtitleGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Download / Export Backup File Button
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark
                                    ? const Color(0xFF2C2C2E)
                                    : const Color(0xFFF2F2F7),
                                foregroundColor:
                                    isDark ? Colors.white : Colors.black87,
                                elevation: 0,
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.black12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _deviceId != null && !_isLoading
                                  ? _exportBackupFile
                                  : null,
                              icon: const Icon(
                                Icons.file_download_outlined,
                                size: 20,
                                color: AppTheme.primaryColor,
                              ),
                              label: const Text(
                                'Download Backup Key File',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Restore Backup File Button
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _deviceId != null && !_isLoading
                                  ? _restoreBackupFromFile
                                  : null,
                              icon: const Icon(
                                Icons.file_upload_outlined,
                                size: 20,
                              ),
                              label: const Text(
                                'Restore Data from Backup File',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Backup & Restore Guide Section
                    _buildSectionHeader('HOW BACKUP & RESTORE WORKS'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: Column(
                        children: [
                          _buildBackupGuideItem(
                            isDark: isDark,
                            step: 'STEP 1',
                            title: 'Export Backup Key File',
                            description:
                                'On your old device, tap "Download Backup Key File" to generate and save your secure device backup file.',
                            icon: Icons.file_download_outlined,
                          ),
                          Divider(
                            height: 24,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                          _buildBackupGuideItem(
                            isDark: isDark,
                            step: 'STEP 2',
                            title: 'Keep File Private',
                            description:
                                'Transfer or store your backup file safely. Do NOT share this file with anyone else as it grants access to your account data.',
                            icon: Icons.security_rounded,
                          ),
                          Divider(
                            height: 24,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                          _buildBackupGuideItem(
                            isDark: isDark,
                            step: 'STEP 3',
                            title: 'Restore on New Device',
                            description:
                                'On your new device, tap "Restore Data from Backup File" and select your saved backup file to restore your account and chats.',
                            icon: Icons.restore_page_rounded,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    _buildSectionHeader('FREQUENTLY ASKED QUESTIONS'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: Column(
                        children: [
                          _buildFaqItem(
                            isDark: isDark,
                            icon: Icons.lock_outline_rounded,
                            question: 'How do I unlock my secret vault?',
                            answer:
                                'Type your secret passcode into the calculator and tap the "=" button. The calculator disguise will immediately unlock your private vault.',
                          ),
                          Divider(
                            height: 24,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                          _buildFaqItem(
                            isDark: isDark,
                            icon: Icons.shield_outlined,
                            question: 'What is Duress / Decoy Mode?',
                            answer:
                                'Entering your decoy passcode (e.g. 4321=) opens a fake empty vault. This protects your actual secret chats if forced to unlock the app.',
                          ),
                          Divider(
                            height: 24,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                          _buildFaqItem(
                            isDark: isDark,
                            icon: Icons.vibration_rounded,
                            question: 'How do Panic Gestures work?',
                            answer:
                                'Shaking your phone or putting it screen down triggers Emergency Panic Mode, immediately closing your vault and returning to the calculator disguise.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackupGuideItem({
    required bool isDark,
    required String step,
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 18,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      step,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.subtitleGrey,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFaqItem({
    required bool isDark,
    required IconData icon,
    required String question,
    required String answer,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                answer,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.subtitleGrey,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12.0, bottom: 6.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.subtitleGrey,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildGroupedCard({required bool isDark, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.all(16.0), child: child),
      ),
    );
  }
}
