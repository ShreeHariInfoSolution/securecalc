import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/compact_settings_header.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../../../core/widgets/shake_panic_wrapper.dart';
import '../../domain/models/server_models.dart';
import '../../domain/services/server_chat_manager.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  List<UserModel> _blockedUsers = [];
  bool _isLoading = true;
  String? _error;
  final Set<int> _unblockingUserIds = {};

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final users = await ServerChatManager.instance.getBlockedUsers();
      if (mounted) {
        setState(() {
          _blockedUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load blocked users.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _unblockUser(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unblock User'),
        content: Text('Are you sure you want to unblock ${user.name.isNotEmpty ? user.name : "User #${user.id}"}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unblock', style: TextStyle(color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _unblockingUserIds.add(user.id);
    });

    final success = await ServerChatManager.instance.unblockUser(user.id);

    if (!mounted) return;

    setState(() {
      _unblockingUserIds.remove(user.id);
    });

    if (success) {
      setState(() {
        _blockedUsers.removeWhere((u) => u.id == user.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${user.name.isNotEmpty ? user.name : "User #${user.id}"} unblocked.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to unblock user. Please try again.'),
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
          bottom: false,
          child: Column(
            children: [
              CompactSettingsHeader(
                title: 'Blocked Users',
                showBackButton: true,
              ),
              Expanded(
                child: _buildBody(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadBlockedUsers,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_blockedUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.block_rounded,
              size: 64,
              color: isDark ? Colors.white30 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              'No Blocked Users',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Users you block will appear here.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBlockedUsers,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _blockedUsers.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          indent: 68,
          color: isDark ? Colors.white10 : Colors.black12,
        ),
        itemBuilder: (context, index) {
          final user = _blockedUsers[index];
          final isUnblocking = _unblockingUserIds.contains(user.id);
          final displayName = user.name.isNotEmpty ? user.name : 'User #${user.id}';

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: IosAvatar(
                name: displayName,
                imagePath: user.avatar,
                size: 44,
              ),
              title: Text(
                displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              subtitle: Text(
                'Blocked',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.redAccent.withValues(alpha: 0.8),
                ),
              ),
              trailing: isUnblocking
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      onPressed: () => _unblockUser(user),
                      child: const Text('Unblock'),
                    ),
            ),
          );
        },
      ),
    );
  }
}
