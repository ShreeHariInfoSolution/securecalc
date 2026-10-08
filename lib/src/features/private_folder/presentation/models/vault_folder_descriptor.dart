import 'package:flutter/cupertino.dart';

class VaultFolderDescriptor {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const VaultFolderDescriptor({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
