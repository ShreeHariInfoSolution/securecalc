import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/compact_settings_header.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/features/calculator/domain/calculator_logic.dart';
import 'package:securecalc/src/features/calculator/presentation/pages/calculator_page.dart';

class PersonalSettingsPage extends StatefulWidget {
  const PersonalSettingsPage({super.key});

  @override
  State<PersonalSettingsPage> createState() => _PersonalSettingsPageState();
}

class _PersonalSettingsPageState extends State<PersonalSettingsPage> {
  late TextEditingController _displayNameController;
  late TextEditingController _passcodeController;
  late TextEditingController _dummyPasscodeController;
  String? _profileImagePath;
  bool _obscurePasscode = true;
  bool _obscureDummyPasscode = true;
  bool _fakeHistoryEnabled = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _profileImagePath = AppPreferences.getProfileImagePath();
    _displayNameController = TextEditingController(
      text: AppPreferences.getDisplayName(),
    );
    _passcodeController = TextEditingController(
      text: CalculatorLogic.secretPasscode,
    );
    _dummyPasscodeController = TextEditingController(
      text: CalculatorLogic.dummyCode,
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.primaryColor,
      ),
    );
  }

  Future<void> _pickProfileImage(ImageSource source) async {
    AppPreferences.isPickerActive = true;
    try {
      if (source == ImageSource.camera) {
        await Permission.camera.request();
      } else if (Platform.isAndroid) {
        await [Permission.photos, Permission.storage].request();
      }

      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) {
        await AppPreferences.setProfileImagePath(picked.path);
        if (mounted) {
          setState(() {
            _profileImagePath = picked.path;
          });
          _showToast('Profile picture updated successfully!');
        }
      }
    } catch (e) {
      debugPrint('[PROFILE PICK ERROR] $e');
      _showToast('Unable to pick image: $e');
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _pickProfileImage(ImageSource.gallery);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                        child: const Icon(Icons.photo_library_rounded,
                            color: AppTheme.primaryColor),
                      ),
                      const SizedBox(height: 8),
                      const Text('Gallery', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _pickProfileImage(ImageSource.camera);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: Color(0x1F007AFF),
                        child: Icon(Icons.camera_alt_rounded,
                            color: Color(0xFF007AFF)),
                      ),
                      SizedBox(height: 8),
                      Text('Camera', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmAccountDeletion(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Delete Account & Data'),
            ],
          ),
          content: const Text(
            'This action permanently deletes your account profile, local credentials, and server session data. This action cannot be undone.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                Navigator.pop(context);
                await AppPreferences.clearAccountProfile();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Account profile and server data cleared.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                    PageRouteBuilder(
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      pageBuilder: (context, animation, secondaryAnimation) {
                        return const CalculatorPage();
                      },
                    ),
                    (route) => false,
                  );
                }
              },
              child: const Text(
                'Delete Account',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _saveDisplayName() {
    final newName = _displayNameController.text.trim();
    if (newName.isEmpty) {
      _showToast('Display name cannot be empty.');
      return;
    }

    HapticFeedback.mediumImpact();
    AppPreferences.setDisplayName(newName);
    _showToast('Display name saved!');
  }

  void _savePasscode() {
    final newPass = _passcodeController.text.trim();
    if (newPass.isEmpty) {
      _showToast('Passcode cannot be empty.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      CalculatorLogic.secretPasscode = newPass;
    });
    AppPreferences.setPasscode(newPass);
    _showToast('Secret trigger code set to "$newPass="');
  }

  void _saveDummyCode() {
    final newDummy = _dummyPasscodeController.text.trim();
    HapticFeedback.mediumImpact();
    setState(() {
      CalculatorLogic.dummyCode = newDummy;
    });
    AppPreferences.setDummyCode(newDummy);
    _showToast(newDummy.isEmpty
        ? 'Dummy crash code cleared.'
        : 'Dummy crash code set to "$newDummy="');
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _passcodeController.dispose();
    _dummyPasscodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasProfilePic = _profileImagePath != null &&
        _profileImagePath!.isNotEmpty &&
        File(_profileImagePath!).existsSync();

    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        body: SafeArea(
          child: Column(
            children: [
              // iOS Style Header
              const CompactSettingsHeader(title: 'Personal & Passcode'),

              // iOS Grouped Settings List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  children: [
                    // Section 1: Profile
                    _buildSectionHeader('PROFILE'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: Column(
                        children: [
                          Center(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CircleAvatar(
                                  radius: 42,
                                  backgroundColor: const Color(0xFF60A5FA),
                                  backgroundImage: hasProfilePic
                                      ? FileImage(File(_profileImagePath!))
                                      : null,
                                  child: !hasProfilePic
                                      ? Text(
                                          _displayNameController.text.isNotEmpty
                                              ? _displayNameController.text[0]
                                                  .toUpperCase()
                                              : 'H',
                                          style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: GestureDetector(
                                    onTap: _showImagePickerOptions,
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isDark
                                              ? AppTheme.darkSurface
                                              : Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _displayNameController,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Display Name',
                              labelStyle: const TextStyle(color: AppTheme.subtitleGrey),
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                                color: AppTheme.primaryColor,
                                size: 20,
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : const Color(0xFFE5E5EA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 42,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _saveDisplayName,
                              child: const Text(
                                'Save Display Name',
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

                    // Section 2: Vault Passcode
                    _buildSectionHeader('SECRET VAULT PASSCODE'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Type this code on the calculator and press "=" to unlock your secure vault.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.subtitleGrey,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passcodeController,
                            keyboardType: TextInputType.number,
                            obscureText: _obscurePasscode,
                            style: TextStyle(
                              fontSize: 16,
                              letterSpacing: _obscurePasscode ? 3.0 : 1.0,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Secret Passcode',
                              labelStyle: const TextStyle(color: AppTheme.subtitleGrey),
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : const Color(0xFFE5E5EA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePasscode
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppTheme.subtitleGrey,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() =>
                                      _obscurePasscode = !_obscurePasscode);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 42,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _savePasscode,
                              child: const Text(
                                'Save Vault Passcode',
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

                    // Section 3: Dummy / Fake Crash Passcode
                    _buildSectionHeader('FAKE CRASH / PANIC PASSCODE'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'When this dummy code is entered into the calculator, it triggers a fake app crash screen. The app becomes unresponsive until closed.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.subtitleGrey,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _dummyPasscodeController,
                            keyboardType: TextInputType.number,
                            obscureText: _obscureDummyPasscode,
                            style: TextStyle(
                              fontSize: 16,
                              letterSpacing: _obscureDummyPasscode ? 3.0 : 1.0,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Dummy Crash Code (Optional)',
                              labelStyle: const TextStyle(color: AppTheme.subtitleGrey),
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : const Color(0xFFE5E5EA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureDummyPasscode
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppTheme.subtitleGrey,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() =>
                                      _obscureDummyPasscode = !_obscureDummyPasscode);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 42,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6B7280),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _saveDummyCode,
                              child: const Text(
                                'Save Dummy Crash Code',
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

                    // Section 4: Security
                    _buildSectionHeader('CALCULATOR SETTINGS'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: SwitchListTile(
                        activeTrackColor: AppTheme.onlineGreen,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Fake Calculator History',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Displays fake calculation entries when calculating',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.subtitleGrey,
                          ),
                        ),
                        value: _fakeHistoryEnabled,
                        onChanged: (val) {
                          setState(() => _fakeHistoryEnabled = val);
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Section 5: Account Deletion
                    _buildSectionHeader('ACCOUNT & DATA PRIVACY'),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: const Text(
                        'Delete Account & Server Data',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _confirmAccountDeletion(context),
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: child,
        ),
      ),
    );
  }
}
