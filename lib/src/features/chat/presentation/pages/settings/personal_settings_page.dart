import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/compact_settings_header.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/features/calculator/domain/calculator_logic.dart';
import 'package:securecalc/src/features/calculator/presentation/pages/calculator_page.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:securecalc/src/features/chat/presentation/widgets/profile_image_cropper_dialog.dart';

class PersonalSettingsPage extends StatefulWidget {
  const PersonalSettingsPage({super.key});

  @override
  State<PersonalSettingsPage> createState() => _PersonalSettingsPageState();
}

class _PersonalSettingsPageState extends State<PersonalSettingsPage> {
  late TextEditingController _displayNameController;
  late TextEditingController _passcodeController;
  late TextEditingController _duressPasscodeController;
  String? _profileImagePath;
  bool _obscurePasscode = true;
  bool _obscureDuressPasscode = true;
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
    _duressPasscodeController = TextEditingController(
      text: CalculatorLogic.duressPasscode,
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
            Expanded(child: Text(AppToast.userFriendlyMessage(message))),
          ],
        ),
        backgroundColor: AppTheme.primaryColor,
      ),
    );
  }

  /// Opens glass popup menu when tapping on avatar
  void _showProfileGlassMenu() {
    HapticFeedback.lightImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ProfileMenu',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.84,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xDD1C1C1E)
                      : const Color(0xF2FFFFFF),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 32,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Profile Avatar Preview
                    IosAvatar(
                      name: AppPreferences.getDisplayName(),
                      imagePath: _profileImagePath,
                      size: 78,
                      showOnline: false,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppPreferences.getDisplayName(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Divider(
                      height: 1,
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                    const SizedBox(height: 12),

                    // Option 1: View Profile
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.fullscreen_rounded,
                            color: AppTheme.primaryColor,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          'View Profile',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        subtitle: const Text(
                          'View full photo in full screen',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.subtitleGrey,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _viewFullProfilePicture();
                        },
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Option 2: Update Profile
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF34C759).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.photo_camera_rounded,
                            color: Color(0xFF34C759),
                            size: 22,
                          ),
                        ),
                        title: Text(
                          'Update Profile',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        subtitle: const Text(
                          'Choose new photo from gallery or camera',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.subtitleGrey,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _showImagePickerOptions();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack).value,
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
  }

  /// Displays full screen image preview dialog
  void _viewFullProfilePicture() {
    final currentPath =
        _profileImagePath ?? AppPreferences.getProfileImagePath();
    showFullProfilePictureDialog(
      context,
      name: AppPreferences.getDisplayName(),
      imagePath: currentPath,
      onChangePhoto: _showImagePickerOptions,
    );
  }

  Future<void> _pickProfileImage(ImageSource source) async {
    AppPreferences.isPickerActive = true;
    try {
      if (source == ImageSource.camera) {
        var status = await Permission.camera.status;
        if (!status.isGranted && !status.isLimited) {
          status = await Permission.camera.request();
          if (!status.isGranted && !status.isLimited) {
            if (mounted) {
              showCupertinoDialog(
                context: context,
                builder: (ctx) => CupertinoAlertDialog(
                  title: const Text('Camera Access Required'),
                  content: const Text(
                    'Calnox Vault needs camera access to update your profile avatar. Please enable Camera in Settings.',
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
            return;
          }
        }
      } else if (Platform.isAndroid) {
        await [Permission.photos, Permission.storage].request();
      }

      final picked = await _picker.pickImage(
        source: source,
        imageQuality: source == ImageSource.camera ? null : 95,
      );
      if (picked != null) {
        if (!mounted) return;
        final croppedFile = await ProfileImageCropperDialog.cropImage(
          context,
          imageFile: File(picked.path),
        );
        if (croppedFile == null) return; // User cancelled crop

        final finalPath = croppedFile.path;
        await AppPreferences.setProfileImagePath(finalPath);
        if (mounted) {
          setState(() {
            _profileImagePath = finalPath;
          });
        }

        try {
          final updatedUser = await ServerApiService.instance.updateProfile(
            name: _displayNameController.text.trim(),
            profileImage: File(finalPath),
          );
          if (updatedUser != null && updatedUser.avatar != null) {
            await AppPreferences.setProfileImagePath(updatedUser.avatar!);
            if (mounted) {
              setState(() {
                _profileImagePath = updatedUser.avatar;
              });
            }
          }
        } catch (e) {
          debugPrint('[PROFILE UPLOAD ERROR] $e');
        }

        if (mounted) {
          _showToast('Profile picture updated successfully!');
        }
      }
    } catch (e) {
      debugPrint('[PROFILE PICK ERROR] $e');
      _showToast(AppToast.userFriendlyMessage('Unable to pick image: $e'));
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _removeProfileImage() async {
    try {
      await ServerApiService.instance.deleteProfileImage();
      await AppPreferences.setProfileImagePath('');
      if (mounted) {
        setState(() {
          _profileImagePath = null;
        });
        _showToast('Profile picture removed');
      }
    } catch (e) {
      _showToast('Failed to remove profile picture: $e');
    }
  }

  void _showImagePickerOptions() {
    final hasPhoto = (_profileImagePath != null && _profileImagePath!.isNotEmpty) ||
        (AppPreferences.getProfileImagePath()?.isNotEmpty == true);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
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
                        backgroundColor: AppTheme.primaryColor.withValues(
                          alpha: 0.15,
                        ),
                        child: const Icon(
                          Icons.photo_library_rounded,
                          color: AppTheme.primaryColor,
                        ),
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
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0x1F007AFF),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Camera', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                if (hasPhoto)
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _removeProfileImage();
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor:
                              Colors.redAccent.withValues(alpha: 0.15),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Remove',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.redAccent,
                          ),
                        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveDisplayName() async {
    final newName = _displayNameController.text.trim();
    if (newName.isEmpty) {
      _showToast('Display name cannot be empty.');
      return;
    }

    HapticFeedback.mediumImpact();
    await AppPreferences.setDisplayName(newName);

    try {
      await ServerApiService.instance.updateProfile(name: newName);
    } catch (e) {
      debugPrint('[SAVE NAME ERROR] $e');
    }

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

  void _saveDuressCode() {
    final newDuress = _duressPasscodeController.text.trim();
    HapticFeedback.mediumImpact();
    setState(() {
      CalculatorLogic.duressPasscode = newDuress;
    });
    AppPreferences.setDuressPasscode(newDuress);
    _showToast(
      newDuress.isEmpty
          ? 'Fake decoy passcode cleared.'
          : 'Fake decoy passcode set to "$newDuress="',
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _passcodeController.dispose();
    _duressPasscodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF000000)
            : const Color(0xFFF2F2F7),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // iOS Style Header
              const CompactSettingsHeader(title: 'Personal & Passcode'),

              // iOS Grouped Settings List
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 100.0),
                  children: [
                    // Section 1: Profile
                    _buildSectionHeader('PROFILE'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: Column(
                        children: [
                          Center(
                            child: GestureDetector(
                              onTap: _showProfileGlassMenu,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ValueListenableBuilder<String?>(
                                    valueListenable:
                                        AppPreferences.profileImagePathNotifier,
                                    builder: (context, currentPath, _) {
                                      return ValueListenableBuilder<String>(
                                        valueListenable:
                                            AppPreferences.displayNameNotifier,
                                        builder: (context, currentName, _) {
                                          return IosAvatar(
                                            name: currentName.isNotEmpty
                                                ? currentName
                                                : _displayNameController.text,
                                            imagePath:
                                                currentPath ?? _profileImagePath,
                                            size: 88,
                                            showOnline: false,
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isDark
                                              ? AppTheme.darkSurface
                                              : Colors.white,
                                          width: 2.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.2),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt_rounded,
                                        size: 15,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap photo to View or Update',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.subtitleGrey,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _buildCustomTextField(
                            isDark: isDark,
                            controller: _displayNameController,
                            label: 'Display Name',
                            hint: 'Enter your display name',
                            icon: Icons.person_rounded,
                            iconBgColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                            iconColor: AppTheme.primaryColor,
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _saveDisplayName,
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                              label: const Text(
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
                    _buildSectionHeader('REAL VAULT PASSCODE'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Type this code into the calculator and press "=" to unlock your real private vault.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.subtitleGrey,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildCustomTextField(
                            isDark: isDark,
                            controller: _passcodeController,
                            label: 'Real Passcode',
                            hint: 'Enter numeric passcode',
                            icon: Icons.lock_rounded,
                            iconBgColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                            iconColor: AppTheme.primaryColor,
                            isNumber: true,
                            isObscured: _obscurePasscode,
                            onToggleObscure: () {
                              setState(() => _obscurePasscode = !_obscurePasscode);
                            },
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _savePasscode,
                              icon: const Icon(Icons.security_rounded, size: 18),
                              label: const Text(
                                'Save Real Passcode',
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

                    // Section 3: Fake / Decoy Passcode
                    _buildSectionHeader('FAKE / DECOY PASSCODE (EMERGENCY)'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'If someone forces you to unlock the app, enter this fake passcode (e.g. 4321=) into the calculator. It will open an empty fake vault, keeping your real private messages completely hidden.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.subtitleGrey,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildCustomTextField(
                            isDark: isDark,
                            controller: _duressPasscodeController,
                            label: 'Fake Passcode (Default: 4321)',
                            hint: 'Enter fake passcode',
                            icon: Icons.shield_outlined,
                            iconBgColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            iconColor: const Color(0xFFF59E0B),
                            isNumber: true,
                            isObscured: _obscureDuressPasscode,
                            onToggleObscure: () {
                              setState(() => _obscureDuressPasscode = !_obscureDuressPasscode);
                            },
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6B7280),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _saveDuressCode,
                              icon: const Icon(Icons.shield_rounded, size: 18),
                              label: const Text(
                                'Save Fake Passcode',
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
                    // _buildSectionHeader('CALCULATOR SETTINGS'),
                    // _buildGroupedCard(
                    //   isDark: isDark,
                    //   child: SwitchListTile(
                    //     activeTrackColor: AppTheme.onlineGreen,
                    //     contentPadding: EdgeInsets.zero,
                    //     title: const Text(
                    //       'Fake Calculator History',
                    //       style: TextStyle(
                    //         fontSize: 14,
                    //         fontWeight: FontWeight.w600,
                    //       ),
                    //     ),
                    //     subtitle: const Text(
                    //       'Displays fake calculation entries when calculating',
                    //       style: TextStyle(
                    //         fontSize: 12,
                    //         color: AppTheme.subtitleGrey,
                    //       ),
                    //     ),
                    //     value: _fakeHistoryEnabled,
                    //     onChanged: (val) {
                    //       setState(() => _fakeHistoryEnabled = val);
                    //     },
                    //   ),
                    // ),
                    // const SizedBox(height: 24),

                    // Section 5: Account Deletion
                    // _buildSectionHeader('ACCOUNT & DATA PRIVACY'),
                    // OutlinedButton.icon(
                    //   style: OutlinedButton.styleFrom(
                    //     foregroundColor: Colors.red,
                    //     side: const BorderSide(color: Colors.red),
                    //     padding: const EdgeInsets.symmetric(vertical: 14),
                    //     shape: RoundedRectangleBorder(
                    //       borderRadius: BorderRadius.circular(12),
                    //     ),
                    //   ),
                    //   icon: const Icon(Icons.delete_forever_rounded),
                    //   label: const Text(
                    //     'Delete Account & Server Data',
                    //     style: TextStyle(fontWeight: FontWeight.bold),
                    //   ),
                    //   onPressed: () => _confirmAccountDeletion(context),
                    // ),
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

  Widget _buildCustomTextField({
    required bool isDark,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    bool isNumber = false,
    bool isObscured = false,
    VoidCallback? onToggleObscure,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: isNumber ? TextInputType.number : TextInputType.text,
              obscureText: isObscured,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: isObscured ? 3.0 : 0.5,
                color: isDark ? Colors.white : Colors.black,
              ),
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                labelStyle: const TextStyle(
                  color: AppTheme.subtitleGrey,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: const TextStyle(
                  color: AppTheme.subtitleGrey,
                  fontSize: 13,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          if (onToggleObscure != null)
            IconButton(
              icon: Icon(
                isObscured
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppTheme.subtitleGrey,
                size: 20,
              ),
              onPressed: onToggleObscure,
            )
          else if (controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.cancel_rounded,
                color: AppTheme.subtitleGrey,
                size: 18,
              ),
              onPressed: () {
                controller.clear();
                setState(() {});
              },
            ),
        ],
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.all(16.0), child: child),
      ),
    );
  }
}
