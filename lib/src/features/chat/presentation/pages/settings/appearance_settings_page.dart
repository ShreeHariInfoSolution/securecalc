import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/theme/font_size_controller.dart';
import 'package:securecalc/src/core/theme/theme_controller.dart';
import 'package:securecalc/src/core/widgets/compact_settings_header.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

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
              // Header matching Screenshot 3
              const CompactSettingsHeader(title: 'Appearance & Theme'),

              // Content List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  children: [
                    _buildSectionHeader('THEME MODE (3 PHONES)', isDark),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: ThemeController.instance,
                      builder: (context, currentMode, _) {
                        return Container(
                          padding: const EdgeInsets.all(16.0),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Choose Phone Theme',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tap any phone preview below to switch theme',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.subtitleGrey,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _build3PhoneRow(context, currentMode, isDark),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // Font Size Scale Section matching Screenshot 3
                    _buildSectionHeader('TEXT & FONT SIZE', isDark),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<double>(
                      valueListenable: FontSizeController.instance,
                      builder: (context, currentScale, _) {
                        return Container(
                          padding: const EdgeInsets.all(16.0),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Text Scale Size',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    FontSizeController.instance.currentLabel,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<double>(
                                  showSelectedIcon: true,
                                  style: SegmentedButton.styleFrom(
                                    selectedBackgroundColor: Colors.white,
                                    selectedForegroundColor: AppTheme.primaryColor,
                                    side: BorderSide(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.12)
                                          : Colors.black.withValues(alpha: 0.08),
                                    ),
                                  ),
                                  segments: const [
                                    ButtonSegment(
                                      value: 0.9,
                                      label: Text('Small'),
                                    ),
                                    ButtonSegment(
                                      value: 1.0,
                                      label: Text('Medium'),
                                    ),
                                    ButtonSegment(
                                      value: 1.15,
                                      label: Text('Large'),
                                    ),
                                  ],
                                  selected: {currentScale},
                                  onSelectionChanged: (newSelection) {
                                    HapticFeedback.selectionClick();
                                    final newScale = newSelection.first;
                                    FontSizeController.instance
                                        .setScale(newScale);
                                    AppPreferences.setFontScale(newScale);
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // Disguise Guarantee Card matching Screenshot 3
                    Container(
                      padding: const EdgeInsets.all(16.0),
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
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Text(
                                'i',
                                style: TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Calculator Guarantee: The main Calculator disguise screen always stays pitch-black iOS style regardless of theme choice.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.black87,
                                height: 1.35,
                              ),
                            ),
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

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 2.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: isDark ? Colors.white38 : AppTheme.subtitleGrey,
        ),
      ),
    );
  }

  Widget _build3PhoneRow(
      BuildContext context, ThemeMode currentMode, bool isDark) {
    return Row(
      children: [
        _buildPhoneMockupCard(
          context: context,
          title: 'System',
          subtitle: 'Auto Match',
          mode: ThemeMode.system,
          currentMode: currentMode,
          isDark: isDark,
          gradient: const LinearGradient(
            colors: [Color(0xFFE5E5EA), Color(0xFF1C1C1E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        const SizedBox(width: 10),
        _buildPhoneMockupCard(
          context: context,
          title: 'Light',
          subtitle: 'Bright Clean',
          mode: ThemeMode.light,
          currentMode: currentMode,
          isDark: isDark,
          gradient: const LinearGradient(
            colors: [Color(0xFFF2F2F7), Color(0xFFFFFFFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        const SizedBox(width: 10),
        _buildPhoneMockupCard(
          context: context,
          title: 'Dark',
          subtitle: 'OLED Black',
          mode: ThemeMode.dark,
          currentMode: currentMode,
          isDark: isDark,
          gradient: const LinearGradient(
            colors: [Color(0xFF1C1C1E), Color(0xFF000000)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneMockupCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required ThemeMode mode,
    required ThemeMode currentMode,
    required bool isDark,
    required Gradient gradient,
  }) {
    final isSelected = currentMode == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          ThemeController.instance.setThemeMode(mode);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? Border.all(color: AppTheme.primaryColor, width: 1.5)
                : Border.all(color: Colors.transparent, width: 1.5),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ]
                : null,
          ),
          child: Column(
            children: [
              Container(
                width: 58,
                height: 88,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    Container(
                      width: 14,
                      height: 3,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white54 : Colors.black38,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      margin: const EdgeInsets.only(left: 6, right: 18),
                      height: 10,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 10, color: AppTheme.subtitleGrey),
              ),
              const SizedBox(height: 6),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: isSelected
                    ? AppTheme.primaryColor
                    : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
