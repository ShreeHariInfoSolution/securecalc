import 'package:flutter/material.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/compact_settings_header.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';

class DisguiseSettingsPage extends StatefulWidget {
  const DisguiseSettingsPage({super.key});

  @override
  State<DisguiseSettingsPage> createState() => _DisguiseSettingsPageState();
}

class _DisguiseSettingsPageState extends State<DisguiseSettingsPage> {
  late bool _panicShakeEnabled;
  late bool _disguiseTitleEnabled;
  late bool _preventScreenshots;
  late String _disappearingDuration;

  @override
  void initState() {
    super.initState();
    _panicShakeEnabled = AppPreferences.getPanicShake();
    _disguiseTitleEnabled = AppPreferences.getDisguiseTitle();
    _preventScreenshots = AppPreferences.getPreventScreenshots();
    _disappearingDuration = AppPreferences.getDisappearingTimer();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
        body: SafeArea(
          child: Column(
            children: [
              // Header matching Screenshot 4
              const CompactSettingsHeader(title: 'Disguise & Security'),

              // Settings Items Card
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: isDark ? AppTheme.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            SwitchListTile(
                              activeTrackColor: AppTheme.onlineGreen,
                              title: const Text('Real Shake Panic Gesture',
                                  style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.bold)),
                              subtitle: const Text(
                                  'Shaking physical device opens Calculator instantly',
                                  style: TextStyle(
                                      fontSize: 12, color: AppTheme.subtitleGrey)),
                              value: _panicShakeEnabled,
                              onChanged: (val) {
                                setState(() => _panicShakeEnabled = val);
                                AppPreferences.setPanicShake(val);
                              },
                            ),
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                            SwitchListTile(
                              activeTrackColor: AppTheme.onlineGreen,
                              title: const Text('Disguise App Title',
                                  style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.bold)),
                              subtitle: const Text(
                                  'App appears as "Calculator" in system Recent Apps',
                                  style: TextStyle(
                                      fontSize: 12, color: AppTheme.subtitleGrey)),
                              value: _disguiseTitleEnabled,
                              onChanged: (val) {
                                setState(() => _disguiseTitleEnabled = val);
                                AppPreferences.setDisguiseTitle(val);
                              },
                            ),
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                            SwitchListTile(
                              activeTrackColor: AppTheme.onlineGreen,
                              title: const Text('Prevent Screenshots',
                                  style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.bold)),
                              subtitle: const Text(
                                  'Blocks screenshots and screen recording inside vault',
                                  style: TextStyle(
                                      fontSize: 12, color: AppTheme.subtitleGrey)),
                              value: _preventScreenshots,
                              onChanged: (val) {
                                setState(() => _preventScreenshots = val);
                                AppPreferences.setPreventScreenshots(val);
                              },
                            ),
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                            ListTile(
                              title: const Text('Disappearing Messages',
                                  style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'Auto-erase messages after: $_disappearingDuration',
                                  style: const TextStyle(
                                      fontSize: 12, color: AppTheme.subtitleGrey)),
                              trailing: DropdownButton<String>(
                                value: _disappearingDuration,
                                underline: const SizedBox(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'Off', child: Text('Off')),
                                  DropdownMenuItem(
                                      value: '1 hour', child: Text('1 hour')),
                                  DropdownMenuItem(
                                      value: '24 hours', child: Text('24 hours')),
                                  DropdownMenuItem(
                                      value: '7 days', child: Text('7 days')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _disappearingDuration = val);
                                    AppPreferences.setDisappearingTimer(val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
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
}
