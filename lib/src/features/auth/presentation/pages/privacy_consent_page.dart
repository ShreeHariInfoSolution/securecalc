import 'package:flutter/material.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/features/chat/presentation/pages/vault_home_page.dart';

/// First-launch onboarding and privacy consent screen shown when the user
/// unlocks the calculator vault for the very first time.
class PrivacyConsentPage extends StatefulWidget {
  const PrivacyConsentPage({super.key});

  @override
  State<PrivacyConsentPage> createState() => _PrivacyConsentPageState();
}

class _PrivacyConsentPageState extends State<PrivacyConsentPage> {
  bool _acceptedTerms = false;

  Future<void> _onAcceptAndContinue() async {
    if (!_acceptedTerms) {
      AppToast.show('Please accept the Privacy Policy & Terms to proceed.', isError: true);
      return;
    }

    // Save consent flag permanently
    await AppPreferences.setHasConsented(true);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) {
            return const VaultHomePage();
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
        body: SafeArea(
          child: Column(
            children: [
              // Header Section
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        size: 42,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Calculator Vault Privacy',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Learn how your privacy and permissions are safeguarded.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.subtitleGrey,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable Disclosures
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    // Section 1: App Features
                    _buildSectionTitle('CORE VAULT UTILITIES'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: Column(
                        children: [
                          _buildFeatureTile(
                            icon: Icons.calculate_outlined,
                            iconColor: Colors.amber.shade700,
                            title: 'Calculator Disguise & Panic Switch',
                            subtitle:
                                'Operates as a fully working calculator. Access the vault by entering your passcode ("1234="). Shake device anytime to return to calculator.',
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildFeatureTile(
                            icon: Icons.lock_outline_rounded,
                            iconColor: AppTheme.primaryColor,
                            title: 'End-to-End Encrypted Messaging',
                            subtitle:
                                'All messages, photos, videos, voice notes, and documents are encrypted using AES-256 before transmission. Only intended recipients can decrypt them.',
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildFeatureTile(
                            icon: Icons.folder_special_outlined,
                            iconColor: Colors.purple,
                            title: 'Private Media & Vault Storage',
                            subtitle:
                                'Store confidential photos, videos, and files inside local encrypted device storage protected from external apps.',
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Section 2: Permissions
                    _buildSectionTitle('APP PERMISSIONS DISCLOSURE'),
                    _buildGroupedCard(
                      isDark: isDark,
                      child: Column(
                        children: [
                          _buildFeatureTile(
                            icon: Icons.camera_alt_outlined,
                            iconColor: Colors.blue,
                            title: 'Camera Access',
                            subtitle:
                                'Required only when capturing photos or updating your profile avatar inside the vault.',
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildFeatureTile(
                            icon: Icons.mic_none_rounded,
                            iconColor: Colors.redAccent,
                            title: 'Microphone Access',
                            subtitle:
                                'Required only when recording voice notes inside encrypted chat conversations.',
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildFeatureTile(
                            icon: Icons.photo_library_outlined,
                            iconColor: Colors.green,
                            title: 'Photo & File Picker',
                            subtitle:
                                'Uses the secure system photo picker to let you attach photos, videos, or documents to messages.',
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Checkbox Consent
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Material(
                        color: isDark ? AppTheme.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: CheckboxListTile(
                            value: _acceptedTerms,
                            activeColor: AppTheme.primaryColor,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              'I agree to the Terms of Service and Privacy Policy for Calculator Vault.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            onChanged: (val) {
                              setState(() {
                                _acceptedTerms = val ?? false;
                              });
                            },
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // Action Button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _onAcceptAndContinue,
                    child: const Text(
                      'I Agree & Enter Vault',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.subtitleGrey,
          letterSpacing: 0.6,
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
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: child,
        ),
      ),
    );
  }

  Widget _buildFeatureTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 16,
      thickness: 1,
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06),
    );
  }
}
