import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/models/server_models.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';

class ChatInfoPage extends StatefulWidget {
  final ChatConversation conversation;

  const ChatInfoPage({super.key, required this.conversation});

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  ServerChatModel? _details;
  bool _loading = true;
  bool _clearingChat = false;
  bool _updatingMembers = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadDetails);
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final chatId = int.tryParse(widget.conversation.id);
    final details = chatId == null
        ? null
        : await ServerApiService.instance.getChatDetails(chatId);
    if (!mounted) return;
    setState(() {
      _details = details;
      _loading = false;
      if (details == null) _error = 'Chat information could not be loaded.';
    });
  }

  Future<void> _clearChat() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'Are you sure you want to delete all messages in this chat? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear chat'),
          ),
        ],
      ),
    );
    if (shouldClear != true || !mounted) return;
    final chatId = int.tryParse(widget.conversation.id);
    if (chatId == null) return;
    setState(() => _clearingChat = true);
    final cleared = await ServerApiService.instance.clearChatREST(chatId);
    if (!mounted) return;
    if (!cleared) {
      setState(() => _clearingChat = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not clear this chat. Please try again.')),
      );
      return;
    }
    await LocalChatStorage.instance.cacheMessages(
      widget.conversation.id,
      const [],
    );
    await LocalChatStorage.instance.updateConversation(
      widget.conversation.id,
      (conversation) => conversation.copyWith(
        lastMessage: 'No messages yet',
        lastMessageTime: '',
        unreadCount: 0,
        messages: const [],
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _addMembers() async {
    final chatId = int.tryParse(widget.conversation.id);
    if (chatId == null || _details == null) return;
    setState(() => _updatingMembers = true);
    try {
      final allUsers = await ServerApiService.instance.getUsers();
      if (!mounted) return;
      final existingIds = _details!.members.map((member) => member.id).toSet();
      final candidates = allUsers
          .where((user) =>
              user.id != ServerApiService.instance.currentUserId &&
              !existingIds.contains(user.id))
          .toList();
      if (candidates.isEmpty) {
        setState(() => _updatingMembers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('There are no users available to add.')),
        );
        return;
      }
      final selectedIds = <int>{};
      final ids = await showModalBottomSheet<List<int>>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Add members',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => Navigator.pop(
                                    sheetContext,
                                    selectedIds.toList(),
                                  ),
                          child: Text('Add (${selectedIds.length})'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (context, index) {
                        final user = candidates[index];
                        return CheckboxListTile(
                          value: selectedIds.contains(user.id),
                          title: Text(user.name),
                          subtitle: Text(user.phone ?? user.email ?? 'Member'),
                          secondary: IosAvatar(
                            name: user.name,
                            imagePath: user.avatar,
                            size: 42,
                          ),
                          onChanged: (checked) => setSheetState(() {
                            if (checked == true) {
                              selectedIds.add(user.id);
                            } else {
                              selectedIds.remove(user.id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (ids == null || ids.isEmpty || !mounted) {
        if (mounted) setState(() => _updatingMembers = false);
        return;
      }
      final added = await ServerApiService.instance.addGroupMembers(
        chatId: chatId,
        userIds: ids,
      );
      if (!mounted) return;
      if (!added) {
        setState(() => _updatingMembers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add group members.')),
        );
        return;
      }
      await ServerChatManager.instance.syncChats();
      if (mounted) setState(() => _updatingMembers = false);
      await _loadDetails();
    } catch (error) {
      if (mounted) {
        setState(() => _updatingMembers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add members: $error')),
        );
      }
    }
  }

  Future<void> _removeMember(UserModel member) async {
    final chatId = int.tryParse(widget.conversation.id);
    if (chatId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('Remove ${member.name} from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removed = await ServerApiService.instance.removeGroupMember(
      chatId: chatId,
      userId: member.id,
    );
    if (!mounted) return;
    if (removed) {
      await ServerChatManager.instance.syncChats();
      await _loadDetails();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove this member.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final surface = isDark ? AppTheme.darkSurface : Colors.white;
    final details = _details;
    final currentUserId = ServerApiService.instance.currentUserId;
    final peers = details?.members
            .where((member) => member.id != currentUserId)
            .toList() ??
        const <UserModel>[];
    final firstPeer = peers.isNotEmpty ? peers.first : null;
    final members = details?.members ?? const <UserModel>[];
    final creators = members
        .where((member) => member.id == details?.createdBy)
        .toList();
    final creatorName = creators.isEmpty ? 'Group admin' : creators.first.name;
    final displayName = details?.isGroup == true
        ? details?.groupName ?? widget.conversation.name
        : peers.isNotEmpty
            ? peers.first.name
            : widget.conversation.name;
    final avatar = details?.isGroup == true
        ? details?.groupAvatar ?? widget.conversation.avatarUrl
        : peers.isNotEmpty
            ? peers.first.avatar
            : widget.conversation.avatarUrl;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        toolbarHeight: 56,
        title: Text(
          details?.isGroup == true ? 'Group info' : 'Contact info',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading && details == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDetails,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        IosAvatar(
                          name: displayName,
                          imagePath: avatar,
                          isOnline: firstPeer?.isOnline ?? false,
                          size: 96,
                          showOnline: details?.isGroup != true,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          displayName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          details?.isGroup == true
                              ? '${details?.totalMembers ?? members.length} members'
                              : (firstPeer?.isOnline == true
                                  ? 'online'
                                  : firstPeer?.phone ??
                                      firstPeer?.email ??
                                      'Calculator Chat contact'),
                          style: const TextStyle(
                            color: AppTheme.subtitleGrey,
                            fontSize: 14,
                          ),
                        ),
                        if (_loading) ...[
                          const SizedBox(height: 14),
                          const LinearProgressIndicator(minHeight: 2),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(color: AppTheme.subtitleGrey),
                          ),
                          TextButton.icon(
                            onPressed: _loadDetails,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (details?.isGroup != true && peers.isNotEmpty)
                    _InfoCard(
                      surface: surface,
                      children: [
                        if ((peers.first.phone ?? '').isNotEmpty)
                          _InfoRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone',
                            value: peers.first.phone!,
                          ),
                        if ((peers.first.email ?? '').isNotEmpty)
                          _InfoRow(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: peers.first.email!,
                          ),
                        if ((peers.first.phone ?? '').isEmpty &&
                            (peers.first.email ?? '').isEmpty)
                          const _InfoRow(
                            icon: Icons.person_outline_rounded,
                            label: 'Contact',
                            value: 'Calculator Chat user',
                            last: true,
                          ),
                      ],
                    ),
                  if (details?.isGroup == true) ...[
                    _InfoCard(
                      surface: surface,
                      children: [
                        _InfoRow(
                          icon: Icons.groups_2_outlined,
                          label: 'Group name',
                          value: displayName,
                        ),
                        _InfoRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Created by',
                          value: creatorName,
                          last: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Members · ${details?.totalMembers ?? members.length}',
                              style: const TextStyle(
                                color: AppTheme.subtitleGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _updatingMembers ? null : _addMembers,
                            icon: _updatingMembers
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.person_add_alt_1_rounded),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                    ),
                    _InfoCard(
                      surface: surface,
                      children: [
                        for (var i = 0; i < members.length; i++)
                          ListTile(
                            leading: IosAvatar(
                              name: members[i].name,
                              imagePath: members[i].avatar,
                              isOnline: members[i].isOnline,
                              size: 42,
                            ),
                            title: Text(members[i].name),
                            subtitle: Text(members[i].role ?? 'member'),
                            trailing: members[i].id == currentUserId
                                ? const Text(
                                    'You',
                                    style: TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : IconButton(
                                    tooltip: 'Remove member',
                                    onPressed: () => _removeMember(members[i]),
                                    icon: const Icon(
                                      Icons.remove_circle_outline_rounded,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  _InfoCard(
                    surface: surface,
                    children: [
                      ListTile(
                        enabled: !_clearingChat,
                        leading: _clearingChat
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(
                                Icons.delete_sweep_outlined,
                                color: Colors.redAccent,
                              ),
                        title: const Text(
                          'Clear chat',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                        subtitle: const Text('Remove messages from this chat'),
                        onTap: _clearingChat ? null : _clearChat,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Color surface;
  final List<Widget> children;

  const _InfoCard({required this.surface, required this.children});

  @override
  Widget build(BuildContext context) => Material(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool last;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ListTile(
            leading: Icon(icon, color: AppTheme.primaryColor),
            title: Text(label,
                style: const TextStyle(color: AppTheme.subtitleGrey, fontSize: 12)),
            subtitle: Text(value, style: const TextStyle(fontSize: 15)),
          ),
          if (!last)
            const Divider(height: 1, indent: 56, endIndent: 16),
        ],
      );
}
