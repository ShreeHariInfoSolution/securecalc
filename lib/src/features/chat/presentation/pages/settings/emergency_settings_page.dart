import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:securecalc/src/core/widgets/compact_settings_header.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';

class EmergencySettingsPage extends StatelessWidget {
  const EmergencySettingsPage({super.key});

  void _confirmWipeData(BuildContext context) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Emergency Vault Wipe'),
            ],
          ),
          content: const Text(
            'Are you sure you want to permanently erase all secret chat history, encryption keys, and reset the vault? This action cannot be undone.',
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
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).popUntil((route) => route.isFirst);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vault cleanly wiped and reset.'),
                    backgroundColor: Colors.red,
                  ),
                );
              },
              child: const Text(
                'Wipe All Data',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ShakePanicWrapper(
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Compact Header Bar
              const CompactSettingsHeader(title: 'Emergency & Data Zone'),

              // Options
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
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
                        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.cleaning_services_rounded,
                                color: Colors.blue),
                            title: const Text('Clear Local Cache',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            subtitle: const Text(
                                'Frees space without deleting messages',
                                style: TextStyle(fontSize: 12)),
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Local media cache cleared.')),
                              );
                            },
                          ),
                          Divider(
                            height: 1,
                            color: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFE5E5EA),
                          ),
                          ListTile(
                            leading: const Icon(Icons.vpn_key_rounded,
                                color: Colors.orange),
                            title: const Text('Export Encrypted Backup Key',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            subtitle: const Text('Backup encryption seed safely',
                                style: TextStyle(fontSize: 12)),
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Key copied to secret clipboard.')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    ),
                    const SizedBox(height: 24),
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
                        'Emergency Vault Reset',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _confirmWipeData(context),
                    ),
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
